import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

/// A RetroAchievements index covering [names].
///
/// Support is joined on ROM hashes, so each fake dump uses its own name as its
/// CRC — enrichment then marks exactly the titles listed here, the way it does
/// for a real system.
RetroAchievementsIndex _raIndex(List<String> names) => RetroAchievementsIndex(
  'test',
  [for (final n in names) RetroAchievementsEntry(name: n, crc32: n)],
);

DatGame _game(
  String name, {
  List<String> langs = const [],
  List<String> regions = const [],
  ProductionStatus status = ProductionStatus.released,
  bool ra = false,
  int revision = 0,
}) => DatGame(
  name: name,
  roms: [
    RomEntry(
      name: '$name.rom',
      size: 1024,
      format: RomFormat.cartridge,
      crc32: name,
    ),
  ],
  metadata: GameMetadata(
    languages: langs,
    regions: regions,
    status: status,
    revision: revision,
  ),
  retroAchievements: ra ? RaMatch.byHash : RaMatch.none,
);

DatFile _dat(List<DatGame> games) => DatFile(
  header: const DatHeader(name: 't', flavor: DatFlavor.noIntro),
  games: games,
);

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
      // Group keys are normalized, so a clonelist group name and an unlisted
      // title's own key can never collide by casing or punctuation alone.
      expect(cands.where((c) => c.groupKey == 'atomic punk').length, 2);
      expect(cands.where((c) => c.groupKey == 'tetris').length, 2);
    });

    test('supersets belong to their group, like titles and compilations', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Alpha',
            titles: const [VariantTitle(searchTerm: 'Alpha')],
            supersets: const [VariantTitle(searchTerm: 'Alpha Collection')],
          ),
        ],
      );
      final cands = grouper.candidates(
        _dat([_game('Alpha (USA)'), _game('Alpha Collection (USA)')]),
        cl,
      );
      expect(cands.every((c) => c.groupKey == 'alpha'), isTrue);
      // The role has to survive grouping; it decides the group below.
      expect(
        {for (final c in cands) c.game.name: c.isSuperset},
        {'Alpha (USA)': false, 'Alpha Collection (USA)': true},
      );
    });
  });

  group('a superset represents its group', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe', 'Japan'],
    );
    final cl = CloneList(
      name: 'x',
      variants: [
        VariantGroup(
          group: 'Alpha',
          titles: const [VariantTitle(searchTerm: 'Alpha')],
          supersets: const [VariantTitle(searchTerm: 'Alpha Deluxe')],
        ),
      ],
    );

    List<String> select(List<DatGame> games) => const GameSelector()
        .select(
          dat: _dat(games),
          config: config,
          scoring: ScoringConfig(
            languagePriority: ['En'],
            regionPriority: ['USA', 'Europe', 'Japan'],
          ),
          cloneList: cl,
        )
        .games
        .map((g) => g.name)
        .toList();

    test('an edition that subsumes the group takes its slot', () {
      // Same region and language on both sides, so nothing above the superset
      // test can separate them.
      expect(
        select([
          _game('Alpha (USA)', langs: const ['En'], regions: const ['USA']),
          _game(
            'Alpha Deluxe (USA)',
            langs: const ['En'],
            regions: const ['USA'],
          ),
        ]),
        ['Alpha Deluxe (USA)'],
      );
    });

    test('even against a higher revision', () {
      // Revision sits below the superset test.
      expect(
        select([
          _game(
            'Alpha (USA)',
            langs: const ['En'],
            regions: const ['USA'],
            revision: 1,
          ),
          _game(
            'Alpha Deluxe (USA)',
            langs: const ['En'],
            regions: const ['USA'],
          ),
        ]),
        ['Alpha Deluxe (USA)'],
      );
    });

    test('but never against a region the caller ranked', () {
      // Naming `region` among the axes lifts it above the superset test.
      expect(
        select([
          _game('Alpha (USA)', langs: const ['En'], regions: const ['USA']),
          _game(
            'Alpha Deluxe (Japan)',
            langs: const ['En'],
            regions: const ['Japan'],
          ),
        ]),
        ['Alpha (USA)'],
      );
    });

    test('and across regions the caller left unranked', () {
      // Region left out of the axes only breaks ties below the superset test, so
      // a superset from a lower-priority region still represents the group: it
      // stands for it in every region.
      expect(
        const GameSelector()
            .select(
              dat: _dat([
                _game(
                  'Alpha (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                ),
                _game(
                  'Alpha Deluxe (Japan)',
                  langs: const ['En'],
                  regions: const ['Japan'],
                ),
              ]),
              config: config,
              scoring: ScoringConfig(
                languagePriority: ['En'],
                regionPriority: ['USA', 'Europe', 'Japan'],
                priority: [ScoreAxis.lang],
              ),
              cloneList: cl,
            )
            .games
            .single
            .name,
        'Alpha Deluxe (Japan)',
      );
    });

    test('never against a language the caller asked for', () {
      expect(
        const GameSelector()
            .select(
              dat: _dat([
                _game(
                  'Alpha (USA)',
                  langs: const ['Es'],
                  regions: const ['USA'],
                ),
                _game(
                  'Alpha Deluxe (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                ),
              ]),
              config: config,
              scoring: ScoringConfig(
                languagePriority: ['Es', 'En'],
                regionPriority: ['USA'],
              ),
              cloneList: cl,
            )
            .games
            .single
            .name,
        'Alpha (USA)',
      );
    });

    test('and not at all once the caller says to ignore supersets', () {
      // The same pair as 'even against a higher revision': dropping the mode puts
      // the revision back in charge.
      expect(
        const GameSelector()
            .select(
              dat: _dat([
                _game(
                  'Alpha (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                  revision: 1,
                ),
                _game(
                  'Alpha Deluxe (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                ),
              ]),
              config: config,
              scoring: ScoringConfig(
                languagePriority: ['En'],
                regionPriority: ['USA'],
                supersets: SupersetMode.ignore,
              ),
              cloneList: cl,
            )
            .games
            .single
            .name,
        'Alpha (USA)',
      );
    });

    test('nor against achievements the caller ranked', () {
      expect(
        const GameSelector()
            .select(
              dat: _dat([
                _game(
                  'Alpha (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                ),
                _game(
                  'Alpha Deluxe (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                ),
              ]),
              config: config,
              scoring: ScoringConfig(
                languagePriority: ['En'],
                priority: [ScoreAxis.ra],
              ),
              cloneList: cl,
              ra: _raIndex(const ['Alpha (USA)']),
            )
            .games
            .single
            .name,
        'Alpha (USA)',
      );
    });
  });

  group('a pack stands for every group that lists it', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe'],
    );
    // One pack listed under three groups; the third has no release of its own,
    // so only the pack can answer for it.
    final cl = CloneList(
      name: 'x',
      variants: [
        VariantGroup(
          group: 'Alpha',
          titles: const [VariantTitle(searchTerm: 'Alpha')],
          compilations: const [VariantTitle(searchTerm: 'Trio Pack')],
        ),
        VariantGroup(
          group: 'Beta',
          titles: const [VariantTitle(searchTerm: 'Beta')],
          compilations: const [VariantTitle(searchTerm: 'Trio Pack')],
        ),
        VariantGroup(
          group: 'Gamma',
          compilations: const [VariantTitle(searchTerm: 'Trio Pack')],
        ),
      ],
    );
    final games = [
      _game('Alpha (USA)', langs: const ['En'], regions: const ['USA']),
      _game('Beta (USA)', langs: const ['En'], regions: const ['USA']),
      _game('Trio Pack (USA)', langs: const ['En'], regions: const ['USA']),
    ];

    SelectionResult select({SupersetMode supersets = SupersetMode.prefer}) =>
        const GameSelector().select(
          dat: _dat(games),
          config: config,
          scoring: ScoringConfig(
            languagePriority: ['En'],
            regionPriority: ['USA'],
            supersets: supersets,
          ),
          cloneList: cl,
        );

    test('it reports under the first group and competes in all of them', () {
      final pack = const CloneGrouper()
          .candidates(_dat(games), cl)
          .firstWhere((c) => c.game.name == 'Trio Pack (USA)');
      expect(pack.groupKey, 'alpha');
      expect(pack.represents, {'beta', 'gamma'});
      expect(pack.groups, ['alpha', 'beta', 'gamma']);
    });

    test('so the titles it holds are not selected beside it', () {
      final result = select();
      expect(result.games.map((g) => g.name), ['Trio Pack (USA)']);
      // Two of the three slots it took were already answered for.
      expect(result.stats.represented, 2);
    });

    test('ignoring it hands each group back to its own release', () {
      final result = select(supersets: SupersetMode.ignore);
      expect(result.games.map((g) => g.name), [
        'Alpha (USA)',
        'Beta (USA)',
        // Nothing else claims Gamma, so the pack still fills it.
        'Trio Pack (USA)',
      ]);
    });

    test('naming it asks for the pack, not for each title inside', () {
      expect(
        const GameSelector()
            .select(
              dat: _dat(games),
              config: config,
              scoring: ScoringConfig(languagePriority: ['En']),
              wishlist: const ['Trio Pack'],
              cloneList: cl,
            )
            .games
            .map((g) => g.name),
        ['Trio Pack (USA)'],
      );
    });

    test('while naming a title it holds answers with the pack', () {
      // Under `prefer` the pack is what answers for its contents, so asking for
      // one of them is asking for it.
      expect(
        const GameSelector()
            .select(
              dat: _dat(games),
              config: config,
              scoring: ScoringConfig(languagePriority: ['En']),
              wishlist: const ['Beta'],
              cloneList: cl,
            )
            .games
            .map((g) => g.name),
        ['Trio Pack (USA)'],
      );
    });

    test('and with the release itself once supersets are ignored', () {
      expect(
        const GameSelector()
            .select(
              dat: _dat(games),
              config: config,
              scoring: ScoringConfig(
                languagePriority: ['En'],
                supersets: SupersetMode.ignore,
              ),
              wishlist: const ['Beta'],
              cloneList: cl,
            )
            .games
            .map((g) => g.name),
        // The pack stays for Gamma, which nothing else can answer for.
        ['Beta (USA)', 'Trio Pack (USA)'],
      );
    });
  });

  group('clonelist filters', () {
    // The real Nintendo 64 clonelist: `Bomberman 64` covers both the USA and
    // Japan releases, and a matchRegions filter splits Japan out — they are
    // different games, so one must not knock the other out of 1G1R.
    final bomberman = CloneList(
      name: 'x',
      variants: [
        VariantGroup(
          group: 'Bomberman 64',
          titles: const [
            VariantTitle(searchTerm: 'Baku Bomberman'),
            VariantTitle(
              searchTerm: 'Bomberman 64',
              filters: [
                VariantFilter(
                  conditions: FilterConditions(matchRegions: ['Japan']),
                  results: FilterResults(group: 'Bomberman 64 (Japan)'),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    test('matchRegions moves the matching dump into its own group', () {
      final cands = grouper.candidates(
        _dat([
          _game('Bomberman 64 (USA)', regions: ['USA']),
          _game('Bomberman 64 (Japan)', regions: ['Japan']),
        ]),
        bomberman,
      );
      expect(
        {for (final c in cands) c.game.name: c.groupKey},
        {
          'Bomberman 64 (USA)': 'bomberman 64',
          'Bomberman 64 (Japan)': 'bomberman 64 japan',
        },
      );
    });

    test('so both dumps survive 1G1R instead of one trashing the other', () {
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game('Bomberman 64 (USA)', langs: ['En'], regions: ['USA']),
            _game('Bomberman 64 (Japan)', langs: ['Ja'], regions: ['Japan']),
          ]),
          bomberman,
        ),
        ScoringConfig(
          languagePriority: ['En', 'Ja'],
          regionPriority: ['USA', 'Japan'],
        ),
      );
      expect(
        {for (final w in winners) w.game.name},
        {'Bomberman 64 (USA)', 'Bomberman 64 (Japan)'},
      );
    });

    test('a condition that fails leaves the title in its group', () {
      final cands = grouper.candidates(
        _dat([
          _game('Bomberman 64 (Europe)', regions: ['Europe']),
        ]),
        bomberman,
      );
      expect(cands.single.groupKey, 'bomberman 64');
    });

    test('every condition present must hold', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Top Model',
            titles: const [
              VariantTitle(
                searchTerm: 'Top Model',
                filters: [
                  VariantFilter(
                    conditions: FilterConditions(
                      matchRegions: ['Europe'],
                      matchLanguages: ['De', 'En'],
                    ),
                    results: FilterResults(group: 'Top Model (German)'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      String groupOf(DatGame g) =>
          grouper.candidates(_dat([g]), cl).single.groupKey;

      expect(
        groupOf(
          _game('Top Model (Europe)', langs: ['De', 'En'], regions: ['Europe']),
        ),
        'top model german',
      );
      // Right region, but only one of the two required languages.
      expect(
        groupOf(
          _game('Top Model (Europe)', langs: ['De'], regions: ['Europe']),
        ),
        'top model',
      );
    });

    test('matchString tests the full name, case-insensitively', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Hugo',
            titles: const [
              VariantTitle(
                searchTerm: 'Hugo',
                filters: [
                  VariantFilter(
                    conditions: FilterConditions(matchString: 'Homebrew'),
                    results: FilterResults(group: 'Hugo (Homebrew)'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final cands = grouper.candidates(
        _dat([_game('Hugo (Europe)'), _game('Hugo (Europe) (Homebrew)')]),
        cl,
      );
      expect(
        {for (final c in cands) c.game.name: c.groupKey},
        {'Hugo (Europe)': 'hugo', 'Hugo (Europe) (Homebrew)': 'hugo homebrew'},
      );
    });

    test('a demoted title loses to one that declares no priority', () {
      // Every title starts at priority 1 and is only ever demoted from
      // there, so `Toki no Ocarina GC (priority 2)` must lose to the plain
      // `Ocarina of Time` rather than outrank it.
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Ocarina of Time',
            titles: const [
              VariantTitle(
                searchTerm: 'Legend of Zelda, The - Ocarina of Time',
              ),
              VariantTitle(
                searchTerm: 'Zelda no Densetsu - Toki no Ocarina GC',
                priority: 2,
              ),
            ],
          ),
        ],
      );
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game(
              'Zelda no Densetsu - Toki no Ocarina GC (Japan)',
              langs: ['Ja'],
              regions: ['Japan'],
            ),
            _game(
              'Legend of Zelda, The - Ocarina of Time (USA)',
              langs: ['En'],
              regions: ['USA'],
            ),
          ]),
          cl,
        ),
        ScoringConfig(languagePriority: ['En', 'Ja']),
      );
      expect(
        winners.single.game.name,
        'Legend of Zelda, The - Ocarina of Time (USA)',
      );
    });

    test('a filter can demote a title below the default priority', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'G',
            titles: const [
              VariantTitle(
                searchTerm: 'Game',
                filters: [
                  VariantFilter(
                    conditions: FilterConditions(matchRegions: ['Europe']),
                    results: FilterResults(priority: 5),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game('Game (Europe)', langs: ['En'], regions: ['Europe']),
            _game('Game (Japan)', langs: ['En'], regions: ['Japan']),
          ]),
          cl,
        ),
        // Both dumps speak English and both regions rank alike, so the priority
        // the filter set is the only thing left to separate them.
        ScoringConfig(
          languagePriority: ['En'],
          regionPriority: [PriorityList.other],
        ),
      );
      expect(winners.single.game.name, 'Game (Japan)');
    });

    test('regionOrder asks about the user\'s preference, not the title', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Tomb Raider III',
            titles: const [
              VariantTitle(
                searchTerm: 'Tomb Raider III',
                filters: [
                  VariantFilter(
                    conditions: FilterConditions(
                      regionOrder: RegionOrderCondition(
                        higherRegions: ['Japan'],
                        lowerRegions: ['Europe', 'USA'],
                      ),
                    ),
                    results: FilterResults(
                      group: 'Tomb Raider III (International Version)',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      String groupOf(List<String> regionPriority) => grouper
          .candidates(
            _dat([
              _game('Tomb Raider III (Japan)', regions: ['Japan']),
            ]),
            cl,
            regionOrder: PriorityList(regionPriority),
          )
          .single
          .groupKey;

      expect(
        groupOf(['Japan', 'USA', 'Europe']),
        'tomb raider iii international version',
      );
      expect(groupOf(['USA', 'Europe', 'Japan']), 'tomb raider iii');
      // A side the user's order doesn't name at all can't be compared.
      expect(groupOf(['Japan']), 'tomb raider iii');
    });

    test(
      'englishFriendly makes a Japan-only dump pass an --lang En filter',
      () {
        final cl = CloneList(
          name: 'x',
          variants: [
            VariantGroup(
              group: 'Fantasy Zone',
              titles: const [
                VariantTitle(
                  searchTerm: 'Fantasy Zone',
                  filters: [
                    VariantFilter(
                      conditions: FilterConditions(matchRegions: ['Japan']),
                      results: FilterResults(englishFriendly: true),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final config = InternalConfig(
          cloneListMetadataUrl: Uri.parse('https://example.invalid'),
          defaultRegionOrder: const ['USA', 'Japan'],
        );
        final result = const GameSelector().select(
          dat: _dat([
            _game('Fantasy Zone (Japan)', langs: ['Ja'], regions: ['Japan']),
          ]),
          config: config,
          scoring: ScoringConfig(languagePriority: ['En']),
          cloneList: cl,
        );
        expect(result.games.single.name, 'Fantasy Zone (Japan)');
        expect(result.games.single.metadata.languages, contains('En'));
      },
    );

    test('a regionFree title has to spell out the non-region tags', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'Aladdin - Hummer Team',
            titles: const [
              VariantTitle(
                searchTerm: 'Aladdin (Hummer Team) (Pirate)',
                match: TitleMatch.regionFree,
              ),
            ],
          ),
        ],
      );
      final config = InternalConfig(
        cloneListMetadataUrl: Uri.parse('https://example.invalid'),
        defaultRegionOrder: const ['Asia', 'USA'],
      );
      final cands = grouper.candidates(
        _dat([
          _game('Aladdin (Asia) (Hummer Team) (Pirate)', regions: ['Asia']),
          _game('Aladdin (USA)', regions: ['USA']),
        ]),
        cl,
        normalizer: TitleNormalizer(config),
      );
      expect(
        {for (final c in cands) c.game.name: c.groupKey},
        {
          'Aladdin (Asia) (Hummer Team) (Pirate)': 'aladdin hummer team',
          'Aladdin (USA)': 'aladdin',
        },
      );
    });

    test('a regex title claims every name it matches', () {
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: 'All Titles',
            titles: const [
              VariantTitle(searchTerm: '.+', match: TitleMatch.regex),
            ],
            categories: const ['BIOS'],
          ),
        ],
      );
      final result = const GameSelector().select(
        dat: _dat([_game('Anything (USA)'), _game('Else (Japan)')]),
        config: InternalConfig(
          cloneListMetadataUrl: Uri.parse('https://example.invalid'),
          defaultRegionOrder: const ['USA', 'Japan'],
        ),
        scoring: ScoringConfig(),
        cloneList: cl,
        exclude: const {ExcludeKind.bios},
      );
      expect(result.games, isEmpty);
      expect(result.stats.excluded, 2);
    });
  });

  group('edition tags', () {
    // The real internal-config lists, trimmed to the entries under test.
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe', 'Japan'],
      modernEditions: const [
        TagPattern(
          r'\s?\((?:\w*?,?\s)*Wii Virtual Console(?:,?\s\w*?)*\)',
          isRegex: true,
        ),
        TagPattern(r'\s?\(Game[Cc]ube.*?\)', isRegex: true),
        TagPattern('(Zelda Collection)'),
      ],
      demoteEditions: const [TagPattern('(LodgeNet)'), TagPattern('(Debug)')],
      promoteEditions: const [TagPattern('(Shindou Edition)')],
      budgetEditions: const [TagPattern('(Greatest Hits)')],
    );
    final normalizer = TitleNormalizer(config);

    test('an edition tag is stripped from the clone key, so dumps compete', () {
      // Without this, every re-release forms its own group and gets downloaded
      // alongside the original.
      for (final name in [
        'Mario Kart 64 (USA) (LodgeNet)',
        'Mario Kart 64 (USA) (Wii Virtual Console)',
        'Mario Kart 64 (USA) (GameCube)',
        'Mario Kart 64 (USA) (Greatest Hits)',
      ]) {
        expect(normalizer.shortName(name), 'mario kart 64', reason: name);
      }
    });

    test('and the original then wins the slot', () {
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game(
              'Mario Kart 64 (USA) (LodgeNet)',
              langs: ['En'],
              regions: ['USA'],
            ),
            _game('Mario Kart 64 (USA)', langs: ['En'], regions: ['USA']),
            _game(
              'Mario Kart 64 (USA) (Wii Virtual Console)',
              langs: ['En'],
              regions: ['USA'],
            ),
          ]),
          null,
          normalizer: normalizer,
        ),
        ScoringConfig(languagePriority: ['En'], regionPriority: ['USA']),
        EditionTags(config),
      );
      expect(winners.single.game.name, 'Mario Kart 64 (USA)');
    });

    test('a promoted edition beats the plain release', () {
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game('Super Mario 64 (Japan)', langs: ['Ja'], regions: ['Japan']),
            _game(
              'Super Mario 64 (Japan) (Shindou Edition)',
              langs: ['Ja'],
              regions: ['Japan'],
            ),
          ]),
          null,
          normalizer: normalizer,
        ),
        ScoringConfig(languagePriority: ['Ja'], regionPriority: ['Japan']),
        EditionTags(config),
      );
      expect(
        winners.single.game.name,
        'Super Mario 64 (Japan) (Shindou Edition)',
      );
    });

    test('a budget re-release beats the first pressing', () {
      final winners = engine.selectBest(
        grouper.candidates(
          _dat([
            _game('Game (USA)', langs: ['En'], regions: ['USA']),
            _game(
              'Game (USA) (Greatest Hits)',
              langs: ['En'],
              regions: ['USA'],
            ),
          ]),
          null,
          normalizer: normalizer,
        ),
        ScoringConfig(languagePriority: ['En'], regionPriority: ['USA']),
        EditionTags(config),
      );
      expect(winners.single.game.name, 'Game (USA) (Greatest Hits)');
    });

    test('with no lists loaded the edition tie-breaks sit out', () {
      const none = EditionTags.none();
      expect(none.modernRank('Game (USA) (Wii Virtual Console)'), 0);
      expect(
        none.editionRank('Game (USA) (LodgeNet)'),
        none.editionRank('Game (USA)'),
      );
    });
  });

  group('name-based categories', () {
    // No-Intro DATs carry no <category> element, so the name is the only signal.
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Japan'],
    );

    Set<String> selectFrom(List<String> names, Set<ExcludeKind> exclude) =>
        const GameSelector()
            .select(
              dat: _dat([
                for (final n in names) _game(n, regions: ['USA']),
              ]),
              config: config,
              scoring: ScoringConfig(),
              exclude: exclude,
            )
            .games
            .map((g) => g.name)
            .toSet();

    test('(Test Program) counts as an application', () {
      expect(
        selectFrom(
          [
            'Nintendo 64 Test Cartridge (USA) (v1.x) (Runtime) (Test Program)',
            '64GB Checker (Japan) (v1.05) (Test Program)',
            'Super Mario 64 (USA)',
          ],
          {ExcludeKind.applications},
        ),
        {'Super Mario 64 (USA)'},
      );
    });

    test('[BIOS] and (Enhancement Chip) count as bios', () {
      expect(
        selectFrom(
          [
            '[BIOS] Something (USA)',
            'Chip Thing (USA) (Enhancement Chip)',
            'Real Game (USA)',
          ],
          {ExcludeKind.bios},
        ),
        {'Real Game (USA)'},
      );
    });

    test('(Manual) counts as a manual', () {
      expect(
        selectFrom(
          ['Guide (USA) (Manual)', 'Real Game (USA)'],
          {ExcludeKind.manuals},
        ),
        {'Real Game (USA)'},
      );
    });

    test('(Video) and trailers count as video', () {
      // The DS Download Play DAT has no <category> element, so without these
      // patterns, the video clips slip through and get downloaded.
      expect(
        selectFrom(
          [
            'Legendary Starfy, The (USA) (Video) (DS Download Station Vol. 13)',
            'Legendary Starfy, The (USA) (Video) (DS Download Station Vol. 14 + 15)',
            'Shrek 2 (USA) - Movie Trailer',
            'Some Game (USA) (E3 2004 Video)',
            'Pokemon Ruby (USA) (Nintendo Direct 2013)',
            'Sonic X - Volume 1 (USA) (Game Boy Advance Video)',
            'Legendary Starfy, The (USA) (Multiplayer) (DS Broadcast)',
          ],
          {ExcludeKind.video},
        ),
        {'Legendary Starfy, The (USA) (Multiplayer) (DS Broadcast)'},
      );
    });

    test('(Magazine) counts as multimedia', () {
      expect(
        selectFrom(
          ['Disc (Europe) (Magazine)', 'Real Game (USA)'],
          {ExcludeKind.multimedia},
        ),
        {'Real Game (USA)'},
      );
    });

    test('a [b] tag counts as a bad dump', () {
      expect(
        selectFrom(
          ['Broken (USA) [b]', 'Real Game (USA)'],
          {ExcludeKind.badDumps},
        ),
        {'Real Game (USA)'},
      );
    });

    test('demo tags cover prefixed words and trials', () {
      expect(
        selectFrom(
          [
            'Game (USA) (Demo)',
            'Game B (USA) (Kiosk Demo)',
            'Game C (Japan) (Taikenban)',
            'Game D (USA) (Trial)',
            'Game E (Japan) (Sample 2004-01-01)',
            'Real Game (USA)',
          ],
          {ExcludeKind.demos},
        ),
        {'Real Game (USA)'},
      );
    });

    test('preproduction tags allow their qualifier words', () {
      expect(
        selectFrom(
          [
            'Game (USA) (Possible Proto)',
            'Game B (USA) (Beta 2)',
            'Game C (USA) (Debug Build)',
            'Game D (USA) (Prerelease)',
            'Real Game (USA)',
          ],
          {ExcludeKind.preproduction},
        ),
        {'Real Game (USA)'},
      );
    });

    test('a category nobody excluded leaves the title alone', () {
      expect(
        selectFrom([
          'Nintendo 64 Test Cartridge (USA) (Test Program)',
          'Real Game (USA)',
        ], const {}),
        {'Nintendo 64 Test Cartridge (USA) (Test Program)', 'Real Game (USA)'},
      );
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
        ScoringConfig(
          languagePriority: ['En', 'Ja'],
          regionPriority: ['USA', 'Europe', 'Japan'],
        ),
      );
      expect(winners.single.game.name, 'Game (USA)');
    });

    test('clonelist priority decides once the ordered axes tie', () {
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
            _game('Beta (USA)', langs: ['En'], regions: ['USA']),
          ]),
          cl,
        ),
        ScoringConfig(languagePriority: ['En'], regionPriority: ['USA']),
      );
      expect(winners.single.game.name, 'Beta (USA)');
    });

    test('region outranks clonelist priority', () {
      // Clonelist priority never decides between two dumps from different
      // regions: the cross-region pass separates them on region priority alone.
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
            _game('Beta (Japan)', langs: ['En'], regions: ['Japan']),
          ]),
          cl,
        ),
        ScoringConfig(
          languagePriority: ['En'],
          regionPriority: ['USA', 'Japan'],
        ),
      );
      expect(winners.single.game.name, 'Alpha (USA)');
    });

    test('achievements outrank clonelist priority', () {
      // The clonelist prefers the `Rubik's Cube` spelling, but the achievement
      // set was cut against `Atari Video Cube (USA)`; with `ra` an axis, the
      // dump that can actually earn achievements has to win.
      final cl = CloneList(
        name: 'x',
        variants: [
          VariantGroup(
            group: "Rubik's Cube",
            titles: const [
              VariantTitle(searchTerm: "Rubik's Cube"),
              VariantTitle(searchTerm: 'Atari Video Cube', priority: 2),
            ],
          ),
        ],
      );
      final config = InternalConfig(
        cloneListMetadataUrl: Uri.parse('https://example.invalid'),
        defaultRegionOrder: const ['USA'],
      );
      final games = const GameSelector()
          .select(
            dat: _dat([
              _game(
                "Rubik's Cube (USA)",
                langs: const ['En'],
                regions: const ['USA'],
              ),
              _game(
                'Atari Video Cube (USA)',
                langs: const ['En'],
                regions: const ['USA'],
              ),
            ]),
            config: config,
            scoring: ScoringConfig(
              languagePriority: const ['En'],
              regionPriority: config.defaultRegionOrder,
              priority: const [ScoreAxis.lang, ScoreAxis.ra],
            ),
            cloneList: cl,
            achievements: AchievementScope.any,
            ra: _raIndex(const ['Atari Video Cube (USA)']),
          )
          .games;
      expect(games.single.name, 'Atari Video Cube (USA)');
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
        grouper.candidates(
          _dat(games),
          null,
          normalizer: TitleNormalizer(config),
        ),
        ScoringConfig(regionPriority: ['Japan']),
      );
      expect(winners.single.game.name, 'Balance (Japan)');
    });

    test('variantRank keeps the alternative tags in precedence order', () {
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
            ScoringConfig(regionPriority: ['USA']),
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
            _game(
              'Game (USA) (Proto)',
              regions: ['USA'],
              status: ProductionStatus.prototype,
            ),
            _game('Game (USA)', regions: ['USA']),
          ]),
          null,
        ),
        ScoringConfig(regionPriority: ['USA']),
      );
      expect(winners.single.game.name, 'Game (USA)');
    });
  });

  group('the wishlist and the achievement set', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA'],
    );
    // Only Contra carries achievements; Random speaks a language the order below
    // does not admit.
    final games = [
      _game('Zelda (USA)', langs: const ['En'], regions: const ['USA']),
      _game('Metroid (USA)', langs: const ['En'], regions: const ['USA']),
      _game(
        'Contra (USA)',
        langs: const ['Es'],
        regions: const ['USA'],
        ra: true,
      ),
      _game('Random (USA)', langs: const ['Ja'], regions: const ['USA']),
    ];

    Set<String> select({
      List<String> wishlist = const [],
      WishlistMode mode = WishlistMode.absolute,
      AchievementScope? achievements,
    }) => const GameSelector()
        .select(
          dat: _dat(games),
          config: config,
          scoring: ScoringConfig(languagePriority: ['Es', 'En']),
          wishlist: wishlist,
          wishlistMode: mode,
          achievements: achievements,
          ra: _raIndex(const ['Contra (USA)']),
        )
        .games
        .map((g) => g.name)
        .toSet();

    test('parses a JSONC array of base titles', () {
      expect(
        parseWishlist('''
          [
            // case, "The" and punctuation are ignored when matching
            "Zelda",
            "Metroid"
          ]
        '''),
        ['Zelda', 'Metroid'],
      );
    });

    test('neither given restricts nothing beyond the orders', () {
      expect(select(), {'Zelda (USA)', 'Metroid (USA)', 'Contra (USA)'});
    });

    test('either one alone is the selection', () {
      expect(select(wishlist: const ['Zelda', 'Metroid']), {
        'Zelda (USA)',
        'Metroid (USA)',
      });
      expect(select(achievements: AchievementScope.any), {'Contra (USA)'});
    });

    test('an absolute wishlist unions with the achievement set', () {
      expect(
        select(wishlist: const ['Zelda'], achievements: AchievementScope.any),
        {'Zelda (USA)', 'Contra (USA)'},
      );
    });

    test('a subset wishlist intersects it instead', () {
      expect(
        select(
          wishlist: const ['Zelda', 'Contra'],
          mode: WishlistMode.subset,
          achievements: AchievementScope.any,
        ),
        {'Contra (USA)'},
      );
    });

    test('a wishlist name may be any of a title\'s regional spellings', () {
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
      expect(
        const GameSelector()
            .select(
              dat: _dat([_game('Atomic Punk (USA)'), _game('Unrelated (USA)')]),
              config: config,
              scoring: ScoringConfig(),
              wishlist: const ['Bomber Boy'],
              cloneList: cl,
            )
            .games
            .map((g) => g.name),
        ['Atomic Punk (USA)'],
      );
    });
  });

  group('an absolute wishlist outranks the language and region orders', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe', 'Spain', 'Japan'],
      regionImpliedLanguages: const {
        'USA': ['En'],
        'Europe': ['En'],
        'Spain': ['Es'],
        'Japan': ['Ja'],
      },
    );

    List<String> select(
      List<DatGame> games, {
      List<String> wishlist = const [],
      WishlistMode mode = WishlistMode.absolute,
      Set<ExcludeKind> exclude = const {},
      CloneList? cloneList,
    }) => const GameSelector()
        .select(
          dat: _dat(games),
          config: config,
          scoring: ScoringConfig(languagePriority: ['Es', 'En']),
          wishlist: wishlist,
          wishlistMode: mode,
          exclude: exclude,
          cloneList: cloneList,
        )
        .games
        .map((g) => g.name)
        .toList();

    test('a named title needs no language on the ranking order', () {
      final games = [
        _game('Wanted (Japan)', langs: const ['Ja'], regions: const ['Japan']),
        _game(
          'Unwanted (Japan)',
          langs: const ['Ja'],
          regions: const ['Japan'],
        ),
      ];
      expect(select(games), isEmpty, reason: 'neither speaks Es or En');
      expect(select(games, wishlist: const ['Wanted']), ['Wanted (Japan)']);
    });

    test('and its group still competes, so you get its best dump', () {
      // Naming a title is not the same as taking whichever dump was named:
      // language goes on ranking the group.
      final games = [
        _game('Game (Japan)', langs: const ['Ja'], regions: const ['Japan']),
        _game('Game (Spain)', langs: const ['Es'], regions: const ['Spain']),
      ];
      expect(select(games, wishlist: const ['Game']), ['Game (Spain)']);
    });

    test('while a subset wishlist is dropped by them like anything else', () {
      final games = [
        _game('Named (Japan)', langs: const ['Ja'], regions: const ['Japan']),
        _game('Spanish (Spain)', langs: const ['Es'], regions: const ['Spain']),
      ];
      expect(
        select(
          games,
          wishlist: const ['Named', 'Spanish'],
          mode: WishlistMode.subset,
        ),
        ['Spanish (Spain)'],
      );
    });

    test('membership follows the clone group, not the spelling', () {
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
      final games = [
        _game(
          'Bomber Boy (Japan)',
          langs: const ['Ja'],
          regions: const ['Japan'],
        ),
        _game(
          'Atomic Punk (Japan)',
          langs: const ['Ja'],
          regions: const ['Japan'],
        ),
      ];
      expect(
        select(games, wishlist: const ['Bomber Boy'], cloneList: cl),
        hasLength(1),
      );
    });

    test('but an exclude still means what it says', () {
      // An exclude describes what kind of dump is unwanted, which is a different
      // statement from naming a game. Naming a title must not quietly re-admit
      // its prototype or its manual.
      expect(
        select(
          [
            _game(
              'Game (Japan)',
              langs: const ['Ja'],
              regions: const ['Japan'],
              status: ProductionStatus.prototype,
            ),
          ],
          wishlist: const ['Game'],
          exclude: {ExcludeKind.preproduction},
        ),
        isEmpty,
      );
      expect(
        select(
          [
            _game('Game (Japan) (Manual)', regions: const ['Japan']),
          ],
          wishlist: const ['Game'],
          exclude: {ExcludeKind.manuals},
        ),
        isEmpty,
      );
    });
  });

  group('a fallback order settles what the caller cannot', () {
    test('Other is an ordered bucket, not a shrug', () {
      // Two languages the caller never named share the one Other slot. Without a
      // fallback they rank alike and the winner is whatever comes next; with one
      // they are ordered by it.
      final list = PriorityList(['Es', 'Other'], fallback: ['En', 'Ja', 'De']);
      expect(list.rank(['En']) < list.rank(['Ja']), isTrue);
      expect(list.rank(['Ja']) < list.rank(['De']), isTrue);
      // And a language the fallback does not name ranks below every one it does.
      expect(list.rank(['De']) < list.rank(['Ko']), isTrue);
    });

    test('and never outranks the order the caller did give', () {
      final list = PriorityList(['Es', 'Other'], fallback: ['En', 'Ja', 'De']);
      // Es is named, En only reachable through Other: Es wins regardless of the
      // fallback putting En first.
      expect(list.rank(['Es']) < list.rank(['En']), isTrue);
    });

    test('no fallback leaves ranking exactly as it was', () {
      final plain = PriorityList(['Es', 'Other']);
      expect(plain.rank(['En']), plain.rank(['Ja']));
      expect(plain.rank(['Es']) < plain.rank(['En']), isTrue);
      expect(plain.rank(['Ko']), plain.rank(['De']));
    });

    test('a list that admits nothing still admits nothing', () {
      final list = PriorityList(['Es'], fallback: ['En', 'Ja']);
      expect(list.admits(['Ja']), isFalse);
      expect(list.admits(['Es']), isTrue);
      expect(list.rank(['Ja']), GameCandidate.worst);
    });

    test('the language fallback outranks region', () {
      // `Other` covers both dumps, so the fallback decides — and it sits on the
      // language axis, weighed before region: its cross-region
      // pass runs `choose_language_top` ahead of any `region_priority` test.
      // Ranking `region` above `lang` inverts it.
      final config = InternalConfig(
        cloneListMetadataUrl: Uri.parse('https://example.invalid'),
        defaultRegionOrder: const ['Europe', 'Japan'],
      );
      final dumps = [
        _game('Game (Europe)', langs: const ['De'], regions: const ['Europe']),
        _game('Game (Japan)', langs: const ['Ja'], regions: const ['Japan']),
      ];
      String winner(List<ScoreAxis> priority) => const GameSelector()
          .select(
            dat: _dat(dumps),
            config: config,
            scoring: ScoringConfig(
              languagePriority: ['Es', 'Other'],
              regionPriority: ['Europe', 'Japan'],
              languageFallback: ['En', 'Ja', 'Es', 'Fr', 'De'],
              priority: priority,
            ),
          )
          .games
          .single
          .name;
      expect(winner([ScoreAxis.lang, ScoreAxis.region]), 'Game (Japan)');
      expect(winner([ScoreAxis.region, ScoreAxis.lang]), 'Game (Europe)');
    });

    test('the default language order follows the region order', () {
      // Derived rather than invented: no arbitrary ranking of languages, just
      // the one the region order already implies.
      final config = InternalConfig(
        cloneListMetadataUrl: Uri.parse('https://example.invalid'),
        defaultRegionOrder: const ['USA', 'Japan', 'Spain'],
        regionImpliedLanguages: const {
          'USA': ['En'],
          'Japan': ['Ja'],
          'Spain': ['Es'],
        },
      );
      expect(config.defaultLanguageOrder, ['En', 'Ja', 'Es']);
    });
  });

  group('TitleNormalizer builds the clone key', () {
    final normalizer = TitleNormalizer(
      InternalConfig(
        cloneListMetadataUrl: Uri.parse('https://example.invalid'),
        languages: const {'English': 'En(?:-[A-Z][A-Z])?', 'Spanish': 'Es'},
        defaultRegionOrder: const ['USA', 'Europe', 'Japan', 'Australia'],
        ignoreTags: const [TagPattern('(DSiWare)')],
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

    test('drops the dump-variant tags that must stay out of the key', () {
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
      expect(normalizer.shortName('Game (USA) (V.Smile)'), 'game v smile');
    });

    test('keeps edition qualifiers, so both variants survive 1G1R', () {
      // Both the standalone release and its compilation entry survive.
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

  group('--lang ranks and restricts', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe', 'Germany'],
    );

    List<String> select(List<DatGame> games, List<String> langs) =>
        const GameSelector()
            .select(
              dat: _dat(games),
              config: config,
              scoring: ScoringConfig(languagePriority: langs),
            )
            .games
            .map((g) => g.name)
            .toList();

    final mixed = [
      _game('German (Germany)', langs: const ['De']),
      _game('English (USA)', langs: const ['En']),
    ];

    test('drops a title speaking nothing on the list', () {
      expect(select(mixed, const ['Es', 'En']), ['English (USA)']);
    });

    test('Other gives every unlisted language a place', () {
      expect(select(mixed, const ['Es', 'En', 'Other']), hasLength(2));
    });

    test('where Other sits decides how unlisted languages rank', () {
      // Both dumps are one clone group, so only the better-ranked one survives.
      final group = [
        _game(
          'Game (Germany)',
          langs: const ['De'],
          regions: const ['Germany'],
        ),
        _game('Game (USA)', langs: const ['En'], regions: const ['USA']),
      ];
      expect(select(group, const ['Other', 'En']), ['Game (Germany)']);
      expect(select(group, const ['En', 'Other']), ['Game (USA)']);
    });

    test('a listed entry covers its subtags', () {
      final games = [
        _game('Regional (USA)', langs: const ['Es-MX']),
      ];
      expect(select(games, const ['Es']), ['Regional (USA)']);
    });

    test('Unknown places titles the DAT says nothing about', () {
      final games = [_game('Silent (Germany)')];
      expect(select(games, const ['En']), isEmpty);
      expect(select(games, const ['En', 'Unknown']), ['Silent (Germany)']);
      // Other covers missing data too, unless Unknown claims it.
      expect(select(games, const ['En', 'Other']), ['Silent (Germany)']);
    });
  });

  group('--region ranks and restricts', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe', 'Japan', 'Unknown'],
    );

    SelectionResult select(List<DatGame> games, List<String> regions) =>
        const GameSelector().select(
          dat: _dat(games),
          config: config,
          scoring: ScoringConfig(regionPriority: regions),
        );

    test('drops titles from a region the list omits', () {
      final result = select(
        [
          _game('Keep (USA)', regions: const ['USA']),
          _game('Away (Japan)', regions: const ['Japan']),
        ],
        const ['USA', 'Europe'],
      );
      expect(result.games.map((g) => g.name), ['Keep (USA)']);
      expect(result.stats.region, 1);
      expect(result.stats.reasons, contains('region -1'));
    });

    test('an untagged title counts as Unknown', () {
      final untagged = [_game('Homebrew')];
      // The full order ends with `Unknown`, so a default run keeps it.
      expect(select(untagged, config.defaultRegionOrder).games, hasLength(1));
      expect(select(untagged, const ['USA']).games, isEmpty);
    });

    test('Other keeps the regions the list leaves out', () {
      final result = select(
        [
          _game('Keep (USA)', regions: const ['USA']),
          _game('Away (Japan)', regions: const ['Japan']),
        ],
        const ['USA', 'Other'],
      );
      expect(result.games, hasLength(2));
      expect(result.stats.region, 0);
    });

    test('an empty region list restricts nothing', () {
      final result = select([
        _game('Odd (Ukraine)', regions: const ['Ukraine']),
      ], const []);
      expect(result.games, hasLength(1));
      expect(result.stats.region, 0);
    });
  });

  group('--priority orders the contested tie-breaks', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Europe', 'Japan'],
    );

    // One clone group: the English dump has no achievements, the Japanese one
    // does, and the caller ranks English above Japanese.
    final group = [
      _game(
        'Metal Gear (Europe)',
        langs: const ['En'],
        regions: const ['Europe'],
      ),
      _game(
        'Metal Gear (Japan)',
        langs: const ['Ja'],
        regions: const ['Japan'],
      ),
    ];

    List<String> select(List<ScoreAxis> priority) => const GameSelector()
        .select(
          dat: _dat(group),
          config: config,
          scoring: ScoringConfig(
            languagePriority: const ['En', 'Ja'],
            regionPriority: config.defaultRegionOrder,
            priority: priority,
          ),
          ra: _raIndex(const ['Metal Gear (Japan)']),
        )
        .games
        .map((g) => g.name)
        .toList();

    test('language first keeps the language, achievements first the dump', () {
      expect(select(const [ScoreAxis.lang, ScoreAxis.ra]), [
        'Metal Gear (Europe)',
      ]);
      expect(select(const [ScoreAxis.ra, ScoreAxis.lang]), [
        'Metal Gear (Japan)',
      ]);
    });

    test('an axis left out plays no part', () {
      // Region alone would pick Europe; with region omitted, language decides.
      expect(select(const [ScoreAxis.lang]), ['Metal Gear (Europe)']);
      expect(select(const [ScoreAxis.region]), ['Metal Gear (Europe)']);
    });

    test('achievements outrank the (Alt) and revision tie-breaks', () {
      final dumps = [
        _game('Balance (Japan)', regions: const ['Japan'], revision: 1),
        _game('Balance (Japan) (Alt)', regions: const ['Japan']),
      ];
      final winners = const GameSelector()
          .select(
            dat: _dat(dumps),
            config: config,
            scoring: ScoringConfig(regionPriority: ['Japan']),
            ra: _raIndex(const ['Balance (Japan) (Alt)']),
          )
          .games;
      expect(winners.single.name, 'Balance (Japan) (Alt)');
    });

    // Two differently-named clones, as the clonelist pairs
    // `Adventures of Star Saver, The` with `Rubble Saver`.
    final questGroup = CloneList(
      name: 'x',
      variants: [
        VariantGroup(
          group: 'Quest',
          titles: const [
            VariantTitle(searchTerm: 'Zebra Quest'),
            VariantTitle(searchTerm: 'Alpha Quest'),
          ],
        ),
      ],
    );
    final dumps = [
      _game('Zebra Quest (Japan)', regions: const ['Japan']),
      _game('Alpha Quest (USA)', regions: const ['USA']),
    ];

    test('a hash-verified dump beats one RA only reaches by name', () {
      // RA sometimes hashes a good but undocumented variant, so the No-Intro
      // entry it names is only reachable by title. Both clones then "have
      // achievements", and ungraded the group falls to the alphabetical
      // fail-safe — which here would hand the slot to Zebra, the dump nobody
      // verified.
      final ra = RetroAchievementsIndex('test', const [
        // Hashed against the USA dump...
        RetroAchievementsEntry(
          name: 'Alpha Quest (USA)',
          crc32: 'Alpha Quest (USA)',
        ),
        // ...and against a variant of the Japanese one no DAT carries, so only
        // its name bridges back.
        RetroAchievementsEntry(
          name: 'Zebra Quest (Japan)',
          crc32: 'undocumented-variant',
        ),
      ]);
      final winners = const GameSelector()
          .select(
            dat: _dat(dumps),
            config: config,
            // Region left out on purpose: the grading has to decide alone.
            scoring: ScoringConfig(priority: [ScoreAxis.ra]),
            cloneList: questGroup,
            ra: ra,
          )
          .games;
      expect(winners.single.name, 'Alpha Quest (USA)');
    });

    test('two hash-verified dumps are then separated by region', () {
      // Two regions are never pitted against each other on anything but
      // region order — its whole tie-break chain runs inside one region. So
      // leaving `region` out of --priority must not promote the alphabetical
      // fail-safe into deciding this; it would hand the slot to Zebra.
      final winners = const GameSelector()
          .select(
            dat: _dat(dumps),
            config: config,
            scoring: ScoringConfig(
              priority: [ScoreAxis.ra],
              regionPriority: ['USA', 'Japan'],
            ),
            cloneList: questGroup,
            ra: _raIndex(const ['Zebra Quest (Japan)', 'Alpha Quest (USA)']),
          )
          .games;
      expect(winners.single.name, 'Alpha Quest (USA)');
    });

    test('and the fail-safe only decides once region cannot', () {
      // Same region on both sides: nothing left to say, so the highest name
      // wins, resolved per region for exactly this case.
      final sameRegion = [
        _game('Zebra Quest (USA)', regions: const ['USA'], ra: true),
        _game('Alpha Quest (USA)', regions: const ['USA'], ra: true),
      ];
      final winners = const GameSelector()
          .select(
            dat: _dat(sameRegion),
            config: config,
            scoring: ScoringConfig(
              priority: [ScoreAxis.ra],
              regionPriority: ['USA', 'Japan'],
            ),
            cloneList: questGroup,
            ra: _raIndex(const ['Zebra Quest (USA)', 'Alpha Quest (USA)']),
          )
          .games;
      expect(winners.single.name, 'Zebra Quest (USA)');
    });

    test('region still cannot outrank an axis the caller ranked above it', () {
      // The point of leaving `region` out is that it must not beat language or
      // achievements — only that it still breaks what they leave tied.
      final winners = const GameSelector()
          .select(
            dat: _dat([
              _game('Zebra Quest (Japan)', regions: const ['Japan'], ra: true),
              _game('Alpha Quest (USA)', regions: const ['USA']),
            ]),
            config: config,
            scoring: ScoringConfig(
              priority: [ScoreAxis.ra],
              regionPriority: ['USA', 'Japan'],
            ),
            cloneList: questGroup,
            ra: _raIndex(const ['Zebra Quest (Japan)']),
          )
          .games;
      expect(winners.single.name, 'Zebra Quest (Japan)');
    });
  });

  group('--achievements chooses how strong a claim it wants', () {
    final config = InternalConfig(
      cloneListMetadataUrl: Uri.parse('https://example.invalid'),
      defaultRegionOrder: const ['USA', 'Japan'],
    );

    List<String> select(AchievementScope scope) => const GameSelector()
        .select(
          dat: _dat([
            _game(
              'Metal Gear (USA)',
              langs: const ['En'],
              regions: const ['USA'],
            ),
            _game(
              'Metal Gear (Japan)',
              langs: const ['Ja'],
              regions: const ['Japan'],
            ),
            _game(
              'No Achievements (USA)',
              langs: const ['En'],
              regions: const ['USA'],
            ),
          ]),
          config: config,
          scoring: ScoringConfig(
            languagePriority: ['En', 'Ja'],
            regionPriority: ['USA', 'Japan'],
          ),
          achievements: scope,
          ra: _raIndex(const ['Metal Gear (Japan)']),
        )
        .games
        .map((g) => g.name)
        .toList();

    test('any keeps the title and lets --priority pick the dump', () {
      expect(select(AchievementScope.any), ['Metal Gear (USA)']);
    });

    test('approved keeps only the dumps the set was authored against', () {
      // It narrows before the contest, so the approved dump wins its group
      // instead of the title being dropped for losing it.
      expect(select(AchievementScope.approved), ['Metal Gear (Japan)']);
    });

    test('and an absolute wishlist still passes without approval', () {
      expect(
        const GameSelector()
            .select(
              dat: _dat([
                _game(
                  'Metal Gear (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                ),
                _game(
                  'No Achievements (USA)',
                  langs: const ['En'],
                  regions: const ['USA'],
                ),
              ]),
              config: config,
              scoring: ScoringConfig(languagePriority: ['En']),
              wishlist: const ['No Achievements'],
              achievements: AchievementScope.approved,
              ra: _raIndex(const ['Metal Gear (USA)']),
            )
            .games
            .map((g) => g.name)
            .toSet(),
        {'Metal Gear (USA)', 'No Achievements (USA)'},
      );
    });
  });

  group('SelectionStats', () {
    test('attributes every dropped title to one reason', () {
      final result = const GameSelector().select(
        dat: _dat([
          _game('Keep (USA)', langs: const ['En'], regions: const ['USA']),
          // 1G1R runner-up.
          _game(
            'Keep (Europe)',
            langs: const ['En'],
            regions: const ['Europe'],
          ),
          _game(
            'Proto (USA)',
            langs: const ['En'],
            regions: const ['USA'],
            status: ProductionStatus.prototype,
          ),
          _game(
            'Solo (Germany)',
            langs: const ['De'],
            regions: const ['Germany'],
          ),
        ]),
        config: InternalConfig(
          cloneListMetadataUrl: Uri.parse('https://example.invalid'),
          defaultRegionOrder: const ['USA', 'Europe', 'Germany'],
        ),
        scoring: ScoringConfig(
          languagePriority: ['En'],
          regionPriority: ['USA', 'Europe'],
        ),
        exclude: const {ExcludeKind.preproduction},
      );

      final s = result.stats;
      expect(s.total, 4);
      expect(s.excluded, 1);
      expect(s.language, 1);
      expect(s.clones, 1);
      expect(s.selected, 1);
      expect(result.games.single.name, 'Keep (USA)');
      expect(
        s.total -
            s.excluded -
            s.language -
            s.region -
            s.clones -
            s.represented -
            s.wanted,
        s.selected,
        reason: 'the funnel must balance',
      );
      expect(s.reasons, ['exclude -1', 'language -1', '1g1r -1']);
    });
  });
}
