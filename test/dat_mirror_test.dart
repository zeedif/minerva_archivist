import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory cache;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('minerva_dat_mirror_test');
  });

  tearDown(() {
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  String datOf(String version) =>
      '<datafile><header><version>$version</version></header></datafile>';

  List<int> zipOf(String name, String contents) => ZipEncoder().encode(
    Archive()..addFile(ArchiveFile.bytes(name, utf8.encode(contents))),
  );

  String blobSha(String contents) {
    final bytes = utf8.encode(contents);
    return crypto.sha1.convert([
      ...utf8.encode('blob ${bytes.length}\x00'),
      ...bytes,
    ]).toString();
  }

  /// Redump lists PS2 and Saturn; MAME-Redump carries PS2 and Dreamcast. Every
  /// request is counted so a skipped download shows up as a missing hit.
  (http.Client, List<String>) provider({
    required String ps2Stamp,
    required String mameDat,
  }) {
    final hits = <String>[];
    final client = MockClient((request) async {
      final url = request.url.toString();
      hits.add(url);
      if (url == '$kRedumpUrl/downloads') {
        return http.Response('''
<tr><td>Sony PlayStation 2</td>
<td class="downloads-version-cell"><time datetime="$ps2Stamp">$ps2Stamp</time></td>
<td class="download-links-cell"><a href="/datfile/PS2">Datfile</a></td></tr>
<tr><td>Sega Saturn</td>
<td class="downloads-version-cell"><time datetime="2026-10-14 05:52:31">x</time></td>
<td class="download-links-cell"><a href="/datfile/SS">Datfile</a></td></tr>
''', 200);
      }
      if (url == '$kRedumpUrl/datfile/PS2') {
        final stamp = ps2Stamp.replaceAll(':', '-');
        return http.Response.bytes(
          zipOf(
            'Sony - PlayStation 2 - Datfile (3) ($stamp).dat',
            datOf(stamp),
          ),
          200,
        );
      }
      if (url == '$kRedumpUrl/datfile/SS') {
        return http.Response.bytes(
          zipOf(
            'Sega - Saturn - Datfile (2) (2026-10-14 05-52-31).dat',
            datOf('2026-10-14 05-52-31'),
          ),
          200,
        );
      }
      if (url == kMameRedumpUrl) {
        return http.Response(
          jsonEncode([
            {
              'name': 'Sony - PlayStation 2 (9).dat',
              'sha': blobSha(mameDat),
              'download_url': 'https://raw.example/ps2.dat',
            },
            {
              'name': 'Sega - Dreamcast (8).dat',
              'sha': blobSha('dreamcast'),
              'download_url': 'https://raw.example/dc.dat',
            },
            {'name': 'Tosec', 'sha': 'x', 'download_url': null},
          ]),
          200,
        );
      }
      if (url == 'https://raw.example/ps2.dat') {
        return http.Response(mameDat, 200);
      }
      if (url == 'https://raw.example/dc.dat') {
        return http.Response('dreamcast', 200);
      }
      return http.Response('nope', 404);
    });
    return (client, hits);
  }

  File dat(String source, String name) =>
      File(p.join(cache.path, source, name));

  void seed(String source, String name, String contents) {
    dat(source, name)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  test('updates a cached DAT in place under a stable name', () async {
    seed(
      'redump',
      'Sony - PlayStation 2 - Datfile (2) (2025-12-10 21-14-18).dat',
      datOf('2025-12-10 21-14-18'),
    );
    seed('mame-redump', 'Sony - PlayStation 2 (7).dat', 'old');
    final (client, _) = provider(
      ps2Stamp: '2026-10-20 02:28:49',
      mameDat: 'new',
    );

    final report = await DatMirror(cacheDir: cache.path, client: client).sync();

    expect(report.ok, isTrue);
    expect((report.downloaded, report.upToDate, report.removed), (2, 0, 2));
    expect(
      dat('redump', 'Sony - PlayStation 2.dat').readAsStringSync(),
      datOf('2026-10-20 02-28-49'),
    );
    expect(
      dat('mame-redump', 'Sony - PlayStation 2.dat').readAsStringSync(),
      'new',
    );
    expect(Directory(p.join(cache.path, 'redump')).listSync(), hasLength(1));
    expect(
      Directory(p.join(cache.path, 'mame-redump')).listSync(),
      hasLength(1),
    );
  });

  test(
    'leaves a current DAT alone and skips systems nobody asked for',
    () async {
      seed('redump', 'Sony - PlayStation 2.dat', datOf('2026-10-20 02-28-49'));
      seed('mame-redump', 'Sony - PlayStation 2.dat', 'new');
      final (client, hits) = provider(
        ps2Stamp: '2026-10-20 02:28:49',
        mameDat: 'new',
      );

      final report = await DatMirror(
        cacheDir: cache.path,
        client: client,
      ).sync();

      expect((report.downloaded, report.upToDate), (0, 2));
      expect(
        hits.where((u) => u.contains('/datfile/') || u.contains('raw.')),
        isEmpty,
      );
      expect(dat('redump', 'Sega - Saturn.dat').existsSync(), isFalse);
      expect(dat('mame-redump', 'Sega - Dreamcast.dat').existsSync(), isFalse);
    },
  );

  test('fetches a requested system that is not cached yet', () async {
    final (client, _) = provider(
      ps2Stamp: '2026-10-20 02:28:49',
      mameDat: 'new',
    );

    final report = await DatMirror(
      cacheDir: cache.path,
      client: client,
    ).sync(only: {DatSource.redump}, systems: {'Sega - Saturn'});

    expect(report.downloaded, 1);
    expect(dat('redump', 'Sega - Saturn.dat').existsSync(), isTrue);
    expect(dat('redump', 'Sony - PlayStation 2.dat').existsSync(), isFalse);
    expect(Directory(p.join(cache.path, 'mame-redump')).existsSync(), isFalse);
  });

  test(
    'a provider that fails is reported without stopping the other',
    () async {
      seed('mame-redump', 'Sony - PlayStation 2.dat', 'new');
      final client = MockClient((request) async {
        return request.url.toString() == kMameRedumpUrl
            ? http.Response('{"message":"rate limited"}', 403)
            : http.Response('nope', 404);
      });

      final report = await DatMirror(
        cacheDir: cache.path,
        client: client,
      ).sync();

      expect(report.ok, isFalse);
      expect(report.errors, hasLength(2));
      expect(
        dat('mame-redump', 'Sony - PlayStation 2.dat').existsSync(),
        isTrue,
      );
    },
  );
}
