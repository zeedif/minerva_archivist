/// MiNERVA Archive access: platform torrents and swarm health.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Resolves a MiNERVA platform to its torrent. Every platform is one torrent
/// holding `Minerva_Myrient/<collection>/<platform>/<game>.zip`.
final class MinervaArchive {
  MinervaArchive({
    this.baseUrl = 'https://minerva-archive.org',
    this.release = 'Minerva_Myrient_v0.3',
    this.timeout = const Duration(seconds: 60),
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String baseUrl;

  /// The `/assets/` folder tried first; a newer one is discovered when it 404s.
  final String release;
  final Duration timeout;
  final http.Client _http;

  /// The `.torrent` of [platform] in [collection] (`No-Intro`, `Redump`).
  ///
  /// Throws [HttpException] when the archive does not publish one.
  Future<Uint8List> platformTorrent(String collection, String platform) async {
    final file = Uri.encodeComponent(
      'Minerva_Myrient - $collection - $platform.torrent',
    );
    final known = await _get('$baseUrl/assets/$release/$file');
    if (known.statusCode == 200) return known.bodyBytes;

    final discovered = await _discoverTorrentUrl(collection, platform);
    if (discovered == null) {
      throw HttpException('No torrent published for $collection / $platform.');
    }
    final response = await _get(discovered);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $discovered');
    }
    return response.bodyBytes;
  }

  /// Seeders the archive's tracker reports for [infoHash], or null when the
  /// torrent is not listed or the dashboard is unreachable.
  Future<int?> seeders(String infoHash) async {
    try {
      final response = await _get('$baseUrl/v1/api/dashboard/latest');
      if (response.statusCode != 200) return null;
      if (jsonDecode(response.body) case {'torrents': final List torrents}) {
        for (final torrent in torrents) {
          if (torrent case {
            'info_hash': final String hash,
            'seeders': final int seeders,
          } when hash.toLowerCase() == infoHash) {
            return seeders;
          }
        }
      }
    } on Exception {
      // Health is advisory.
    }
    return null;
  }

  void close() => _http.close();

  /// Follows the platform listing to any file page, which links the torrent.
  Future<String?> _discoverTorrentUrl(
    String collection,
    String platform,
  ) async {
    final listing = await _get(
      '$baseUrl/browse/${Uri.encodeComponent(collection)}/'
      '${Uri.encodeComponent(platform)}/',
    );
    final romPage = _romLink.firstMatch(listing.body)?.group(1);
    if (romPage == null) return null;
    final page = await _get('$baseUrl$romPage');
    final href = _torrentLink.firstMatch(page.body)?.group(1);
    return href == null
        ? null
        : Uri.parse(baseUrl).resolve(Uri.encodeFull(href)).toString();
  }

  Future<http.Response> _get(String url) =>
      _http.get(Uri.parse(url)).timeout(timeout);

  static final _romLink = RegExp(r'href="(/rom\?id=\d+)"');
  static final _torrentLink = RegExp(r'href="(/assets/[^"]+\.torrent)"');
}
