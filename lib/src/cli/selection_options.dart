/// The selection option set (`--lang`, `--wishlist`, `--exclude-*`, ...) and its
/// resolution into a `GameSelector` run.
///
/// Kept out of `runner.dart` so that file stays the command registry; stages
/// that act on the filtered set opt in with `with SelectionCommand`.
library;

import 'dart:io';

import 'package:args/args.dart';

import '../data/dat_loader.dart';
import '../data/metadata_repository.dart';
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

  /// `404 -> 309  (status -55, category -30, 1g1r -10)`
  String get funnel {
    final s = selection.stats;
    final why = s.reasons.isEmpty ? '' : '  (${s.reasons.join(', ')})';
    return '${s.total} -> ${s.selected}$why';
  }
}

/// Retool's `exclusions` argument group, as a `package:args` separator block.
extension SelectionFlags on ArgParser {
  void addSelectionFlags() {
    addSeparator('Selection:');
    addMultiOption(
      'lang',
      valueHelp: 'code',
      defaultsTo: const ['En'],
      help:
          'Language priority, best first (e.g. Es,Es-MX,En,Ja). Ranking only — '
          'a title is never dropped for lacking a language.',
    );
    addFlag(
      'filter-languages',
      abbr: 'l',
      negatable: false,
      help:
          'Also *drop* titles that support none of --lang (Retool\'s -l). '
          'Titles whose languages are unknown are kept.',
    );
    addOption(
      'wishlist',
      valueHelp: 'path',
      help: 'JSON/JSONC file holding an array of game names to keep.',
    );
    addFlag(
      'retroachievements',
      abbr: 'a',
      negatable: false,
      help: 'Keep RetroAchievements-supported titles.',
    );
    addOption(
      'combine',
      valueHelp: 'mode',
      allowed: FilterCombineMode.values.map((m) => m.name),
      defaultsTo: FilterCombineMode.or.name,
      allowedHelp: {
        'or': 'Union: wishlisted titles plus RetroAchievements titles.',
        'and': 'Intersection: wishlisted titles that also have achievements.',
      },
      help: 'How --wishlist and --retroachievements combine.',
    );
    addMultiOption(
      'exclude-status',
      valueHelp: 'status',
      allowed: ProductionStatus.values.map((s) => s.name),
      help: 'Drop games with these production statuses.',
    );
    addMultiOption(
      'exclude-category',
      valueHelp: 'name',
      help:
          'Drop games whose DAT or clonelist category contains any of these '
          '(case-insensitive), e.g. Applications,Manuals,Video,Coverdiscs.',
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
    required this.includeRetroAchievements,
    required this.combine,
    required this.excludeStatuses,
    required this.excludeCategories,
    required this.filterLanguages,
    this.selector = const GameSelector(),
  });

  final MetadataRepository repo;
  final InternalConfig config;
  final ScoringConfig scoring;
  final List<String> wishlist;
  final bool includeRetroAchievements;
  final FilterCombineMode combine;
  final Set<ProductionStatus> excludeStatuses;
  final Set<String> excludeCategories;
  final bool filterLanguages;
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
      includeRetroAchievements: includeRetroAchievements,
      combine: combine,
      excludeStatuses: excludeStatuses,
      excludeCategories: excludeCategories,
      filterLanguages: filterLanguages,
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
        regionPriority: config.defaultRegionOrder,
      ),
      wishlist: wishlistPath == null
          ? const []
          : parseWishlist(await File(wishlistPath).readAsString()),
      includeRetroAchievements: r.flag('retroachievements'),
      combine: FilterCombineMode.values.byName(r.option('combine')!),
      excludeStatuses: {
        for (final s in r.multiOption('exclude-status'))
          ProductionStatus.values.byName(s),
      },
      excludeCategories: r.multiOption('exclude-category').toSet(),
      filterLanguages: r.flag('filter-languages'),
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
