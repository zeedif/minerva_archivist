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

    test(
      'creates a store and preserves every setting through save and reload',
      () async {
        final file = File(p.join(dir.path, 'new', 'profiles.jsonc'));
        final profiles = Profiles.empty(file);
        expect(await file.exists(), isFalse);
        final options = RunOptions.fromJson({
          'dat': ['Nintendo - Game Boy', 'Sony - PlayStation'],
          'root': p.join(dir.path, 'roms'),
          'wishlist': p.join(dir.path, 'wishlist.jsonc'),
          'lang': ['Es', 'En'],
          'region': ['Europe'],
          'priority': ['lang', 'langcount'],
          'langcount': 'fewest',
          'wishlist-mode': 'subset',
          'achievements': 'approved',
          'supersets': 'ignore',
          'compilations': 'never',
          'exclude': ['demos'],
          'layout': 'extracted-in-folder',
          'protect': ['Favorites'],
          'skip': ['prune'],
          'depth': 2,
        });
        await profiles.save(' My collection ', options);
        var loaded = await Profiles.load(file);
        expect(loaded.names, ['My collection']);
        expect(loaded.resolve('My collection').toJson(), options.toJson());
        await loaded.save('Other', const RunOptions(dats: ['Other']));
        await loaded.save('My collection', const RunOptions(dats: ['Updated']));
        loaded = await Profiles.load(file);
        expect(loaded.resolve('My collection').dats, ['Updated']);
        await loaded.delete('Other');
        expect((await Profiles.load(file)).names, ['My collection']);
      },
    );

    test(
      'saving a legacy profile keeps defaults and neighboring profiles',
      () async {
        final file = File(p.join(dir.path, 'profiles.jsonc'));
        final profiles = await Profiles.load(file);
        final before = profiles.resolve('gb').toJson();
        await profiles.save('New', const RunOptions(dats: ['New']));
        final loaded = await Profiles.load(file);
        expect(loaded.resolve('gb').toJson(), before);
        expect(loaded.resolve('New').languages, ['En']);
        expect(loaded.resolve('New').layout, Layout.zip);
      },
    );

    test('saving keeps comments and untouched entries byte for byte', () async {
      final file = File(p.join(dir.path, 'profiles.jsonc'));
      await file.writeAsString(
        '{\r\n'
        '  "defaults": {"lang": ["Es", "En"], "layout": "extracted"},\r\n'
        '  "profiles": {\r\n'
        '    // HANDHELDS\r\n'
        '    "gb": {"dat": "Nintendo - Game Boy", "root": "Z:/Roms/gb"},\r\n'
        '    // "gbc": {"dat": "Nintendo - Game Boy Color"}\r\n'
        '    "gba": {"dat": "Nintendo - Game Boy Advance", "layout": "zip"}\r\n'
        '  }\r\n'
        '}\r\n',
      );
      final profiles = await Profiles.load(file);
      final gba = profiles.resolve('gba');
      await profiles.save(
        'gba',
        RunOptions.fromJson({...gba.toJson(), 'depth': 1}),
      );
      await profiles.save(
        'nds',
        RunOptions.fromJson({
          ...profiles.defaults.toJson(),
          'dat': ['Nintendo - Nintendo DS'],
          'root': p.join(dir.path, 'roms', 'nds'),
        }),
      );
      expect(
        await file.readAsString(),
        '{\r\n'
        '  "defaults": {"lang": ["Es", "En"], "layout": "extracted"},\r\n'
        '  "profiles": {\r\n'
        '    // HANDHELDS\r\n'
        '    "gb": {"dat": "Nintendo - Game Boy", "root": "Z:/Roms/gb"},\r\n'
        '    // "gbc": {"dat": "Nintendo - Game Boy Color"}\r\n'
        '    "gba": {"dat": "Nintendo - Game Boy Advance", "layout": "zip", "depth": 1},\r\n'
        '    "nds": {"dat": "Nintendo - Nintendo DS", "root": "roms/nds"}\r\n'
        '  }\r\n'
        '}\r\n',
      );
      await profiles.delete('nds');
      await profiles.delete('gb');
      expect(
        await file.readAsString(),
        '{\r\n'
        '  "defaults": {"lang": ["Es", "En"], "layout": "extracted"},\r\n'
        '  "profiles": {\r\n'
        '    // HANDHELDS\r\n'
        '    // "gbc": {"dat": "Nintendo - Game Boy Color"}\r\n'
        '    "gba": {"dat": "Nintendo - Game Boy Advance", "layout": "zip", "depth": 1}\r\n'
        '  }\r\n'
        '}\r\n',
      );
    });

    test('writes a null that clears an inherited langcount', () async {
      final file = File(p.join(dir.path, 'profiles.jsonc'));
      await file.writeAsString(
        '{"defaults": {"priority": ["lang", "langcount"], "langcount": "most"},'
        ' "profiles": {}}',
      );
      final profiles = await Profiles.load(file);
      await profiles.save(
        'plain',
        RunOptions.fromJson({
          'dat': 'X',
          'priority': ['lang'],
        }),
      );
      expect(
        await file.readAsString(),
        contains(
          '"plain": {"dat": "X", "priority": ["lang"], "langcount": null}',
        ),
      );
      expect((await Profiles.load(file)).resolve('plain').langCount, isNull);
    });

    test('keeps edits made to the file after it was loaded', () async {
      final file = File(p.join(dir.path, 'profiles.jsonc'));
      final profiles = await Profiles.load(file);
      await file.writeAsString(
        (await file.readAsString()).replaceFirst('// shared', '// edited'),
      );
      await profiles.save('New', const RunOptions(dats: ['New']));
      expect(await file.readAsString(), contains('// edited'));
    });

    test('never overwrites a file it cannot parse', () async {
      final file = File(p.join(dir.path, 'profiles.jsonc'));
      final profiles = await Profiles.load(file);
      await file.writeAsString('{broken');
      await expectLater(
        profiles.save('New', const RunOptions(dats: ['New'])),
        throwsFormatException,
      );
      expect(await file.readAsString(), '{broken');
    });

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

    test('matches a system the archive files under another name', () async {
      await touch(
        'nointro',
        'Sony - PlayStation Vita (PSVgameSD) (20260101-000000).dat',
      );
      expect(await names('Sony - PlayStation Vita (PSVgameSD)'), hasLength(1));
    });
    test('lists every cached system once per source', () async {
      expect(await cachedDatReferences(cache.path), [
        'mame-redump:Sega - Saturn',
        'nointro:Sega - 32X',
        'redump:Sega - Saturn',
      ]);
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
