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

/// How a game reached the RetroAchievements index, weakest claim first.
///
/// A hash join proves the achievement set was authored against these bytes. A
/// name join only proves RA covers a title so named: RA sometimes validates an
/// undocumented variant, leaving the title the only bridge back to the catalogued
/// dump. Ordered so `index` doubles as a confidence ranking for 1G1R.
enum RaMatch { none, byName, byHash }

/// Production/release status, declared best-first so `index` doubles as a
/// ranking for 1G1R scoring.
///
/// [mia] ("Missing In Action") rides along as a status so an unpreserved dump
/// loses to an obtainable one, though being unpreserved is really orthogonal to
/// the rest.
enum ProductionStatus {
  released,
  prototype,
  beta,
  alpha,
  demo,
  pirate,
  unlicensed,
  mia,
}

/// A kind of dump that can be excluded outright, and every signal that betrays
/// it: the DAT's own `<category>`, the clonelist's, and the name patterns that
/// stand in for a `<category>` element the DAT omits.
///
/// One taxonomy for two jobs — [statusFor] grades a dump for 1G1R,
/// [matchesName]/[matchesCategory] drop one — so a trial disc is recognized as
/// one whether or not the DAT says so.
enum ExcludeKind {
  addOns(cli: 'add-ons', categories: ['add-on']),
  applications(
    cli: 'applications',
    categories: ['application'],
    patterns: [r'\((?:Test )?Program\)', r'(?:Check|Sample) Program'],
  ),
  audio(cli: 'audio', categories: ['audio'], patterns: [r'\(Soundtrack\)']),
  badDumps(cli: 'bad-dumps', categories: ['bad dump'], patterns: [r'\[b\]']),
  bios(
    // A DAT that files firmware under `Console` means this.
    cli: 'bios',
    categories: ['bios', 'console'],
    patterns: [r'\[BIOS\]', r'\(Enhancement Chip\)'],
  ),
  bonusDiscs(cli: 'bonus-discs', categories: ['bonus disc']),
  coverdiscs(
    cli: 'coverdiscs',
    categories: ['coverdisc'],
    patterns: [r'\(Covermount\)'],
  ),
  demos(
    cli: 'demos',
    categories: ['demo'],
    status: ProductionStatus.demo,
    patterns: [
      r'\((?:\w[-.]?\s*)*Demo(?:(?:,?\s|-)[\w0-9.]*)*\)',
      r'\(Sample(?:\s[0-9]*|\s\d{4}-\d{2}-\d{2})?\)',
      // Trial editions as the Japanese and Korean releases spell them.
      'Taikenban',
      'Cheheompan',
      r'\(@barai\)',
      r'\((?:Full )?Trial\)',
      r'Trial (?:Disc|Edition|Version|ver\.)',
      r'\((?:GameCube )?Preview\)',
      r'\((?:\w-?\s*)*?Kiosk,?(?:\s\w*?)*\)|Kiosk Demo Disc|(?:PSP System|PS2) Kiosk',
    ],
  ),
  educational(cli: 'educational', categories: ['educational']),
  manuals(cli: 'manuals', categories: ['manual'], patterns: [r'\(Manual\)']),
  mia(cli: 'mia', status: ProductionStatus.mia),
  multimedia(
    cli: 'multimedia',
    categories: ['multimedia'],
    patterns: [r'\(Magazine\)'],
  ),
  pirate(
    cli: 'pirate',
    categories: ['pirate'],
    status: ProductionStatus.pirate,
    patterns: [r'\(Pirate\)'],
  ),
  preproduction(
    cli: 'preproduction',
    categories: ['preproduction'],
    status: ProductionStatus.prototype,
    patterns: [
      r'\((?:\w*?\s)*Alpha(?:\s\d+)?\)',
      r'\((?:\w*?\s)*Beta(?:\s\d+)?\)',
      r'\((?:\w*?\s)*Proto(?:type)?(?:\s\d+)?\)',
      r'\((?:Pre-production|Prerelease)\)',
      r'\((?:DEV|DEBUG|Debug Build)\)',
    ],
  ),
  promotional(
    cli: 'promotional',
    categories: ['promotional'],
    patterns: [r'\(Promo\)', 'EPK', 'Press Kit'],
  ),
  unlicensed(
    cli: 'unlicensed',
    categories: ['unlicensed', 'aftermarket'],
    status: ProductionStatus.unlicensed,
    patterns: [r'\(Unl\)', r'\(Aftermarket\)'],
  ),
  video(
    cli: 'video',
    categories: ['video'],
    patterns: [
      r'Game Boy Advance Video',
      r'- (?:Preview|Movie) Trailer',
      r'\(Nintendo (?:3DS )?(?:Direct|Conference).*?\)',
      r'\((?:\w*\s)*Trailer(?:s|\sDisc)?(?:\s\w*)*\)',
      r'\((?:E3.*)?Video\)',
    ],
  );

  const ExcludeKind({
    required this.cli,
    this.categories = const [],
    this.patterns = const [],
    this.status,
  });

  /// The spelling the CLI accepts.
  final String cli;

  /// Substrings that identify this kind inside a category string.
  final List<String> categories;

  /// Full-name patterns, as source so the enum stays a `const` declaration.
  final List<String> patterns;

  /// The status a name match implies, for the kinds that grade a dump rather
  /// than merely classify it. [ProductionStatus.beta] and [ProductionStatus
  /// .alpha] are reachable only through a tag, never through this enum: they
  /// share [preproduction] with prototypes and nothing ranks between them.
  final ProductionStatus? status;

  static final _compiled = {
    for (final kind in values)
      kind: [for (final p in kind.patterns) RegExp(p, caseSensitive: false)],
  };

  static final _byCli = {for (final kind in values) kind.cli: kind};

  /// The kind named [cli], or null when nothing is.
  static ExcludeKind? byCli(String cli) => _byCli[cli.trim().toLowerCase()];

  /// The kind a graded dump belongs to, so excluding a kind also excludes what
  /// the DAT's own tags already said. Released dumps belong to none.
  static ExcludeKind? forStatus(ProductionStatus status) => switch (status) {
    ProductionStatus.prototype ||
    ProductionStatus.beta ||
    ProductionStatus.alpha => preproduction,
    ProductionStatus.demo => demos,
    ProductionStatus.pirate => pirate,
    ProductionStatus.unlicensed => unlicensed,
    ProductionStatus.mia => mia,
    ProductionStatus.released => null,
  };

  /// Whether [gameName] carries a name pattern of this kind.
  bool matchesName(String gameName) =>
      _compiled[this]!.any((p) => p.hasMatch(gameName));

  /// Whether [category] names this kind.
  bool matchesCategory(String category) {
    final c = category.toLowerCase();
    return categories.any(c.contains);
  }

  /// The worst status [gameName] betrays, or [ProductionStatus.released].
  ///
  /// Worst rather than first so the answer never depends on declaration order: a
  /// dump that is both preproduction and unlicensed is graded by whichever is
  /// further from a finished release.
  static ProductionStatus statusFor(String gameName) {
    var worst = ProductionStatus.released;
    for (final kind in values) {
      final status = kind.status;
      if (status == null || status.index <= worst.index) continue;
      if (kind.matchesName(gameName)) worst = status;
    }
    return worst;
  }
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
    this.retroAchievements = RaMatch.none,
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

  /// How this game reached the RetroAchievements index — tagged internally,
  /// never read from a DAT attribute.
  final RaMatch retroAchievements;

  /// Whether achievements exist at all. Filters ask this; the 1G1R tie-break asks
  /// [retroAchievements], where the strength of the claim matters.
  bool get supportsRetroAchievements => retroAchievements != RaMatch.none;

  bool get hasChd => chdRoms.isNotEmpty;

  DatGame copyWith({
    String? name,
    String? cloneGroupId,
    String? category,
    List<RomEntry>? roms,
    List<RomEntry>? chdRoms,
    GameMetadata? metadata,
    RaMatch? retroAchievements,
  }) {
    return DatGame(
      name: name ?? this.name,
      cloneGroupId: cloneGroupId ?? this.cloneGroupId,
      category: category ?? this.category,
      roms: roms ?? this.roms,
      chdRoms: chdRoms ?? this.chdRoms,
      metadata: metadata ?? this.metadata,
      retroAchievements: retroAchievements ?? this.retroAchievements,
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
