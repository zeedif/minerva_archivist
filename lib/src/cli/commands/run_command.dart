import 'dart:io';

import 'package:args/args.dart';

import '../../data/archive_source.dart';
import '../../data/aria2_client.dart';
import '../../data/dat_loader.dart';
import '../../data/metadata_repository.dart';
import '../../data/torrent.dart';
import '../../domain/auditor.dart';
import '../../domain/download.dart';
import '../../domain/organize.dart';
import '../../models/dat.dart';
import '../runner.dart';
import '../selection_options.dart';

class RunCommand extends ArchivistCommand with SelectionCommand {
  RunCommand() {
    argParser
      ..addMultiOption(
        'only',
        help: 'Run only these stages '
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
      )
      ..addOption('aria2', defaultsTo: 'aria2c', help: 'Path to aria2c.')
      ..addFlag('seed', negatable: false, help: 'Keep seeding after download.');
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
      stdout.writeln('[sync] ${s.downloaded} file(s), ${s.errors.length} error(s)');
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
        stdout.writeln('\n=== ${dat.header.name} [${dat.header.flavor.name}] ===');

        var target = dat;
        if (active('select')) {
          final result = await selection.select(dat);
          target = DatFile(header: dat.header, games: result.games);
          final why = result.stats.reasons;
          stdout.writeln(
            '[select] ${dat.games.length} in DAT -> ${result.games.length} wanted'
            '${why.isEmpty ? "" : "  (${why.join(', ')})"}',
          );
        }

        final root = romRoot == null ? null : Directory(romRoot!);
        final needsReport = root != null &&
            (active('audit') ||
                active('download') ||
                active('organize') ||
                active('m3u') ||
                active('prune'));
        var report =
            needsReport ? await auditor.audit(dat: target, romRoot: root) : null;
        if (report != null && active('audit')) {
          stdout.writeln(
            '[audit] ${report.present.length}/${target.games.length} on disk, '
            '${report.missing.length} missing, '
            '${report.unknownFiles.length} unknown',
          );
        }

        if (active('download')) {
          final wanted = report != null
              ? [for (final a in report.missing) a.game]
              : target.games;
          final didDownload = await _download(dat, wanted, romRoot, apply, r);
          // Re-audit so organize/m3u/prune see the freshly flattened files.
          if (didDownload && root != null) {
            report = await auditor.audit(dat: target, romRoot: root);
            stdout.writeln(
              '[audit] ${report.present.length}/${target.games.length} on disk, '
              '${report.missing.length} missing',
            );
          }
        }
        if (report != null && root != null && active('organize')) {
          final actions = await const EsdeRomOrganizer().organize(
            present: report.present,
            romRoot: root,
            config: organizeConfig,
            dryRun: !apply,
          );
          stdout.writeln('[organize] ${actions.summary}'
              '${apply ? "" : " (dry run)"}');
          for (final f in actions.where((a) => a.op == OrganizeOp.failed)) {
            stderr.writeln('           ! ${f.game}: ${f.error}');
          }
        }
        if (report != null && root != null && active('m3u')) {
          final written = await const DiscM3uGenerator().generate(
            present: report.present,
            romRoot: root,
            dryRun: !apply,
          );
          stdout.writeln('[m3u] ${written.length} playlist(s)${apply ? "" : " (dry run)"}');
        }
        if (report != null && root != null && active('prune')) {
          final moved = await const TrashPruner().prune(
            report: report,
            romRoot: root,
            protectedFolders: organizeConfig.protectedFolders,
            dryRun: !apply,
          );
          stdout.writeln('[prune] ${moved.length} orphan(s)${apply ? "" : " (dry run)"}');
        }
      }
    }
    repo.close();
    return 0;
  }

  /// Returns true if a real download completed (so the caller should re-audit).
  Future<bool> _download(
    DatFile dat,
    Iterable<DatGame> wanted,
    String? romRoot,
    bool apply,
    ArgResults r,
  ) async {
    final collection = switch (dat.header.flavor) {
      DatFlavor.redump || DatFlavor.mameRedump => 'Redump',
      _ => 'No-Intro',
    };
    final platform = const SystemNameResolver().baseSystem(dat.header.name);
    final source = MinervaArchiveSource();
    try {
      final ref = await source.resolvePlatform(collection, platform);
      final bytes = await source.fetchTorrentFile(ref);
      final manifest = await const BencodeTorrentInspector().read(bytes);
      final plan = const DownloadPlanner().plan(wanted, manifest);
      final wantedCount = wanted.length;
      stdout.writeln(
        '[download] $wantedCount missing -> ${plan.selectedFiles.length} in torrent'
        '${plan.unmatched.isEmpty ? "" : ", ${plan.unmatched.length} not distributed"}'
        ', ${(plan.totalBytes / 1048576).toStringAsFixed(1)} MB'
        '${apply ? "" : " (dry run)"}',
      );
      for (final u in plan.unmatched) {
        stdout.writeln('           ? not in torrent: $u');
      }
      if (!apply || plan.selectedFiles.isEmpty) return false;

      final saveDir = Directory(romRoot ?? Directory.current.path);
      final client = Aria2TorrentClient(aria2Path: r.option('aria2')!);
      var completed = false;
      try {
        await client.start();
        final handle = await client.add(
          TorrentAddRequest(
            torrentData: bytes,
            saveDirectory: saveDir.path,
            selectedFileIndices: plan.selectedIndices,
            seedAfterComplete: r.flag('seed'),
          ),
        );
        await for (final progress in client.watch(handle)) {
          if (progress.state == TorrentState.completed) {
            completed = true;
            break;
          }
          if (progress.state == TorrentState.error) break;
        }
      } finally {
        await client.dispose();
      }

      if (completed) {
        final keep = {
          for (final f in plan.selectedFiles) f.path.split('/').last.toLowerCase(),
        };
        final result = await const TorrentRelocator().flatten(
          romRoot: saveDir,
          topDir: manifest.name,
          keepBasenames: keep,
        );
        stdout.writeln(
          '[download] flattened ${result.moved.length} selected, '
          'discarded ${result.discarded} boundary file(s); '
          'removed ${result.removedControlFiles} control file(s).',
        );
      }
      return completed;
    } catch (e) {
      stderr.writeln('[download] failed: $e');
      return false;
    } finally {
      source.close();
    }
  }
}
