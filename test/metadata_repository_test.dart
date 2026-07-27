import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A stable 8-hex-digit stand-in for a ROM's CRC32, so a title's DAT entry and
/// its RetroAchievements entry join without hardcoding digests.
String crcOf(String title) => crypto.md5
    .convert(utf8.encode(title))
    .toString()
    .substring(0, 8);

void main() {
  late Directory cache;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('minerva_repo_test');
  });

  tearDown(() {
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  void write(String relativePath, String contents) {
    final file = File(p.join(cache.path, p.joinAll(relativePath.split('/'))));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String sha256Of(String relativePath) {
    final file = File(p.join(cache.path, p.joinAll(relativePath.split('/'))));
    return crypto.sha256.convert(file.readAsBytesSync()).toString();
  }

  /// Every request fails, so a lookup that falls through to the network is a
  /// test failure rather than a silent pass.
  http.Client offline() => MockClient((_) async => http.Response('nope', 404));

  const raJson = '''
{
    "retroachievements": [
        {
            "name": "Antarctic Adventure (USA, Europe)",
            "crc": "275C800E",
            "md5": "1ea45edc04bc4df444a38e50f8a75d5d",
            "sha1": "00db7cf9bd66aecac3d9368dd205680781b2e542"
        }
    ]
}
''';

  const antarctic = DatGame(
    name: 'Antarctic Adventure (USA, Europe)',
    roms: [
      RomEntry(
        name: 'Antarctic Adventure (USA, Europe).col',
        size: 32768,
        format: RomFormat.cartridge,
        crc32: '275c800e',
      ),
    ],
    metadata: GameMetadata(),
  );

  /// One RA entry, joinable by CRC.
  String raFile(List<String> names) => jsonEncode({
    'retroachievements': [
      for (final name in names) {'name': name, 'crc': crcOf(name)},
    ],
  });

  DatGame game(String name) => DatGame(
    name: name,
    roms: [
      RomEntry(
        name: '$name.rom',
        size: 1024,
        format: RomFormat.cartridge,
        crc32: crcOf(name),
      ),
    ],
    metadata: const GameMetadata(),
  );

  DatFile dat(List<String> names) => DatFile(
    header: const DatHeader(name: 'probe', flavor: DatFlavor.noIntro),
    games: [for (final n in names) game(n)],
  );

  group('RetroAchievements lookup follows upstream renames', () {
    test('finds the manufacturer-free file the folder ships', () async {
      // The DAT says `Coleco - ColecoVision`; upstream files it as
      // `ColecoVision.json` and the old name is a stale leftover.
      write('config/internal-config.json', '{"datFileTags": ["Parent-Clone"]}');
      write('retroachievements/ColecoVision.json', raJson);
      write(
        'retroachievements/Coleco - Colecovision.json',
        '{"retroachievements": []}',
      );
      write(
        'retroachievements/hash.json',
        jsonEncode({
          'ColecoVision.json': sha256Of('retroachievements/ColecoVision.json'),
        }),
      );

      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      final ra = await repo.retroAchievements(
        'Coleco - ColecoVision (Parent-Clone) (20260710-180934)',
      );
      expect(ra, isNotNull);
      // Upstream writes CRCs uppercase; the join folds case.
      expect(ra!.supportsGame(antarctic), isTrue);
    });

    test('matches a separator-only difference in the filename', () async {
      write('config/internal-config.json', '{"datFileTags": []}');
      write('retroachievements/Sony PlayStation.json', raJson);
      write(
        'retroachievements/hash.json',
        jsonEncode({
          'Sony PlayStation.json': sha256Of(
            'retroachievements/Sony PlayStation.json',
          ),
        }),
      );

      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      expect(await repo.retroAchievements('Sony - PlayStation'), isNotNull);
    });

    test('a system the folder does not cover stays unsupported', () async {
      write('config/internal-config.json', '{"datFileTags": []}');
      write(
        'retroachievements/hash.json',
        jsonEncode({'ColecoVision.json': 'irrelevant'}),
      );

      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      expect(await repo.retroAchievements('Sega - Beena'), isNull);
    });
  });

  group('RetroAchievements discovery by ROM hash', () {
    /// Writes a `retroachievements` folder plus the manifest that lists it.
    void folder(Map<String, String> files) {
      write('config/internal-config.json', '{"datFileTags": ["Parent-Clone"]}');
      files.forEach((name, body) => write('retroachievements/$name', body));
      write(
        'retroachievements/hash.json',
        jsonEncode({
          for (final name in files.keys)
            name: sha256Of('retroachievements/$name'),
        }),
      );
    }

    test('finds a variant filed under its base console', () async {
      // RA covers WonderSwan Color inside the base WonderSwan console's file,
      // a relationship no rule reads off the DAT name.
      folder({
        'Bandai WonderSwan.json': raFile(['Battle Spirit - Digimon Frontier']),
      });
      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      final ra = await repo.retroAchievements(
        'Bandai - WonderSwan Color (Parent-Clone)',
        dat: dat(['Battle Spirit - Digimon Frontier']),
      );
      expect(ra, isNotNull);
      expect(
        ra!.supportsGame(game('Battle Spirit - Digimon Frontier')),
        isTrue,
      );
    });

    test('finds a console RA spells too differently to derive', () async {
      folder({
        'Nintendo Famicom Disk System.json': raFile(['Zelda no Densetsu']),
        'Nintendo - Game Boy.json': raFile(['Tetris']),
      });
      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      final ra = await repo.retroAchievements(
        'Nintendo - Family Computer Disk System (Parent-Clone)',
        dat: dat(['Zelda no Densetsu']),
      );
      expect(ra, isNotNull);
      expect(ra!.supportsGame(game('Zelda no Densetsu')), isTrue);
    });

    test('a name match that describes the DAT is never second-guessed', () async {
      // The bigger file would win a hash count, but the named one already
      // covers the DAT, so no content search runs.
      folder({
        'Sony PlayStation.json': raFile(['Ridge Racer']),
        'Nintendo - Game Boy.json': raFile(['Ridge Racer', 'Tetris', 'Mario']),
      });
      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      final ra = await repo.retroAchievements(
        'Sony - PlayStation',
        dat: dat(['Ridge Racer', 'Tetris']),
      );
      expect(ra!.supportsGame(game('Tetris')), isFalse);
    });

    test('a same-manufacturer file wins before the folder is swept', () async {
      // The unrelated file matches more titles, but the search only reaches it
      // if nothing sharing the manufacturer matched.
      folder({
        'Nintendo Famicom Disk System.json': raFile(['Zelda no Densetsu']),
        'Sega - Mega Drive - Genesis.json': raFile([
          'Zelda no Densetsu',
          'Sonic',
          'Golden Axe',
        ]),
      });
      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      final ra = await repo.retroAchievements(
        'Nintendo - Family Computer Disk System',
        dat: dat(['Zelda no Densetsu', 'Sonic']),
      );
      expect(ra!.supportsGame(game('Sonic')), isFalse);
    });

    test('a name hit that covers nothing hands over to the search', () async {
      // `Sony PlayStation.json` resolves by name but describes another set, so
      // the search takes over — without weighing that file a second time.
      folder({
        'Sony PlayStation.json': raFile(['Ridge Racer']),
        'Nintendo - Game Boy.json': raFile(['Tetris']),
      });
      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      final ra = await repo.retroAchievements(
        'Sony - PlayStation',
        dat: dat(['Tetris']),
      );
      expect(ra!.supportsGame(game('Tetris')), isTrue);
    });

    test('sweeps the rest of the folder when nothing related matches', () async {
      folder({
        'Nintendo - Game Boy.json': raFile(['Tetris']),
        'NEC PC-8000-8800.json': raFile(['Thexder']),
      });
      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      final ra = await repo.retroAchievements(
        'Hudson - Whatever',
        dat: dat(['Thexder']),
      );
      expect(ra, isNotNull);
      expect(ra!.supportsGame(game('Thexder')), isTrue);
    });

    test('an uncovered system still resolves to null', () async {
      folder({'Nintendo - Game Boy.json': raFile(['Tetris'])});
      final repo = RemoteMetadataRepository(
        cacheDir: cache.path,
        client: offline(),
      );
      addTearDown(repo.close);

      expect(
        await repo.retroAchievements(
          'Commodore - Commodore 64',
          dat: dat(['Turrican']),
        ),
        isNull,
      );
    });
  });

  test('sync prunes cached assets the manifest no longer lists', () async {
    write('retroachievements/ColecoVision.json', raJson);
    write(
      'retroachievements/Coleco - Colecovision.json',
      '{"retroachievements": []}',
    );
    write('retroachievements/notes.txt', 'not an asset, so not pruned');
    final manifest = jsonEncode({
      'ColecoVision.json': sha256Of('retroachievements/ColecoVision.json'),
    });

    final repo = RemoteMetadataRepository(
      cacheDir: cache.path,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/retroachievements/hash.json')) {
          return http.Response(manifest, 200);
        }
        return http.Response('nope', 404);
      }),
    );
    addTearDown(repo.close);

    final report = await repo.sync(only: {MetadataAsset.retroAchievements});
    expect(report.removed, 1);

    File cached(String name) =>
        File(p.join(cache.path, 'retroachievements', name));
    expect(cached('Coleco - Colecovision.json').existsSync(), isFalse);
    expect(cached('ColecoVision.json').existsSync(), isTrue);
    expect(cached('notes.txt').existsSync(), isTrue);
  });
}
