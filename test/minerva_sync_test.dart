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
        hasRetroAchievements: false,
        revision: 0,
      );
      const beta = GameScore(
        cloneListPriority: 0,
        status: ProductionStatus.beta,
        languageRank: 0,
        regionRank: 0,
        hasRetroAchievements: false,
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
  });
}
