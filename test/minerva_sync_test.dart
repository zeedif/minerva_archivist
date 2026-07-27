import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

void main() {
  group('core models', () {
    test('RomEntry matches across formats by shared hash', () {
      const raw = RomEntry(
        name: 'game.bin',
        size: 4,
        format: RomFormat.raw,
        sha1: 'abc',
      );
      const chd = RomEntry(
        name: 'game.chd',
        size: 8,
        format: RomFormat.chd,
        sha1: 'abc',
      );
      // Different formats/sizes, same SHA-1 -> same logical bytes.
      expect(raw.matchesHashes(chd), isTrue);
    });

    test('GameScore ranks released above beta', () {
      const released = GameScore(
        cloneListPriority: 0,
        status: ProductionStatus.released,
        languageRank: 0,
        regionRank: 0,
        retroAchievements: RaMatch.none,
        revision: 0,
      );
      const beta = GameScore(
        cloneListPriority: 0,
        status: ProductionStatus.beta,
        languageRank: 0,
        regionRank: 0,
        retroAchievements: RaMatch.none,
        revision: 0,
      );
      final ranked = [beta, released]..sort();
      expect(ranked.first.status, ProductionStatus.released);
    });

    test('RetroAchievementsIndex matches a game by raw ROM hash', () {
      final index = RetroAchievementsIndex('Nintendo - Game Boy', const [
        RetroAchievementsEntry(name: 'Tetris', sha1: 'deadbeef'),
      ]);
      const game = DatGame(
        name: 'Tetris (World)',
        roms: [
          RomEntry(
            name: 'Tetris (World).gb',
            size: 32768,
            format: RomFormat.cartridge,
            sha1: 'deadbeef',
          ),
        ],
        metadata: GameMetadata(),
      );
      expect(index.supportsGame(game), isTrue);
    });

    group('RA name fallback is scoped to what hashes cannot reach', () {
      DatGame game(String name, String sha1) => DatGame(
        name: name,
        roms: [
          RomEntry(
            name: '$name.nds',
            size: 4,
            format: RomFormat.cartridge,
            sha1: sha1,
          ),
        ],
        metadata: const GameMetadata(),
      );

      // RA publishes one entry per title, hashed against the original dump. A
      // Decrypted DAT re-hashes part of the set, so it joins on some entries and
      // misses the rest.
      final index = RetroAchievementsIndex('Nintendo - Nintendo DS', const [
        RetroAchievementsEntry(name: 'Joined (Europe)', sha1: 'aaaa'),
        RetroAchievementsEntry(name: 'Rehashed (Europe)', sha1: 'bbbb'),
      ]);

      test('an entry no hash reaches is recoverable by name', () {
        final games = [
          game('Joined (Europe)', 'aaaa'),
          game('Rehashed (Europe)', 'cccc'),
        ];
        expect(index.namesBeyondHashes(games), {'rehashed'});
      });

      test('an entry a hash already claimed is not', () {
        // Otherwise the region-free name would carry Europe's achievements over
        // to every sibling dump, and the RA tie-break would stop discriminating.
        final games = [
          game('Joined (Europe)', 'aaaa'),
          game('Joined (USA)', 'dddd'),
          game('Joined (Japan)', 'eeee'),
        ];
        expect(index.namesBeyondHashes(games), isNot(contains('joined')));
      });

      test('a DAT that joins on nothing falls back on everything', () {
        // The disc-system case: RA hashes the primary executable, so no raw
        // file digest ever matches.
        final games = [game('Joined (Europe)', 'zzzz')];
        expect(index.namesBeyondHashes(games), {'joined', 'rehashed'});
      });

      test('a DAT that joins on everything falls back on nothing', () {
        final games = [
          game('Joined (Europe)', 'aaaa'),
          game('Rehashed (Europe)', 'bbbb'),
        ];
        expect(index.namesBeyondHashes(games), isEmpty);
      });

      test('the enricher marks the rehashed dump, not its siblings', () {
        final enriched = const DatEnricher().enrich(
          DatFile(
            header: const DatHeader(name: 't', flavor: DatFlavor.noIntro),
            games: [
              game('Joined (Europe)', 'aaaa'),
              game('Rehashed (Europe)', 'cccc'),
              game('Rehashed (USA)', 'ffff'),
            ],
          ),
          config: InternalConfig(
            cloneListMetadataUrl: Uri.parse('https://example.invalid'),
          ),
          ra: index,
        );
        final ra = {
          for (final g in enriched.games) g.name: g.supportsRetroAchievements,
        };
        expect(ra['Joined (Europe)'], isTrue, reason: 'matched by hash');
        expect(ra['Rehashed (Europe)'], isTrue, reason: 'matched by name');
        expect(ra['Rehashed (USA)'], isTrue, reason: 'same region-free name');
      });
    });
  });
}
