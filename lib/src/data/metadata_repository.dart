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
  Future<RetroAchievementsIndex?> retroAchievements(String system);

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

  String assetFile(String datName, DatFlavor flavor, MetadataAsset asset) {
    final base = metadataSystem(datName);
    if (asset == MetadataAsset.retroAchievements) return '$base.json';
    return '$base (${suffix(flavor)}).json';
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
      onProgress?.call(
        '$folder: ${result.downloaded} downloaded, '
        '${result.upToDate} up-to-date'
        '${result.errors > 0 ? ", ${result.errors} error(s)" : ""}',
      );
    }

    return (
      downloaded: downloaded,
      upToDate: upToDate,
      removed: 0,
      errors: errors,
    );
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
    final json = await _loadAssetJson(MetadataAsset.cloneLists, file);
    return json == null ? null : _parseCloneList(file, json);
  }

  @override
  Future<SystemMetadata?> metadata(String system, DatFlavor flavor) async {
    final r = await _assetResolver();
    final file = r.assetFile(system, flavor, MetadataAsset.metadata);
    final json = await _loadAssetJson(MetadataAsset.metadata, file);
    return json == null ? null : _parseMetadata(json);
  }

  @override
  Future<RetroAchievementsIndex?> retroAchievements(String system) async {
    final r = await _assetResolver();
    final file = r.assetFile(
      system,
      DatFlavor.unknown,
      MetadataAsset.retroAchievements,
    );
    final json = await _loadAssetJson(MetadataAsset.retroAchievements, file);
    return json == null ? null : _parseRa(r.metadataSystem(system), json);
  }

  @override
  Future<MiaList?> mias(String system, DatFlavor flavor) async {
    final r = await _assetResolver();
    final file = r.assetFile(system, flavor, MetadataAsset.mias);
    final json = await _loadAssetJson(MetadataAsset.mias, file);
    return json == null ? null : _parseMia(r.metadataSystem(system), json);
  }

  void close() => _client.close();

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

  Future<Map<String, dynamic>?> _loadAssetJson(
    MetadataAsset asset,
    String filename,
  ) async {
    final folder = _folders[asset]!;
    final local = File(p.join(cacheDir, folder, filename));
    final expected = (await _manifest(folder))[filename];

    if (expected != null && await local.exists()) {
      final bytes = await local.readAsBytes();
      if (crypto.sha256.convert(bytes).toString() == expected) {
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
    }

    // Not cached or stale. A 404 means the asset doesn't exist for this system
    // (e.g. RetroAchievements only covers ~61 systems).
    try {
      final bytes = await _download('$folder/$filename');
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on HttpException {
      return null;
    }
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
