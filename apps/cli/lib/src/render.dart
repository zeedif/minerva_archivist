import 'dart:io';

import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;

/// Prints pipeline events; download progress is a live block when the
/// terminal supports it and a line per finished file otherwise.
final class EventRenderer {
  EventRenderer({required this.apply, this.root});

  final bool apply;
  final String? root;

  /// Whether any stage reported a failure.
  bool failed = false;

  final _finished = <int>{};
  var _liveLines = 0;

  String get _dry => apply ? '' : ' (dry run)';

  void render(PipelineEvent event) {
    switch (event) {
      case SyncFinished(:final report):
        stdout.writeln(
          '[sync] ${report.downloaded} file(s) updated, '
          '${report.errors.length} error(s)',
        );
        failed |= report.errors.isNotEmpty;
      case PlatformStarted(:final dat):
        _finished.clear();
        stdout.writeln(
          '\n=== ${dat.header.name} [${dat.header.flavor.name}] ===',
        );
      case SelectionFinished(:final selection):
        stdout.writeln('[select] ${funnel(selection)}');
        for (final entry in selection.unmatchedWishlist) {
          stdout.writeln('         ? wishlist entry matches nothing: $entry');
        }
      case AuditFinished(:final report):
        stdout.writeln(
          '[audit] ${report.present.length}/${report.results.length} on disk, '
          '${report.missing.length} missing, '
          '${report.unknownFiles.length} unknown; ${report.library.summary}',
        );
      case DownloadPlanned(
        :final plan,
        :final missing,
        :final held,
        :final seeders,
      ):
        stdout.writeln(
          '[download] $missing missing -> ${plan.selected.length} to fetch, '
          '${size(plan.totalBytes)}'
          '${seeders == null ? "" : ", $seeders seeder(s)"}$_dry',
        );
        for (final name in plan.unmatched) {
          stdout.writeln('           ? not distributed: $name');
        }
        for (final name in held) {
          stdout.writeln('           = held by a curated folder: $name');
        }
      case DownloadProgress(:final snapshot):
        _progress(snapshot);
      case DownloadFinished(:final files, :final unrecognized):
        _clearLive();
        stdout.writeln('[download] ${files.length} file(s) fetched');
        for (final file in unrecognized) {
          stdout.writeln(
            '           ! not described by this DAT: ${p.basename(file.path)}',
          );
        }
      case OrganizeFinished(:final actions):
        stdout.writeln('[organize] ${actions.summary}$_dry');
        for (final a in actions.where((a) => a.op == OrganizeOp.failed)) {
          stderr.writeln('           ! ${a.game}: ${a.error}');
          failed = true;
        }
      case PlaylistsFinished(:final playlists):
        stdout.writeln('[playlists] ${playlists.length} written$_dry');
      case PruneFinished(:final moved, :final curatedDuplicates):
        stdout.writeln(
          '[prune] ${moved.length} moved to $trashFolderName$_dry',
        );
        for (final file in moved) {
          stdout.writeln('        - ${_relative(file, trashFolderName)}');
        }
        for (final file in curatedDuplicates) {
          stdout.writeln(
            '        = duplicate kept in a curated folder: ${_relative(file)}',
          );
        }
      case StageFailed(:final stage, :final message):
        _clearLive();
        stderr.writeln('[${stage.name}] failed: $message');
        failed = true;
    }
  }

  void _progress(TransferSnapshot snapshot) {
    _clearLive();
    for (final file in snapshot.files) {
      if (file.isComplete && _finished.add(file.index)) {
        stdout.writeln('           + ${file.name}');
      }
    }
    if (!stdout.supportsAnsiEscapes || snapshot.isComplete) return;

    final width = stdout.hasTerminal ? stdout.terminalColumns - 1 : 79;
    final lines = [
      for (final file
          in snapshot.files
              .where((f) => !f.isComplete && f.done > 0)
              .take(_liveRows))
        '   ${(file.fraction * 100).toStringAsFixed(1).padLeft(5)}%  '
            '${size(file.done)}/${size(file.total)}  ${file.name}',
      '   ${_finished.length}/${snapshot.files.length} files  '
          '${size(snapshot.done)}/${size(snapshot.total)}  '
          '${size(snapshot.bytesPerSecond)}/s  '
          '${snapshot.seeds} seeds, ${snapshot.peers} peers',
    ];
    for (final line in lines) {
      stdout.writeln(line.length > width ? line.substring(0, width) : line);
    }
    _liveLines = lines.length;
  }

  /// Erases the live block so the next output replaces it.
  void _clearLive() {
    if (_liveLines == 0) return;
    stdout.write('\x1B[${_liveLines}A\x1B[0J');
    _liveLines = 0;
  }

  String _relative(File file, [String? under]) =>
      p.relative(file.path, from: p.joinAll([?root, ?under]));

  static const _liveRows = 12;

  /// `404 -> 309  (exclude -55, language -30, 1g1r -10)`
  static String funnel(SelectionResult selection) {
    final stats = selection.stats;
    final why = stats.reasons.isEmpty ? '' : '  (${stats.reasons.join(', ')})';
    return '${stats.total} -> ${stats.selected}$why';
  }

  static String size(int bytes) => switch (bytes) {
    >= 1 << 30 => '${(bytes / (1 << 30)).toStringAsFixed(2)} GB',
    >= 1 << 20 => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB',
    _ => '${(bytes / 1024).toStringAsFixed(0)} KB',
  };
}
