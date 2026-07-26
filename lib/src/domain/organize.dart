/// On-disk library layout: the 4-mode organizer, `.m3u` playlists, and the
/// reversible pruner.
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'auditor.dart';

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
}

enum OrganizeOp { moved, extracted, skippedProtected, failed }

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
    bool dryRun = false,
  }) async {
    final trash = Directory(p.join(romRoot.path, trashFolderName));
    final moved = <File>[];
    for (final file in report.unknownFiles) {
      final rel = p.relative(file.path, from: romRoot.path);
      final top = p.split(rel).first;
      if (top == trashFolderName || protectedFolders.contains(top)) continue;

      final dest = File(p.join(trash.path, rel));
      moved.add(dest);
      if (!dryRun) {
        await dest.parent.create(recursive: true);
        await file.rename(dest.path);
      }
    }
    return moved;
  }
}
