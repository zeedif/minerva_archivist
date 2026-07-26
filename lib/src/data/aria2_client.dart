/// BitTorrent engine driver: the [TorrentClient] boundary and its aria2
/// JSON-RPC implementation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'torrent.dart';

/// Drives an external BitTorrent engine (primary implementation: `aria2c` via
/// JSON-RPC) with first-class selective-file download.
abstract interface class TorrentClient {
  /// Ensure the underlying engine/daemon is running.
  Future<void> start();

  Future<TorrentHandle> add(TorrentAddRequest request);

  /// Change which 1-based file indices are downloaded on an active torrent.
  Future<void> updateSelection(TorrentHandle handle, List<int> fileIndices);

  Future<TorrentProgress> status(TorrentHandle handle);

  Stream<TorrentProgress> watch(
    TorrentHandle handle, {
    Duration interval = const Duration(seconds: 1),
  });

  Future<void> pause(TorrentHandle handle);

  Future<void> resume(TorrentHandle handle);

  Future<void> remove(TorrentHandle handle, {bool deleteData = false});

  Future<void> dispose();
}

/// Drives `aria2c` as a local JSON-RPC daemon. First-class selective download
/// via `--select-file`.
final class Aria2TorrentClient implements TorrentClient {
  Aria2TorrentClient({
    this.aria2Path = 'aria2c',
    this.port = 6800,
    this.secret = 'minerva',
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String aria2Path;
  final int port;
  final String secret;
  final http.Client _http;

  Process? _process;
  var _id = 0;

  Uri get _endpoint => Uri.parse('http://127.0.0.1:$port/jsonrpc');

  @override
  Future<void> start() async {
    if (_process != null) return;
    // A path (contains a separator) is resolved to an absolute, OS-normalized
    // path so it works regardless of cwd/slashes; a bare command is left for
    // PATH resolution.
    final executable = (aria2Path.contains('/') || aria2Path.contains(r'\'))
        ? p.normalize(p.absolute(aria2Path))
        : aria2Path;
    try {
      _process = await Process.start(executable, [
        '--enable-rpc',
        '--rpc-listen-all=false',
        '--rpc-listen-port=$port',
        '--rpc-secret=$secret',
        '--continue=true',
        '--bt-save-metadata=true',
        '--quiet=true',
      ]);
    } on ProcessException catch (e) {
      throw StateError(
        'Could not start aria2c ("$aria2Path"). Install aria2 or pass '
        '--aria2 <path>. ($e)',
      );
    }
    for (var i = 0; i < 50; i++) {
      try {
        await _call('aria2.getVersion', const []);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError('aria2c RPC did not become ready on port $port.');
  }

  @override
  Future<TorrentHandle> add(TorrentAddRequest request) async {
    final options = <String, Object?>{
      'dir': request.saveDirectory,
      // Never pre-allocate space for the whole torrent — only what we fetch.
      'file-allocation': 'none',
    };
    if (request.selectedFileIndices.isNotEmpty) {
      options['select-file'] = request.selectedFileIndices.join(',');
      // aria2 downloads only the pieces needed for selected files; this deletes
      // any unselected files materialized purely by shared piece boundaries
      // once the download completes.
      options['bt-remove-unselected-file'] = 'true';
    }
    if (!request.seedAfterComplete) options['seed-time'] = '0';

    if (request.torrentData != null) {
      final result = await _call('aria2.addTorrent', [
        base64Encode(request.torrentData!),
        <String>[],
        options,
      ]);
      return result.toString();
    }
    if (request.magnetUri != null) {
      final result = await _call('aria2.addUri', [
        [request.magnetUri],
        options,
      ]);
      return result.toString();
    }
    throw ArgumentError('TorrentAddRequest needs torrentData or magnetUri.');
  }

  @override
  Future<void> updateSelection(TorrentHandle handle, List<int> fileIndices) =>
      _call('aria2.changeOption', [
        handle,
        {'select-file': fileIndices.join(',')},
      ]);

  @override
  Future<TorrentProgress> status(TorrentHandle handle) async => _progress(
    handle,
    await _call('aria2.tellStatus', [handle]) as Map<String, dynamic>,
  );

  @override
  Stream<TorrentProgress> watch(
    TorrentHandle handle, {
    Duration interval = const Duration(seconds: 1),
  }) async* {
    while (true) {
      final progress = await status(handle);
      yield progress;
      if (progress.state == TorrentState.completed ||
          progress.state == TorrentState.error) {
        return;
      }
      await Future<void>.delayed(interval);
    }
  }

  @override
  Future<void> pause(TorrentHandle handle) => _call('aria2.pause', [handle]);

  @override
  Future<void> resume(TorrentHandle handle) => _call('aria2.unpause', [handle]);

  @override
  Future<void> remove(TorrentHandle handle, {bool deleteData = false}) =>
      _call('aria2.remove', [handle]);

  @override
  Future<void> dispose() async {
    _process?.kill();
    _process = null;
    _http.close();
  }

  Future<dynamic> _call(String method, List<Object?> params) async {
    final resp = await _http.post(
      _endpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': (_id++).toString(),
        'method': method,
        'params': ['token:$secret', ...params],
      }),
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    if (decoded['error'] != null) {
      throw StateError('aria2 error: ${decoded['error']}');
    }
    return decoded['result'];
  }

  TorrentProgress _progress(String handle, Map<String, dynamic> r) {
    int intOf(String key) => int.tryParse(r[key]?.toString() ?? '') ?? 0;

    final files = <TorrentFileProgress>[];
    for (final f in (r['files'] as List? ?? const [])) {
      final fm = f as Map<String, dynamic>;
      files.add(
        TorrentFileProgress(
          index: int.tryParse(fm['index']?.toString() ?? '') ?? 0,
          path: fm['path']?.toString() ?? '',
          completedBytes: int.tryParse(fm['completedLength']?.toString() ?? '') ?? 0,
          totalBytes: int.tryParse(fm['length']?.toString() ?? '') ?? 0,
          selected: fm['selected']?.toString() == 'true',
        ),
      );
    }

    final selected = files.where((f) => f.selected).toList();
    final selTotal = selected.fold<int>(0, (s, f) => s + f.totalBytes);
    final selDone = selected.fold<int>(0, (s, f) => s + f.completedBytes);

    return TorrentProgress(
      handle: handle,
      state: switch (r['status']?.toString()) {
        'active' => TorrentState.downloading,
        'waiting' => TorrentState.queued,
        'paused' => TorrentState.paused,
        'complete' => TorrentState.completed,
        _ => TorrentState.error,
      },
      completedBytes: selTotal > 0 ? selDone : intOf('completedLength'),
      totalBytes: selTotal > 0 ? selTotal : intOf('totalLength'),
      downloadSpeed: intOf('downloadSpeed'),
      seeders: intOf('numSeeders'),
      peers: intOf('connections'),
      files: files,
    );
  }
}
