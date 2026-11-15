/// What one run is asked to do, and the named profiles that store it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/dat.dart';
import 'organize.dart';
import 'selection.dart';

/// The stages of a run that can be left out.
enum Stage { sync, download, organize, playlists, prune }

/// Every setting of a run. Keys of [RunOptions.fromJson] are the option
/// names the CLI and the profiles file share.
final class RunOptions {
  const RunOptions({
    required this.dats,
    this.root,
    this.languages = const ['En'],
    this.regions = const [],
    this.priority = ScoringConfig.defaultPriority,
    this.langCount,
    this.wishlist,
    this.wishlistMode = WishlistMode.absolute,
    this.achievements,
    this.supersets = SupersetMode.prefer,
    this.compilations = CompilationMode.fill,
    this.exclude = const {},
    this.layout = Layout.zip,
    this.protect = const {},
    this.skip = const {},
    this.depth,
  });

  /// Reads options from decoded JSON.
  ///
  /// Relative `root` and `wishlist` paths resolve against [baseDir]. Throws
  /// [FormatException] naming the offending key.
  factory RunOptions.fromJson(Map<String, Object?> json, {String? baseDir}) {
    if (json.keys.where((k) => !keys.contains(k)).firstOrNull case final key?) {
      throw FormatException('Unknown option "$key".');
    }
    String? path(String key) => switch (json[key]) {
      null => null,
      final String value => baseDir == null ? value : p.join(baseDir, value),
      _ => throw FormatException('"$key" must be a path.'),
    };
    final priority = _enums(json, 'priority', ScoreAxis.values, (a) => a.name);
    final langCount = _enum(json, 'langcount', LangCount.values, (c) => c.name);
    if (priority != null && priority.toSet().length != priority.length) {
      throw const FormatException('"priority" names an axis twice.');
    }
    final byCount = priority?.contains(ScoreAxis.langcount) ?? false;
    if (byCount != (langCount != null)) {
      throw FormatException(
        byCount
            ? '"priority" names langcount, so "langcount" must say most or fewest.'
            : '"langcount" needs langcount in "priority".',
      );
    }
    return RunOptions(
      dats: _strings(json, 'dat') ?? const [],
      root: path('root'),
      languages: _strings(json, 'lang') ?? const ['En'],
      regions: _strings(json, 'region') ?? const [],
      priority: priority ?? ScoringConfig.defaultPriority,
      langCount: langCount,
      wishlist: path('wishlist'),
      wishlistMode:
          _enum(json, 'wishlist-mode', WishlistMode.values, (m) => m.name) ??
          WishlistMode.absolute,
      achievements: _enum(
        json,
        'achievements',
        AchievementScope.values,
        (s) => s.name,
      ),
      supersets:
          _enum(json, 'supersets', SupersetMode.values, (m) => m.name) ??
          SupersetMode.prefer,
      compilations:
          _enum(json, 'compilations', CompilationMode.values, (m) => m.name) ??
          CompilationMode.fill,
      exclude: {...?_enums(json, 'exclude', ExcludeKind.values, (k) => k.cli)},
      layout: _enum(json, 'layout', Layout.values, (l) => l.cli) ?? Layout.zip,
      protect: {...?_strings(json, 'protect')},
      skip: {...?_enums(json, 'skip', Stage.values, (s) => s.name)},
      depth: switch (json['depth']) {
        null => null,
        final int depth when depth >= 0 => depth,
        final String text when int.tryParse(text) != null => int.parse(text),
        _ => throw const FormatException('"depth" must be 0 or more.'),
      },
    );
  }

  /// The option names [RunOptions.fromJson] accepts.
  static const keys = {
    'dat', 'root', 'lang', 'region', 'priority', 'langcount', 'wishlist',
    'wishlist-mode', 'achievements', 'supersets', 'compilations', 'exclude',
    'layout', 'protect', 'skip', 'depth', //
  };

  /// DAT references: a file, a folder of DATs, or a system name optionally
  /// prefixed with its source (`redump:Sony - PlayStation`).
  final List<String> dats;

  /// The ROM collection; null limits a run to selection.
  final String? root;
  final List<String> languages;

  /// Empty means the full region order, which restricts nothing.
  final List<String> regions;
  final List<ScoreAxis> priority;
  final LangCount? langCount;
  final String? wishlist;
  final WishlistMode wishlistMode;
  final AchievementScope? achievements;
  final SupersetMode supersets;
  final CompilationMode compilations;
  final Set<ExcludeKind> exclude;
  final Layout layout;
  final Set<String> protect;
  final Set<Stage> skip;

  /// How many folders below [root] are searched; null is unbounded.
  final int? depth;

  static List<String>? _strings(Map<String, Object?> json, String key) =>
      switch (json[key]) {
        null => null,
        final String value => [value],
        final List<Object?> values when values.every((v) => v is String) =>
          values.cast<String>(),
        _ => throw FormatException('"$key" must be a list of strings.'),
      };

  static T? _enum<T extends Enum>(
    Map<String, Object?> json,
    String key,
    List<T> values,
    String Function(T) spelling,
  ) => switch (json[key]) {
    null => null,
    final String value => _parse(key, value, values, spelling),
    _ => throw FormatException(
      '"$key" must be one of ${_list(values, spelling)}.',
    ),
  };

  static List<T>? _enums<T extends Enum>(
    Map<String, Object?> json,
    String key,
    List<T> values,
    String Function(T) spelling,
  ) => _strings(
    json,
    key,
  )?.map((value) => _parse(key, value, values, spelling)).toList();

  static T _parse<T extends Enum>(
    String key,
    String value,
    List<T> values,
    String Function(T) spelling,
  ) =>
      values.where((v) => spelling(v) == value).firstOrNull ??
      (throw FormatException(
        '"$value" is not a valid "$key": use ${_list(values, spelling)}.',
      ));

  static String _list<T>(List<T> values, String Function(T) spelling) =>
      values.map(spelling).join(', ');
}

/// Named option sets read from a JSON/JSONC file shaped
/// `{"defaults": {...}, "profiles": {"<name>": {...}}}`.
final class Profiles {
  const Profiles._(this._defaults, this._profiles, this._baseDir);

  /// Throws [FormatException] when [file] is not shaped as documented.
  static Future<Profiles> load(File file) async {
    final decoded = jsonDecode(stripJsonComments(await file.readAsString()));
    if (decoded case {'profiles': final Map<String, Object?> profiles}) {
      return Profiles._(
        switch (decoded['defaults']) {
          final Map<String, Object?> defaults => defaults,
          null => const {},
          _ => throw const FormatException('"defaults" must be an object.'),
        },
        {
          for (final MapEntry(:key, :value) in profiles.entries)
            key: value is Map<String, Object?>
                ? value
                : throw FormatException('Profile "$key" must be an object.'),
        },
        p.dirname(p.absolute(file.path)),
      );
    }
    throw const FormatException('A profiles file needs a "profiles" object.');
  }

  final Map<String, Object?> _defaults;
  final Map<String, Map<String, Object?>> _profiles;
  final String _baseDir;

  Iterable<String> get names => _profiles.keys;

  /// The options of [name]: defaults, then the profile, then [overrides].
  ///
  /// Throws [FormatException] when no profile is called [name].
  RunOptions resolve(String name, {Map<String, Object?> overrides = const {}}) {
    final profile =
        _profiles[name] ??
        (throw FormatException(
          'No profile "$name". Known: ${names.join(', ')}.',
        ));
    final stored = RunOptions.fromJson({
      ..._defaults,
      ...profile,
    }, baseDir: _baseDir);
    if (overrides.isEmpty) return stored;
    final absolute = {
      ..._defaults,
      ...profile,
      'root': ?stored.root,
      'wishlist': ?stored.wishlist,
      ...overrides,
    };
    return RunOptions.fromJson(absolute);
  }
}
