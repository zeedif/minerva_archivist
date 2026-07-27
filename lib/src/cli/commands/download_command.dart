import 'dart:io';
import 'dart:typed_data';

import '../../data/archive_source.dart';
import '../../data/aria2_client.dart';
import '../../data/metadata_repository.dart';
import '../../data/torrent.dart';
import '../../domain/auditor.dart';
import '../../domain/download.dart';
import '../../models/dat.dart';
import '../runner.dart';
import '../selection_options.dart';

class DownloadCommand extends ArchivistCommand with SelectionCommand {
  DownloadCommand() {
    argParser
      ..addOption(
        'collection',
        help: 'MiNERVA collection, e.g. No-Intro (derived from the DAT if omitted).',
      )
      ..addOption(
        'platform',
        help: 'Platform name (derived from the DAT if omitted).',
      )
      ..addOption(
        'torrent',
        help: 'Use a local .torrent file instead of resolving from the archive.',
      )
      ..addOption('aria2', defaultsTo: 'aria2c', help: 'Path to the aria2c binary.')
      ..addFlag(
        'seed',
        negatable: false,
        help: 'Keep seeding after the selected files complete.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Show the selection plan without downloading.',
      );
    argParser.addSelectionFlags();
  }

  @override
  String get name => 'download';

  @override
  String get description =>
      'Selectively download the filtered (1G1R) game set from the '
      'platform-wide torrent via aria2c.';

  @override
  Future<int> run() async {
    final r = argResults!;
    final root = romRoot == null ? null : Directory(romRoot!);
    final torrentPath = r.option('torrent');
    var collection = r.option('collection');
    var platform = r.option('platform');
    final dryRun = r.flag('dry-run');
    final seed = r.flag('seed');

    // With --dat, only the selected games are wanted (minus what --rom-root
    // already holds); with no --dat the whole torrent is fair game.
    final targets = datPaths.isEmpty ? const <SelectedTarget>[] : await loadSelectedTargets();
    final wanted = <DatGame>[];
    for (final t in targets) {
      if (root == null) {
        wanted.addAll(t.games);
        continue;
      }
      final report = await const RomAuditor().audit(
        dat: DatFile(header: t.dat.header, games: t.games),
        romRoot: root,
        catalog: t.dat,
      );
      // Another dump of the same game already sitting in a curated folder means
      // this one has nothing to add: it would land beside a patch built against
      // its sibling.
      final settled = t.settledByCuratedGroup(report);
      final held = [
        for (final a in report.missing)
          if (settled.contains(a.game.name)) a.game.name,
      ];
      if (held.isNotEmpty) {
        stdout.writeln(
          '${held.length} skipped: the same game is already settled in a '
          'curated folder',
        );
        for (final name in held) {
          stdout.writeln('  - $name');
        }
      }
      wanted.addAll([
        for (final a in report.missing)
          if (!settled.contains(a.game.name)) a.game,
      ]);
    }
    final firstDat = targets.isEmpty ? null : targets.first.dat;

    Uint8List bytes;
    if (torrentPath != null) {
      bytes = await File(torrentPath).readAsBytes();
    } else {
      if (firstDat != null) {
        collection ??= _collectionFor(firstDat.header.flavor);
        platform ??= const SystemNameResolver().baseSystem(firstDat.header.name);
      }
      if (collection == null || platform == null) {
        usageException(
          'Provide --torrent, or --collection and --platform '
          '(or a --dat to derive them).',
        );
      }
      final source = MinervaArchiveSource();
      final ref = await source.resolvePlatform(collection, platform);
      stdout.writeln('Resolving ${ref.torrentUri} ...');
      try {
        bytes = await source.fetchTorrentFile(ref);
      } finally {
        source.close();
      }
    }

    final manifest = await const BencodeTorrentInspector().read(bytes);
    const planner = DownloadPlanner();
    // An empty `wanted` under a DAT means "nothing missing", not "grab it all".
    final plan = firstDat == null
        ? planner.planAll(manifest)
        : planner.plan(wanted, manifest);

    stdout.writeln(
      'Torrent "${manifest.name}" (${manifest.infoHash}): '
      '${manifest.files.length} files.',
    );
    stdout.writeln(
      'Selected ${plan.selectedFiles.length} file(s), ${_mb(plan.totalBytes)}; '
      '${plan.unmatched.length} wanted not found in torrent.',
    );
    for (final u in plan.unmatched) {
      stderr.writeln('  ? not in torrent: $u');
    }

    if (dryRun || plan.selectedFiles.isEmpty) {
      stdout.writeln(dryRun ? '(dry run — nothing downloaded)' : 'Nothing to download.');
      return 0;
    }

    final saveDir = root ?? Directory.current;
    final client = Aria2TorrentClient(aria2Path: r.option('aria2')!);
    var completed = false;
    try {
      await client.start();
      final handle = await client.add(
        TorrentAddRequest(
          torrentData: bytes,
          saveDirectory: saveDir.path,
          selectedFileIndices: plan.selectedIndices,
          seedAfterComplete: seed,
        ),
      );
      await for (final progress in client.watch(handle)) {
        stdout.write(
          '\r  ${(progress.fraction * 100).toStringAsFixed(1)}%  '
          '${_mb(progress.completedBytes)}/${_mb(progress.totalBytes)}  '
          'peers=${progress.peers}    ',
        );
        if (progress.state == TorrentState.completed) {
          completed = true;
          stdout.writeln('\n  done.');
          break;
        }
        if (progress.state == TorrentState.error) {
          stderr.writeln('\n  download error.');
          return 70;
        }
      }
    } on StateError catch (e) {
      stderr.writeln(e.message);
      return 70;
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
        '  flattened ${result.moved.length} selected file(s) into '
        '${saveDir.path}; discarded ${result.discarded} boundary file(s); '
        'removed ${result.removedControlFiles} control file(s).',
      );
    }
    return 0;
  }

  String _collectionFor(DatFlavor flavor) => switch (flavor) {
    DatFlavor.redump || DatFlavor.mameRedump => 'Redump',
    _ => 'No-Intro',
  };

  String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
}
