/// Filesystem access: directory scanning and streaming ROM hashing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

final class ScannedFile {
  const ScannedFile({
    required this.file,
    required this.relativePath,
    required this.size,
  });

  final File file;
  final String relativePath;
  final int size;
}

/// Walks a ROM directory, optionally filtered by extension.
abstract interface class FileScanner {
  Stream<ScannedFile> scan(
    Directory root, {
    bool recursive = true,
    Set<String>? extensions,
  });
}

final class DirectoryFileScanner implements FileScanner {
  const DirectoryFileScanner();

  @override
  Stream<ScannedFile> scan(
    Directory root, {
    bool recursive = true,
    Set<String>? extensions,
  }) async* {
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: recursive, followLinks: false)) {
      if (entity is! File) continue;
      if (extensions != null && !extensions.contains(p.extension(entity.path).toLowerCase())) {
        continue;
      }
      final stat = await entity.stat();
      yield ScannedFile(
        file: entity,
        relativePath: p.relative(entity.path, from: root.path),
        size: stat.size,
      );
    }
  }
}

/// The digests computed for a file, plus its byte size.
final class FileHashes {
  const FileHashes({
    required this.size,
    this.crc32,
    this.md5,
    this.sha1,
    this.sha256,
  });

  final int size;
  final String? crc32;
  final String? md5;
  final String? sha1;
  final String? sha256;
}

/// Computes ROM digests. Implementations should stream each source once and
/// derive all requested digests in a single pass.
abstract interface class Hasher {
  Future<FileHashes> hashFile(
    File file, {
    bool crc32 = true,
    bool md5 = true,
    bool sha1 = true,
    bool sha256 = false,
  });

  /// Hash every file entry inside an archive (e.g. a MiNERVA `.zip`), keyed by
  /// the entry path. Returns an empty map when [archive] isn't a supported
  /// container.
  Future<Map<String, FileHashes>> hashArchive(
    File archive, {
    bool crc32 = true,
    bool md5 = true,
    bool sha1 = true,
    bool sha256 = false,
  });
}

/// Streams each source once, deriving CRC32/MD5/SHA-1/SHA-256 together.
final class StreamingHasher implements Hasher {
  const StreamingHasher();

  @override
  Future<FileHashes> hashFile(
    File file, {
    bool crc32 = true,
    bool md5 = true,
    bool sha1 = true,
    bool sha256 = false,
  }) async {
    final crc = crc32 ? Crc32() : null;
    final md5d = md5 ? _ChunkedDigest(crypto.md5) : null;
    final sha1d = sha1 ? _ChunkedDigest(crypto.sha1) : null;
    final sha256d = sha256 ? _ChunkedDigest(crypto.sha256) : null;

    var size = 0;
    await for (final chunk in file.openRead()) {
      size += chunk.length;
      crc?.add(chunk);
      md5d?.add(chunk);
      sha1d?.add(chunk);
      sha256d?.add(chunk);
    }

    return FileHashes(
      size: size,
      crc32: crc?.hex,
      md5: md5d?.close(),
      sha1: sha1d?.close(),
      sha256: sha256d?.close(),
    );
  }

  @override
  Future<Map<String, FileHashes>> hashArchive(
    File archive, {
    bool crc32 = true,
    bool md5 = true,
    bool sha1 = true,
    bool sha256 = false,
  }) async {
    if (!archive.path.toLowerCase().endsWith('.zip')) return const {};
    final bytes = await archive.readAsBytes();
    final decoded = ZipDecoder().decodeBytes(bytes);
    final result = <String, FileHashes>{};
    for (final entry in decoded) {
      if (entry.name.endsWith('/')) continue;
      final data = entry.readBytes();
      if (data == null) continue;
      result[entry.name] = _fromBytes(
        data,
        crc32: crc32,
        md5: md5,
        sha1: sha1,
        sha256: sha256,
      );
    }
    return result;
  }

  FileHashes _fromBytes(
    List<int> bytes, {
    required bool crc32,
    required bool md5,
    required bool sha1,
    required bool sha256,
  }) {
    return FileHashes(
      size: bytes.length,
      crc32: crc32 ? (Crc32()..add(bytes)).hex : null,
      md5: md5 ? crypto.md5.convert(bytes).toString() : null,
      sha1: sha1 ? crypto.sha1.convert(bytes).toString() : null,
      sha256: sha256 ? crypto.sha256.convert(bytes).toString() : null,
    );
  }
}

/// Wraps a crypto [crypto.Hash] in a streaming sink and captures the result.
class _ChunkedDigest {
  _ChunkedDigest(crypto.Hash hash) {
    _input = hash.startChunkedConversion(
      ChunkedConversionSink<crypto.Digest>.withCallback(
        (digests) => _result = digests.single,
      ),
    );
  }

  late final ByteConversionSink _input;
  crypto.Digest? _result;

  void add(List<int> chunk) => _input.add(chunk);

  String close() {
    _input.close();
    return _result!.toString();
  }
}

/// Streaming CRC-32 (IEEE 802.3 / zlib polynomial `0xEDB88320`) — the CRC used
/// by DAT files and ZIP central directories. Self-contained so the core has no
/// hard dependency on a third-party CRC implementation.
class Crc32 {
  Crc32();

  static final List<int> _table = _buildTable();
  int _crc = 0xffffffff;

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  void add(List<int> chunk) {
    var c = _crc;
    for (var i = 0; i < chunk.length; i++) {
      c = _table[(c ^ chunk[i]) & 0xff] ^ (c >> 8);
    }
    _crc = c;
  }

  int get value => (_crc ^ 0xffffffff) & 0xffffffff;

  String get hex => value.toRadixString(16).padLeft(8, '0');
}
