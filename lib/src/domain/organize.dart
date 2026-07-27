/// On-disk library layout: the 4-mode organizer, in-place canonicalisation of
/// curated folders, `.m3u` playlists, and the reversible pruner.
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'auditor.dart';
import 'library.dart';

enum FolderLayout {
  /// Files/folders sit directly in the ROM root.
  flat,

  /// ES-DE "folder-as-file": each game gets its own folder.
  folderAsFile,
}

/// Organization config. The four legacy layout modes are the (layout × extract)
/// matrix:
///
/// | layout        | extract | result                                              |
/// |---------------|---------|-----------------------------------------------------|
/// | flat          | false   | `<root>/<game>.zip`                    (Archived Flat)|
/// | flat          | true    | `<root>/<game>.<ext>` or `<root>/<game>/<tracks>` (Smart Flat)|
/// | folderAsFile  | false   | `<root>/<game>/<game>.zip`         (Archived in Folder)|
/// | folderAsFile  | true    | `<root>/<game>.<ext>/<game>.<ext>` or `<root>/<game>/<tracks>` |
final class OrganizeConfig {
  const OrganizeConfig({
    this.layout = FolderLayout.flat,
    this.extract = false,
    this.protectedFolders = const {},
  });

  final FolderLayout layout;

  /// When true, `.zip` archives are unzipped; when false, kept compressed.
  final bool extract;

  /// Top-level folder names never touched (user mods/hacks/patches).
  final Set<String> protectedFolders;

  /// The same layout with [folders] protected too. Curated folders are discovered
  /// per audit, so they join the explicitly protected ones here rather than at
  /// the point the layout is read off the command line.
  OrganizeConfig protecting(Set<String> folders) => OrganizeConfig(
    layout: layout,
    extract: extract,
    protectedFolders: {...protectedFolders, ...folders},
  );
}

enum OrganizeOp { moved, extracted, renamed, skippedProtected, failed }

/// A planned or executed organization step.
final class OrganizeAction {
  const OrganizeAction({
    required this.op,
    required this.game,
    required this.destination,
    this.error,
  });

  final OrganizeOp op;
  final String game;

  /// Final path (file or folder) the game was placed at, or the protected path
  /// that was skipped.
  final String destination;

  /// Why the step failed, when [op] is [OrganizeOp.failed].
  final String? error;
}

extension OrganizeActionsX on List<OrganizeAction> {
  int countOf(OrganizeOp op) => where((a) => a.op == op).length;

  /// `12 moved, 3 extracted, 1 protected-skip, 1 failed` — zero counts omitted.
  String get summary {
    final parts = [
      if (countOf(OrganizeOp.moved) > 0) '${countOf(OrganizeOp.moved)} moved',
      if (countOf(OrganizeOp.extracted) > 0)
        '${countOf(OrganizeOp.extracted)} extracted',
      if (countOf(OrganizeOp.renamed) > 0)
        '${countOf(OrganizeOp.renamed)} renamed in place',
      if (countOf(OrganizeOp.skippedProtected) > 0)
        '${countOf(OrganizeOp.skippedProtected)} protected-skip',
      if (countOf(OrganizeOp.failed) > 0) '${countOf(OrganizeOp.failed)} failed',
    ];
    return parts.isEmpty ? 'nothing to do' : parts.join(', ');
  }
}

/// Lays out present ROMs on disk (EmulationStation-DE compatible) across the
/// four (layout × extract) modes with streaming zip extraction (no
/// whole-archive-in-memory, safe for large disc sets), renaming to the
/// canonical DAT name and never disturbing protected/user-content folders.
final class EsdeRomOrganizer {
  const EsdeRomOrganizer();

  /// If a destination folder already contains any of these, it's treated as a
  /// user folder (patches/saves/hacks) and left untouched.
  static const _userContentExtensions = {
    '.ips', '.bps', '.ups', '.aps', '.xdelta', '.patch',
    '.sav', '.srm', '.state', '.cht', '.rtc', '.mcr',
  };

  Future<List<OrganizeAction>> organize({
    required Iterable<AuditedRom> present,
    required Directory romRoot,
    OrganizeConfig config = const OrganizeConfig(),
    bool dryRun = false,
  }) async {
    final actions = <OrganizeAction>[];
    for (final ar in present) {
      final source = ar.location;
      if (source == null) continue;
      final game = ar.game.name;

      // Never touch files that live under a protected top-level folder.
      final top = p.split(p.relative(source.path, from: romRoot.path)).first;
      if (config.protectedFolders.contains(top)) {
        actions.add(_skip(game, source.path));
        continue;
      }

      // One unwritable game must not abort the pipeline.
      try {
        final action = await _organizeOne(source, game, romRoot, config, dryRun);
        if (action != null) actions.add(action);
      } on FileSystemException catch (e) {
        actions.add(
          OrganizeAction(
            op: OrganizeOp.failed,
            game: game,
            destination: source.path,
            error: e.osError?.message ?? e.message,
          ),
        );
      }
    }
    return actions;
  }

  Future<OrganizeAction?> _organizeOne(
    File source,
    String game,
    Directory romRoot,
    OrganizeConfig config,
    bool dryRun,
  ) async {
    final sourceExt = p.extension(source.path);
    final folderMode = config.layout == FolderLayout.folderAsFile;

    // --- Keep-compressed modes (no extraction) ---
    if (!config.extract) {
      final unit = '$game$sourceExt';
      if (!folderMode) {
        // Mode 1: Archived Flat -> <root>/<game>.zip
        return _move(source, File(p.join(romRoot.path, unit)), game, dryRun);
      }
      // Mode 3: Archived in Folder -> <root>/<game>/<game>.zip
      if (_isProtectedFolder(config, romRoot, game)) {
        return _skip(game, p.join(romRoot.path, game));
      }
      return _move(source, File(p.join(romRoot.path, game, unit)), game, dryRun);
    }

    // --- Extract modes ---
    // A loose (non-zip) source is already "extracted"; treat it as one file.
    if (sourceExt.toLowerCase() != '.zip') {
      if (!folderMode) {
        // Mode 2 (single, loose)
        return _move(source, File(p.join(romRoot.path, '$game$sourceExt')), game, dryRun);
      }
      // Mode 4 (single, loose) -> <game>.<ext>/<game>.<ext>
      final folderName = '$game$sourceExt';
      if (_isProtectedFolder(config, romRoot, folderName)) {
        return _skip(game, p.join(romRoot.path, folderName));
      }
      return _move(
        source,
        File(p.join(romRoot.path, folderName, '$game$sourceExt')),
        game,
        dryRun,
      );
    }

    // Zip: stream entries out.
    OrganizeAction? result;
    final input = InputFileStream(source.path);
    try {
      final entries = [
        for (final f in ZipDecoder().decodeStream(input).files)
          if (!f.name.endsWith('/')) f,
      ];
      if (entries.isEmpty) return null;

      if (entries.length > 1) {
        // Multi-file (disc): Smart-Flat and Folder-as-File both -> <game>/<tracks>
        if (_isProtectedFolder(config, romRoot, game)) {
          return _skip(game, p.join(romRoot.path, game));
        }
        final folder = p.join(romRoot.path, game);
        if (!dryRun) {
          for (final f in entries) {
            _writeEntry(f, File(p.join(folder, p.basename(f.name))));
          }
        }
        result = OrganizeAction(
          op: OrganizeOp.extracted,
          game: game,
          destination: folder,
        );
      } else {
        final entry = entries.first;
        final ext = p.extension(entry.name);
        if (!folderMode) {
          // Mode 2 (single) -> <root>/<game><ext>
          final dest = File(p.join(romRoot.path, '$game$ext'));
          if (!dryRun) _writeEntry(entry, dest);
          result = OrganizeAction(
            op: OrganizeOp.extracted,
            game: game,
            destination: dest.path,
          );
        } else {
          // Mode 4 (single) -> <root>/<game><ext>/<game><ext>
          final folderName = '$game$ext';
          if (_isProtectedFolder(config, romRoot, folderName)) {
            return _skip(game, p.join(romRoot.path, folderName));
          }
          final dest = File(p.join(romRoot.path, folderName, '$game$ext'));
          if (!dryRun) _writeEntry(entry, dest);
          result = OrganizeAction(
            op: OrganizeOp.extracted,
            game: game,
            destination: dest.path,
          );
        }
      }
    } finally {
      input.closeSync();
    }

    // Drop the now-extracted source archive.
    if (!dryRun && await source.exists()) await source.delete();
    return result;
  }

  void _writeEntry(ArchiveFile entry, File dest) {
    dest.parent.createSync(recursive: true);
    if (dest.existsSync()) dest.deleteSync();
    final out = OutputFileStream(dest.path);
    entry.writeContent(out);
    out.closeSync();
  }

  Future<OrganizeAction?> _move(
    File src,
    File dest,
    String game,
    bool dryRun,
  ) async {
    if (p.equals(src.path, dest.path)) return null; // already in place
    if (!dryRun) {
      await dest.parent.create(recursive: true);
      if (await dest.exists()) await dest.delete();
      await src.rename(dest.path);
    }
    return OrganizeAction(
      op: OrganizeOp.moved,
      game: game,
      destination: dest.path,
    );
  }

  OrganizeAction _skip(String game, String path) =>
      OrganizeAction(op: OrganizeOp.skippedProtected, game: game, destination: path);

  bool _isProtectedFolder(
    OrganizeConfig config,
    Directory romRoot,
    String folderName,
  ) {
    if (config.protectedFolders.contains(folderName)) return true;
    final dir = Directory(p.join(romRoot.path, folderName));
    // One syscall, no exists/list race: a directory that is missing or can't be
    // read holds no user content we could clobber.
    try {
      return dir
          .listSync(recursive: true, followLinks: false)
          .any(
            (e) =>
                e is File &&
                _userContentExtensions.contains(
                  p.extension(e.path).toLowerCase(),
                ),
          );
    } on FileSystemException {
      return false;
    }
  }
}

/// Brings names inside curated folders in line with the DAT without moving
/// anything out of them.
///
/// A curated folder is off-limits to [EsdeRomOrganizer]: its patches, manuals and
/// translations only make sense beside the dump they were made for. Names still
/// drift — an abbreviated folder, a hand-renamed ROM — and renaming in place is
/// the one correction that cannot disturb what was built around the dump, so it
/// is the only one this stage makes.
final class CuratedFolderRenamer {
  const CuratedFolderRenamer();

  Future<List<OrganizeAction>> rename({
    required AuditReport report,
    required Directory romRoot,
    OrganizeConfig config = const OrganizeConfig(),
    bool dryRun = false,
  }) async {
    final actions = <OrganizeAction>[];
    for (final entry in report.library.curated) {
      // An explicit --protect means hands off, full stop.
      if (config.protectedFolders.contains(entry.name)) {
        actions.add(
          OrganizeAction(
            op: OrganizeOp.skippedProtected,
            game: entry.games.join(', '),
            destination: p.join(romRoot.path, entry.name),
          ),
        );
        continue;
      }

      // ROMs first: they are renamed within the folder as it stands, so a
      // folder rename afterwards can't invalidate the paths.
      for (final located in entry.roms) {
        if (located.hasCanonicalName) continue;
        actions.add(
          await _rename(
            located.file,
            p.join(located.file.parent.path, located.rom.name),
            located.game.name,
            dryRun,
          ),
        );
      }

      final action = await _renameFolder(entry, romRoot, config, dryRun);
      if (action != null) actions.add(action);
    }
    return actions;
  }

  /// Renames the folder only when it unambiguously holds one complete game —
  /// with two games in it there is no name that would be right, and with a
  /// half-present one the game it holds isn't settled yet.
  Future<OrganizeAction?> _renameFolder(
    LibraryEntry entry,
    Directory romRoot,
    OrganizeConfig config,
    bool dryRun,
  ) async {
    if (entry.games.length != 1) return null;
    final complete = entry.completeGames;
    if (complete.length != 1) return null;

    final game = complete.first;
    // The extracted folder-as-file layout names the folder after the file, so it
    // is the one layout that keeps the extension.
    final canonical =
        config.layout == FolderLayout.folderAsFile && config.extract
        ? '$game${p.extension(entry.roms.first.rom.name)}'
        : game;
    if (entry.name == canonical) return null;

    return _rename(
      Directory(p.join(romRoot.path, entry.name)),
      p.join(romRoot.path, canonical),
      game,
      dryRun,
    );
  }

  Future<OrganizeAction> _rename(
    FileSystemEntity source,
    String destination,
    String game,
    bool dryRun,
  ) async {
    // Never overwrite: a name already taken means two things want one slot, and
    // choosing between them is not this stage's call.
    if (await File(destination).exists() ||
        await Directory(destination).exists()) {
      return OrganizeAction(
        op: OrganizeOp.failed,
        game: game,
        destination: destination,
        error: 'already exists',
      );
    }
    try {
      if (!dryRun) await source.rename(destination);
      return OrganizeAction(
        op: OrganizeOp.renamed,
        game: game,
        destination: destination,
      );
    } on FileSystemException catch (e) {
      return OrganizeAction(
        op: OrganizeOp.failed,
        game: game,
        destination: destination,
        error: e.osError?.message ?? e.message,
      );
    }
  }
}

/// Groups present games into disc/side families and writes one `.m3u` per
/// multi-disc family, ordered so `Disc 1` leads.
final class DiscM3uGenerator {
  const DiscM3uGenerator();

  static final _discTag = RegExp(
    r'\s*\((?:Disc|Disk|Side)\s+[^)]*\)',
    caseSensitive: false,
  );

  Future<List<File>> generate({
    required Iterable<AuditedRom> present,
    required Directory romRoot,
    bool dryRun = false,
  }) async {
    final families = <String, List<AuditedRom>>{};
    for (final ar in present) {
      if (ar.location == null || !_discTag.hasMatch(ar.game.name)) continue;
      final family = ar.game.name.replaceAll(_discTag, '').trim();
      families.putIfAbsent(family, () => []).add(ar);
    }

    final written = <File>[];
    for (final entry in families.entries) {
      if (entry.value.length < 2) continue;
      final members = entry.value
        ..sort((a, b) => a.game.name.compareTo(b.game.name));
      final lines = [
        for (final ar in members)
          p.relative(ar.location!.path, from: romRoot.path),
      ];
      final m3u = File(p.join(romRoot.path, '${entry.key}.m3u'));
      written.add(m3u);
      if (!dryRun) await m3u.writeAsString('${lines.join('\n')}\n');
    }
    return written;
  }
}

/// Moves unknown/orphan files into a `.trash` folder under the ROM root,
/// preserving relative layout. Reversible (move, not delete); never touches the
/// trash itself or protected folders.
final class TrashPruner {
  const TrashPruner();

  Future<List<File>> prune({
    required AuditReport report,
    required Directory romRoot,
    Set<String> protectedFolders = const {},

    /// Canonicalized paths to spare whatever the audit says of them. The pipeline
    /// passes what the download stage just fetched: quarantining that would undo
    /// the fetch and have the next run repeat it.
    Set<String> keep = const {},
    bool dryRun = false,
  }) async {
    final trash = Directory(p.join(romRoot.path, trashFolderName));
    final moved = <File>[];
    final emptied = <String>{};
    // `prunable` already withholds anything under a folder the user has curated.
    for (final file in report.prunable(romRoot)) {
      final rel = p.relative(file.path, from: romRoot.path);
      final top = p.split(rel).first;
      if (top == trashFolderName || protectedFolders.contains(top)) continue;
      if (keep.contains(p.canonicalize(file.path))) continue;

      final dest = File(p.join(trash.path, rel));
      moved.add(dest);
      if (!dryRun) {
        await dest.parent.create(recursive: true);
        if (!p.equals(file.parent.path, romRoot.path)) {
          emptied.add(file.parent.path);
        }
        await file.rename(dest.path);
      }
    }
    // A folder that held nothing but a redundant dump has no reason to survive
    // it; leaving it behind makes the root look like the game is still there.
    if (!dryRun) await _removeIfEmpty(emptied, romRoot);
    return moved;
  }

  Future<void> _removeIfEmpty(Set<String> candidates, Directory romRoot) async {
    // Deepest first, so a nested pair collapses in one pass.
    for (final path in candidates.toList()
      ..sort((a, b) => b.length.compareTo(a.length))) {
      var current = Directory(path);
      while (!p.equals(current.path, romRoot.path) &&
          p.isWithin(romRoot.path, current.path)) {
        try {
          if (await current.list(followLinks: false).isEmpty) {
            final parent = current.parent;
            await current.delete();
            current = parent;
          } else {
            break;
          }
        } on FileSystemException {
          break;
        }
      }
    }
  }
}
