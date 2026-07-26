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

    // Carts match RA by raw hash. Disc systems don't (RA uses a special
    // primary-executable hash), so fall back to region-free name matching only
    // when hash matching yields nothing across the whole DAT.
    final raHashHits = ra == null ? 0 : dat.games.where(ra.supportsGame).length;
    final useNameFallback = ra != null && ra.isNotEmpty && raHashHits == 0;

    final games = <DatGame>[];
    for (final g in dat.games) {
      final regions = _regionsFromTags(g.metadata.rawTags, regionSet);
      final effectiveRegions = regions.isNotEmpty ? regions : g.metadata.regions;

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
          supportsRetroAchievements: ra == null
              ? false
              : (ra.supportsGame(g) ||
                    (useNameFallback && ra.supportsName(g.name))),
        ),
      );
    }

    return DatFile(header: dat.header, games: games);
  }

  /// A game is MIA when any of its ROMs is.
  ///
  /// Retool matches on CRC alone — a name match after a redump/rename is a
  /// false positive — so the name set is only a fallback for entries the MIA
  /// list publishes without a CRC.
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
}
