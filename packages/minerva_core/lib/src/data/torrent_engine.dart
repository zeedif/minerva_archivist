/// Selective BitTorrent downloads through an in-process libtorrent session.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:libtorrent_dart/libtorrent_dart.dart' as lt;
import 'package:path/path.dart' as p;

/// Which files of a torrent to fetch, and where.
final class FetchRequest {
  const FetchRequest({
    required this.torrent,
    required this.into,
    required this.files,
    this.stallTimeout = const Duration(minutes: 3),
  });

  /// Raw `.torrent` bytes.
  final Uint8List torrent;

  /// Receives every file directly, with no torrent folder structure.
  final Directory into;

  /// 0-based torrent file index to the name it is written under in [into].
  final Map<int, String> files;

  /// How long the transfer may go without receiving a byte.
  final Duration stallTimeout;
}

/// Byte-exact progress of one requested file.
final class FileTransfer {
  const FileTransfer({
    required this.index,
    required this.name,
    required this.done,
    required this.total,
  });

  final int index;
  final String name;
  final int done;
  final int total;

  bool get isComplete => done >= total;
  double get fraction => total == 0 ? 1 : done / total;
}

/// The state of a fetch at one instant.
final class TransferSnapshot {
  const TransferSnapshot({
    required this.files,
    required this.bytesPerSecond,
    required this.seeds,
    required this.peers,
  });

  final List<FileTransfer> files;
  final int bytesPerSecond;
  final int seeds;
  final int peers;

  int get done => files.fold(0, (sum, f) => sum + f.done);
  int get total => files.fold(0, (sum, f) => sum + f.total);
  bool get isComplete => files.every((f) => f.isComplete);
}

/// A fetch that ended without every requested file.
final class TransferException implements Exception {
  const TransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class TorrentEngine {
  /// Downloads the requested files, emitting a snapshot per [interval] and a
  /// final complete one before closing.
  ///
  /// Partial data is kept when the subscription is cancelled or the stream
  /// fails with a [TransferException], so a later fetch resumes from it.
  Stream<TransferSnapshot> fetch(
    FetchRequest request, {
    Duration interval = const Duration(seconds: 1),
  });

  /// Stops every transfer and releases the session.
  void close();
}

/// Runs libtorrent inside this process: nothing is spawned, nothing outlives
/// it, and nothing is seeded once a fetch completes.
final class LibtorrentEngine implements TorrentEngine {
  lt.Session? _session;

  @override
  Stream<TransferSnapshot> fetch(
    FetchRequest request, {
    Duration interval = const Duration(seconds: 1),
  }) async* {
    if (request.files.isEmpty) return;
    await request.into.create(recursive: true);

    final session = _session ??= lt.createSession();
    final handle = session.addTorrentData(
      torrentData: request.torrent,
      savePath: p.normalize(p.absolute(request.into.path)),
      renamedFiles: request.files,
    );
    var finished = false;
    try {
      final entries = handle.getFiles();
      handle.prioritizeFiles([
        for (final entry in entries)
          request.files.containsKey(entry.index) ? _wanted : _skipped,
      ]);
      final sizes = {for (final entry in entries) entry.index: entry.size};

      var lastDone = -1;
      final idle = Stopwatch()..start();
      while (true) {
        final status = handle.getStatus();
        if (status.error.isNotEmpty) throw TransferException(status.error);

        final progress = handle.getFileProgress();
        final snapshot = TransferSnapshot(
          files: [
            for (final MapEntry(key: index, value: name)
                in request.files.entries)
              FileTransfer(
                index: index,
                name: name,
                done: progress[index],
                total: sizes[index]!,
              ),
          ],
          bytesPerSecond: status.downloadPayloadRate.round(),
          seeds: status.numSeeds,
          peers: status.numPeers,
        );
        yield snapshot;
        if (snapshot.isComplete) {
          finished = true;
          return;
        }

        if (snapshot.done != lastDone) {
          lastDone = snapshot.done;
          idle.reset();
        } else if (idle.elapsed > request.stallTimeout) {
          throw TransferException(
            'No data received for ${request.stallTimeout.inMinutes} min '
            '(${status.numSeeds} seeds, ${status.numPeers} peers).',
          );
        }
        await Future<void>.delayed(interval);
      }
    } finally {
      handle.cancel(deleteFiles: false, deletePartfile: finished);
    }
  }

  @override
  void close() {
    _session?.close();
    _session = null;
  }

  static const _skipped = 0;
  static const _wanted = 4;
}
