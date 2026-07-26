/// Domain mirrors of the `unexpectedpanda/retool-clonelists-metadata` assets:
/// `clonelists/`, `metadata/`, `mias/`, `retroachievements/`, and
/// `config/internal-config.json`.
library;

import 'dat.dart';

// --- clonelists/<System> (<Flavor>).json -----------------------------------

/// A single title within a clone group, matched against a region-free
/// normalization of a DAT game name. Mirrors `variants[].titles[]`.
final class VariantTitle {
  const VariantTitle({
    required this.searchTerm,
    this.priority,
    this.titlePosition,
    this.filters,
    this.localNames,
  });

  final String searchTerm;

  /// Resolution order within the group (lower = preferred).
  final int? priority;

  /// For compilation members: position of this title inside the pack.
  final int? titlePosition;

  /// Region/attribute-conditional remaps. Raw JSON (object or array upstream);
  /// interpreted by the clone-resolution stage.
  final Object? filters;

  /// Non-English display names keyed by language code.
  final Map<String, String>? localNames;
}

/// A clone group bundling related titles (and multi-game compilations) under a
/// canonical [group] name.
final class VariantGroup {
  const VariantGroup({
    required this.group,
    this.titles = const [],
    this.compilations = const [],
    this.categories = const [],
  });

  final String group;
  final List<VariantTitle> titles;
  final List<VariantTitle> compilations;

  /// e.g. `['Applications']`, `['Applications', 'Educational']`.
  final List<String> categories;
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
/// O(1) membership tests. Only ~61 systems are covered upstream; unsupported
/// systems simply have no index (every game resolves to `false`).
final class RetroAchievementsIndex {
  RetroAchievementsIndex(this.system, List<RetroAchievementsEntry> entries)
    : _bySha1 = {
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
          if (e.name.isNotEmpty) _norm(e.name),
      };

  final String system;
  final Map<String, RetroAchievementsEntry> _bySha1;
  final Map<String, RetroAchievementsEntry> _byMd5;
  final Map<String, RetroAchievementsEntry> _byCrc;
  final Set<String> _names;

  bool get isNotEmpty => _names.isNotEmpty;

  static String _norm(String s) => s
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
  /// Caveat: disc-based systems use a special RA primary-executable hash; the
  /// upstream RA DATs are aligned to Redump entries, so a raw-hash join holds
  /// for covered systems but should be revisited per-console during audit.
  bool supportsGame(DatGame game) => game.roms.any(supportsRom);

  /// Name-based fallback (region-free) for disc systems, whose RA hashes are
  /// computed differently from raw Redump file hashes.
  bool supportsName(String gameName) => _names.contains(_norm(gameName));
}

// --- config/internal-config.json ---------------------------------------------

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

  /// Technical DAT tags used to classify entries.
  final List<String> datFileTags;

  /// Tags ignored during title normalization.
  final List<String> ignoreTags;

  /// Version tokens ignored when comparing revisions.
  final List<String> versionIgnore;

  final List<String> budgetEditions;
  final List<String> demoteEditions;
  final List<String> modernEditions;
  final List<String> promoteEditions;

  /// Disc-label normalization map (e.g. `Disc` ↔ `Disk`).
  final Map<String, String> discRename;
}
