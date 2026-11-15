/// Matching wanted games to the files of a platform torrent.
library;

import '../data/torrent.dart';
import '../models/dat.dart';

/// Folder under the ROM root owned by this tool: downloads in progress and
/// its own state. Never audited, organized or pruned.
const workFolderName = '.minerva';

/// Where a fetch lands before its files join the collection.
const incomingFolderName = 'incoming';

/// The torrent files that answer for a set of wanted games.
final class DownloadPlan {
  const DownloadPlan._(this.selected, this.unmatched);

  /// Matches each game to `<game name>.zip`, case-insensitively, wherever the
  /// torrent keeps it.
  factory DownloadPlan.match(
    Iterable<DatGame> wanted,
    TorrentManifest manifest,
  ) {
    final byName = <String, TorrentFile>{};
    for (final file in manifest.files) {
      byName.putIfAbsent(file.basename.toLowerCase(), () => file);
    }
    final selected = <TorrentFile>{};
    final unmatched = <String>[];
    for (final game in wanted) {
      switch (byName['${game.name}.zip'.toLowerCase()]) {
        case final file?:
          selected.add(file);
        case null:
          unmatched.add(game.name);
      }
    }
    return DownloadPlan._(
      selected.toList()..sort((a, b) => a.index.compareTo(b.index)),
      unmatched..sort(),
    );
  }

  final List<TorrentFile> selected;

  /// Wanted games the torrent does not carry.
  final List<String> unmatched;

  int get totalBytes => selected.fold(0, (sum, f) => sum + f.length);

  /// Torrent file index to the flat name it is saved under.
  Map<int, String> get files => {
    for (final file in selected) file.index: file.basename,
  };
}
