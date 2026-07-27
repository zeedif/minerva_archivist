/// Retool metadata mirroring: remote fetch + local hash-validated cache.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/dat.dart';
import '../models/metadata.dart';

const kMetadataBaseUrl =
    'https://raw.githubusercontent.com/unexpectedpanda/retool-clonelists-metadata/main';

/// The five asset kinds mirrored from `unexpectedpanda/retool-clonelists-metadata`.
enum MetadataAsset { config, cloneLists, metadata, retroAchievements, mias }

/// Outcome of a metadata sync — how many asset files were fetched, were already
/// current (per `hash.json`), or removed, plus any per-file errors.
typedef SyncReport = ({
  int downloaded,
  int upToDate,
  int removed,
  List<String> errors,
});

extension SyncReportX on SyncReport {
  bool get ok => errors.isEmpty;
}

/// Provides Retool's clone/metadata/RA/MIA data locally, fetched and kept fresh
/// from the source repository.
abstract interface class MetadataRepository {
  /// Full offline mirror: for each folder, fetch its `hash.json` and download
  /// every listed file that is missing or whose SHA-256 differs. [onProgress]
  /// receives human-readable progress lines.
  Future<SyncReport> sync({
    bool force = false,
    Set<MetadataAsset>? only,
    void Function(String message)? onProgress,
  });

  Future<InternalConfig> config();

  Future<CloneList?> cloneList(String system, DatFlavor flavor);

  Future<SystemMetadata?> metadata(String system, DatFlavor flavor);

  /// Base system name (no flavor suffix); null when RA doesn't cover it.
  ///
  /// Pass [dat] to let the lookup fall back to matching the mirrored files
  /// against its ROM hashes, for the systems whose file name can't be derived
  /// from the system name.
  Future<RetroAchievementsIndex?> retroAchievements(
    String system, {
    DatFile? dat,
  });

  Future<MiaList?> mias(String system, DatFlavor flavor);
}

/// Maps a DAT's header name + flavor to a MiNERVA platform folder
/// ([baseSystem]) and to the Retool asset filenames ([metadataSystem]).
///
/// The two differ: MiNERVA ships each dump format as its own torrent, Retool
/// files them all under the plain system name. `clonelists` / `metadata` /
/// `mias` are flavor-suffixed; `retroachievements` is not.
final class SystemNameResolver {
  const SystemNameResolver({this.datFileTags = const {}});

  /// `InternalConfig.datFileTags` — the parentheticals Retool treats as dump
  /// format/tooling markers rather than part of the system name. Empty until
  /// the internal config has been read, which leaves [metadataSystem] equal to
  /// [baseSystem].
  final Set<String> datFileTags;

  SystemNameResolver withDatFileTags(Iterable<String> tags) =>
      SystemNameResolver(datFileTags: tags.toSet());

  /// The platform name MiNERVA distributes under.
  ///
  /// Strips trailing DAT-tooling markers, bracket tags and date stamps, but
  /// keeps dump-format qualifiers — each is its own MiNERVA folder.
  String baseSystem(String datName) {
    final trailing = RegExp(
      r'\s*(?:'
      r'\[[^\]]*\]' // [noIntro], [b], ...
      r'|\((?:Parent-Clone|Retool|1G1R)\)' // DAT-tooling markers
      r'|\(\d{6,8}(?:-\d{6})?\)' // (20260222-023943)
      r'|\(\d{4}-\d{2}-\d{2}(?:[ _]\d{2}-\d{2}-\d{2})?\)' // (2025-12-08 01-48-29)
      r')\s*$',
      caseSensitive: false,
    );
    var name = datName.trim();
    String previous;
    do {
      previous = name;
      name = name.replaceFirst(trailing, '').trimRight();
    } while (name != previous);
    return name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// The system name Retool files its assets under: [baseSystem] with every
  /// `(tag)` from [datFileTags] removed, wherever it appears.
  ///
  /// Ports `format_system_name()`; case-sensitive, as that tag list is.
  String metadataSystem(String datName) {
    final base = baseSystem(datName);
    if (datFileTags.isEmpty) return base;
    final tags = datFileTags.map(RegExp.escape).join('|');
    return base
        .replaceAll(RegExp(' \\((?:$tags)\\)'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  String suffix(DatFlavor flavor) => switch (flavor) {
    DatFlavor.redump || DatFlavor.mameRedump => 'Redump',
    _ => 'No-Intro',
  };

  /// The RetroAchievements base name Retool looks for: [metadataSystem] without
  /// the `Non-Redump - ` prefix (`import_clone_list()` in `input.py` strips it
  /// along with the flavor suffix, which we never add for this asset).
  String raSystem(String datName) =>
      metadataSystem(datName).replaceFirst(RegExp('^Non-Redump - '), '');

  /// RetroAchievements base names to try for [datName], best first.
  ///
  /// Retool opens `<raSystem>.json` and nothing else, which works for it only
  /// because Windows paths are case-insensitive. Part of that folder is named
  /// after RetroAchievements' own consoles rather than the DAT's system
  /// (`ColecoVision.json`, `Sony PlayStation.json`), so the second candidate
  /// drops the manufacturer prefix.
  ///
  /// Both candidates are derived from the DAT name, never looked up in a table
  /// of console names that upstream can rename. Systems whose file name can't
  /// be derived at all are matched by ROM hash instead.
  List<String> raSystemCandidates(String datName) {
    final base = raSystem(datName);
    // `Coleco - ColecoVision` -> `ColecoVision`.
    final cut = base.indexOf(' - ');
    return cut > 0 ? [base, base.substring(cut + 3)] : [base];
  }

  /// Case- and separator-insensitive comparison key, so `Sony - PlayStation`
  /// and `Sony PlayStation` collapse onto one another.
  static String normalizeKey(String name) =>
      name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');

  String assetFile(String datName, DatFlavor flavor, MetadataAsset asset) {
    if (asset == MetadataAsset.retroAchievements) {
      return '${raSystem(datName)}.json';
    }
    return '${metadataSystem(datName)} (${suffix(flavor)}).json';
  }
}

/// Fetches Retool's clone/metadata/RA/MIA data from the source repo and caches
/// it locally, validating freshness against each folder's `hash.json`.
final class RemoteMetadataRepository implements MetadataRepository {
  RemoteMetadataRepository({
    required this.cacheDir,
    this.baseUrl = kMetadataBaseUrl,
    this.resolver = const SystemNameResolver(),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String cacheDir;
  final String baseUrl;
  final SystemNameResolver resolver;
  final http.Client _client;

  static const _folders = <MetadataAsset, String>{
    MetadataAsset.cloneLists: 'clonelists',
    MetadataAsset.metadata: 'metadata',
    MetadataAsset.retroAchievements: 'retroachievements',
    MetadataAsset.mias: 'mias',
  };

  final Map<String, Map<String, String>> _manifests = {};

  @override
  Future<SyncReport> sync({
    bool force = false,
    Set<MetadataAsset>? only,
    void Function(String message)? onProgress,
  }) async {
    final assets = only ?? MetadataAsset.values.toSet();
    var downloaded = 0;
    var upToDate = 0;
    var removed = 0;
    final errors = <String>[];

    if (assets.contains(MetadataAsset.config)) {
      try {
        await _download('config/internal-config.json');
        downloaded++;
        onProgress?.call('config: internal-config.json');
      } catch (e) {
        errors.add('config/internal-config.json: $e');
      }
    }

    for (final entry in _folders.entries) {
      if (!assets.contains(entry.key)) continue;
      final folder = entry.value;

      // Refresh the manifest, then mirror every file it lists.
      Map<String, String> manifest;
      try {
        final raw =
            jsonDecode(utf8.decode(await _download('$folder/hash.json')))
                as Map<String, dynamic>;
        manifest = raw.map((k, v) => MapEntry(k, v.toString()));
        _manifests[folder] = manifest;
        downloaded++;
      } catch (e) {
        errors.add('$folder/hash.json: $e');
        continue;
      }

      final files = manifest.keys
          .where((k) => k.endsWith('.json') && k != 'hash.json')
          .toList();
      onProgress?.call('$folder: mirroring ${files.length} file(s)...');
      final result = await _mirrorFolder(folder, files, manifest, force);
      downloaded += result.downloaded;
      upToDate += result.upToDate;
      if (result.errors > 0) {
        errors.add('$folder: ${result.errors} file error(s)');
      }
      final pruned = await _pruneFolder(folder, manifest);
      removed += pruned;
      onProgress?.call(
        '$folder: ${result.downloaded} downloaded, '
        '${result.upToDate} up-to-date'
        '${pruned > 0 ? ", $pruned stale removed" : ""}'
        '${result.errors > 0 ? ", ${result.errors} error(s)" : ""}',
      );
    }

    return (
      downloaded: downloaded,
      upToDate: upToDate,
      removed: removed,
      errors: errors,
    );
  }

  /// Deletes cached assets the manifest no longer lists.
  ///
  /// Upstream renames files (`Coleco - Colecovision.json` ->
  /// `ColecoVision.json`); left in place, the old copy keeps answering lookups
  /// on a case-insensitive filesystem and pins the cache to dead data.
  Future<int> _pruneFolder(String folder, Map<String, String> manifest) async {
    final dir = Directory(p.join(cacheDir, folder));
    if (!await dir.exists()) return 0;
    // Compared case-insensitively: writing `Foo.json` over an existing
    // `foo.json` keeps the old casing on Windows, and that file is current.
    final keep = {for (final k in manifest.keys) k.toLowerCase()};
    var removed = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.json') || name == 'hash.json') continue;
      if (keep.contains(name)) continue;
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // A locked or already-deleted file isn't worth failing the sync over.
      }
    }
    return removed;
  }

  /// Downloads every listed file that is missing or whose SHA-256 differs from
  /// the manifest, with bounded concurrency.
  Future<({int downloaded, int upToDate, int errors})> _mirrorFolder(
    String folder,
    List<String> files,
    Map<String, String> manifest,
    bool force,
  ) async {
    var downloaded = 0;
    var upToDate = 0;
    var errors = 0;
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= files.length) break;
        final name = files[index];
        try {
          final local = File(p.join(cacheDir, folder, name));
          if (!force && await local.exists()) {
            final actual =
                crypto.sha256.convert(await local.readAsBytes()).toString();
            if (actual == manifest[name]) {
              upToDate++;
              continue;
            }
          }
          await _download('$folder/$name');
          downloaded++;
        } catch (_) {
          errors++;
        }
      }
    }

    final workerCount =
        files.isEmpty ? 0 : (files.length < 8 ? files.length : 8);
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    return (downloaded: downloaded, upToDate: upToDate, errors: errors);
  }

  @override
  Future<InternalConfig> config() async {
    final local = File(p.join(cacheDir, 'config', 'internal-config.json'));
    final text = await local.exists()
        ? await local.readAsString()
        : utf8.decode(await _download('config/internal-config.json'));
    return _parseConfig(jsonDecode(text) as Map<String, dynamic>);
  }

  /// [resolver] augmented with the internal config's `datFileTags`, so asset
  /// names match Retool's. Memoized — every asset lookup needs it.
  Future<SystemNameResolver> _assetResolver() async =>
      _tagged ??= resolver.withDatFileTags((await config()).datFileTags);
  SystemNameResolver? _tagged;

  @override
  Future<CloneList?> cloneList(String system, DatFlavor flavor) async {
    final r = await _assetResolver();
    final file = r.assetFile(system, flavor, MetadataAsset.cloneLists);
    final json = await _loadAssetJson(MetadataAsset.cloneLists, [file]);
    return json == null ? null : _parseCloneList(file, json);
  }

  @override
  Future<SystemMetadata?> metadata(String system, DatFlavor flavor) async {
    final r = await _assetResolver();
    final file = r.assetFile(system, flavor, MetadataAsset.metadata);
    final json = await _loadAssetJson(MetadataAsset.metadata, [file]);
    return json == null ? null : _parseMetadata(json);
  }

  @override
  Future<RetroAchievementsIndex?> retroAchievements(
    String system, {
    DatFile? dat,
  }) async {
    final r = await _assetResolver();
    final base = r.raSystem(system);
    final candidates = [
      for (final candidate in r.raSystemCandidates(system)) '$candidate.json',
    ];

    // Resolve the name up front, so a content search knows which file it has
    // already been through.
    final folder = _folders[MetadataAsset.retroAchievements]!;
    final named = _resolveAssetName(
      await _manifest(folder),
      candidates,
      separatorInsensitive: true,
    );
    final json = await _loadAssetJson(
      MetadataAsset.retroAchievements,
      named == null ? candidates : [named],
    );

    final byName = json == null ? null : _parseRa(base, json);
    if (dat == null || (byName != null && _covers(byName, dat))) return byName;
    return await _discoverRetroAchievements(base, dat, read: named) ?? byName;
  }

  /// Whether an index describes [dat] at all: any ROM hash in it, or — for the
  /// disc systems whose RA hashes are computed over the primary executable —
  /// any region-free title match.
  bool _covers(RetroAchievementsIndex index, DatFile dat) =>
      dat.games.any((g) => index.supportsGame(g) || index.supportsName(g.name));

  @override
  Future<MiaList?> mias(String system, DatFlavor flavor) async {
    final r = await _assetResolver();
    final file = r.assetFile(system, flavor, MetadataAsset.mias);
    final json = await _loadAssetJson(MetadataAsset.mias, [file]);
    return json == null ? null : _parseMia(r.metadataSystem(system), json);
  }

  void close() => _client.close();

  // --- RetroAchievements discovery by content ---

  /// Picks the mirrored RetroAchievements file whose hashes best describe [dat],
  /// for the systems RA files under a name no rule can derive from the DAT's.
  ///
  /// Reading every file to answer that would be wasteful, so the search runs in
  /// two passes over disjoint sets: first the files whose name is related to
  /// [system] — same manufacturer, or one name contained in the other — and only
  /// if none of those matches a single ROM, the rest of the folder. The file with
  /// the most matching hashes wins; a tie on zero means RA doesn't cover the
  /// system. [read] names the file the caller already resolved and rejected, and
  /// is left out of both passes.
  ///
  /// Only files already mirrored and current per `hash.json` are read: this
  /// searches the local cache and never downloads the whole folder.
  Future<RetroAchievementsIndex?> _discoverRetroAchievements(
    String system,
    DatFile dat, {
    String? read,
  }) async {
    final folder = _folders[MetadataAsset.retroAchievements]!;
    final manifest = await _manifest(folder);
    final related = <String>[];
    final rest = <String>[];
    for (final name in manifest.keys) {
      if (name == 'hash.json' || !name.endsWith('.json') || name == read) {
        continue;
      }
      (_isRelatedName(system, name) ? related : rest).add(name);
    }
    if (related.isEmpty && rest.isEmpty) return null;

    final hashes = _romHashes(dat);
    if (hashes.isEmpty) return null;
    return await _bestByHashes(folder, related, hashes, system) ??
        await _bestByHashes(folder, rest, hashes, system);
  }

  /// Whether an asset filename plausibly belongs to [system]: same manufacturer
  /// (the segment before the first ` - `), or either normalized name contains
  /// the other, which covers a console spelled longer or shorter than the DAT's.
  bool _isRelatedName(String system, String filename) {
    final asset = p.basenameWithoutExtension(filename);
    final a = SystemNameResolver.normalizeKey(system);
    final b = SystemNameResolver.normalizeKey(asset);
    if (a.isEmpty || b.isEmpty) return false;
    if (a.contains(b) || b.contains(a)) return true;
    final maker = SystemNameResolver.normalizeKey(_manufacturer(system));
    return maker.isNotEmpty &&
        SystemNameResolver.normalizeKey(_manufacturer(asset)) == maker;
  }

  /// `Coleco - ColecoVision` -> `Coleco`; a name without a ` - ` has no
  /// manufacturer segment to compare, so its first word stands in for one.
  String _manufacturer(String name) {
    final cut = name.indexOf(' - ');
    if (cut > 0) return name.substring(0, cut);
    final space = name.indexOf(' ');
    return space > 0 ? name.substring(0, space) : name;
  }

  /// Every hash a ROM in [dat] can be joined on, lowercased.
  Set<String> _romHashes(DatFile dat) => {
    for (final game in dat.games)
      for (final rom in game.roms)
        for (final hash in [rom.crc32, rom.md5, rom.sha1, rom.sha256])
          if (hash != null && hash.isNotEmpty) hash.toLowerCase(),
  };

  /// The candidate with the most entries hashing into [hashes], or null when
  /// none matches even one.
  Future<RetroAchievementsIndex?> _bestByHashes(
    String folder,
    List<String> candidates,
    Set<String> hashes,
    String system,
  ) async {
    var bestHits = 0;
    Map<String, dynamic>? best;
    for (final name in candidates) {
      final json = await _cachedAssetJson(folder, name);
      if (json == null) continue;
      var hits = 0;
      for (final entry in (json['retroachievements'] as List? ?? const [])) {
        if (entry is! Map) continue;
        for (final key in const ['crc', 'crc32', 'md5', 'sha1', 'sha256']) {
          final hash = entry[key]?.toString().toLowerCase();
          if (hash != null && hashes.contains(hash)) {
            hits++;
            break;
          }
        }
      }
      if (hits > bestHits) {
        bestHits = hits;
        best = json;
      }
    }
    return best == null ? null : _parseRa(system, best);
  }

  /// The cached copy of one asset, or null unless it is present and current.
  Future<Map<String, dynamic>?> _cachedAssetJson(
    String folder,
    String filename,
  ) async {
    final expected = (await _manifest(folder))[filename];
    if (expected == null) return null;
    final local = File(p.join(cacheDir, folder, filename));
    if (!await local.exists()) return null;
    final bytes = await local.readAsBytes();
    if (crypto.sha256.convert(bytes).toString() != expected) return null;
    final json = jsonDecode(utf8.decode(bytes));
    return json is Map<String, dynamic> ? json : null;
  }

  // --- fetching + caching ---

  String _urlFor(String relativePath) {
    final encoded = relativePath.split('/').map(Uri.encodeComponent).join('/');
    return '$baseUrl/$encoded';
  }

  Future<List<int>> _download(String relativePath) async {
    final resp = await _client.get(Uri.parse(_urlFor(relativePath)));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode} for $relativePath');
    }
    final local = File(p.join(cacheDir, p.joinAll(relativePath.split('/'))));
    await local.parent.create(recursive: true);
    await local.writeAsBytes(resp.bodyBytes);
    return resp.bodyBytes;
  }

  Future<Map<String, String>> _manifest(String folder) async {
    final cached = _manifests[folder];
    if (cached != null) return cached;
    final local = File(p.join(cacheDir, folder, 'hash.json'));
    Map<String, dynamic> raw;
    if (await local.exists()) {
      raw = jsonDecode(await local.readAsString()) as Map<String, dynamic>;
    } else {
      try {
        raw =
            jsonDecode(utf8.decode(await _download('$folder/hash.json')))
                as Map<String, dynamic>;
      } catch (_) {
        raw = const {};
      }
    }
    final manifest = raw.map((k, v) => MapEntry(k, v.toString()));
    _manifests[folder] = manifest;
    return manifest;
  }

  /// Loads one asset, resolving [candidates] (best first) against the folder's
  /// `hash.json`.
  ///
  /// The manifest doubles as a directory listing, which is the only way to
  /// notice that upstream renamed a file: asking for a name it doesn't list can
  /// only 404, and a same-named local leftover would be stale anyway.
  Future<Map<String, dynamic>?> _loadAssetJson(
    MetadataAsset asset,
    List<String> candidates, {
    bool separatorInsensitive = false,
  }) async {
    final folder = _folders[asset]!;
    final manifest = await _manifest(folder);
    // With no manifest (never synced, or offline) fall through on the primary
    // name so a direct fetch can still answer.
    final filename =
        _resolveAssetName(
          manifest,
          candidates,
          separatorInsensitive: separatorInsensitive,
        ) ??
        (manifest.isEmpty ? candidates.first : null);
    // Nothing in the folder answers to this system, so the asset doesn't exist
    // upstream (e.g. RetroAchievements only covers ~50 systems).
    if (filename == null) return null;

    final local = File(p.join(cacheDir, folder, filename));
    final expected = manifest[filename];

    if (expected != null && await local.exists()) {
      final bytes = await local.readAsBytes();
      if (crypto.sha256.convert(bytes).toString() == expected) {
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
    }

    // Not cached or stale.
    try {
      final bytes = await _download('$folder/$filename');
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on HttpException {
      return null;
    }
  }

  /// The manifest key answering the first of [candidates] that matches.
  ///
  /// Retool reads these files by name and inherits Windows' case-insensitive
  /// path matching, so an exact-case miss must not lose the file for us either.
  /// [separatorInsensitive] additionally collapses punctuation — needed for
  /// `retroachievements`, where `Sony - PlayStation` is filed as
  /// `Sony PlayStation.json`.
  String? _resolveAssetName(
    Map<String, String> manifest,
    List<String> candidates, {
    bool separatorInsensitive = false,
  }) {
    for (final wanted in candidates) {
      if (manifest.containsKey(wanted)) return wanted;
      final lower = wanted.toLowerCase();
      for (final key in manifest.keys) {
        if (key.toLowerCase() == lower) return key;
      }
      if (!separatorInsensitive) continue;
      final norm = SystemNameResolver.normalizeKey(wanted);
      for (final key in manifest.keys) {
        if (SystemNameResolver.normalizeKey(key) == norm) return key;
      }
    }
    return null;
  }

  // --- parsing ---

  InternalConfig _parseConfig(Map<String, dynamic> json) {
    final u = json['cloneListMetadataUrl'];
    final url = Uri.tryParse(u is String ? u : baseUrl) ?? Uri.parse(baseUrl);

    // languages: name -> regex of ISO-ish codes (e.g. "English" -> "En(?:-..)?").
    final languages = <String, String>{};
    final langRaw = json['languages'];
    if (langRaw is Map) {
      langRaw.forEach((k, v) {
        if (v is String) languages[k.toString()] = v;
      });
    }

    // Extract the primary code from a language regex ("En(?:-[A-Z][A-Z])?" -> "En").
    String primaryCode(String regex) =>
        RegExp(r'^([A-Za-z]{2}(?:-[A-Za-z]{2,4})?)').firstMatch(regex)?.group(1) ??
        regex;

    // defaultRegionOrder is an ORDERED object: key order = priority; each value
    // carries an impliedLanguage (a language name).
    final regionOrder = <String>[];
    final regionImplied = <String, List<String>>{};
    final regRaw = json['defaultRegionOrder'];
    if (regRaw is Map) {
      regRaw.forEach((region, v) {
        final name = region.toString();
        regionOrder.add(name);
        final impliedName = v is Map ? (v['impliedLanguage']?.toString() ?? '') : '';
        if (impliedName.isNotEmpty && languages.containsKey(impliedName)) {
          regionImplied[name] = [primaryCode(languages[impliedName]!)];
        }
      });
    } else if (regRaw is List) {
      regionOrder.addAll(regRaw.map((e) => e.toString()));
    }

    final video = <String>[];
    final vidRaw = json['defaultVideoOrder'];
    if (vidRaw is List) video.addAll(vidRaw.map((e) => e.toString()));

    List<String> strings(String key) {
      final raw = json[key];
      return raw is List ? [for (final e in raw) e.toString()] : const [];
    }

    return InternalConfig(
      cloneListMetadataUrl: url,
      languages: languages,
      defaultRegionOrder: regionOrder,
      regionImpliedLanguages: regionImplied,
      defaultVideoOrder: video,
      datFileTags: strings('datFileTags'),
      ignoreTags: _ignoreTags(json['ignoreTags']),
    );
  }

  /// `ignoreTags` is a list of `[pattern, "string"|"regex"]` pairs; literal
  /// entries are returned verbatim (escaped at use) and regexes as written.
  List<String> _ignoreTags(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is List && e.isNotEmpty) e.first.toString(),
    ];
  }

  CloneList _parseCloneList(String name, Map<String, dynamic> json) {
    final variants = <VariantGroup>[];
    for (final v in (json['variants'] as List? ?? const [])) {
      if (v is! Map) continue;
      variants.add(
        VariantGroup(
          group: v['group']?.toString() ?? '',
          titles: _titles(v['titles']),
          compilations: _titles(v['compilations']),
          categories:
              (v['categories'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
        ),
      );
    }
    return CloneList(name: name, variants: variants);
  }

  List<VariantTitle> _titles(Object? raw) {
    if (raw is! List) return const [];
    final out = <VariantTitle>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final localNames = e['localNames'];
      out.add(
        VariantTitle(
          searchTerm: e['searchTerm']?.toString() ?? '',
          priority: (e['priority'] as num?)?.toInt(),
          titlePosition: (e['titlePosition'] as num?)?.toInt(),
          filters: e['filters'],
          localNames: localNames is Map
              ? localNames.map((k, v) => MapEntry(k.toString(), v.toString()))
              : null,
        ),
      );
    }
    return out;
  }

  SystemMetadata _parseMetadata(Map<String, dynamic> json) {
    final byTitle = <String, TitleMetadata>{};
    json.forEach((k, v) {
      if (v is Map) {
        byTitle[k] = TitleMetadata(
          languages:
              (v['languages'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
          localName: v['localName']?.toString(),
        );
      }
    });
    return byTitle;
  }

  RetroAchievementsIndex _parseRa(String system, Map<String, dynamic> json) {
    final entries = <RetroAchievementsEntry>[];
    for (final e in (json['retroachievements'] as List? ?? const [])) {
      if (e is! Map) continue;
      entries.add(
        RetroAchievementsEntry(
          name: e['name']?.toString() ?? '',
          crc32: (e['crc'] ?? e['crc32'])?.toString().toLowerCase(),
          md5: e['md5']?.toString().toLowerCase(),
          sha1: e['sha1']?.toString().toLowerCase(),
          sha256: e['sha256']?.toString().toLowerCase(),
        ),
      );
    }
    return RetroAchievementsIndex(system, entries);
  }

  MiaList _parseMia(String system, Map<String, dynamic> json) {
    final names = <String>{};
    final crcs = <String>{};
    for (final e in (json['mias'] as List? ?? const [])) {
      if (e is! Map) continue;
      final n = e['name']?.toString();
      if (n != null) names.add(n);
      final c = e['crc']?.toString().toLowerCase();
      if (c != null) crcs.add(c);
    }
    return MiaList(system: system, names: names, crcs: crcs);
  }
}
