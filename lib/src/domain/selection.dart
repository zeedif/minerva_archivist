/// Everything that turns a parsed DAT + metadata into the chosen game set:
/// wishlist parsing, clone grouping, 1G1R scoring, and membership.
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
/// Matching lives in [wishlistReach]; what naming a title claims about it is
/// [WishlistMode]'s job.
List<String> parseWishlist(String source) {
  final decoded = jsonDecode(_stripComments(source));
  if (decoded is! List) {
    throw const FormatException(
      'Wishlist must be a JSON/JSONC array of strings.',
    );
  }
  return [
    for (final e in decoded)
      if (e is String) e,
  ];
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
  name
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' '),
);

/// Builds the clone key (`short_name`): the identity two titles must share to
/// compete for one slot.
///
/// Region, language, version, ignore and edition tags are all dropped, so two
/// dumps of one release land in the same group however it was re-issued. Which
/// of them takes the slot is [EditionTags]' job.
final class TitleNormalizer {
  TitleNormalizer(InternalConfig config)
    : _regions = {for (final r in config.defaultRegionOrder) r.toLowerCase()},
      _languages = {
        for (final regex in config.languages.values) ...?_primaryCode(regex),
      },
      _ignore = [for (final t in config.allIgnoredTags) t.toRegExp()];

  final Set<String> _regions;
  final Set<String> _languages;
  final List<RegExp> _ignore;

  /// `En(?:-[A-Z][A-Z])?` -> `en`.
  static Iterable<String>? _primaryCode(String regex) {
    final m = RegExp(r'^([A-Za-z]{2})').firstMatch(regex);
    return m == null ? null : [m.group(1)!.toLowerCase()];
  }

  static final _tag = RegExp(r'\(([^)]*)\)');

  /// Only region and language tags dropped, case intact — the form a `regionFree`
  /// clonelist title matches. Every other qualifier survives and has to be
  /// spelled out in full.
  String regionFree(String fullName) {
    var name = fullName;
    for (final m in _tag.allMatches(fullName)) {
      if (_isRegionOrLanguage(m.group(1)!.trim())) {
        name = name.replaceFirst(' ${m.group(0)}', '');
      }
    }
    return name;
  }

  /// Tags dropped before comparing titles, so dump variants of one release share
  /// a clone key instead of each becoming its own group: versions,
  /// preproduction, unlicensed markers, dates and video standards.
  ///
  /// Serial and mastering codes are left out on purpose: they need per-system
  /// validation, and a pattern that is too broad merges two distinct releases.
  static final _dumpVariant = <RegExp>[
    // Versions.
    RegExp(r'^Rev(?:[ -][0-9A-Za-z].*)?$', caseSensitive: false),
    RegExp(r'^v[.0-9](?:(?!Smile).)*$', caseSensitive: false),
    RegExp(r'^Build [0-9].*$', caseSensitive: false),
    RegExp(r'^Alt.*$', caseSensitive: false),
    RegExp(r'^DV [0-9].*$', caseSensitive: false), // Famicom Disk System
    RegExp(r'^FW[0-9].*$', caseSensitive: false), // PlayStation firmware
    RegExp(r'^USE[0-9]$', caseSensitive: false), // HyperScan
    // Preproduction.
    RegExp(r'^(?:\w*?\s)*Alpha(?:\s\d+)?$', caseSensitive: false),
    RegExp(r'^(?:\w*?\s)*Beta(?:\s\d+)?$', caseSensitive: false),
    RegExp(r'^(?:\w*?\s)*Proto(?:type)?(?:\s\d+)?$', caseSensitive: false),
    RegExp(r'^(?:Pre-production|Prerelease)$', caseSensitive: false),
    RegExp(r'^(?:DEV|DEBUG|Debug Build)$', caseSensitive: false),
    // Unlicensed group.
    RegExp(r'^(?:Aftermarket|Pirate|Unl)$', caseSensitive: false),
    // Other tags kept out of the key.
    RegExp(r'^(?:\w-?\s*)*?OEM$', caseSensitive: false),
    RegExp(r'^Rerelease$', caseSensitive: false),
    RegExp(r'^Review (?:Code|Kit [0-9]+)$', caseSensitive: false),
    RegExp(r'^Magazine$', caseSensitive: false),
    // Video standards.
    RegExp(r'^(?:MPAL|NTSC|NTSC-PAL|SECAM)$', caseSensitive: false),
    RegExp(r'^PAL(?:\s(?:\w+|50[Hh]z|60[Hh]z))?$', caseSensitive: false),
    // Dates.
    RegExp(r'^\d{8}$'),
    RegExp(r'^\d{4}-\d{2}-\d{2}(?:T\d{6})?$'),
    RegExp(r'^\d{2}-\d{2}-\d{4}$'),
    RegExp(r'^\d{2}-\d{2}-\d{2}$'),
    RegExp(r'^~?\d{4}-\d{2}-xx$', caseSensitive: false),
    RegExp(r'^~?\d{4}-xx-xx$', caseSensitive: false),
    RegExp(r'^\d{1,2}-\d{1,2}$'),
    RegExp(
      r'^(?:January|February|March|April|May|June|July|August|September'
      r'|October|November|December),\s?\d{4}$',
      caseSensitive: false,
    ),
  ];

  /// The normalized clone key for a DAT game name.
  String shortName(String fullName) {
    var name = fullName;
    for (final ignore in _ignore) {
      name = name.replaceAll(ignore, ' ');
    }
    name = name
        .replaceAllMapped(
          _tag,
          (m) => _isDropped(m.group(1)!) ? ' ' : m.group(0)!,
        )
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    return normalizeName(name);
  }

  bool _isDropped(String tag) {
    final t = tag.trim();
    return _isRegionOrLanguage(t) || _dumpVariant.any((p) => p.hasMatch(t));
  }

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
    this.isSuperset = false,
    this.represents = const {},
  });

  /// Binds a game to what the clonelist says about it. An `englishFriendly`
  /// title carries `En` from here on, so the language filter and the language
  /// axis both see it.
  factory GameCandidate.resolved(DatGame game, CloneResolution resolution) {
    final added = [
      for (final l in resolution.addedLanguages)
        if (!game.metadata.languages.contains(l)) l,
    ];
    return GameCandidate(
      game: added.isEmpty
          ? game
          : game.copyWith(
              metadata: game.metadata.copyWith(
                languages: [...game.metadata.languages, ...added],
              ),
            ),
      groupKey: resolution.group,
      cloneListPriority: resolution.priority,
      isSuperset: resolution.isSuperset,
      represents: resolution.represents,
    );
  }

  /// Sentinel rank for "no match against the user's priority list".
  static const int worst = 1 << 30;

  /// What a title with no `priority` key is worth. Every title starts at 1 and a
  /// clonelist only ever pushes one *down*, so an undeclared priority is the best
  /// one, not the worst.
  static const int defaultCloneListPriority = 1;

  final DatGame game;

  /// Clone group / normalized title the candidate competes within.
  final String groupKey;

  /// The clonelist title's `priority` (lower = preferred); null when the title
  /// declares none, which ranks as [defaultCloneListPriority].
  final int? cloneListPriority;

  /// See [CloneResolution.isSuperset].
  final bool isSuperset;

  /// See [CloneResolution.represents].
  final Set<String> represents;

  /// Every group this candidate competes in, the one it reports under first.
  Iterable<String> get groups => [groupKey, ...represents];

  /// Whether the candidate stands for content beyond its own group.
  bool get isRepresentative => represents.isNotEmpty;
}

/// What the clonelist says about one DAT game, after its conditional filters
/// have been evaluated.
final class CloneResolution {
  const CloneResolution({
    required this.group,
    this.priority,
    this.categories = const [],
    this.addedLanguages = const [],
    this.isSuperset = false,
    this.represents = const {},
  });

  /// The clone group the game competes in, normalized so a clonelist group name
  /// and an unlisted game's own key live in the same space.
  final String group;

  /// Clonelist priority (lower = preferred), or null when unlisted.
  final int? priority;

  /// The categories in force: the title's own if it declares any, else the
  /// group's, else whatever a matching filter set.
  final List<String> categories;

  /// Languages an `englishFriendly` flag adds on top of the title's tags.
  final List<String> addedLanguages;

  /// Declared under `supersets[]`, or promoted there by a filter: an edition that
  /// subsumes the rest of its group and so should represent it.
  final bool isSuperset;

  /// Groups this title competes in besides [group] — the other groups that
  /// declared it a compilation or a superset.
  ///
  /// A pack is listed under every group it contains, so it stands for all of
  /// them: it competes for each slot and, winning, fills it.
  final Set<String> represents;

  /// Whether the title stands for content beyond its own group.
  bool get isRepresentative => represents.isNotEmpty;
}

/// A clonelist compiled for lookup, one map per [TitleMatch] plus the regex
/// list. Built once per DAT by [CloneGrouper.buildIndex].
final class CloneIndex {
  CloneIndex._(this._short, this._full, this._regionFree, this._regex);

  /// Empty: every game falls back to its own group.
  CloneIndex.empty() : this._(const {}, const {}, const {}, const []);

  final Map<String, List<CloneListMatch>> _short;
  final Map<String, List<CloneListMatch>> _full;
  final Map<String, List<CloneListMatch>> _regionFree;
  final List<(RegExp, CloneListMatch)> _regex;

  /// Every clonelist declaration claiming [fullName], most specific matcher
  /// first: the full name, then the region-free name, then [shortKey], then a
  /// regex — an exact spelling has to beat a catch-all pattern. All declarations
  /// at the winning tier are returned, since a pack is declared once per group it
  /// contains.
  ///
  /// [shortKey] is passed in rather than derived because building it walks every
  /// ignored tag, and the caller needs it anyway.
  List<CloneListMatch> lookup(
    String fullName,
    String shortKey, {
    TitleNormalizer? normalizer,
  }) {
    final hit =
        _full[fullName] ??
        (_regionFree.isEmpty
            ? null
            : _regionFree[normalizer?.regionFree(fullName) ?? fullName]) ??
        _short[shortKey];
    if (hit != null) return hit;
    return [
      for (final (pattern, entry) in _regex)
        if (pattern.hasMatch(fullName)) entry,
    ];
  }
}

/// How a clonelist declared a title inside a group.
enum TitleRole {
  /// `titles[]` — a release that belongs to the group and competes for its slot.
  member,

  /// `compilations[]` — a pack holding the group's content alongside other
  /// groups'.
  compilation,

  /// `supersets[]` — an edition that subsumes the group, which [GameScore] ranks
  /// ahead of the releases it replaces.
  superset;

  /// Whether the title answers for its group rather than merely belonging to it.
  bool get represents => this != member;
}

/// A clonelist title bound to the group that declared it, and in what role.
typedef CloneListMatch = ({
  String group,
  List<String> categories,
  VariantTitle title,
  TitleRole role,
});

/// What a pack or subsuming edition is worth against the releases it contains.
enum SupersetMode {
  /// It answers for them: it takes the slot of every group it stands for, so
  /// those titles are not selected again beside it.
  prefer,

  /// Its claim is set aside, so a group goes to a release of its own wherever one
  /// exists. The pack still fills a group that has nothing else to nominate.
  ignore,
}

/// Groups DAT games into clone groups using the clonelist, falling back to the
/// region-free title so same-title regional variants still compete (1G1R).
final class CloneGrouper {
  const CloneGrouper();

  /// Compiles [cloneList] for lookup. Group categories are inherited by every
  /// title in the group unless the title overrides them.
  CloneIndex buildIndex(CloneList? cloneList) {
    if (cloneList == null) return CloneIndex.empty();
    final short = <String, List<CloneListMatch>>{};
    final full = <String, List<CloneListMatch>>{};
    final regionFree = <String, List<CloneListMatch>>{};
    final regex = <(RegExp, CloneListMatch)>[];

    for (final vg in cloneList.variants) {
      for (final (role, titles) in [
        (TitleRole.member, vg.titles),
        (TitleRole.compilation, vg.compilations),
        (TitleRole.superset, vg.supersets),
      ]) {
        for (final t in titles) {
          if (t.searchTerm.isEmpty) continue;
          final entry = (
            group: vg.group,
            categories: vg.categories,
            title: t,
            role: role,
          );
          switch (t.match) {
            case TitleMatch.full:
              (full[t.searchTerm] ??= []).add(entry);
            case TitleMatch.regionFree:
              (regionFree[t.searchTerm] ??= []).add(entry);
            case TitleMatch.short:
              final key = normalizeName(t.searchTerm);
              if (key.isNotEmpty) (short[key] ??= []).add(entry);
            case TitleMatch.regex:
              // An unparseable pattern comes from the metadata, so it is skipped
              // rather than fatal.
              if (_tryCompile(t.searchTerm) case final pattern?) {
                regex.add((pattern, entry));
              }
          }
        }
      }
    }
    return CloneIndex._(short, full, regionFree, regex);
  }

  static RegExp? _tryCompile(String pattern) {
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return null;
    }
  }

  /// Resolves [game] against [index], applying every filter whose conditions
  /// hold.
  ///
  /// [normalizer] supplies the clone key; without it the key falls back to the
  /// over-eager [regionFreeName]. [regionOrder] and [defaultRegions] are read
  /// only by the `regionOrder` condition, which asks about the caller's
  /// preference rather than about the title.
  CloneResolution resolve(
    DatGame game,
    CloneIndex index, {
    TitleNormalizer? normalizer,
    PriorityList? regionOrder,
    List<String> defaultRegions = const [],
  }) {
    final ownKey =
        normalizer?.shortName(game.name) ?? regionFreeName(game.name);
    final matches = index.lookup(game.name, ownKey, normalizer: normalizer);
    if (matches.isEmpty) return CloneResolution(group: ownKey);

    // A title listed as a plain member somewhere competes there; a pack has no
    // group of its own, so its first listing stands in for one.
    final entry = matches.firstWhere(
      (m) => m.role == TitleRole.member,
      orElse: () => matches.first,
    );
    var group = normalizeName(entry.group);
    var priority = entry.title.priority;
    var categories = entry.title.categories ?? entry.categories;
    var superset = entry.role == TitleRole.superset;
    final represents = <String>{
      for (final m in matches)
        if (m.role.represents) normalizeName(m.group),
    };
    final added = <String>[if (entry.title.englishFriendly) _english];

    // Only the first matching filter may move the group; every other result keeps
    // being applied.
    var groupMoved = false;
    for (final filter in entry.title.filters) {
      if (!_holds(filter.conditions, game, regionOrder, defaultRegions)) {
        continue;
      }
      final results = filter.results;
      if (results.group != null && !groupMoved) {
        group = normalizeName(results.group!);
        groupMoved = true;
      }
      if (results.priority != null) priority = results.priority;
      if (results.categories != null) categories = results.categories!;
      if (results.englishFriendly == true && !added.contains(_english)) {
        added.add(_english);
      }
      if (results.superset != null) superset = results.superset!;
    }

    final primary = group.isEmpty ? ownKey : group;
    represents.remove(primary);
    return CloneResolution(
      group: primary,
      priority: priority,
      categories: categories,
      addedLanguages: added,
      // Standing for other groups is itself a claim over them.
      isSuperset: superset || represents.isNotEmpty,
      represents: represents,
    );
  }

  static const _english = 'En';

  bool _holds(
    FilterConditions c,
    DatGame game,
    PriorityList? regionOrder,
    List<String> defaultRegions,
  ) {
    if (!c.matchRegions.every(game.metadata.regions.contains)) return false;
    if (!c.matchLanguages.every(game.metadata.languages.contains)) return false;
    if (c.matchString case final pattern?) {
      final regex = _tryCompile(pattern);
      if (regex == null || !regex.hasMatch(game.name)) return false;
    }
    if (c.regionOrder case final order?) {
      if (!_regionOrderHolds(order, regionOrder, defaultRegions)) return false;
    }
    return true;
  }

  /// True when any of `higherRegions` sits above *every* `lowerRegions` entry in
  /// the caller's priority. A region the list doesn't name takes no part, and if
  /// that empties either side the condition fails.
  bool _regionOrderHolds(
    RegionOrderCondition condition,
    PriorityList? regionOrder,
    List<String> defaultRegions,
  ) {
    if (regionOrder == null) return false;
    var higher = _withUkAliases(condition.higherRegions);
    var lower = _withUkAliases(condition.lowerRegions);
    const wildcard = RegionOrderCondition.allOtherRegions;
    // The wildcard on both sides cancels out, so the condition cannot hold.
    if (higher.contains(wildcard) && lower.contains(wildcard)) return false;
    if (higher.contains(wildcard)) {
      higher = [
        for (final r in defaultRegions)
          if (!lower.contains(r)) r,
      ];
    }
    if (lower.contains(wildcard)) {
      lower = [
        for (final r in defaultRegions)
          if (!higher.contains(r)) r,
      ];
    }

    final higherRanks = [for (final r in higher) ?regionOrder.indexOf(r)];
    final lowerRanks = [for (final r in lower) ?regionOrder.indexOf(r)];
    if (higherRanks.isEmpty || lowerRanks.isEmpty) return false;
    final bestLower = lowerRanks.reduce((a, b) => a < b ? a : b);
    return higherRanks.any((rank) => rank < bestLower);
  }

  /// Both spellings of the United Kingdom are in circulation; a list naming one
  /// means both.
  static List<String> _withUkAliases(List<String> regions) {
    const uk = 'UK';
    const united = 'United Kingdom';
    if (regions.contains(uk) && !regions.contains(united)) {
      return [...regions, united];
    }
    if (regions.contains(united) && !regions.contains(uk)) {
      return [...regions, uk];
    }
    return regions;
  }

  /// Produces one [GameCandidate] per game, grouped and priority-tagged.
  List<GameCandidate> candidates(
    DatFile dat,
    CloneList? cloneList, {
    TitleNormalizer? normalizer,
    PriorityList? regionOrder,
    List<String> defaultRegions = const [],
  }) {
    final index = buildIndex(cloneList);
    return [
      for (final g in dat.games)
        GameCandidate.resolved(
          g,
          resolve(
            g,
            index,
            normalizer: normalizer,
            regionOrder: regionOrder,
            defaultRegions: defaultRegions,
          ),
        ),
    ];
  }
}

// --- 1G1R scoring -----------------------------------------------------------------

/// An ordered language or region preference. It ranks and restricts: a title
/// matching no entry is dropped, since the list is the only statement of what
/// the caller wants.
///
/// Two entries stand in for the values not spelled out, and rank where they sit:
///
/// - [other] — a value the list doesn't name, plus missing values unless
///   [unknown] claims them.
/// - [unknown] — a title with no value on this axis.
final class PriorityList {
  PriorityList(Iterable<String> order, {Iterable<String> fallback = const []})
    : _order = [for (final entry in order) entry.toLowerCase()],
      _fallback = [for (final entry in fallback) entry.toLowerCase()];

  /// A value the list doesn't name.
  static const other = 'Other';

  /// No value at all on this axis.
  static const unknown = 'Unknown';

  final List<String> _order;

  /// Ranks values [_order] lands on one position — everything sharing an [other]
  /// slot. Without it they rank alike and the winner is left to whichever
  /// tie-break comes next.
  final List<String> _fallback;

  /// The best position [values] reach, or [GameCandidate.worst] when the list
  /// admits none of them. An empty list ranks nothing.
  ///
  /// Two orders folded into one comparable number. Scaling the primary position
  /// by a stride wider than [_fallback] keeps the fallback from ever crossing
  /// into the next position, so it only ever breaks ties.
  int rank(List<String> values) {
    if (_order.isEmpty) return GameCandidate.worst;
    final primary = values.isEmpty
        ? _positionOf(unknown)
        : values.map(_positionOf).reduce((a, b) => a < b ? a : b);
    if (primary == GameCandidate.worst) return GameCandidate.worst;
    return primary * (_fallback.length + 1) + _fallbackPosition(values);
  }

  /// Whether the list has a place for [values]. An empty list restricts nothing.
  bool admits(List<String> values) =>
      _order.isEmpty || rank(values) != GameCandidate.worst;

  /// Where [value] is named outright, or null when it isn't. Unlike [rank] this
  /// ignores the [other] wildcard: callers comparing two values against each
  /// other need to know the list really distinguishes them.
  int? indexOf(String value) {
    final i = _order.indexOf(value.toLowerCase());
    return i == -1 ? null : i;
  }

  /// Where [value] sits in [_order]: its own entry, else the [other] entry, else
  /// nowhere.
  int _positionOf(String value) {
    var wildcard = GameCandidate.worst;
    for (var i = 0; i < _order.length; i++) {
      if (_covers(_order[i], value)) return i;
      if (_order[i] == _other) wildcard = i;
    }
    return wildcard;
  }

  /// The first [_fallback] position any of [values] reaches, or one past the end,
  /// so a value the fallback names always beats one it doesn't.
  int _fallbackPosition(List<String> values) {
    for (var i = 0; i < _fallback.length; i++) {
      if (values.any((v) => _covers(_fallback[i], v))) return i;
    }
    return _fallback.length;
  }

  /// An entry covers its subtags, so `Es` matches `Es-MX`.
  static bool _covers(String entry, String value) {
    final v = value.toLowerCase();
    return v == entry || v.startsWith('$entry-');
  }

  static final _other = other.toLowerCase();
}

/// The `internal-config.json` edition tag lists, compiled for ranking.
///
/// [TitleNormalizer] strips all of these from the clone key, which is what puts a
/// re-release in the same group as the original release; these ranks then decide
/// which of the two takes the slot.
final class EditionTags {
  EditionTags(InternalConfig config)
    : _modern = _compile(config.modernEditions),
      _budget = _compile(config.budgetEditions),
      _promote = _compile(config.promoteEditions),
      _demote = _compile(config.demoteEditions);

  /// No lists loaded: every title ranks the same, so the edition tie-breaks
  /// simply don't participate.
  const EditionTags.none()
    : _modern = const [],
      _budget = const [],
      _promote = const [],
      _demote = const [];

  static List<RegExp> _compile(List<TagPattern> tags) => [
    for (final t in tags) t.toRegExp(),
  ];

  final List<RegExp> _modern;
  final List<RegExp> _budget;
  final List<RegExp> _promote;
  final List<RegExp> _demote;

  static bool _any(List<RegExp> patterns, String name) =>
      patterns.any((p) => p.hasMatch(name));

  /// A port or compilation rip loses to the original release.
  int modernRank(String gameName) => _any(_modern, gameName) ? 1 : 0;

  /// A budget re-release *wins* — it generally carries the fixes the
  /// first pressing shipped without.
  int budgetRank(String gameName) => _any(_budget, gameName) ? 0 : 1;

  /// Promoted editions win, demoted ones lose. Promotion is applied
  /// first, so it takes the high bit and one comparison covers both.
  int editionRank(String gameName) =>
      (_any(_promote, gameName) ? 0 : 2) | (_any(_demote, gameName) ? 1 : 0);
}

/// The tie-breaks whose precedence the caller chooses.
///
/// [lang] and [ra] play no part when left out. [region] keeps a fixed position
/// instead — see [GameScore] — so naming it only moves it up.
enum ScoreAxis { lang, region, ra }

/// User-tunable inputs to the 1G1R scorer.
///
/// The `*Fallback` orders settle values the priority lists land on one position;
/// the CLI passes the full region order and the language order it implies.
final class ScoringConfig {
  ScoringConfig({
    List<String> languagePriority = const [],
    List<String> regionPriority = const [],
    List<String> languageFallback = const [],
    List<String> regionFallback = const [],
    this.priority = defaultPriority,
    this.supersets = SupersetMode.prefer,
  }) : languages = PriorityList(languagePriority, fallback: languageFallback),
       regions = PriorityList(regionPriority, fallback: regionFallback);

  /// Language, then region, then achievements.
  static const defaultPriority = [
    ScoreAxis.lang,
    ScoreAxis.region,
    ScoreAxis.ra,
  ];

  /// e.g. `['Es', 'En', 'Other']` — earlier is better.
  final PriorityList languages;

  /// e.g. `['USA', 'Europe', 'Japan', 'Unknown']` — earlier is better.
  final PriorityList regions;

  /// Which tie-breaks take part, best first. See [ScoreAxis] for what leaving
  /// one out means.
  final List<ScoreAxis> priority;

  /// What a pack is worth against the releases it stands for.
  final SupersetMode supersets;

  bool get ranksRetroAchievements => priority.contains(ScoreAxis.ra);

  /// Where a candidate sits on the superset tie-break, lower being better. A
  /// plain release is the middle value, so the mode decides whether a pack is
  /// preferred to it or yields to it.
  int supersetRank({required bool isSuperset}) => switch (supersets) {
    _ when !isSuperset => 1,
    SupersetMode.prefer => 0,
    SupersetMode.ignore => 2,
  };
}

/// The comparable 1G1R outcome, best first: production status, the [axes] the
/// caller ordered, then superset, region, clonelist priority, modern edition,
/// budget edition, revision, alternative tag, promotion and demotion.
///
/// Four placements carry the load:
///
/// - [status] above the axes, so a preproduction dump never takes the slot for
///   carrying an achievement set.
/// - The axes above the rest of the chain, so a dump is never passed over for an
///   `(Alt)` tag or an older revision when it wins on the axis ranked highest.
/// - [supersetRank] above [regionRank]: an edition standing for its group is
///   exempt from being separated by region, since it stands for it in every one.
/// - [regionRank] above everything under it whether or not [axes] names region.
///   Nothing further down may decide between two regions, and without this a
///   cross-region pair falls through to the alphabetical fail-safe.
///
/// Sorting ascending puts the winner first.
final class GameScore implements Comparable<GameScore> {
  const GameScore({
    required this.cloneListPriority,
    required this.status,
    required this.languageRank,
    required this.regionRank,
    required this.retroAchievements,
    required this.revision,
    this.supersetRank = 1,
    this.modernRank = 0,
    this.budgetRank = 0,
    this.editionRank = 0,
    this.variantRank = 0,
    this.axes = ScoringConfig.defaultPriority,
  });

  final int cloneListPriority;
  final ProductionStatus status;
  final int languageRank;
  final int regionRank;

  /// Forced to [RaMatch.none] when the caller left `ra` out of [axes], so the
  /// axis has nothing to say.
  final RaMatch retroAchievements;

  final int revision;

  /// Where the candidate sits on the superset tie-break; see
  /// [ScoringConfig.supersetRank].
  final int supersetRank;

  /// Port/compilation-rip penalty. See [EditionTags.modernRank].
  final int modernRank;

  /// Budget-re-release preference. See [EditionTags.budgetRank].
  final int budgetRank;

  /// Promotion/demotion penalty. See [EditionTags.editionRank].
  final int editionRank;

  /// "Original over alternative" penalty; 0 for an untagged release. See
  /// [ScoringEngine.variantRank].
  final int variantRank;

  /// The contested tie-breaks, best first ([ScoringConfig.priority]).
  final List<ScoreAxis> axes;

  @override
  int compareTo(GameScore other) {
    var c = status.index.compareTo(other.status.index);
    if (c != 0) return c;
    for (final axis in axes) {
      c = _onAxis(axis, other);
      if (c != 0) return c;
    }
    c = supersetRank.compareTo(other.supersetRank);
    if (c != 0) return c;
    // Region keeps ranking even when [axes] left it out; a no-op when it didn't.
    c = _onAxis(ScoreAxis.region, other);
    if (c != 0) return c;
    c = cloneListPriority.compareTo(other.cloneListPriority);
    if (c != 0) return c;
    c = modernRank.compareTo(other.modernRank);
    if (c != 0) return c;
    c = budgetRank.compareTo(other.budgetRank);
    if (c != 0) return c;
    c = other.revision.compareTo(revision);
    if (c != 0) return c;
    c = variantRank.compareTo(other.variantRank);
    if (c != 0) return c;
    return editionRank.compareTo(other.editionRank);
  }

  int _onAxis(ScoreAxis axis, GameScore other) => switch (axis) {
    ScoreAxis.lang => languageRank.compareTo(other.languageRank),
    ScoreAxis.region => regionRank.compareTo(other.regionRank),
    // Graded, so two clones that both carry achievements resolve here rather
    // than at the fail-safe: a hash join proves the set runs on these bytes, a
    // name join only suggests it.
    ScoreAxis.ra => other.retroAchievements.index.compareTo(
      retroAchievements.index,
    ),
  };
}

/// 1G1R selection: groups clones and picks one winner per group, via
/// [GameScore.compareTo].
final class ScoringEngine {
  const ScoringEngine();

  /// Exposed for `--explain`-style diagnostics.
  ///
  /// [editions] carries the `internal-config.json` edition lists; without them
  /// those tie-breaks sit out.
  GameScore score(
    GameCandidate candidate,
    ScoringConfig config, [
    EditionTags editions = const EditionTags.none(),
  ]) {
    final g = candidate.game;
    return GameScore(
      cloneListPriority:
          candidate.cloneListPriority ?? GameCandidate.defaultCloneListPriority,
      status: g.metadata.status,
      languageRank: config.languages.rank(g.metadata.languages),
      regionRank: config.regions.rank(g.metadata.regions),
      modernRank: editions.modernRank(g.name),
      budgetRank: editions.budgetRank(g.name),
      editionRank: editions.editionRank(g.name),
      variantRank: variantRank(g.name),
      retroAchievements: config.ranksRetroAchievements
          ? g.retroAchievements
          : RaMatch.none,
      revision: g.metadata.revision,
      supersetRank: config.supersetRank(isSuperset: candidate.isSuperset),
      axes: config.priority,
    );
  }

  /// Tags that mark a title as an alternative to an original release, in step
  /// 13's order of precedence.
  static final _variantTags = <RegExp>[
    RegExp(r'\(Alt.*?\)', caseSensitive: false),
    RegExp(r'\((?:\w-?\s*)*?OEM\)', caseSensitive: false),
    RegExp(r'\((?:Hibaihin|Not for Resale)\)', caseSensitive: false),
    RegExp(r'\(Covermount\)', caseSensitive: false),
    RegExp(r'\(Rerelease\)', caseSensitive: false),
  ];

  /// A bitmask over [_variantTags], most significant bit first, so one integer
  /// comparison covers the whole ordered chain. 0 means "no alternative tag",
  /// which always wins.
  static int variantRank(String gameName) {
    var rank = 0;
    for (final tag in _variantTags) {
      rank <<= 1;
      if (tag.hasMatch(gameName)) rank |= 1;
    }
    return rank;
  }

  /// One winner per clone group, deduplicated.
  ///
  /// A pack competes in every group it stands for, so it can take several slots
  /// at once; it is still returned once, which is what keeps the titles it
  /// contains from being selected beside it.
  List<GameCandidate> selectBest(
    Iterable<GameCandidate> candidates,
    ScoringConfig config, [
    EditionTags editions = const EditionTags.none(),
  ]) {
    final byGroup = <String, List<GameCandidate>>{};
    for (final c in candidates) {
      for (final key in c.groups) {
        (byGroup[key] ??= []).add(c);
      }
    }
    final winners = <GameCandidate>[];
    final taken = <String>{};
    for (final group in byGroup.values) {
      // Scored once each and reduced, not sorted: scoring walks every edition tag
      // list, which a comparator would repeat for each comparison.
      var best = group.first;
      var bestScore = score(best, config, editions);
      for (final c in group.skip(1)) {
        final s = score(c, config, editions);
        final ranked = s.compareTo(bestScore);
        // Fail-safe so a tie resolves the same way every run, whatever
        // order the DAT listed the clones in. The higher name wins.
        if (ranked < 0 ||
            (ranked == 0 && c.game.name.compareTo(best.game.name) > 0)) {
          best = c;
          bestScore = s;
        }
      }
      if (taken.add(best.game.name)) winners.add(best);
    }
    return winners;
  }
}

// --- membership ----------------------------------------------------------------

/// What naming a title in a wishlist claims about it: a set of its own, or one
/// condition among the others. That single answer settles both how the orders
/// treat it and how it meets an achievement requirement.
enum WishlistMode {
  /// A set of its own, ranked above the language and region orders: everything
  /// named is selected, those orders only choose which of its dumps you get, and
  /// an achievement requirement adds to it rather than cutting it down.
  absolute,

  /// One condition among the others: a named title still has to speak a ranked
  /// language, come from a ranked region and meet the achievement requirement.
  subset,
}

/// How much of an achievement claim a title needs: [any] speaks about titles,
/// [approved] about dumps.
enum AchievementScope {
  /// Any dump of the title carries achievements, leaving the orders to choose
  /// which one represents it.
  any,

  /// Only the dumps the achievement set was authored against — a hash match, not
  /// a title RA merely names.
  approved,
}

/// Which clone groups a wishlist reaches, and on what terms.
typedef WishlistReach = ({
  /// Games matched by name outright.
  Set<String> names,

  /// Groups a wishlisted release belongs to: every dump in them is wanted.
  Set<String> groups,

  /// Groups reached only through a pack that contains them. Naming a pack asks
  /// for the pack, not for each title inside it, so only the pack is wanted.
  Set<String> packGroups,
});

/// Resolves a wishlist against a clonelist: normalized exact-name matching,
/// never a substring, plus the group aliases that let the wishlist name any of a
/// title's regional spellings.
WishlistReach wishlistReach(
  List<String> wishlist,
  Iterable<DatGame> games,
  CloneList? cloneList,
) {
  final wanted = {for (final item in wishlist) _cleanBasename(item)}
    ..remove('');
  final names = {
    for (final g in games)
      if (wanted.contains(_cleanBasename(g.name))) g.name,
  };
  if (cloneList == null || wanted.isEmpty) {
    return (names: names, groups: const {}, packGroups: const {});
  }

  final groups = <String>{};
  final packGroups = <String>{};
  for (final variant in cloneList.variants) {
    final key = normalizeName(variant.group);
    for (final (role, titles) in [
      (TitleRole.member, variant.titles),
      (TitleRole.superset, variant.supersets),
      (TitleRole.compilation, variant.compilations),
    ]) {
      if (!titles.any((t) => wanted.contains(_cleanBasename(t.searchTerm)))) {
        continue;
      }
      (role == TitleRole.compilation ? packGroups : groups).add(key);
    }
  }
  return (
    names: names,
    groups: groups,
    packGroups: packGroups.difference(groups),
  );
}

/// Strips path, extension, parenthetical/bracket tags, and a trailing
/// mod-suffix (`  - ...`), then normalizes.
String _cleanBasename(String pathOrName) {
  var basename = _percentDecoded(
    pathOrName,
  ).split(RegExp(r'[/\\]')).last.split('?').first;

  final lastDot = basename.lastIndexOf('.');
  if (lastDot > 0 && basename.length - lastDot <= 5) {
    final ext = basename.substring(lastDot);
    // A letter is required so a volume number (`Vol.1`) survives. A bare title
    // has no region tag shielding it, so without this the wishlist side loses a
    // suffix the DAT side keeps and the two stop matching.
    if (!ext.contains(' ') &&
        RegExp(r'^\.[a-zA-Z0-9]*[a-zA-Z]$').hasMatch(ext)) {
      basename = basename.substring(0, lastDot);
    }
  }

  var noTags = basename.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ').trim();
  final modSeparator = RegExp(r'\s{2,}-\s+');
  if (modSeparator.hasMatch(noTags)) {
    noTags = noTags.split(modSeparator).first.trim();
  }
  return _normalizeTitle(noTags);
}

/// A title carrying a literal `%` is not percent-encoded, and decoding it throws.
/// Falling back to the raw string keeps the tag stripping above running, which a
/// try/catch around the whole cleanup would skip.
String _percentDecoded(String s) {
  if (!s.contains('%')) return s;
  try {
    return Uri.decodeFull(s);
  } catch (_) {
    return s;
  }
}

/// Accent-folds, lowercases, reduces to `[a-z0-9 ]`, and drops a leading/trailing
/// "the".
String _normalizeTitle(String text) {
  if (text.isEmpty) return '';
  const map = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
    'Á': 'a',
    'À': 'a',
    'Ä': 'a',
    'É': 'e',
    'È': 'e',
    'Ë': 'e',
    'Í': 'i',
    'Ì': 'i',
    'Ï': 'i',
    'Ó': 'o',
    'Ò': 'o',
    'Ö': 'o',
    'Ú': 'u',
    'Ù': 'u',
    'Ü': 'u',
    'Ñ': 'n',
    'Ç': 'c',
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
/// reportable.
final class SelectionStats {
  const SelectionStats({
    required this.total,
    required this.excluded,
    required this.language,
    required this.region,
    required this.clones,
    required this.represented,
    required this.wanted,
    required this.selected,
  });

  final int total;

  /// Dropped by `--exclude`.
  final int excluded;

  /// Dropped for speaking nothing the language order admits.
  final int language;

  /// Dropped for coming from a region the region order omits.
  final int region;

  /// Runners-up dropped by 1G1R.
  final int clones;

  /// Winners dropped because a pack already answers for their group.
  final int represented;

  /// Winners dropped by the wishlist / achievement sets.
  final int wanted;

  final int selected;

  /// Non-zero reasons as `label -n` pairs, in pipeline order.
  List<String> get reasons => [
    if (excluded > 0) 'exclude -$excluded',
    if (language > 0) 'language -$language',
    if (region > 0) 'region -$region',
    if (clones > 0) '1g1r -$clones',
    if (represented > 0) 'superset -$represented',
    if (wanted > 0) 'wishlist/ra -$wanted',
  ];
}

/// The chosen games plus the funnel that produced them.
final class SelectionResult {
  const SelectionResult({
    required this.games,
    required this.stats,
    this.groups = const {},
    this.raMatches = const {},
  });

  final List<DatGame> games;
  final SelectionStats stats;

  /// Clone group per candidate game name, winners and runners-up alike, so a
  /// caller can ask what else competed for a slot.
  final Map<String, String> groups;

  /// How each candidate reached the RetroAchievements index. Enrichment happens
  /// inside [GameSelector.select], so a caller holding the raw DAT cannot tell
  /// why the `ra` axis ordered two clones as it did.
  final Map<String, RaMatch> raMatches;
}

/// End-to-end selection:
/// enrich → exclude → filter by language/region → 1G1R → apply the wanted sets.
final class GameSelector {
  const GameSelector({
    this.enricher = const DatEnricher(),
    this.grouper = const CloneGrouper(),
    this.engine = const ScoringEngine(),
  });

  final DatEnricher enricher;
  final CloneGrouper grouper;
  final ScoringEngine engine;

  SelectionResult select({
    required DatFile dat,
    required InternalConfig config,
    required ScoringConfig scoring,
    List<String> wishlist = const [],
    WishlistMode wishlistMode = WishlistMode.absolute,
    AchievementScope? achievements,
    Set<ExcludeKind> exclude = const {},
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

    // Group first so clonelist categories are in play, exclude next, pick a
    // winner last: excluding after 1G1R would empty a group instead of promoting
    // its runner-up.
    final index = grouper.buildIndex(cloneList);
    final normalizer = TitleNormalizer(config);
    var excluded = 0;
    final grouped = <GameCandidate>[];
    for (final g in enriched.games) {
      final resolution = grouper.resolve(
        g,
        index,
        normalizer: normalizer,
        regionOrder: scoring.regions,
        defaultRegions: config.defaultRegionOrder,
      );
      if (_isExcluded(g, resolution.categories, exclude)) {
        excluded++;
        continue;
      }
      grouped.add(GameCandidate.resolved(g, resolution));
    }

    // Resolved against every grouped title, before the orders narrow anything: a
    // set that outranks them cannot be settled from what survived them.
    final wanted = wishlist.isEmpty
        ? const <String>{}
        : _wishlisted(grouped, wishlist, cloneList);

    // An absolute wishlist is ranked above the orders, so they only choose which
    // of its dumps wins; a subset wishlist sits among them and they may drop it.
    final exempt = wishlistMode == WishlistMode.absolute
        ? wanted
        : const <String>{};
    var byLanguage = 0;
    var byRegion = 0;
    var byWanted = 0;
    final candidates = <GameCandidate>[];
    for (final c in grouped) {
      if (!exempt.contains(c.game.name)) {
        // `approved` speaks about dumps, so it has to narrow the field before the
        // contest: asking it afterwards would only keep the titles whose winner
        // happened to be one, instead of the approved dumps themselves.
        if (achievements == AchievementScope.approved &&
            c.game.retroAchievements != RaMatch.byHash) {
          byWanted++;
          continue;
        }
        if (!scoring.languages.admits(c.game.metadata.languages)) {
          byLanguage++;
          continue;
        }
        if (!scoring.regions.admits(c.game.metadata.regions)) {
          byRegion++;
          continue;
        }
      }
      candidates.add(c);
    }

    final winners = engine.selectBest(candidates, scoring, EditionTags(config));
    // Every group yields one winner, so the slots a pack absorbed are the ones
    // deduplication removed.
    final groupCount = {for (final c in candidates) ...c.groups}.length;
    final chosen = _applyWantedSets(
      winners,
      candidates,
      wanted: wishlist.isEmpty ? null : wanted,
      wishlistMode: wishlistMode,
      achievements: achievements,
    );

    return SelectionResult(
      games: [for (final c in chosen) c.game],
      groups: {for (final c in candidates) c.game.name: c.groupKey},
      raMatches: {
        for (final c in candidates) c.game.name: c.game.retroAchievements,
      },
      stats: SelectionStats(
        total: dat.games.length,
        excluded: excluded,
        language: byLanguage,
        region: byRegion,
        clones: candidates.length - groupCount,
        represented: groupCount - winners.length,
        wanted: byWanted + winners.length - chosen.length,
        selected: chosen.length,
      ),
    );
  }

  /// The winners the wanted sets admit.
  ///
  /// With neither set given nothing is dropped. Given both, the wishlist's mode
  /// decides whether they meet as a union or an intersection — the same answer
  /// that decided whether the orders could touch the wishlist at all.
  static List<GameCandidate> _applyWantedSets(
    List<GameCandidate> winners,
    List<GameCandidate> candidates, {
    required Set<String>? wanted,
    required WishlistMode wishlistMode,
    required AchievementScope? achievements,
  }) {
    if (wanted == null && achievements == null) return winners;

    final earned = switch (achievements) {
      null => null,
      // A hash match speaks about one dump, so it never widens to the group.
      AchievementScope.approved => {
        for (final c in candidates)
          if (c.game.retroAchievements == RaMatch.byHash) c.game.name,
      },
      AchievementScope.any => _wholeGroups(candidates, {
        for (final c in candidates)
          if (c.game.supportsRetroAchievements) c.game.name,
      }),
    };

    bool admits(GameCandidate c) {
      final named = wanted?.contains(c.game.name);
      final plays = earned?.contains(c.game.name);
      return switch ((named, plays)) {
        (null, final p?) => p,
        (final n?, null) => n,
        (final n?, final p?) =>
          wishlistMode == WishlistMode.absolute ? n || p : n && p,
        (null, null) => true,
      };
    }

    return [
      for (final c in winners)
        if (admits(c)) c,
    ];
  }

  /// The games a wishlist names, widened to the clone group so the orders still
  /// choose which dump represents a title however you spelled it.
  ///
  /// A pack is the exception: naming one asks for the pack, so a group it merely
  /// contains admits only the pack itself.
  static Set<String> _wishlisted(
    List<GameCandidate> candidates,
    List<String> wishlist,
    CloneList? cloneList,
  ) {
    final reach = wishlistReach(wishlist, [
      for (final c in candidates) c.game,
    ], cloneList);
    return {
      for (final c in candidates)
        if (reach.names.contains(c.game.name) ||
            c.groups.any(reach.groups.contains) ||
            (c.isRepresentative && c.groups.any(reach.packGroups.contains)))
          c.game.name,
    };
  }

  /// Widens [seeds] to every dump sharing their clone groups.
  static Set<String> _wholeGroups(
    List<GameCandidate> candidates,
    Set<String> seeds,
  ) {
    final groups = {
      for (final c in candidates)
        if (seeds.contains(c.game.name)) ...c.groups,
    };
    return {
      for (final c in candidates)
        if (c.groups.any(groups.contains)) c.game.name,
    };
  }

  /// Whether any excluded kind claims this game — by the status it was graded
  /// with, by a category the DAT or the clonelist gave it, or by a name pattern
  /// standing in for a `<category>` element the DAT omits.
  static bool _isExcluded(
    DatGame g,
    List<String> groupCategories,
    Set<ExcludeKind> exclude,
  ) {
    if (exclude.isEmpty) return false;
    if (ExcludeKind.forStatus(g.metadata.status) case final kind?
        when exclude.contains(kind)) {
      return true;
    }
    for (final c in [?g.category, ...groupCategories]) {
      if (c.isNotEmpty && exclude.any((k) => k.matchesCategory(c))) return true;
    }
    return exclude.any((k) => k.matchesName(g.name));
  }
}
