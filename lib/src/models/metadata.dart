/// Domain mirrors of the `unexpectedpanda/retool-clonelists-metadata` assets:
/// `clonelists/`, `metadata/`, `mias/`, `retroachievements/`, and
/// `config/internal-config.json`.
library;

import 'dat.dart';

// --- clonelists/<System> (<Flavor>).json -----------------------------------

/// How a clonelist `searchTerm` is matched against a DAT game name. Mirrors
/// `nameType`, whose default is [short].
enum TitleMatch {
  /// The clone key: the name with region, language and dump-variant tags
  /// dropped.
  short,

  /// The full DAT game name, exactly as written.
  full,

  /// The full name with only its region and language tags dropped, so every
  /// other qualifier still has to match.
  regionFree,

  /// A case-insensitive regular expression over the full name.
  regex,
}

/// A region/language/name test that a [VariantFilter] requires. Every condition
/// present must hold for the filter to fire.
final class FilterConditions {
  const FilterConditions({
    this.matchRegions = const [],
    this.matchLanguages = const [],
    this.matchString,
    this.regionOrder,
  });

  /// Every region listed must be one of the title's regions.
  final List<String> matchRegions;

  /// Every language listed must be one of the title's languages.
  final List<String> matchLanguages;

  /// Regular expression that must be found in the full game name.
  final String? matchString;

  /// A test on the *user's* region priority rather than on the title.
  final RegionOrderCondition? regionOrder;
}

/// True when any of [higherRegions] outranks every one of [lowerRegions] in the
/// user's region priority — the hook clonelists use to say "only split this
/// title out when the user actually prefers the other region".
final class RegionOrderCondition {
  const RegionOrderCondition({
    this.higherRegions = const [],
    this.lowerRegions = const [],
  });

  /// The wildcard for "every region not named on the other side".
  static const allOtherRegions = 'All other regions';

  final List<String> higherRegions;
  final List<String> lowerRegions;
}

/// What a matching [VariantFilter] changes about a title.
final class FilterResults {
  const FilterResults({
    this.group,
    this.priority,
    this.categories,
    this.localNames,
    this.englishFriendly,
    this.superset,
  });

  /// Moves the title into its own group, so it stops competing for the 1G1R
  /// slot. The hook for releases that share a title but are different games.
  final String? group;

  final int? priority;
  final List<String>? categories;

  /// Native display names keyed by language *name* (`spanish`, `german`).
  final Map<String, String>? localNames;

  /// Marks a title playable in English even though its tags don't say so.
  final bool? englishFriendly;

  /// Marks the title a superset of its group: an edition that subsumes the
  /// others and so represents them in 1G1R.
  final bool? superset;
}

/// One `filters[]` entry: [conditions] that must all hold, and the [results]
/// applied to the title when they do.
final class VariantFilter {
  const VariantFilter({
    this.conditions = const FilterConditions(),
    this.results = const FilterResults(),
  });

  final FilterConditions conditions;
  final FilterResults results;
}

/// A single title within a clone group, matched against a DAT game name as
/// [match] dictates. Mirrors `variants[].titles[]`.
final class VariantTitle {
  const VariantTitle({
    required this.searchTerm,
    this.match = TitleMatch.short,
    this.priority,
    this.titlePosition,
    this.categories,
    this.englishFriendly = false,
    this.filters = const [],
    this.localNames,
  });

  final String searchTerm;

  /// Which form of the DAT name [searchTerm] is compared against.
  final TitleMatch match;

  /// Resolution order within the group (lower = preferred).
  final int? priority;

  /// For compilation members: position of this title inside the pack.
  final int? titlePosition;

  /// Overrides the group's categories for this title alone.
  final List<String>? categories;

  /// Playable in English despite carrying no `En` language tag.
  final bool englishFriendly;

  /// Conditional remaps, evaluated in order.
  final List<VariantFilter> filters;

  /// Non-English display names keyed by language code.
  final Map<String, String>? localNames;
}

/// A clone group bundling related titles, multi-game compilations, and supersets
/// (editions that subsume other group members) under a canonical [group] name.
final class VariantGroup {
  const VariantGroup({
    required this.group,
    this.titles = const [],
    this.compilations = const [],
    this.supersets = const [],
    this.categories = const [],
  });

  final String group;
  final List<VariantTitle> titles;
  final List<VariantTitle> compilations;
  final List<VariantTitle> supersets;

  /// e.g. `['Applications']`, `['Applications', 'Educational']`.
  final List<String> categories;

  /// Every title that belongs to the group, whatever its role.
  Iterable<VariantTitle> get allTitles => [...titles, ...compilations, ...supersets];
}

/// The parsed contents of one clonelist file.
final class CloneList {
  const CloneList({required this.name, required this.variants});

  final String name;
  final List<VariantGroup> variants;
}

// --- metadata/<System> (<Flavor>).json --------------------------------------

/// Per-title metadata that supplements what the filename encodes — chiefly
/// languages that aren't present in the title string, plus native names.
final class TitleMetadata {
  const TitleMetadata({this.languages = const [], this.localName});

  final List<String> languages;
  final String? localName;
}

/// A whole system's metadata, keyed by the **full** DAT game name.
typedef SystemMetadata = Map<String, TitleMetadata>;

// --- mias/<System> (<Flavor>).json -------------------------------------------

/// "Missing In Action" — dumps known to exist but not yet preserved. Used to
/// downgrade a "missing" audit result for unobtainable titles so they don't
/// pollute the missing/download set.
final class MiaList {
  const MiaList({
    required this.system,
    this.names = const {},
    this.crcs = const {},
  });

  final String system;

  /// ROM file names known to be Missing-In-Action.
  final Set<String> names;

  /// CRC32s (lowercase hex) of MIA dumps.
  final Set<String> crcs;

  bool containsName(String romName) => names.contains(romName);
  bool containsCrc(String crc) => crcs.contains(crc.toLowerCase());
}

// --- retroachievements/<System>.json -----------------------------------------

/// One RetroAchievements-supported title, as listed in `retroachievements[]`.
///
/// The join key is the raw file hash, never the name (RA names carry no region
/// tags).
final class RetroAchievementsEntry {
  const RetroAchievementsEntry({
    required this.name,
    this.crc32,
    this.md5,
    this.sha1,
    this.sha256,
  });

  final String name;
  final String? crc32;
  final String? md5;
  final String? sha1;
  final String? sha256;
}

/// A hash-indexed view of one system's RetroAchievements support, built for
/// O(1) membership tests. Only ~61 systems are covered; the rest have no index
/// at all, so every game resolves to `false`.
final class RetroAchievementsIndex {
  RetroAchievementsIndex(this.system, List<RetroAchievementsEntry> entries)
    : _entries = entries,
      _bySha1 = {
        for (final e in entries)
          if (e.sha1 != null) e.sha1!: e,
      },
      _byMd5 = {
        for (final e in entries)
          if (e.md5 != null) e.md5!: e,
      },
      _byCrc = {
        for (final e in entries)
          if (e.crc32 != null) e.crc32!: e,
      },
      _names = {
        for (final e in entries)
          if (e.name.isNotEmpty) normalize(e.name),
      };

  final String system;
  final List<RetroAchievementsEntry> _entries;
  final Map<String, RetroAchievementsEntry> _bySha1;
  final Map<String, RetroAchievementsEntry> _byMd5;
  final Map<String, RetroAchievementsEntry> _byCrc;
  final Set<String> _names;

  /// The name-matching key: tag groups dropped, punctuation flattened. Public so
  /// callers can key lookups against [namesBeyondHashes].
  static String normalize(String s) => s
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Whether a single raw ROM's hash appears in the RA set.
  bool supportsRom(RomEntry rom) =>
      (rom.sha1 != null && _bySha1.containsKey(rom.sha1)) ||
      (rom.md5 != null && _byMd5.containsKey(rom.md5)) ||
      (rom.crc32 != null && _byCrc.containsKey(rom.crc32));

  /// Whether any of a game's **raw** ROMs matches the RA set.
  ///
  /// Caveat: disc systems are hashed on their primary executable instead, so a
  /// raw-file join holds only for the systems whose sets are aligned to Redump
  /// entries. Worth revisiting per console during an audit.
  bool supportsGame(DatGame game) => game.roms.any(supportsRom);

  /// Name-based fallback (region-free) for disc systems, whose RA hashes are
  /// computed differently from raw Redump file hashes.
  bool supportsName(String gameName) => _names.contains(normalize(gameName));

  /// The titles here that no hash in [games] reaches, keyed as [supportsName]
  /// keys — the only entries a name match may stand in for.
  ///
  /// Excluding titles some hash already claimed is what stops a region-free name
  /// carrying one region's achievements across to its siblings.
  Set<String> namesBeyondHashes(Iterable<DatGame> games) {
    final datHashes = <String>{
      for (final g in games)
        for (final rom in g.roms)
          ...[?rom.crc32, ?rom.md5, ?rom.sha1, ?rom.sha256],
    };
    final claimed = <String>{};
    final unclaimed = <String>{};
    for (final e in _entries) {
      if (e.name.isEmpty) continue;
      final reached = [?e.crc32, ?e.md5, ?e.sha1, ?e.sha256].any(
        datHashes.contains,
      );
      (reached ? claimed : unclaimed).add(normalize(e.name));
    }
    return unclaimed.difference(claimed);
  }
}

// --- config/internal-config.json ---------------------------------------------

/// One entry of a `[pattern, "string"|"regex"]` tag list. Matching is
/// case-sensitive: the lists carry several spellings of the same tag precisely
/// because casing is significant.
final class TagPattern {
  const TagPattern(this.pattern, {this.isRegex = false});

  final String pattern;
  final bool isRegex;

  /// The pattern as a regular expression, literal entries escaped.
  RegExp toRegExp() => RegExp(isRegex ? pattern : RegExp.escape(pattern));
}

/// The subset of `config/internal-config.json` we consume — the tables that
/// drive clone resolution and 1G1R scoring (region/language order, edition
/// handling, tag classification, disc renaming).
final class InternalConfig {
  const InternalConfig({
    required this.cloneListMetadataUrl,
    this.languages = const {},
    this.defaultRegionOrder = const [],
    this.defaultVideoOrder = const [],
    this.regionImpliedLanguages = const {},
    this.datFileTags = const [],
    this.ignoreTags = const [],
    this.versionIgnore = const [],
    this.budgetEditions = const [],
    this.demoteEditions = const [],
    this.modernEditions = const [],
    this.promoteEditions = const [],
    this.discRename = const {},
  });

  /// Base URL the metadata assets are fetched from.
  final Uri cloneListMetadataUrl;

  /// Language name → ISO-style code (e.g. `English` → `En`).
  final Map<String, String> languages;

  /// Region priority order.
  final List<String> defaultRegionOrder;

  /// Video-standard priority order (NTSC, PAL, ...).
  final List<String> defaultVideoOrder;

  /// Languages implied by a region when the filename omits them.
  final Map<String, List<String>> regionImpliedLanguages;

  /// Each region's implied language in [defaultRegionOrder], deduplicated.
  ///
  /// Answers "which language wins when the caller ranked neither": the metadata
  /// justifies no independent ordering of languages, only the one the region
  /// order already implies.
  List<String> get defaultLanguageOrder => {
    for (final region in defaultRegionOrder)
      ...?regionImpliedLanguages[region],
  }.toList();

  /// Technical DAT tags used to classify entries.
  final List<String> datFileTags;

  /// Tags ignored during title normalization.
  final List<TagPattern> ignoreTags;

  /// Version tokens ignored when comparing revisions.
  final List<String> versionIgnore;

  /// The four edition lists. All of them come out of the clone key, so a
  /// re-release competes with the original instead of forming its own group, and
  /// they then rank the two. See `EditionTags`.
  ///
  /// A budget re-release is *preferred*: it usually carries the fixes.
  final List<TagPattern> budgetEditions;

  /// Dumps that lose: hotel-rental, debug and boutique-reprint tags.
  final List<TagPattern> demoteEditions;

  /// Ports and compilation rips that lose to the original release.
  final List<TagPattern> modernEditions;

  /// Dumps that win: enhanced and corrected pressings.
  final List<TagPattern> promoteEditions;

  /// Every tag list that has to come out of a title before two dumps of one
  /// game can be recognized as the same game.
  List<TagPattern> get allIgnoredTags => [
    ...ignoreTags,
    ...budgetEditions,
    ...promoteEditions,
    ...demoteEditions,
    ...modernEditions,
  ];

  /// Disc-label normalization map (e.g. `Disc` ↔ `Disk`).
  final Map<String, String> discRename;
}
