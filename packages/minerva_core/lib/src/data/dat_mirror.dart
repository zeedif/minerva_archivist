/// Redump and MAME-Redump DAT mirroring: remote fetch + local freshness check.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'metadata_repository.dart';

const kRedumpUrl = 'https://redump.info';
const kMameRedumpUrl =
    'https://api.github.com/repos/MetalSlug/MAMERedump/contents/MAME%20Redump';

/// DAT providers, each mirrored into its own `<cache>/<folder>`.
enum DatSource {
  redump('redump'),
  mameRedump('mame-redump');

  const DatSource(this.folder);

  final String folder;
}

/// A system's DAT as its provider publishes it right now; [isCurrent] tells
/// whether the bytes of a local copy are that very revision.
typedef _RemoteDat = ({
  String system,
  bool Function(List<int> local) isCurrent,
  Future<({String fileName, List<int> bytes})> Function() fetch,
});

/// Keeps Redump and MAME-Redump DATs in the cache current.
///
/// A system is mirrored when its DAT is already in the cache or is named in
/// `systems`. The copy is saved as `<system>.dat`, so a path to it survives
/// every update.
final class DatMirror {
  DatMirror({required this.cacheDir, http.Client? client})
    : _client = client ?? http.Client();

  final String cacheDir;
  final http.Client _client;

  Future<SyncReport> sync({
    Set<DatSource>? only,
    Set<String> systems = const {},
    void Function(String message)? onProgress,
  }) async {
    var downloaded = 0;
    var upToDate = 0;
    var removed = 0;
    final errors = <String>[];
    final requested = systems.map(SystemNameResolver.normalizeKey).toSet();

    for (final source in only ?? DatSource.values) {
      final dir = Directory(p.join(cacheDir, source.folder));
      final local = <String, List<File>>{};
      if (await dir.exists()) {
        await for (final file in dir.list()) {
          if (file is! File || p.extension(file.path).toLowerCase() != '.dat') {
            continue;
          }
          final key = SystemNameResolver.normalizeKey(_systemOf(file.path));
          (local[key] ??= []).add(file);
        }
      }

      final List<_RemoteDat> remote;
      try {
        remote = switch (source) {
          DatSource.redump => await _redump(),
          DatSource.mameRedump => await _mameRedump(),
        };
      } catch (e) {
        errors.add('${source.folder}: $e');
        continue;
      }

      for (final dat in remote) {
        final key = SystemNameResolver.normalizeKey(dat.system);
        final copies = local[key] ?? const <File>[];
        if (copies.isEmpty && !requested.contains(key)) continue;
        try {
          final contents = [for (final f in copies) await f.readAsBytes()];
          if (contents.any(dat.isCurrent)) {
            upToDate++;
            continue;
          }
          final fetched = await dat.fetch();
          await dir.create(recursive: true);
          final target = File(
            p.join(dir.path, '${_systemOf(fetched.fileName)}.dat'),
          );
          await target.writeAsBytes(fetched.bytes);
          downloaded++;
          onProgress?.call('${source.folder}: ${p.basename(target.path)}');
          for (final old in copies) {
            if (p.equals(old.path, target.path)) continue;
            await old.delete();
            removed++;
          }
        } catch (e) {
          errors.add('${source.folder}/${dat.system}: $e');
        }
      }
    }

    return (
      downloaded: downloaded,
      upToDate: upToDate,
      removed: removed,
      errors: errors,
    );
  }

  /// `Sony - PlayStation 2 - Datfile (11844) (2026-10-20 02-28-49).dat` and
  /// `Sony - PlayStation 2 (11735).dat` both name `Sony - PlayStation 2`.
  static String _systemOf(String path) => p
      .basenameWithoutExtension(path)
      .replaceFirst(RegExp(r' (?:- Datfile )?\(\d+\).*$'), '');

  Future<List<_RemoteDat>> _redump() async {
    final page = utf8.decode(
      (await _get('$kRedumpUrl/downloads')).bodyBytes,
      allowMalformed: true,
    );
    final row = RegExp(
      r'<td>([^<]+)</td>\s*<td class="downloads-version-cell">\s*'
      r'<time datetime="([^"]+)">(?:(?!</tr>).)*?href="/datfile/([^"]+)"',
      dotAll: true,
    );
    return [
      for (final m in row.allMatches(page))
        (
          system: m[1]!.replaceAll('&amp;', '&'),
          // The page lists `2026-10-20 02:28:49`; the DAT's `<version>` says
          // `2026-10-20 02-28-49`.
          isCurrent: (local) =>
              RegExp(
                r'<version>([^<]*)</version>',
              ).firstMatch(utf8.decode(local, allowMalformed: true))?[1] ==
              m[2]!.replaceAll(':', '-'),
          fetch: () async {
            final zip = ZipDecoder().decodeBytes(
              (await _get('$kRedumpUrl/datfile/${m[3]}')).bodyBytes,
            );
            final dat = zip.firstWhere(
              (f) => f.name.toLowerCase().endsWith('.dat'),
            );
            return (fileName: dat.name, bytes: dat.readBytes()!);
          },
        ),
    ];
  }

  Future<List<_RemoteDat>> _mameRedump() async {
    final listing =
        jsonDecode(utf8.decode((await _get(kMameRedumpUrl)).bodyBytes)) as List;
    return [
      for (final entry in listing.cast<Map<String, dynamic>>())
        if ((entry['name'] as String).toLowerCase().endsWith('.dat'))
          (
            system: _systemOf(entry['name'] as String),
            // GitHub identifies a file by the SHA-1 of its blob.
            isCurrent: (local) =>
                crypto.sha1.convert([
                  ...utf8.encode('blob ${local.length}\x00'),
                  ...local,
                ]).toString() ==
                entry['sha'],
            fetch: () async => (
              fileName: entry['name'] as String,
              bytes: (await _get(entry['download_url'] as String)).bodyBytes,
            ),
          ),
    ];
  }

  Future<http.Response> _get(String url) async {
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode} for $url');
    }
    return resp;
  }

  void close() => _client.close();
}
