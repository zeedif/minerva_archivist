/// Torrent domain types + the pure-Dart `.torrent` (bencode) reader.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Opaque handle to an added torrent within a [TorrentClient] session (an
/// aria2 GID, a qBittorrent info-hash, etc.).
typedef TorrentHandle = String;

enum TorrentState {
  queued,
  checking,
  downloading,
  seeding,
  paused,
  completed,
  error,
}

/// One file inside a `.torrent`. [index] is **1-based** to line up directly
/// with aria2's `--select-file`.
final class TorrentFileEntry {
  const TorrentFileEntry({
    required this.index,
    required this.path,
    required this.length,
  });

  final int index;
  final String path;
  final int length;
}

/// Locally-parsed `.torrent` metadata — enough to compute a selective download
/// without contacting the swarm.
final class TorrentManifest {
  const TorrentManifest({
    required this.name,
    required this.infoHash,
    required this.files,
  });

  final String name;
  final String infoHash;
  final List<TorrentFileEntry> files;
}

/// A resolved MiNERVA platform and how to obtain its torrent.
final class PlatformTorrentRef {
  const PlatformTorrentRef({
    required this.collection,
    required this.platform,
    required this.torrentUri,
    required this.magnetUri,
    required this.internalPathPrefix,
  });

  final String collection;
  final String platform;
  final Uri torrentUri;
  final Uri magnetUri;

  /// Path prefix files share inside the torrent:
  /// `Minerva_Myrient/<collection>/<platform>/`.
  final String internalPathPrefix;
}

final class TorrentAddRequest {
  const TorrentAddRequest({
    required this.saveDirectory,
    this.torrentData,
    this.magnetUri,
    this.selectedFileIndices = const [],
    this.seedAfterComplete = false,
  });

  /// Raw `.torrent` bytes (preferred over [magnetUri]).
  final Uint8List? torrentData;
  final String? magnetUri;
  final String saveDirectory;

  /// 1-based file indices to download; empty means all files.
  final List<int> selectedFileIndices;
  final bool seedAfterComplete;
}

final class TorrentFileProgress {
  const TorrentFileProgress({
    required this.index,
    required this.path,
    required this.completedBytes,
    required this.totalBytes,
    required this.selected,
  });

  final int index;
  final String path;
  final int completedBytes;
  final int totalBytes;
  final bool selected;
}

final class TorrentProgress {
  const TorrentProgress({
    required this.handle,
    required this.state,
    required this.completedBytes,
    required this.totalBytes,
    required this.downloadSpeed,
    required this.seeders,
    required this.peers,
    this.files = const [],
  });

  final TorrentHandle handle;
  final TorrentState state;

  /// Bytes over the **selected** files, not the whole torrent.
  final int completedBytes;
  final int totalBytes;
  final int downloadSpeed; // bytes/s
  final int seeders;
  final int peers;
  final List<TorrentFileProgress> files;

  double get fraction => totalBytes == 0 ? 0 : completedBytes / totalBytes;
}

/// Pure-Dart `.torrent` reader: decodes bencode, computes the info-hash, and
/// lists files with 1-based indices (matching aria2 `--select-file`), so the
/// domain can compute a selective download without touching the swarm.
final class BencodeTorrentInspector {
  const BencodeTorrentInspector();

  Future<TorrentManifest> read(Uint8List torrentData) async {
    final decoder = _Bencode(torrentData);
    final root = decoder.decode();
    if (root is! Map<String, Object>) {
      throw const FormatException('Torrent is not a bencoded dictionary.');
    }
    final info = root['info'];
    if (info is! Map<String, Object>) {
      throw const FormatException('Torrent has no info dictionary.');
    }

    final name = utf8.decode(info['name'] as Uint8List, allowMalformed: true);
    final infoHash = decoder.infoStart != null
        ? sha1
              .convert(torrentData.sublist(decoder.infoStart!, decoder.infoEnd!))
              .toString()
        : '';

    final files = <TorrentFileEntry>[];
    final rawFiles = info['files'];
    if (rawFiles is List) {
      var index = 1;
      for (final f in rawFiles) {
        if (f is! Map<String, Object>) continue;
        final length = (f['length'] as int?) ?? 0;
        final segments =
            (f['path'] as List?)
                ?.map((e) => utf8.decode(e as Uint8List, allowMalformed: true))
                .toList() ??
            const <String>[];
        files.add(
          TorrentFileEntry(
            index: index++,
            path: [name, ...segments].join('/'),
            length: length,
          ),
        );
      }
    } else {
      files.add(
        TorrentFileEntry(index: 1, path: name, length: (info['length'] as int?) ?? 0),
      );
    }

    return TorrentManifest(name: name, infoHash: infoHash, files: files);
  }
}

/// Minimal bencode decoder that records the byte range of the top-level `info`
/// value (needed to compute the info-hash).
class _Bencode {
  _Bencode(this.data);

  final Uint8List data;
  int _pos = 0;
  int? infoStart;
  int? infoEnd;

  Object decode() {
    final c = data[_pos];
    return switch (c) {
      0x69 => _int(), // 'i'
      0x6c => _list(), // 'l'
      0x64 => _dict(), // 'd'
      _ => _string(),
    };
  }

  int _int() {
    _pos++; // 'i'
    final start = _pos;
    while (data[_pos] != 0x65) {
      _pos++;
    }
    final value = int.parse(ascii.decode(data.sublist(start, _pos)));
    _pos++; // 'e'
    return value;
  }

  Uint8List _string() {
    var len = 0;
    while (data[_pos] != 0x3a) {
      // ':'
      len = len * 10 + (data[_pos] - 0x30);
      _pos++;
    }
    _pos++; // ':'
    final bytes = data.sublist(_pos, _pos + len);
    _pos += len;
    return bytes;
  }

  List<Object> _list() {
    _pos++; // 'l'
    final list = <Object>[];
    while (data[_pos] != 0x65) {
      list.add(decode());
    }
    _pos++; // 'e'
    return list;
  }

  Map<String, Object> _dict() {
    _pos++; // 'd'
    final map = <String, Object>{};
    while (data[_pos] != 0x65) {
      final key = utf8.decode(_string(), allowMalformed: true);
      final valueStart = _pos;
      final value = decode();
      if (key == 'info') {
        infoStart = valueStart;
        infoEnd = _pos;
      }
      map[key] = value;
    }
    _pos++; // 'e'
    return map;
  }
}
