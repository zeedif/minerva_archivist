/// The DAT universe: hash entries, per-game metadata, and the parsed DAT file.
library;

/// The physical form a hash-set describes.
///
/// This distinction is the crux of the Redump/CHD unification: the same game
/// can be verified against [RomFormat.raw] hashes (required by
/// RetroAchievements) while being stored on disk as a [RomFormat.chd].
enum RomFormat {
  /// Raw disc dump (`.bin`/`.cue`, `.iso`, `.gdi`) — what Redump DATs hash.
  raw,

  /// Compressed Hunks of Data (`.chd`) — what MAME-Redump DATs hash. Preferred
  /// for local storage.
  chd,

  /// Single-file cartridge dump (`.nes`, `.sfc`, `.gba`) — No-Intro.
  cartridge,

  /// A container (typically a `.zip` as distributed by MiNERVA); the hash is of
  /// the archive itself, not its contents.
  archive,
}

/// A single hashed file inside a game — one disc track, one disc image, or one
/// cartridge.
///
/// Hashes are lowercase hex with no separators; any subset may be absent
/// depending on the DAT flavor (MAME/CHD DATs typically carry only SHA-1).
final class RomEntry {
  const RomEntry({
    required this.name,
    required this.size,
    required this.format,
    this.crc32,
    this.md5,
    this.sha1,
    this.sha256,
  });

  final String name;
  final int size;
  final RomFormat format;
  final String? crc32;
  final String? md5;
  final String? sha1;
  final String? sha256;

  /// Whether this entry and [other] describe the same bytes, using whichever
  /// digests both sides possess (SHA-1 preferred, then MD5, then CRC32 + size).
  bool matchesHashes(RomEntry other) {
    if (sha1 != null && other.sha1 != null) return sha1 == other.sha1;
    if (md5 != null && other.md5 != null) return md5 == other.md5;
    if (crc32 != null && other.crc32 != null) {
      return crc32 == other.crc32 && size == other.size;
    }
    return false;
  }

  RomEntry copyWith({
    String? name,
    int? size,
    RomFormat? format,
    String? crc32,
    String? md5,
    String? sha1,
    String? sha256,
  }) {
    return RomEntry(
      name: name ?? this.name,
      size: size ?? this.size,
      format: format ?? this.format,
      crc32: crc32 ?? this.crc32,
      md5: md5 ?? this.md5,
      sha1: sha1 ?? this.sha1,
      sha256: sha256 ?? this.sha256,
    );
  }

  @override
  String toString() => 'RomEntry($name, ${format.name}, sha1: $sha1)';
}

/// The provenance/format of a DAT, detected automatically from its header and
/// element shape.
enum DatFlavor { noIntro, redump, mameRedump, retool, unknown }

/// Production/release status, declared best-first so `index` doubles as a
/// ranking for 1G1R scoring.
///
/// [mia] ("Missing In Action") rides along as a status so `--exclude-status mia`
/// works and an unpreserved dump loses to an obtainable one. Note this makes it
/// exclusive with the other statuses, unlike Retool's orthogonal `is_mia` flag.
enum ProductionStatus {
  released,
  prototype,
  beta,
  alpha,
  demo,
  sample,
  pirate,
  unlicensed,
  mia,
}

/// Region/language/version signals parsed from a game's filename tags and
/// enriched from the metadata repository.
final class GameMetadata {
  const GameMetadata({
    this.regions = const [],
    this.languages = const [],
    this.version,
    this.revision = 0,
    this.status = ProductionStatus.released,
    this.localName,
    this.rawTags = const {},
  });

  /// Ordered as written, e.g. `['USA', 'Europe']`.
  final List<String> regions;

  /// ISO-style codes, e.g. `['En', 'Fr', 'De']`.
  final List<String> languages;

  /// Raw version/revision text, e.g. `'Rev 2'`, `'v1.1'`.
  final String? version;

  /// Normalized numeric revision for comparison (0 when absent).
  final int revision;

  final ProductionStatus status;

  /// Native-language title, supplied by the metadata repository.
  final String? localName;

  /// Every parenthetical tag, kept for diagnostics.
  final Set<String> rawTags;

  GameMetadata copyWith({
    List<String>? regions,
    List<String>? languages,
    String? version,
    int? revision,
    ProductionStatus? status,
    String? localName,
    Set<String>? rawTags,
  }) {
    return GameMetadata(
      regions: regions ?? this.regions,
      languages: languages ?? this.languages,
      version: version ?? this.version,
      revision: revision ?? this.revision,
      status: status ?? this.status,
      localName: localName ?? this.localName,
      rawTags: rawTags ?? this.rawTags,
    );
  }
}

/// A game/machine entry.
///
/// Holds both the canonical [roms] (Redump raw / No-Intro) and any unified
/// [chdRoms] (from a MAME-Redump DAT), so the auditor can accept a local `.chd`
/// while the pipeline keeps the raw hashes that RetroAchievements matching
/// needs.
final class DatGame {
  const DatGame({
    required this.name,
    required this.roms,
    required this.metadata,
    this.cloneGroupId,
    this.category,
    this.chdRoms = const [],
    this.supportsRetroAchievements = false,
  });

  final String name;

  /// Clone-group parent key (from the DAT's `cloneof` or the clonelist).
  final String? cloneGroupId;

  /// Clonelist category, e.g. `Applications`, `Demos`, `Educational`.
  final String? category;

  /// Canonical hash set (raw disc / cartridge).
  final List<RomEntry> roms;

  /// Unified `.chd` entries merged from a MAME-Redump DAT; may be empty.
  final List<RomEntry> chdRoms;

  final GameMetadata metadata;

  /// Tagged internally by hash-matching [roms] against the RetroAchievements
  /// index — never read from a DAT attribute.
  final bool supportsRetroAchievements;

  bool get hasChd => chdRoms.isNotEmpty;

  DatGame copyWith({
    String? name,
    String? cloneGroupId,
    String? category,
    List<RomEntry>? roms,
    List<RomEntry>? chdRoms,
    GameMetadata? metadata,
    bool? supportsRetroAchievements,
  }) {
    return DatGame(
      name: name ?? this.name,
      cloneGroupId: cloneGroupId ?? this.cloneGroupId,
      category: category ?? this.category,
      roms: roms ?? this.roms,
      chdRoms: chdRoms ?? this.chdRoms,
      metadata: metadata ?? this.metadata,
      supportsRetroAchievements:
          supportsRetroAchievements ?? this.supportsRetroAchievements,
    );
  }
}

final class DatHeader {
  const DatHeader({
    required this.name,
    required this.flavor,
    this.description,
    this.version,
    this.homepage,
    this.url,
    this.author,
  });

  final String name;
  final DatFlavor flavor;
  final String? description;
  final String? version;
  final String? homepage;
  final String? url;
  final String? author;

  DatHeader copyWith({DatFlavor? flavor}) {
    return DatHeader(
      name: name,
      flavor: flavor ?? this.flavor,
      description: description,
      version: version,
      homepage: homepage,
      url: url,
      author: author,
    );
  }
}

final class DatFile {
  const DatFile({required this.header, required this.games});

  final DatHeader header;
  final List<DatGame> games;
}
