/// MiNERVA Archive access.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'torrent.dart';

const kMinervaBaseUrl = 'https://minerva-archive.org';

/// Resolves MiNERVA Archive collections/platforms to their platform-wide
/// torrents (the `/browse` + `/rom` surface).
abstract interface class ArchiveSource {
  Future<List<String>> listCollections();

  Future<List<String>> listPlatforms(String collection);

  Future<PlatformTorrentRef> resolvePlatform(String collection, String platform);

  Future<Uint8List> fetchTorrentFile(PlatformTorrentRef ref);
}

/// Resolves MiNERVA Archive platforms to their platform-wide torrents.
///
/// Torrent files follow the pattern
/// `/assets/<version>/Minerva_Myrient - <collection> - <platform>.torrent`,
/// and the internal layout is `Minerva_Myrient/<collection>/<platform>/`.
final class MinervaArchiveSource implements ArchiveSource {
  MinervaArchiveSource({
    this.baseUrl = kMinervaBaseUrl,
    this.assetVersion = 'Minerva_Myrient_v0.3',
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String baseUrl;
  final String assetVersion;
  final http.Client _http;

  @override
  Future<List<String>> listCollections() async =>
      _dirNames((await _http.get(Uri.parse('$baseUrl/browse/'))).body);

  @override
  Future<List<String>> listPlatforms(String collection) async => _dirNames(
    (await _http.get(
      Uri.parse('$baseUrl/browse/${Uri.encodeComponent(collection)}/'),
    )).body,
  );

  @override
  Future<PlatformTorrentRef> resolvePlatform(
    String collection,
    String platform,
  ) async {
    final file = 'Minerva_Myrient - $collection - $platform.torrent';
    return PlatformTorrentRef(
      collection: collection,
      platform: platform,
      torrentUri: Uri.parse(
        '$baseUrl/assets/$assetVersion/${Uri.encodeComponent(file)}',
      ),
      magnetUri: Uri.parse('magnet:?dn=${Uri.encodeComponent(platform)}'),
      internalPathPrefix: 'Minerva_Myrient/$collection/$platform/',
    );
  }

  @override
  Future<Uint8List> fetchTorrentFile(PlatformTorrentRef ref) async {
    final resp = await _http.get(ref.torrentUri);
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode} for ${ref.torrentUri}');
    }
    return resp.bodyBytes;
  }

  void close() => _http.close();

  /// Extracts directory display names from a `/browse` listing page.
  List<String> _dirNames(String html) => [
    for (final m in RegExp(r'data-name="([^"]*)"').allMatches(html))
      if ((m.group(1) ?? '').isNotEmpty) m.group(1)!,
  ];
}
