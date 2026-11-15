/// Download planning (DAT → torrent file selection) and post-download cleanup.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/torrent.dart';
import '../models/dat.dart';

/// The outcome of matching wanted games to a platform-wide torrent.
final class DownloadPlan {
  const DownloadPlan({
    required this.selectedIndices,
    required this.selectedFiles,
    required this.totalBytes,
    required this.unmatched,
  });

  /// 1-based file indices to pass to the torrent client.
  final List<int> selectedIndices;
  final List<TorrentFileEntry> selectedFiles;
  final int totalBytes;

  /// Wanted zip names not present in the torrent.
  final List<String> unmatched;
}

/// Matches wanted games against a torrent's file list by zip basename
/// (`<game name>.zip`, MiNERVA's convention), robust to the torrent's internal
/// path prefix.
final class DownloadPlanner {
  const DownloadPlanner();

  DownloadPlan plan(Iterable<DatGame> wanted, TorrentManifest manifest) {
    final wantedZips = {for (final g in wanted) '${g.name}.zip'.toLowerCase()};
    final byBasename = <String, TorrentFileEntry>{};
    for (final f in manifest.files) {
      byBasename[_basename(f.path).toLowerCase()] = f;
    }

    final selected = <TorrentFileEntry>[];
    final matched = <String>{};
    for (final zip in wantedZips) {
      final file = byBasename[zip];
      if (file != null) {
        selected.add(file);
        matched.add(zip);
      }
    }
    selected.sort((a, b) => a.index.compareTo(b.index));

    return DownloadPlan(
      selectedIndices: [for (final f in selected) f.index],
      selectedFiles: selected,
      totalBytes: selected.fold(0, (sum, f) => sum + f.length),
      unmatched: (wantedZips.difference(matched).toList())..sort(),
    );
  }

  DownloadPlan planAll(TorrentManifest manifest) => DownloadPlan(
    selectedIndices: [for (final f in manifest.files) f.index],
    selectedFiles: manifest.files,
    totalBytes: manifest.files.fold(0, (sum, f) => sum + f.length),
    unmatched: const [],
  );

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? path : path.substring(i + 1);
  }
}

/// Outcome of flattening a completed torrent download.
final class RelocationResult {
  const RelocationResult({
    required this.moved,
    required this.discarded,
    required this.removedControlFiles,
  });

  final List<File> moved;

  /// Files present under the tree but NOT in the keep set (boundary-materialized
  /// unselected files) — left behind and removed with the nesting tree.
  final int discarded;

  final int removedControlFiles;
}

/// Flattens a completed torrent download.
///
/// aria2 preserves the torrent's nesting, which risks Windows' `MAX_PATH`. This
/// moves the selected files up to the ROM root and deletes the control files
/// and now-empty tree, leaving a flat layout for the later stages.
final class TorrentRelocator {
  const TorrentRelocator();

  Future<RelocationResult> flatten({
    required Directory romRoot,
    required String topDir,

    /// Lowercased basenames of the files to preserve. When null, everything is
    /// kept (legacy behavior).
    Set<String>? keepBasenames,
  }) async {
    final moved = <File>[];
    var discarded = 0;
    var removedControl = 0;

    // Top-level control file, e.g. Minerva_Myrient.aria2.
    final topControl = File(p.join(romRoot.path, '$topDir.aria2'));
    if (await topControl.exists()) {
      await topControl.delete();
      removedControl++;
    }

    final nested = Directory(p.join(romRoot.path, topDir));
    if (!await nested.exists()) {
      return RelocationResult(
        moved: moved,
        discarded: discarded,
        removedControlFiles: removedControl,
      );
    }

    // Snapshot first (don't mutate the tree while listing it).
    final entities = await nested.list(recursive: true, followLinks: false).toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      if (entity.path.toLowerCase().endsWith('.aria2')) {
        await entity.delete();
        removedControl++;
        continue;
      }
      final base = p.basename(entity.path);
      if (keepBasenames != null && !keepBasenames.contains(base.toLowerCase())) {
        // Unselected boundary leftover — don't promote it; the recursive
        // delete below reclaims its space.
        discarded++;
        continue;
      }
      final dest = File(p.join(romRoot.path, base));
      if (p.equals(entity.path, dest.path)) continue;
      if (await dest.exists()) await dest.delete();
      await entity.rename(dest.path);
      moved.add(dest);
    }

    // Remove the nesting tree: empty dirs + any discarded/partial files.
    if (await nested.exists()) await nested.delete(recursive: true);

    return RelocationResult(
      moved: moved,
      discarded: discarded,
      removedControlFiles: removedControl,
    );
  }
}
