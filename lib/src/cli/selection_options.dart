/// The selection option set (`--lang`, `--wishlist`, `--exclude`, ...) and its
/// resolution into a `GameSelector` run.
///
/// Kept out of `runner.dart` so that file stays the command registry; stages
/// that act on the filtered set opt in with `with SelectionCommand`.
library;

import 'dart:io';

import 'package:args/args.dart';

import '../data/dat_loader.dart';
import '../data/metadata_repository.dart';
import '../domain/auditor.dart';
import '../domain/selection.dart';
import '../models/dat.dart';
import '../models/metadata.dart';
import 'runner.dart';

/// One DAT paired with its selection outcome.
typedef SelectedTarget = ({DatFile dat, SelectionResult selection});

extension SelectedTargetX on SelectedTarget {
  List<DatGame> get games => selection.games;

  /// The selected games as a DAT, for the stages that audit against one.
  DatFile get target => DatFile(header: dat.header, games: selection.games);

  /// The games whose clone group already has a dump settled inside a curated
  /// folder. Fetching another dump of one of these would put a second copy of the
  /// same game beside work built against the first.
  ///
  /// A pack answers for every group it holds, so owning any one of its games
  /// settles it too — otherwise a curated single release would be duplicated by
  /// the bundle that contains it.
  Set<String> settledByCuratedGroup(AuditReport report) {
    final settled = {
      for (final name in report.library.curatedGames)
        ...?selection.groups[name],
    };
    if (settled.isEmpty) return const {};
    return {
      for (final entry in selection.groups.entries)
        if (entry.value.any(settled.contains)) entry.key,
    };
  }

  /// `404 -> 309  (exclude -55, language -30, 1g1r -10)`
  String get funnel {
    final s = selection.stats;
    final why = s.reasons.isEmpty ? '' : '  (${s.reasons.join(', ')})';
    return '${s.total} -> ${s.selected}$why';
  }
}

/// The selection argument group, as a `package:args` separator block.
extension SelectionFlags on ArgParser {
  void addSelectionFlags() {
    addSeparator('Selection:');
    addMultiOption(
      'lang',
      valueHelp: 'code',
      defaultsTo: const ['En'],
      help:
          'Language priority, best first (e.g. Es,Es-MX,En,Ja). Ranks the dumps '
          'of a title and drops a title speaking nothing on the list, so naming '
          'one language gives you that set. Add "Other" to give every unlisted '
          'language a place and "Unknown" for titles with no language at all — '
          'both rank wherever you put them. Asking for Es accepts Es-MX.',
    );
    addMultiOption(
      'region',
      valueHelp: 'name',
      help:
          'Region priority, best first (e.g. Spain,USA,Europe,Japan). Ranks and '
          'restricts like --lang, with the same "Other" and "Unknown" entries; '
          'untagged titles count as Unknown. Defaults to the full region order, '
          'which lists every region and so drops nothing.',
    );
    addMultiOption(
      'priority',
      valueHelp: 'axis',
      allowed: ScoreAxis.values.map((a) => a.name),
      defaultsTo: ScoringConfig.defaultPriority.map((a) => a.name).toList(),
      allowedHelp: {
        'lang': 'Rank by --lang order.',
        'region': 'Rank by --region order.',
        'ra':
            'Rank titles that carry achievements first, a hash-verified dump '
            'ahead of one only matched by name.',
      },
      help:
          'Which tie-breaks decide a clone group, best first. region keeps a '
          'fixed place below the others even when left out, so naming it only '
          'lifts it above the axes you did list; lang and ra left out play no '
          'part at all.',
    );
    addOption(
      'wishlist',
      valueHelp: 'path',
      help:
          'JSON/JSONC file holding an array of game names to select. A name may '
          'be any of a title\'s regional spellings, and naming a multi-game pack '
          'asks for the pack rather than for each title in it.',
    );
    addOption(
      'wishlist-mode',
      valueHelp: 'mode',
      allowed: WishlistMode.values.map((m) => m.name),
      defaultsTo: WishlistMode.absolute.name,
      allowedHelp: {
        'absolute':
            'A set of its own, ranked above --lang and --region: everything you '
            'named is selected, those orders only pick which of its dumps, and '
            '--achievements adds to it instead of cutting it down.',
        'subset':
            'One condition among the others: a named title still has to pass '
            '--lang, --region and --achievements.',
      },
      help: 'What naming a title claims about it.',
    );
    addOption(
      'achievements',
      valueHelp: 'scope',
      allowed: AchievementScope.values.map((s) => s.name),
      allowedHelp: {
        'any':
            'Titles with achievements on any of their dumps, leaving --priority '
            'to pick which dump represents them.',
        'approved':
            'Only the dumps the achievement set was authored against, matching '
            'their hashes exactly.',
      },
      help:
          'Select only titles with RetroAchievements support. Omit it and '
          'achievements restrict nothing, though --priority ra still ranks them.',
    );
    addOption(
      'supersets',
      valueHelp: 'mode',
      allowed: SupersetMode.values.map((m) => m.name),
      defaultsTo: SupersetMode.prefer.name,
      allowedHelp: {
        'prefer':
            'The subsuming edition represents its group and takes its slot, the '
            'way a higher revision does.',
        'ignore': 'Set the claim aside and take a plain release.',
      },
      help:
          'What an edition that subsumes the rest of its group is worth against '
          'it. Same game, more in it, so it is preferred by default.',
    );
    addOption(
      'compilations',
      valueHelp: 'mode',
      allowed: CompilationMode.values.map((m) => m.name),
      defaultsTo: CompilationMode.fill.name,
      allowedHelp: {
        'never': 'A pack never stands in for the games it holds.',
        'fill':
            'It stands in for them but ranks last, so it wins only a group with '
            'no release of its own.',
        'prefer': 'It takes their slots, though --priority still comes first.',
        'first': 'It takes their slots ahead of --priority too.',
      },
      help:
          'What a pack holding several games is worth against them. A bundle is '
          'no improvement on any one of them, so it yields by default.',
    );
    addMultiOption(
      'exclude',
      valueHelp: 'kind',
      allowed: ExcludeKind.values.map((k) => k.cli),
      help:
          'Drop these kinds of dump outright. Each is recognized by the DAT '
          'category, the clonelist category and the name, so a trial disc counts '
          'as one however it is spelled. Excludes always apply, the wishlist '
          'included.',
    );
  }
}

/// The resolved selection options bound to the repository they were read
/// against, so [select] needs nothing but a DAT.
final class SelectionContext {
  const SelectionContext({
    required this.repo,
    required this.config,
    required this.scoring,
    required this.wishlist,
    required this.wishlistMode,
    required this.achievements,
    required this.exclude,
    this.selector = const GameSelector(),
  });

  final MetadataRepository repo;
  final InternalConfig config;
  final ScoringConfig scoring;
  final List<String> wishlist;
  final WishlistMode wishlistMode;
  final AchievementScope? achievements;
  final Set<ExcludeKind> exclude;
  final GameSelector selector;

  /// Runs the full pipeline for one DAT, pulling its clonelist/metadata/RA/MIA
  /// assets from [repo].
  Future<SelectionResult> select(DatFile dat) async {
    final (name, flavor) = (dat.header.name, dat.header.flavor);
    return selector.select(
      dat: dat,
      config: config,
      scoring: scoring,
      wishlist: wishlist,
      wishlistMode: wishlistMode,
      achievements: achievements,
      exclude: exclude,
      cloneList: await repo.cloneList(name, flavor),
      metadata: await repo.metadata(name, flavor),
      ra: await repo.retroAchievements(name, dat: dat),
      mias: await repo.mias(name, flavor),
    );
  }
}

/// For commands that act on the filtered set. Call `argParser.addSelectionFlags()`
/// from the constructor, then [loadSelectedTargets] (or [selectionContext], when
/// the command already owns a repository) from `run()`.
mixin SelectionCommand on ArchivistCommand {
  Future<SelectionContext> selectionContext(MetadataRepository repo) async {
    final r = argResults!;
    final config = await repo.config();
    final wishlistPath = r.option('wishlist');
    return SelectionContext(
      repo: repo,
      config: config,
      scoring: ScoringConfig(
        languagePriority: r.multiOption('lang'),
        // Without --region the full order ranks everything, `Unknown` included.
        regionPriority: r.multiOption('region').isEmpty
            ? config.defaultRegionOrder
            : r.multiOption('region'),
        // What settles values the lists above land on one position — everything
        // sharing an `Other` slot, chiefly. Without these the winner among them
        // is whatever the next tie-break happens to say, down to alphabetical.
        languageFallback: config.defaultLanguageOrder,
        regionFallback: config.defaultRegionOrder,
        priority: [
          for (final axis in r.multiOption('priority'))
            ScoreAxis.values.byName(axis),
        ],
        supersets: SupersetMode.values.byName(r.option('supersets')!),
        compilations: CompilationMode.values.byName(r.option('compilations')!),
      ),
      wishlist: wishlistPath == null
          ? const []
          : parseWishlist(await File(wishlistPath).readAsString()),
      wishlistMode: WishlistMode.values.byName(r.option('wishlist-mode')!),
      achievements: switch (r.option('achievements')) {
        final scope? => AchievementScope.values.byName(scope),
        null => null,
      },
      exclude: {
        for (final kind in r.multiOption('exclude')) ?ExcludeKind.byCli(kind),
      },
    );
  }

  /// Loads every `--dat` and selects from it, so callers never see a game that
  /// filtering discarded.
  Future<List<SelectedTarget>> loadSelectedTargets() async {
    final repo = RemoteMetadataRepository(cacheDir: cacheDir);
    try {
      final selection = await selectionContext(repo);
      const loader = DatLoader();
      final targets = <SelectedTarget>[];
      for (final path in datPaths) {
        for (final dat in await loader.loadPath(path)) {
          targets.add((dat: dat, selection: await selection.select(dat)));
        }
      }
      return targets;
    } finally {
      repo.close();
    }
  }
}
