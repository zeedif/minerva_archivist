/// Everything that turns a parsed DAT + metadata into the chosen game set:
/// wishlist parsing, clone grouping, 1G1R scoring, and wishlist/RA filtering.
library;

import 'dart:convert';

import '../models/dat.dart';
import '../models/metadata.dart';
import 'enrichment.dart';

// --- wishlist -----------------------------------------------------------------

/// Parses a wishlist strictly as a JSON/JSONC **array of base game-name
/// strings**. Line (`//`) and block (`/* */`) comments are tolerated.
///
/// Example: `[ "Chrono Trigger", "Final Fantasy VII", "Super Metroid" ]`
///
/// Matching/normalization lives in [SelectionFilter]; how the wishlist combines
/// with the RetroAchievements filter is a CLI concern ([FilterCombineMode]).
List<String> parseWishlist(String source) {
  final decoded = jsonDecode(_stripComments(source));
  if (decoded is! List) {
    throw const FormatException(
      'Wishlist must be a JSON/JSONC array of strings.',
    );
  }
  return [for (final e in decoded) if (e is String) e];
}

String _stripComments(String s) {
  final out = StringBuffer();
  var i = 0;
  var inString = false;
  while (i < s.length) {
    final c = s[i];
    if (inString) {
      out.write(c);
      if (c == r'\' && i + 1 < s.length) {
        out.write(s[i + 1]);
        i += 2;
        continue;
      }
      if (c == '"') inString = false;
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      i++;
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
      i += 2;
      while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

// --- clone grouping -------------------------------------------------------------

/// Normalizes a title for clone matching: lowercase, punctuation → spaces,
/// collapsed. Titles and clonelist `searchTerm`s share the "Title, The"
/// convention, so no article juggling is needed.
String normalizeName(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// Region-free base name: strip all `(...)`/`[...]` tag groups, then normalize.
///
/// Only correct when the config-driven [TitleNormalizer] isn't available; it
/// over-strips (see that class).
String regionFreeName(String name) => normalizeName(
  name.replaceAll(RegExp(r'\([^)]*\)'), ' ').replaceAll(RegExp(r'\[[^\]]*\]'), ' '),
);

/// Builds Retool's `short_name`: the clone identity two titles must share.
///
/// Only region, language, version and ignore tags are dropped. Edition
/// qualifiers survive, so titles that differ only by edition stay distinct —
/// and clonelist `searchTerm`s that carry a qualifier still match.
final class TitleNormalizer {
  TitleNormalizer(InternalConfig config)
    : _regions = {for (final r in config.defaultRegionOrder) r.toLowerCase()},
      _languages = {
        for (final regex in config.languages.values)
          ...?_primaryCode(regex),
      },
      _ignore = [
        for (final t in config.ignoreTags)
          RegExp(t.startsWith('(') ? RegExp.escape(t) : t, caseSensitive: false),
      ];

  final Set<String> _regions;
  final Set<String> _languages;
  final List<RegExp> _ignore;

  /// `En(?:-[A-Z][A-Z])?` -> `en`.
  static Iterable<String>? _primaryCode(String regex) {
    final m = RegExp(r'^([A-Za-z]{2})').firstMatch(regex);
    return m == null ? null : [m.group(1)!.toLowerCase()];
  }

  static final _tag = RegExp(r'\(([^)]*)\)');

  /// The patterns `DatLoader` turns into `GameMetadata.revision`. Kept out of
  /// the key so revisions of one title compete and `GameScore` picks the newer.
  static final _version = RegExp(r'^(?:Rev\s+[0-9A-Za-z]+|v[0-9]+(?:\.[0-9]+)*)$');

  /// The normalized clone key for a DAT game name.
  String shortName(String fullName) {
    var name = fullName;
    for (final ignore in _ignore) {
      name = name.replaceAll(ignore, ' ');
    }
    name = name
        .replaceAllMapped(_tag, (m) => _isDropped(m.group(1)!) ? ' ' : m.group(0)!)
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    return normalizeName(name);
  }

  bool _isDropped(String tag) =>
      _version.hasMatch(tag.trim()) || _isRegionOrLanguage(tag);

  /// True when every comma-separated part of a tag is a known region, or every
  /// part is a language code.
  bool _isRegionOrLanguage(String tag) {
    final parts = [
      for (final p in tag.split(',')) p.trim().toLowerCase(),
      ].where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return false;
    if (parts.every(_regions.contains)) return true;
    return parts.every((p) {
      final m = RegExp(r'^([a-z]{2})(?:-[a-z]{2,4})?$').firstMatch(p);
      return m != null && _languages.contains(m.group(1));
    });
  }
}

/// One clone competing to be the 1G1R winner of its group. Carries the raw
/// [DatGame] plus the signals the [ScoringEngine] ranks on.
final class GameCandidate {
  const GameCandidate({
    required this.game,
    required this.groupKey,
    this.cloneListPriority,
    this.languageRank = worst,
    this.regionRank = worst,
    this.wishlisted = false,
    this.selectedByFilter = false,
  });

  /// Sentinel rank for "no match against the user's priority list".
  static const int worst = 1 << 30;

  final DatGame game;

  /// Clone group / normalized title the candidate competes within.
  final String groupKey;

  /// From the clonelist title's `priority` (lower = preferred); null when the
  /// title isn't listed.
  final int? cloneListPriority;

  /// Index into the user's language priority (lower = better).
  final int languageRank;

  /// Index into the user's region priority (lower = better).
  final int regionRank;

  final bool wishlisted;
  final bool selectedByFilter;

  GameCandidate copyWith({
    int? cloneListPriority,
    int? languageRank,
    int? regionRank,
    bool? wishlisted,
    bool? selectedByFilter,
  }) {
    return GameCandidate(
      game: game,
      groupKey: groupKey,
      cloneListPriority: cloneListPriority ?? this.cloneListPriority,
      languageRank: languageRank ?? this.languageRank,
      regionRank: regionRank ?? this.regionRank,
      wishlisted: wishlisted ?? this.wishlisted,
      selectedByFilter: selectedByFilter ?? this.selectedByFilter,
    );
  }
}

/// Groups DAT games into clone groups using the clonelist, falling back to the
/// region-free title so same-title regional variants still compete (1G1R).
final class CloneGrouper {
  const CloneGrouper();

  /// Builds `normalized searchTerm -> (group, priority, categories)` from a
  /// clonelist; group categories are inherited by every title in the group.
  Map<String, ({String group, int? priority, List<String> categories})>
  buildIndex(CloneList? cloneList) {
    final index =
        <String, ({String group, int? priority, List<String> categories})>{};
    if (cloneList == null) return index;
    for (final vg in cloneList.variants) {
      for (final t in [...vg.titles, ...vg.compilations]) {
        final key = normalizeName(t.searchTerm);
        if (key.isEmpty) continue;
        index.putIfAbsent(
          key,
          () => (group: vg.group, priority: t.priority, categories: vg.categories),
        );
      }
    }
    return index;
  }

  /// [normalizer] supplies Retool's `short_name` key; without it the key falls
  /// back to the over-eager [regionFreeName].
  ({String group, int? priority, List<String> categories}) groupFor(
    DatGame game,
    Map<String, ({String group, int? priority, List<String> categories})> index,
    [TitleNormalizer? normalizer]
  ) {
    final key = normalizer?.shortName(game.name) ?? regionFreeName(game.name);
    return index[key] ?? (group: key, priority: null, categories: const <String>[]);
  }

  /// Produces one [GameCandidate] per game, grouped and priority-tagged.
  List<GameCandidate> candidates(
    DatFile dat,
    CloneList? cloneList, [
    TitleNormalizer? normalizer,
  ]) {
    final index = buildIndex(cloneList);
    return [
      for (final g in dat.games)
        () {
          final r = groupFor(g, index, normalizer);
          return GameCandidate(
            game: g,
            groupKey: r.group,
            cloneListPriority: r.priority,
          );
        }(),
    ];
  }
}

// --- 1G1R scoring -----------------------------------------------------------------

/// User-tunable inputs to the 1G1R scorer.
final class ScoringConfig {
  const ScoringConfig({
    this.languagePriority = const [],
    this.regionPriority = const [],
    this.preferRetroAchievements = true,
    this.preferChd = true,
  });

  /// e.g. `['En', 'Es', 'Ja']` — earlier is better.
  final List<String> languagePriority;

  /// e.g. `['USA', 'Europe', 'World', 'Japan']` — earlier is better.
  final List<String> regionPriority;

  /// Use RA support as a tie-break (smart merge).
  final bool preferRetroAchievements;

  final bool preferChd;
}

/// The comparable 1G1R outcome, evaluated in the agreed precedence:
/// clonelist priority → production status → language → region → RA → revision.
///
/// Sorting ascending puts the winner first.
final class GameScore implements Comparable<GameScore> {
  const GameScore({
    required this.cloneListPriority,
    required this.status,
    required this.languageRank,
    required this.regionRank,
    required this.hasRetroAchievements,
    required this.revision,
  });

  final int cloneListPriority;
  final ProductionStatus status;
  final int languageRank;
  final int regionRank;
  final bool hasRetroAchievements;
  final int revision;

  @override
  int compareTo(GameScore other) {
    var c = cloneListPriority.compareTo(other.cloneListPriority);
    if (c != 0) return c;
    c = status.index.compareTo(other.status.index);
    if (c != 0) return c;
    c = languageRank.compareTo(other.languageRank);
    if (c != 0) return c;
    c = regionRank.compareTo(other.regionRank);
    if (c != 0) return c;
    // Prefer RA support as a tie-break (smart merge).
    c = (other.hasRetroAchievements ? 1 : 0) - (hasRetroAchievements ? 1 : 0);
    if (c != 0) return c;
    // Higher revision wins.
    return other.revision.compareTo(revision);
  }
}

/// Retool-analogous 1G1R selection: groups clones and picks a single winner per
/// group, via [GameScore.compareTo].
final class ScoringEngine {
  const ScoringEngine();

  /// Exposed for `--explain`-style diagnostics.
  GameScore score(GameCandidate candidate, ScoringConfig config) {
    final g = candidate.game;
    return GameScore(
      cloneListPriority: candidate.cloneListPriority ?? GameCandidate.worst,
      status: g.metadata.status,
      languageRank: _rank(config.languagePriority, g.metadata.languages),
      regionRank: _rank(config.regionPriority, g.metadata.regions),
      hasRetroAchievements:
          config.preferRetroAchievements && g.supportsRetroAchievements,
      revision: g.metadata.revision,
    );
  }

  List<GameCandidate> selectBest(
    Iterable<GameCandidate> candidates,
    ScoringConfig config,
  ) {
    final byGroup = <String, List<GameCandidate>>{};
    for (final c in candidates) {
      byGroup.putIfAbsent(c.groupKey, () => []).add(c);
    }
    final winners = <GameCandidate>[];
    for (final group in byGroup.values) {
      group.sort((a, b) => score(a, config).compareTo(score(b, config)));
      winners.add(group.first);
    }
    return winners;
  }

  /// Best (lowest) index of any [values] within the [priority] list.
  int _rank(List<String> priority, List<String> values) {
    var best = GameCandidate.worst;
    for (final v in values) {
      final i = priority.indexOf(v);
      if (i >= 0 && i < best) best = i;
    }
    return best;
  }
}

// --- wishlist / RA filtering ---------------------------------------------------

/// How the wishlist combines with the RetroAchievements filter. A CLI toggle
/// (`--combine and|or`), not part of the wishlist file.
enum FilterCombineMode { and, or }

/// Legacy-faithful selection: normalized exact-name matching (plus clonelist
/// aliases) for the wishlist, combined AND/OR with the RetroAchievements filter.
final class SelectionFilter {
  const SelectionFilter();

  /// With neither a wishlist nor the RA filter, every game passes through.
  ///
  /// [cloneList] enables alias matching — a wishlist entry naming any title in a
  /// clone group matches every game in that group.
  List<DatGame> apply(
    Iterable<DatGame> games, {
    List<String> wishlist = const [],
    bool includeRetroAchievements = false,
    FilterCombineMode combine = FilterCombineMode.or,
    CloneList? cloneList,
  }) {
    final all = games.toList();
    final hasWishlist = wishlist.isNotEmpty;
    if (!hasWishlist && !includeRetroAchievements) return all;

    final fromWishlist = hasWishlist
        ? _findWishlistMatches(wishlist, all, cloneList)
        : <String>{};
    final fromRa = includeRetroAchievements
        ? {for (final g in all) if (g.supportsRetroAchievements) g.name}
        : <String>{};

    final Set<String> keep;
    if (hasWishlist && includeRetroAchievements) {
      keep = combine == FilterCombineMode.and
          ? fromWishlist.intersection(fromRa)
          : fromWishlist.union(fromRa);
    } else if (hasWishlist) {
      keep = fromWishlist;
    } else {
      keep = fromRa;
    }
    return [for (final g in all) if (keep.contains(g.name)) g];
  }

  /// Two-phase matcher (ported from the legacy monolith):
  ///  1. direct match on the normalized, region-free name;
  ///  2. clonelist alias — a wishlisted title anywhere in a group pulls the
  ///     whole group.
  Set<String> _findWishlistMatches(
    List<String> wishlist,
    List<DatGame> games,
    CloneList? cloneList,
  ) {
    final matched = <String>{};
    final normalizedWishlist = {
      for (final item in wishlist) _cleanBasename(item),
    }..remove('');

    // Phase 1 — direct normalized-name match (exact, no substrings).
    for (final g in games) {
      if (normalizedWishlist.contains(_cleanBasename(g.name))) matched.add(g.name);
    }

    // Phase 2 — clonelist alias match.
    if (cloneList != null) {
      const grouper = CloneGrouper();
      final index = grouper.buildIndex(cloneList);
      final wantedGroups = <String>{};
      for (final variant in cloneList.variants) {
        for (final title in [...variant.titles, ...variant.compilations]) {
          if (normalizedWishlist.contains(_cleanBasename(title.searchTerm))) {
            wantedGroups.add(variant.group.toLowerCase());
            break;
          }
        }
      }
      if (wantedGroups.isNotEmpty) {
        for (final g in games) {
          if (matched.contains(g.name)) continue;
          if (wantedGroups.contains(grouper.groupFor(g, index).group.toLowerCase())) {
            matched.add(g.name);
          }
        }
      }
    }
    return matched;
  }
}

/// Strips path, extension, parenthetical/bracket tags, and a trailing
/// mod-suffix (`  - ...`), then normalizes. Legacy `_getCleanBasename`.
String _cleanBasename(String pathOrName) {
  try {
    final decoded = Uri.decodeFull(pathOrName);
    var basename = decoded.split(RegExp(r'[/\\]')).last.split('?').first;

    final lastDot = basename.lastIndexOf('.');
    if (lastDot > 0 && basename.length - lastDot <= 5) {
      final ext = basename.substring(lastDot);
      if (!ext.contains(' ') && RegExp(r'^\.[a-zA-Z0-9]+$').hasMatch(ext)) {
        basename = basename.substring(0, lastDot);
      }
    }

    var noTags = basename.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ').trim();
    final modSeparator = RegExp(r'\s{2,}-\s+');
    if (modSeparator.hasMatch(noTags)) {
      noTags = noTags.split(modSeparator).first.trim();
    }
    return _normalizeTitle(noTags);
  } catch (_) {
    return _normalizeTitle(pathOrName);
  }
}

/// Accent-folds, lowercases, reduces to `[a-z0-9 ]`, and drops a leading/trailing
/// "the". Legacy `_normalizeTitle`.
String _normalizeTitle(String text) {
  if (text.isEmpty) return '';
  const map = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c',
    'Á': 'a', 'À': 'a', 'Ä': 'a', 'É': 'e', 'È': 'e', 'Ë': 'e',
    'Í': 'i', 'Ì': 'i', 'Ï': 'i', 'Ó': 'o', 'Ò': 'o', 'Ö': 'o',
    'Ú': 'u', 'Ù': 'u', 'Ü': 'u', 'Ñ': 'n', 'Ç': 'c',
  };

  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(map[ch] ?? ch.toLowerCase());
  }

  var s = buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.startsWith('the ')) s = s.substring(4).trim();
  if (s.endsWith(' the')) s = s.substring(0, s.length - 4).trim();
  return s;
}

// --- end-to-end selection --------------------------------------------------------

/// How many titles each stage discarded, so the funnel from DAT to selection is
/// reportable. Mirrors Retool's stats block.
final class SelectionStats {
  const SelectionStats({
    required this.total,
    required this.status,
    required this.category,
    required this.language,
    required this.clones,
    required this.wishlist,
    required this.selected,
  });

  final int total;
  final int status;
  final int category;
  final int language;

  /// Runners-up dropped by 1G1R.
  final int clones;

  /// Dropped by the wishlist / RetroAchievements filter.
  final int wishlist;

  final int selected;

  /// Non-zero reasons as `label -n` pairs, in pipeline order.
  List<String> get reasons => [
    if (status > 0) 'status -$status',
    if (category > 0) 'category -$category',
    if (language > 0) 'language -$language',
    if (clones > 0) '1g1r -$clones',
    if (wishlist > 0) 'wishlist/ra -$wishlist',
  ];
}

/// The chosen games plus the funnel that produced them.
final class SelectionResult {
  const SelectionResult({required this.games, required this.stats});

  final List<DatGame> games;
  final SelectionStats stats;
}

/// End-to-end selection:
/// enrich → exclude (status/category/language) → 1G1R → wishlist/RA filter.
final class GameSelector {
  const GameSelector({
    this.enricher = const DatEnricher(),
    this.grouper = const CloneGrouper(),
    this.engine = const ScoringEngine(),
    this.filter = const SelectionFilter(),
  });

  final DatEnricher enricher;
  final CloneGrouper grouper;
  final ScoringEngine engine;
  final SelectionFilter filter;

  SelectionResult select({
    required DatFile dat,
    required InternalConfig config,
    required ScoringConfig scoring,
    List<String> wishlist = const [],
    bool includeRetroAchievements = false,
    FilterCombineMode combine = FilterCombineMode.or,
    Set<ProductionStatus> excludeStatuses = const {},
    Set<String> excludeCategories = const {},
    bool filterLanguages = false,
    CloneList? cloneList,
    SystemMetadata? metadata,
    RetroAchievementsIndex? ra,
    MiaList? mias,
  }) {
    final enriched = enricher.enrich(
      dat,
      config: config,
      cloneList: cloneList,
      metadata: metadata,
      ra: ra,
      mias: mias,
    );

    // Retool's order: group first so clonelist categories are in play, exclude
    // next, pick a winner last — excluding after 1G1R would empty a group
    // instead of promoting its runner-up.
    final index = grouper.buildIndex(cloneList);
    final normalizer = TitleNormalizer(config);
    final excludeCats = {for (final c in excludeCategories) c.toLowerCase()};

    var byStatus = 0;
    var byCategory = 0;
    var byLanguage = 0;
    final candidates = <GameCandidate>[];
    for (final g in enriched.games) {
      if (excludeStatuses.contains(g.metadata.status)) {
        byStatus++;
        continue;
      }
      final grp = grouper.groupFor(g, index, normalizer);
      if (excludeCats.isNotEmpty) {
        final cats = _effectiveCategories(g, grp.categories);
        if (cats.any((c) => excludeCats.any((e) => c.contains(e)))) {
          byCategory++;
          continue;
        }
      }
      if (filterLanguages && !_speaksAny(g, scoring.languagePriority)) {
        byLanguage++;
        continue;
      }
      candidates.add(
        GameCandidate(
          game: g,
          groupKey: grp.group,
          cloneListPriority: grp.priority,
        ),
      );
    }

    final winners = engine.selectBest(candidates, scoring);
    final games = filter.apply(
      [for (final c in winners) c.game],
      wishlist: wishlist,
      includeRetroAchievements: includeRetroAchievements,
      combine: combine,
      cloneList: cloneList,
    );

    return SelectionResult(
      games: games,
      stats: SelectionStats(
        total: dat.games.length,
        status: byStatus,
        category: byCategory,
        language: byLanguage,
        clones: candidates.length - winners.length,
        wishlist: winners.length - games.length,
        selected: games.length,
      ),
    );
  }

  /// Whether [g] supports any of [wanted], for `--filter-languages`.
  ///
  /// Follows `filter_languages()`: unknown languages are kept, and a wanted
  /// base code matches a regional variant of it.
  static bool _speaksAny(DatGame g, List<String> wanted) {
    final have = g.metadata.languages;
    if (have.isEmpty || wanted.isEmpty) return true;
    for (final w in wanted) {
      final code = w.toLowerCase();
      for (final h in have) {
        final lang = h.toLowerCase();
        if (lang == code || lang.startsWith('$code-')) return true;
      }
    }
    return false;
  }

  /// A game's categories, lowercased: the DAT `<category>` plus its clonelist
  /// group's — the only signal for entries the DAT leaves uncategorized.
  /// Follows Retool in mapping `Console` to `bios` and reading a `[BIOS]` tag.
  static Set<String> _effectiveCategories(
    DatGame g,
    List<String> groupCategories,
  ) {
    final cats = <String>{};
    for (final c in [?g.category, ...groupCategories]) {
      if (c.isEmpty) continue;
      cats.add(c.toLowerCase() == 'console' ? 'bios' : c.toLowerCase());
    }
    if (_biosTag.hasMatch(g.name)) cats.add('bios');
    return cats;
  }

  static final _biosTag = RegExp(r'\[bios\]', caseSensitive: false);
}
