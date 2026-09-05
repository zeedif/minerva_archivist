import '../models/dat.dart';
import '../models/metadata.dart';

/// Fills in each game's regions, languages, local name, RetroAchievements
/// support and MIA status from the metadata repo.
///
/// Clone grouping is `CloneGrouper`'s job; this only touches per-game data.
final class DatEnricher {
  const DatEnricher();

  DatFile enrich(
    DatFile dat, {
    required InternalConfig config,
    CloneList? cloneList,
    SystemMetadata? metadata,
    RetroAchievementsIndex? ra,
    MiaList? mias,
  }) {
    final regionSet = config.defaultRegionOrder.toSet();

    // Hash joining is partial, not all-or-nothing: a disc DAT reaches no RA entry
    // at all, since RA hashes the primary executable, and a re-hashed flavor
    // reaches some. Scoping the name fallback to the entries no hash reaches
    // covers both without letting a name stand in for an already-claimed dump.
    //
    // Kept as raw names, not just a set of matched keys: a same-named RA entry
    // that also tags a region only speaks for the sibling wearing that region,
    // not for all of them — see `_raMatchFor`.
    final beyondHashes =
        ra?.unclaimedEntryNames(dat.games) ?? const <String, List<String>>{};

    final games = <DatGame>[];
    for (final g in dat.games) {
      final regions = _regionsFromTags(g.metadata.rawTags, regionSet);
      var effectiveRegions = regions.isNotEmpty ? regions : g.metadata.regions;
      // An untagged title carries the region `Unknown`, so region ranking and
      // filtering have a value to work with.
      if (effectiveRegions.isEmpty) effectiveRegions = const ['Unknown'];

      final md = metadata?[g.name];
      final languages = <String>[...g.metadata.languages];
      for (final l in md?.languages ?? const <String>[]) {
        if (!languages.contains(l)) languages.add(l);
      }
      if (languages.isEmpty) {
        for (final r in effectiveRegions) {
          for (final code in config.regionImpliedLanguages[r] ?? const <String>[]) {
            if (!languages.contains(code)) languages.add(code);
          }
        }
      }

      final status = (mias != null && _isMia(g, mias))
          ? ProductionStatus.mia
          : g.metadata.status;

      games.add(
        g.copyWith(
          metadata: g.metadata.copyWith(
            regions: effectiveRegions,
            languages: languages,
            localName: md?.localName ?? g.metadata.localName,
            status: status,
          ),
          retroAchievements: ra == null
              ? RaMatch.none
              : ra.supportsGame(g)
              ? RaMatch.byHash
              : _nameMatchFor(g, effectiveRegions, beyondHashes, regionSet),
        ),
      );
    }

    return DatFile(header: dat.header, games: games);
  }

  /// A game is MIA when any of its ROMs is.
  ///
  /// Matched on CRC alone, since a name match after a redump or rename is a
  /// false positive. The name set is only a fallback for entries the list
  /// publishes without a CRC.
  bool _isMia(DatGame g, MiaList mias) {
    for (final r in g.roms) {
      final crc = r.crc32;
      if (crc != null) {
        if (mias.containsCrc(crc)) return true;
      } else if (mias.containsName(r.name)) {
        return true;
      }
    }
    return false;
  }

  List<String> _regionsFromTags(Set<String> tags, Set<String> regionSet) {
    for (final t in tags) {
      final parts = t.split(',').map((e) => e.trim()).toList();
      if (parts.isNotEmpty && parts.every(regionSet.contains)) return parts;
    }
    return const [];
  }

  /// The RA name join for [g], given the raw entry names sharing its
  /// normalized title that no hash reaches (see [unclaimedEntryNames]).
  ///
  /// An entry that names a region only speaks for the sibling wearing that
  /// region: [RaMatch.byNameRegion] when [g] is the one it names,
  /// [RaMatch.none] when it names a *different* one — never the same credit
  /// regardless of region. An entry naming no region at all is the original,
  /// genuinely region-free case, so every sibling still gets [RaMatch.byName].
  RaMatch _nameMatchFor(
    DatGame g,
    List<String> effectiveRegions,
    Map<String, List<String>> beyondHashes,
    Set<String> regionSet,
  ) {
    final entryNames = beyondHashes[RetroAchievementsIndex.normalize(g.name)];
    if (entryNames == null) return RaMatch.none;

    var regionFree = false;
    for (final name in entryNames) {
      final entryRegions = _regionsFromTags(_tagsOf(name), regionSet);
      if (entryRegions.isEmpty) {
        regionFree = true;
      } else if (entryRegions.any(effectiveRegions.contains)) {
        return RaMatch.byNameRegion;
      }
    }
    return regionFree ? RaMatch.byName : RaMatch.none;
  }

  Set<String> _tagsOf(String name) => {
    for (final m in RegExp(r'\(([^)]*)\)').allMatches(name))
      if (m.group(1) != null) m.group(1)!.trim(),
  };
}
