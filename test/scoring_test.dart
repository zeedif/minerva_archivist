import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

DatGame _game(
  String name, {
  List<String> langs = const [],
  List<String> regions = const [],
  ProductionStatus status = ProductionStatus.released,
  bool ra = false,
  int revision = 0,
}) => DatGame(
  name: name,
  roms: const [],
  metadata: GameMetadata(
    languages: langs,
    regions: regions,
    status: status,
    revision: revision,
  ),
  supportsRetroAchievements: ra,
);

DatFile _dat(List<DatGame> games) =>
    DatFile(header: const DatHeader(name: 't', flavor: DatFlavor.noIntro), games: games);

void main() {
  const grouper = CloneGrouper();
  const engine = ScoringEngine();

  group('clone grouping', () {
    test('groups by clonelist group and by region-free name', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Atomic Punk',
            titles: const [
              VariantTitle(searchTerm: 'Atomic Punk', priority: 2),
              VariantTitle(searchTerm: 'Dynablaster', priority: 1),
            ],
          ),
        ],
      );
      final cands = grouper.candidates(
        _dat([
          _game('Atomic Punk (USA)'),
          _game('Dynablaster (Europe)'),
          _game('Tetris (USA)'),
          _game('Tetris (Japan)'),
        ]),
        cl,
      );
      expect(cands.where((c) => c.groupKey == 'Atomic Punk').length, 2);
      expect(cands.where((c) => c.groupKey == 'tetris').length, 2);
    });
  });

  group('1G1R scoring', () {
    test('prefers language then region order', () {
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game('Game (Japan)', langs: ['Ja'], regions: ['Japan']),
            _game('Game (USA)', langs: ['En'], regions: ['USA']),
            _game('Game (Europe)', langs: ['En'], regions: ['Europe']),
          ]),
          null,
        ),
        const ScoringConfig(
          languagePriority: ['En', 'Ja'],
          regionPriority: ['USA', 'Europe', 'Japan'],
        ),
      );
      expect(winners.single.game.name, 'Game (USA)');
    });

    test('clonelist priority overrides region', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'G',
            titles: const [
              VariantTitle(searchTerm: 'Alpha', priority: 1),
              VariantTitle(searchTerm: 'Beta', priority: 0),
            ],
          ),
        ],
      );
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game('Alpha (USA)', langs: ['En'], regions: ['USA']),
            _game('Beta (Japan)', langs: ['Ja'], regions: ['Japan']),
          ]),
          cl,
        ),
        const ScoringConfig(
          languagePriority: ['En'],
          regionPriority: ['USA', 'Japan'],
        ),
      );
      expect(winners.single.game.name, 'Beta (Japan)');
    });

    test('an (Alt) dump competes with its original, never duplicates it', () {
      // MSX ships up to five dumps of one game; only the original may survive.
      final games = [
        _game('Balance (Japan) (Alt 3)', regions: ['Japan']),
        _game('Balance (Japan)', regions: ['Japan']),
        _game('Balance (Japan) (Alt)', regions: ['Japan']),
      ];
      final config = InternalConfig(
        cloneListMetadataUrl: Uri.parse('https://example.invalid'),
        defaultRegionOrder: const ['Japan'],
      );
      final winners = engine.selectBest(
        grouper.candidates(_dat(games), null, TitleNormalizer(config)),
        const ScoringConfig(regionPriority: ['Japan']),
      );
      expect(winners.single.game.name, 'Balance (Japan)');
    });

    test('variantRank ranks Retool step 13 in its precedence order', () {
      // Alt is filtered before OEM, so an OEM title outranks an Alt one.
      expect(ScoringEngine.variantRank('Game (USA)'), 0);
      expect(
        ScoringEngine.variantRank('Game (USA) (OEM)'),
        lessThan(ScoringEngine.variantRank('Game (USA) (Alt)')),
      );
      expect(
        ScoringEngine.variantRank('Game (USA) (Rerelease)'),
        lessThan(ScoringEngine.variantRank('Game (USA) (Covermount)')),
      );
    });

    test('a full tie resolves to the higher name, whatever the DAT order', () {
      List<String> pick(List<DatGame> games) => engine
          .selectBest(
            grouper.candidates(_dat(games), null),
            const ScoringConfig(regionPriority: ['USA']),
          )
          .map((c) => c.game.name)
          .toList();

      final a = _game('Game (USA) (Set 1)', regions: ['USA']);
      final b = _game('Game (USA) (Set 2)', regions: ['USA']);
      expect(pick([a, b]), ['Game (USA) (Set 2)']);
      expect(pick([b, a]), ['Game (USA) (Set 2)']);
    });

    test('released beats prototype', () {
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game('Game (USA) (Proto)', regions: ['USA'], status: ProductionStatus.prototype),
            _game('Game (USA)', regions: ['USA']),
          ]),
          null,
        ),
        const ScoringConfig(regionPriority: ['USA']),
      );
      expect(winners.single.game.name, 'Game (USA)');
    });
  });

  group('wishlist + selection filter', () {
    test('parses a JSON array and applies OR with RA', () {
      final wl = parseWishlist('''
        [
          // exact base titles (case / "The" / punctuation ignored)
          "Zelda",
          "Metroid"
        ]
      ''');
      expect(wl, ['Zelda', 'Metroid']);

      final out = const SelectionFilter().apply(
        [
          _game('Zelda (USA)'),
          _game('Metroid (USA)'),
          _game('Contra (USA)', ra: true),
          _game('Random (USA)'),
        ],
        wishlist: wl,
        includeRetroAchievements: true,
        combine: FilterCombineMode.or,
      ).map((g) => g.name).toSet();

      expect(
        out,
        containsAll(<String>['Zelda (USA)', 'Metroid (USA)', 'Contra (USA)']),
      );
      expect(out.contains('Random (USA)'), isFalse);
    });

    test('AND intersects wishlist and RA', () {
      final out = const SelectionFilter().apply(
        [
          _game('Zelda (USA)', ra: true),
          _game('Zelda II (USA)'),
          _game('Contra (USA)', ra: true),
        ],
        wishlist: const ['Zelda'],
        includeRetroAchievements: true,
        combine: FilterCombineMode.and,
      ).map((g) => g.name).toSet();
      expect(out, {'Zelda (USA)'});
    });

    test('matches via clonelist alias (whole group)', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Atomic Punk',
            titles: const [
              VariantTitle(searchTerm: 'Atomic Punk'),
              VariantTitle(searchTerm: 'Bomber Boy'),
            ],
          ),
        ],
      );
      final out = const SelectionFilter().apply(
        [_game('Atomic Punk (USA)'), _game('Unrelated (USA)')],
        wishlist: const ['Bomber Boy'],
        cloneList: cl,
      ).map((g) => g.name).toSet();
      expect(out, {'Atomic Punk (USA)'});
    });
  });

  group('TitleNormalizer (Retool short_name)', () {
    final normalizer = TitleNormalizer(
      InternalConfig(
        cloneListMetadataUrl: Uri.parse('https://example.invalid'),
        languages: const {'English': 'En(?:-[A-Z][A-Z])?', 'Spanish': 'Es'},
        defaultRegionOrder: const ['USA', 'Europe', 'Japan', 'Australia'],
        ignoreTags: const ['(DSiWare)'],
      ),
    );

    test('drops region, language, version and ignore tags', () {
      expect(normalizer.shortName('Game (USA)'), 'game');
      expect(normalizer.shortName('Game (Europe, Australia)'), 'game');
      expect(normalizer.shortName('Game (Europe) (En,Es)'), 'game');
      expect(normalizer.shortName('Game (Europe) (Rev 1)'), 'game');
      expect(normalizer.shortName('Game (Europe) (v1.02)'), 'game');
      expect(normalizer.shortName('Game (USA) (DSiWare)'), 'game');
    });

    test('drops the dump-variant tags Retool keeps out of the key', () {
      for (final tag in const [
        '(Alt)',
        '(Alt 2)',
        '(Build 1234)',
        '(Beta)',
        '(Beta 2)',
        '(Proto)',
        '(Prototype 3)',
        '(Pre-production)',
        '(Debug Build)',
        '(Aftermarket)',
        '(Unl)',
        '(OEM)',
        '(Rerelease)',
        '(Review Code)',
        '(NTSC)',
        '(PAL 60Hz)',
        '(20260710)',
        '(2026-07-10)',
      ]) {
        expect(normalizer.shortName('Game (USA) $tag'), 'game', reason: tag);
      }
    });

    test('keeps look-alike tags that name a different product', () {
      expect(normalizer.shortName('Game (USA) (Revenge)'), 'game revenge');
      expect(normalizer.shortName('Game (USA) (Vol. 2)'), 'game vol 2');
      expect(
        normalizer.shortName('Game (USA) (V.Smile)'),
        'game v smile',
      );
    });

    test('keeps edition qualifiers, so both variants survive 1G1R', () {
      // Retool keeps "Overlander (Europe)" AND its compilation entry.
      expect(normalizer.shortName('Overlander (Europe)'), 'overlander');
      expect(
        normalizer.shortName('Overlander (Europe) (Compilation - Finale)'),
        'overlander compilation finale',
      );
    });

    test('matches clonelist searchTerms that carry a qualifier', () {
      // A blanket tag strip reduced this to "1942" and missed the entry.
      expect(normalizer.shortName('1942 (Extended) (USA)'), '1942 extended');
      expect(normalizeName('1942 (Extended)'), '1942 extended');
    });
  });

  group('language filtering (Retool -l)', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe', 'Germany'],
    );
    const scoring = ScoringConfig(languagePriority: ['Es', 'En']);

    List<String> select(List<DatGame> games, {required bool filter}) =>
        const GameSelector()
            .select(
              dat: _dat(games),
              config: config,
              scoring: scoring,
              filterLanguages: filter,
            )
            .games
            .map((g) => g.name)
            .toList();

    test('off by default: --lang only ranks', () {
      final games = [
        _game('Solo (Germany)', langs: const ['De']),
        _game('Other (USA)', langs: const ['En']),
      ];
      expect(select(games, filter: false), hasLength(2));
    });

    test('on: drops titles supporting none of --lang', () {
      final games = [
        _game('Solo (Germany)', langs: const ['De']),
        _game('Other (USA)', langs: const ['En']),
      ];
      expect(select(games, filter: true), ['Other (USA)']);
    });

    test('a wanted "Es" matches a title\'s "Es-MX"', () {
      final games = [_game('Regional (USA)', langs: const ['Es-MX'])];
      expect(select(games, filter: true), ['Regional (USA)']);
    });

    test('keeps titles whose languages are unknown', () {
      final games = [_game('Unknown (Germany)')];
      expect(select(games, filter: true), ['Unknown (Germany)']);
    });
  });

  group('SelectionStats', () {
    test('attributes every dropped title to one reason', () {
      final result = const GameSelector().select(
        dat: _dat([
          _game('Keep (USA)', langs: const ['En']),
          _game('Keep (Europe)', langs: const ['En']), // 1G1R runner-up
          _game('Proto (USA)', langs: const ['En'], status: ProductionStatus.prototype),
          _game('Solo (Germany)', langs: const ['De']),
        ]),
        config: InternalConfig(
          cloneListMetadataUrl: Uri.parse('https://example.invalid'),
          defaultRegionOrder: const ['USA', 'Europe', 'Germany'],
        ),
        scoring: const ScoringConfig(
          languagePriority: ['En'],
          regionPriority: ['USA', 'Europe'],
        ),
        excludeStatuses: const {ProductionStatus.prototype},
        filterLanguages: true,
      );

      final s = result.stats;
      expect(s.total, 4);
      expect(s.status, 1);
      expect(s.language, 1);
      expect(s.clones, 1);
      expect(s.selected, 1);
      expect(result.games.single.name, 'Keep (USA)');
      expect(
        s.total - s.status - s.category - s.language - s.clones - s.wishlist,
        s.selected,
        reason: 'the funnel must balance',
      );
      expect(s.reasons, ['status -1', 'language -1', '1g1r -1']);
    });
  });
}
