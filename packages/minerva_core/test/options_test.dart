import 'dart:io';

import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('RunOptions.fromJson', () {
    test('reads every option by its CLI spelling', () {
      final options = RunOptions.fromJson({
        'dat': 'Sony - PlayStation',
        'root': 'roms',
        'lang': ['Es', 'En'],
        'priority': ['lang', 'langcount'],
        'langcount': 'fewest',
        'exclude': ['bonus-discs', 'demos'],
        'layout': 'extracted-in-folder',
        'skip': ['prune'],
        'depth': 2,
      }, baseDir: 'base');
      expect(options.dats, ['Sony - PlayStation']);
      expect(options.root, p.join('base', 'roms'));
      expect(options.priority, [ScoreAxis.lang, ScoreAxis.langcount]);
      expect(options.langCount, LangCount.fewest);
      expect(options.exclude, {ExcludeKind.bonusDiscs, ExcludeKind.demos});
      expect(options.layout, Layout.extractedInFolder);
      expect(options.skip, {Stage.prune});
      expect(options.depth, 2);
    });

    test('ties langcount to its direction, both ways', () {
      expect(
        () => RunOptions.fromJson({
          'priority': ['lang', 'langcount'],
        }),
        throwsFormatException,
      );
      expect(
        () => RunOptions.fromJson({'langcount': 'most'}),
        throwsFormatException,
      );
    });

    test('rejects unknown keys, values and repeated axes', () {
      for (final json in <Map<String, Object?>>[
        {'langs': 'En'},
        {'layout': 'flat'},
        {
          'skip': ['prun'],
        },
        {
          'priority': ['lang', 'lang'],
        },
        {'depth': -1},
      ]) {
        expect(() => RunOptions.fromJson(json), throwsFormatException);
      }
    });
  });

  group('Profiles', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('minerva_profiles_');
      await File(p.join(dir.path, 'profiles.jsonc')).writeAsString('''
{
  // shared
  "defaults": { "lang": ["Es", "En"], "layout": "extracted" },
  "profiles": {
    "gb": { "dat": "Nintendo - Game Boy", "root": "gb", "lang": ["En"] }
  }
}''');
    });

    tearDown(() => dir.delete(recursive: true));

    test('layer defaults, the profile and overrides', () async {
      final profiles = await Profiles.load(
        File(p.join(dir.path, 'profiles.jsonc')),
      );
      expect(profiles.names, ['gb']);

      final stored = profiles.resolve('gb');
      expect(stored.languages, ['En']);
      expect(stored.layout, Layout.extracted);
      expect(stored.root, p.join(p.absolute(dir.path), 'gb'));

      final overridden = profiles.resolve('gb', overrides: {'layout': 'zip'});
      expect(overridden.layout, Layout.zip);
      expect(overridden.root, stored.root);

      expect(() => profiles.resolve('nes'), throwsFormatException);
    });
  });

  group('locateDats', () {
    late Directory cache;

    Future<void> touch(String folder, String name) =>
        File(p.join(cache.path, folder, name)).create(recursive: true);

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('minerva_dats_');
      await touch('nointro', 'Sega - 32X (Parent-Clone) (20250101-000000).dat');
      await touch('nointro', 'Sega - 32X (Parent-Clone) (20260101-000000).dat');
      await touch('redump', 'Sega - Saturn.dat');
      await touch('mame-redump', 'Sega - Saturn.dat');
    });

    tearDown(() => cache.delete(recursive: true));

    Future<List<String>> names(String reference) async => [
      for (final file in await locateDats(reference, cache.path))
        p.relative(file.path, from: cache.path).replaceAll(r'\', '/'),
    ];

    test('finds the newest DAT of a system whatever its date stamp', () async {
      expect(await names('sega - 32x'), [
        'nointro/Sega - 32X (Parent-Clone) (20260101-000000).dat',
      ]);
    });

    test('returns one DAT per source unless a source is named', () async {
      expect(await names('Sega - Saturn'), [
        'mame-redump/Sega - Saturn.dat',
        'redump/Sega - Saturn.dat',
      ]);
      expect(await names('redump:Sega - Saturn'), ['redump/Sega - Saturn.dat']);
    });

    test('accepts a path and fails on an unknown system', () async {
      final path = p.join(cache.path, 'redump', 'Sega - Saturn.dat');
      expect((await locateDats(path, cache.path)).single.path, path);
      expect(
        () => locateDats('Sega - Pico', cache.path),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
