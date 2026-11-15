import 'dart:io';

import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;

import '../runner.dart';
import '../selection_options.dart';

class RunCommand extends ArchivistCommand with SelectionCommand {
  RunCommand() {
    argParser
      ..addMultiOption(
        'only',
        help:
            'Run only these stages '
            '(sync, select, audit, download, organize, m3u, prune).',
      )
      ..addMultiOption('skip', help: 'Skip these stages.')
      ..addFlag(
        'with-download',
        negatable: false,
        help: 'Enable the download stage (off by default).',
      )
      ..addFlag(
        'folder-as-file',
        negatable: false,
        help: 'ES-DE folder-as-file layout for organize.',
      )
      ..addFlag(
        'extract',
        negatable: false,
        help: 'Unzip archives during organize (off = keep .zip).',
      )
      ..addMultiOption('protect', help: 'Folder names to never touch.')
      ..addFlag(
        'apply',
        negatable: false,
        help: 'Apply organize/prune/download (default is a dry run).',
      );
    argParser.addSelectionFlags();
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Run the full pipeline: '
      'sync -> select -> audit -> [download] -> organize -> m3u -> prune.';

  @override
  Future<int> run() async {
    final r = argResults!;
    final paths = requireDatPaths();
    final apply = r.flag('apply');

    final only = r.multiOption('only').toSet();
    final skip = r.multiOption('skip').toSet();
    final withDownload = r.flag('with-download');
    bool active(String id) {
      if (skip.contains(id)) return false;
      if (only.isNotEmpty) return only.contains(id);
      if (id == 'download') return withDownload;
      return true;
    }

    final repo = RemoteMetadataRepository(cacheDir: cacheDir);
    const loader = DatLoader();
    const auditor = RomAuditor();

    if (active('sync')) {
      stdout.writeln('[sync] fetching metadata ...');
      final s = await repo.sync();
      stdout.writeln(
        '[sync] ${s.downloaded} file(s)'
        '${s.removed > 0 ? ", ${s.removed} stale removed" : ""}'
        ', ${s.errors.length} error(s)',
      );
    }

    final selection = await selectionContext(repo);
    final organizeConfig = OrganizeConfig(
      layout: r.flag('folder-as-file')
          ? FolderLayout.folderAsFile
          : FolderLayout.flat,
      extract: r.flag('extract'),
      protectedFolders: r.multiOption('protect').toSet(),
    );

    for (final path in paths) {
      for (final dat in await loader.loadPath(path)) {
        stdout.writeln(
          '\n=== ${dat.header.name} [${dat.header.flavor.name}] ===',
        );

        var target = dat;
        SelectedTarget? selected;
        if (active('select')) {
          final result = await selection.select(dat);
          selected = (dat: dat, selection: result);
          target = DatFile(header: dat.header, games: result.games);
          final why = result.stats.reasons;
          stdout.writeln(
            '[select] ${dat.games.length} in DAT -> ${result.games.length} wanted'
            '${why.isEmpty ? "" : "  (${why.join(', ')})"}',
          );
        }

        final root = romRoot == null ? null : Directory(romRoot!);
        final needsReport =
            root != null &&
            (active('audit') ||
                active('download') ||
                active('organize') ||
                active('m3u') ||
                active('prune'));
        // The full DAT is the catalog, so a curated folder holding a variant
        // that lost its 1G1R slot is recognized rather than read as junk.
        var report = needsReport
            ? await auditor.audit(dat: target, romRoot: root, catalog: dat)
            : null;
        if (report != null && active('audit')) {
          stdout.writeln(
            '[audit] ${report.present.length}/${target.games.length} on disk, '
            '${report.missing.length} missing, '
            '${report.unknownFiles.length} unknown',
          );
          stdout.writeln('[audit] ${report.library.summary}');
        }

        // What this run fetched, so prune can tell it from the collection's own
        // strays and never quarantine work just done.
        var fetched = const <File>[];
        if (active('download')) {
          var wanted = report != null
              ? [for (final a in report.missing) a.game]
              : target.games;
          if (report != null && selected != null) {
            final settled = selected.settledByCuratedGroup(report);
            final held = [
              for (final g in wanted)
                if (settled.contains(g.name)) g,
            ];
            if (held.isNotEmpty) {
              wanted = [
                for (final g in wanted)
                  if (!settled.contains(g.name)) g,
              ];
              stdout.writeln(
                '[download] ${held.length} skipped: another dump of the same '
                'game is already settled in a curated folder',
              );
              for (final g in held) {
                stdout.writeln('           - ${g.name}');
              }
            }
          }
          fetched = await _download(dat, wanted, romRoot, apply);
          // Re-audit so organize/m3u/prune see the freshly flattened files.
          if (fetched.isNotEmpty && root != null) {
            report = await auditor.audit(
              dat: target,
              romRoot: root,
              catalog: dat,
            );
            stdout.writeln(
              '[audit] ${report.present.length}/${target.games.length} on disk, '
              '${report.missing.length} missing',
            );
            // A fetched file the re-audit cannot place holds bytes this DAT does
            // not describe — what a re-hashed flavor audited against a torrent of
            // original dumps yields for every title. Reported rather than left to
            // be inferred from a download and a prune that never meet.
            final strays = {for (final f in fetched) p.canonicalize(f.path)}
                .intersection({
                  for (final f in report.unknownFiles) p.canonicalize(f.path),
                });
            if (strays.isNotEmpty) {
              stdout.writeln(
                '[download] ${strays.length} fetched file(s) hash to nothing in '
                'this DAT, so they stay missing. Kept, not pruned:',
              );
              for (final path in strays) {
                stdout.writeln('           ! ${p.basename(path)}');
              }
            }
          }
        }
        if (report != null && root != null && active('organize')) {
          final actions = await const EsdeRomOrganizer().organize(
            present: report.present,
            romRoot: root,
            config: organizeConfig.protecting(report.library.curatedFolders),
            dryRun: !apply,
          );
          // Curated folders are skipped above; names inside them are still
          // brought in line, without anything leaving the folder.
          final renames = await const CuratedFolderRenamer().rename(
            report: report,
            romRoot: root,
            config: organizeConfig,
            dryRun: !apply,
          );
          final all = [...actions, ...renames];
          stdout.writeln(
            '[organize] ${all.summary}${apply ? "" : " (dry run)"}',
          );
          for (final f in all.where((a) => a.op == OrganizeOp.failed)) {
            stderr.writeln('           ! ${f.game}: ${f.error}');
          }
        }
        if (report != null && root != null && active('m3u')) {
          final written = await const DiscM3uGenerator().generate(
            present: report.present,
            romRoot: root,
            dryRun: !apply,
          );
          stdout.writeln(
            '[m3u] ${written.length} playlist(s)${apply ? "" : " (dry run)"}',
          );
        }
        if (report != null && root != null && active('prune')) {
          final moved = await const TrashPruner().prune(
            report: report,
            romRoot: root,
            protectedFolders: organizeConfig
                .protecting(report.library.curatedFolders)
                .protectedFolders,
            keep: {for (final f in fetched) p.canonicalize(f.path)},
            dryRun: !apply,
          );
          stdout.writeln(
            '[prune] ${moved.length} orphan(s)${apply ? "" : " (dry run)"}',
          );
          // Named, not just counted: a wrong move has to be visible in the run
          // that made it rather than in a later directory listing.
          for (final f in moved) {
            stdout.writeln(
              '           - ${p.relative(f.path, from: p.join(root.path, trashFolderName))}',
            );
          }
          final twinned = report.duplicatesInCuratedFolders(root);
          if (twinned.isNotEmpty) {
            stdout.writeln(
              '[prune] ${twinned.length} duplicate(s) left alone inside curated '
              'folders — merge them by hand to drop the extra copy:',
            );
            for (final f in twinned) {
              stdout.writeln(
                '           = ${p.relative(f.path, from: root.path)}',
              );
            }
          }
        }
      }
    }
    repo.close();
    return _failed ? 1 : 0;
  }

  /// The files a completed download just landed in the ROM root, empty when
  /// nothing was fetched.
  Future<List<File>> _download(
    DatFile dat,
    Iterable<DatGame> wanted,
    String? romRoot,
    bool apply,
  ) async {
    final collection = switch (dat.header.flavor) {
      DatFlavor.redump || DatFlavor.mameRedump => 'Redump',
      _ => 'No-Intro',
    };
    final platform = const SystemNameResolver().baseSystem(dat.header.name);
    final archive = MinervaArchive();
    final engine = LibtorrentEngine();
    try {
      final torrent = await archive.platformTorrent(collection, platform);
      final manifest = TorrentManifest.parse(torrent);
      final plan = DownloadPlan.match(wanted, manifest);
      stdout.writeln(
        '[download] ${wanted.length} missing -> ${plan.selected.length} in torrent'
        '${plan.unmatched.isEmpty ? "" : ", ${plan.unmatched.length} not distributed"}'
        ', ${_mb(plan.totalBytes)}${apply ? "" : " (dry run)"}',
      );
      for (final name in plan.unmatched) {
        stdout.writeln('           ? not in torrent: $name');
      }
      if (!apply || plan.selected.isEmpty) return const [];

      if (await archive.seeders(manifest.infoHash) case final seeders?) {
        stdout.writeln('[download] $seeders seeder(s) reported');
      }
      final root = Directory(romRoot ?? Directory.current.path);
      final incoming = Directory(
        p.join(root.path, workFolderName, incomingFolderName),
      );
      final reported = <int>{};
      await for (final snapshot in engine.fetch(
        FetchRequest(torrent: torrent, into: incoming, files: plan.files),
      )) {
        for (final file in snapshot.files) {
          if (file.isComplete && reported.add(file.index)) {
            stdout.writeln('\r           + ${file.name}'.padRight(79));
          }
        }
        final active = snapshot.files
            .where((f) => !f.isComplete && f.done > 0)
            .firstOrNull;
        final line =
            '           ${reported.length}/${snapshot.files.length}  '
            '${_mb(snapshot.done)}/${_mb(snapshot.total)}  '
            '${_mb(snapshot.bytesPerSecond)}/s  ${snapshot.seeds} seeds'
            '${active == null ? "" : "  ${(active.fraction * 100).toStringAsFixed(0)}% ${active.name}"}';
        stdout.write('\r${line.padRight(79).substring(0, 79)}');
      }
      stdout.writeln();

      final landed = <File>[];
      for (final name in plan.files.values) {
        final destination = File(p.join(root.path, name));
        if (await destination.exists()) await destination.delete();
        landed.add(
          await File(p.join(incoming.path, name)).rename(destination.path),
        );
      }
      return landed;
    } on Exception catch (e) {
      stderr.writeln('\n[download] failed: $e');
      _failed = true;
      return const [];
    } finally {
      engine.close();
      archive.close();
    }
  }

  var _failed = false;

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
}
