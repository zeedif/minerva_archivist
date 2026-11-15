/// The run itself: select, audit, download, organize, playlists, prune —
/// reported as a stream of events so any front end can render it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/archive_source.dart';
import '../data/dat_loader.dart';
import '../data/metadata_repository.dart';
import '../data/torrent.dart';
import '../data/torrent_engine.dart';
import '../models/dat.dart';
import 'auditor.dart';
import 'download.dart';
import 'options.dart';
import 'organize.dart';
import 'selection.dart';

/// Something a run did or learned, in the order it happened.
sealed class PipelineEvent {
  const PipelineEvent();
}

final class SyncFinished extends PipelineEvent {
  const SyncFinished(this.report);
  final SyncReport report;
}

/// A DAT is about to be processed; every event up to the next one is its.
final class PlatformStarted extends PipelineEvent {
  const PlatformStarted(this.dat);
  final DatFile dat;
}

final class SelectionFinished extends PipelineEvent {
  const SelectionFinished(this.dat, this.selection);
  final DatFile dat;
  final SelectionResult selection;
}

final class AuditFinished extends PipelineEvent {
  const AuditFinished(this.report);
  final AuditReport report;
}

final class DownloadPlanned extends PipelineEvent {
  const DownloadPlanned({
    required this.plan,
    required this.missing,
    required this.held,
    required this.seeders,
  });

  final DownloadPlan plan;

  /// Games the audit found absent.
  final int missing;

  /// Missing games left alone because a curated folder already holds another
  /// dump of the same title.
  final List<String> held;

  /// Null when the archive reports none or the fetch will not start.
  final int? seeders;
}

final class DownloadProgress extends PipelineEvent {
  const DownloadProgress(this.snapshot);
  final TransferSnapshot snapshot;
}

final class DownloadFinished extends PipelineEvent {
  const DownloadFinished(this.files, this.unrecognized);

  /// The files now in the ROM root.
  final List<File> files;

  /// Fetched files whose bytes the DAT does not describe.
  final List<File> unrecognized;
}

final class OrganizeFinished extends PipelineEvent {
  const OrganizeFinished(this.actions);
  final List<OrganizeAction> actions;
}

final class PlaylistsFinished extends PipelineEvent {
  const PlaylistsFinished(this.playlists);
  final List<File> playlists;
}

final class PruneFinished extends PipelineEvent {
  const PruneFinished(this.moved, this.curatedDuplicates);

  /// Destinations inside the trash folder.
  final List<File> moved;

  /// Redundant copies left in place because their folder is curated.
  final List<File> curatedDuplicates;
}

final class StageFailed extends PipelineEvent {
  const StageFailed(this.stage, this.message);
  final Stage stage;
  final String message;
}

/// Runs [RunOptions] against the metadata cache at [cacheDir].
final class Pipeline {
  Pipeline({
    required this.cacheDir,
    MetadataRepository? repository,
    MinervaArchive? archive,
    TorrentEngine? engine,
  }) : _repo = repository ?? RemoteMetadataRepository(cacheDir: cacheDir),
       _archive = archive ?? MinervaArchive(),
       _engine = engine ?? LibtorrentEngine();

  final String cacheDir;
  final MetadataRepository _repo;
  final MinervaArchive _archive;
  final TorrentEngine _engine;

  /// Selects from every DAT [options] names, touching nothing on disk.
  Stream<SelectionFinished> select(RunOptions options) async* {
    final wishlist = await _wishlist(options);
    for (final dat in await _dats(options)) {
      yield SelectionFinished(dat, await _select(dat, options, wishlist));
    }
  }

  /// Runs every stage [options] does not skip. Without [apply] nothing is
  /// downloaded, moved or written.
  Stream<PipelineEvent> run(RunOptions options, {required bool apply}) async* {
    bool runs(Stage stage) => !options.skip.contains(stage);

    if (runs(Stage.sync)) yield SyncFinished(await _repo.sync());

    final wishlist = await _wishlist(options);
    final root = options.root == null ? null : Directory(options.root!);
    final organize = OrganizeConfig(
      layout: options.layout,
      protectedFolders: options.protect,
    );
    const auditor = RomAuditor();

    for (final dat in await _dats(options)) {
      yield PlatformStarted(dat);
      final selection = await _select(dat, options, wishlist);
      yield SelectionFinished(dat, selection);
      if (root == null) continue;

      final target = DatFile(header: dat.header, games: selection.games);
      Future<AuditReport> audit() => auditor.audit(
        dat: target,
        romRoot: root,
        catalog: dat,
        maxDepth: options.depth,
      );
      var report = await audit();
      yield AuditFinished(report);

      var fetched = const <File>[];
      if (runs(Stage.download)) {
        try {
          await for (final event in _download(
            dat,
            selection,
            report,
            root,
            apply,
          )) {
            if (event is DownloadFinished) fetched = event.files;
            if (event is! DownloadFinished) yield event;
          }
          if (fetched.isNotEmpty) {
            report = await audit();
            final unknown = {
              for (final f in report.unknownFiles) p.canonicalize(f.path),
            };
            yield DownloadFinished(fetched, [
              for (final f in fetched)
                if (unknown.contains(p.canonicalize(f.path))) f,
            ]);
            yield AuditFinished(report);
          }
        } on Exception catch (e) {
          yield StageFailed(Stage.download, '$e');
        }
      }

      if (runs(Stage.organize)) {
        final actions = [
          ...await const EsdeRomOrganizer().organize(
            present: report.present,
            romRoot: root,
            config: organize.protecting(report.library.curatedFolders),
            dryRun: !apply,
          ),
          ...await const CuratedFolderRenamer().rename(
            report: report,
            romRoot: root,
            config: organize,
            dryRun: !apply,
          ),
        ];
        yield OrganizeFinished(actions);
        final changed = actions.any(
          (a) =>
              a.op != OrganizeOp.skippedProtected && a.op != OrganizeOp.failed,
        );
        if (apply && changed) report = await audit();
      }

      if (runs(Stage.playlists)) {
        yield PlaylistsFinished(
          await const DiscM3uGenerator().generate(
            present: report.present,
            romRoot: root,
            dryRun: !apply,
          ),
        );
      }

      if (runs(Stage.prune)) {
        yield PruneFinished(
          await const TrashPruner().prune(
            report: report,
            romRoot: root,
            protectedFolders: organize
                .protecting(report.library.curatedFolders)
                .protectedFolders,
            keep: {for (final f in fetched) p.canonicalize(f.path)},
            dryRun: !apply,
          ),
          report.duplicatesInCuratedFolders(root),
        );
      }
    }
  }

  /// Releases the network client and the torrent session.
  void close() {
    _engine.close();
    _archive.close();
    if (_repo case final RemoteMetadataRepository repo) repo.close();
  }

  Stream<PipelineEvent> _download(
    DatFile dat,
    SelectionResult selection,
    AuditReport report,
    Directory root,
    bool apply,
  ) async* {
    final settled = _settledByCuratedGroup(selection, report);
    final missing = [for (final a in report.missing) a.game];
    final wanted = [
      for (final g in missing)
        if (!settled.contains(g.name)) g,
    ];
    if (wanted.isEmpty && settled.isEmpty) return;

    final collection = switch (dat.header.flavor) {
      DatFlavor.redump || DatFlavor.mameRedump => 'Redump',
      _ => 'No-Intro',
    };
    final torrent = await _archive.platformTorrent(
      collection,
      const SystemNameResolver().baseSystem(dat.header.name),
    );
    final manifest = TorrentManifest.parse(torrent);
    final plan = DownloadPlan.match(wanted, manifest);
    final fetches = apply && plan.selected.isNotEmpty;
    yield DownloadPlanned(
      plan: plan,
      missing: missing.length,
      held: [
        for (final g in missing)
          if (settled.contains(g.name)) g.name,
      ],
      seeders: fetches ? await _archive.seeders(manifest.infoHash) : null,
    );
    if (!fetches) return;

    final incoming = Directory(
      p.join(root.path, workFolderName, incomingFolderName),
    );
    await for (final snapshot in _engine.fetch(
      FetchRequest(torrent: torrent, into: incoming, files: plan.files),
    )) {
      yield DownloadProgress(snapshot);
    }

    final landed = <File>[];
    for (final name in plan.files.values) {
      final destination = File(p.join(root.path, name));
      if (await destination.exists()) await destination.delete();
      landed.add(
        await File(p.join(incoming.path, name)).rename(destination.path),
      );
    }
    yield DownloadFinished(landed, const []);
  }

  /// Selected games whose clone group already has a dump inside a curated
  /// folder; a pack answers for every group it holds.
  static Set<String> _settledByCuratedGroup(
    SelectionResult selection,
    AuditReport report,
  ) {
    final settled = {
      for (final name in report.library.curatedGames)
        ...?selection.groups[name],
    };
    if (settled.isEmpty) return const {};
    return {
      for (final MapEntry(key: name, value: groups) in selection.groups.entries)
        if (groups.any(settled.contains)) name,
    };
  }

  Future<List<String>> _wishlist(RunOptions options) async =>
      switch (options.wishlist) {
        null => const [],
        final path => parseWishlist(await File(path).readAsString()),
      };

  Future<List<DatFile>> _dats(RunOptions options) async {
    const loader = DatLoader();
    return [
      for (final reference in options.dats)
        for (final file in await locateDats(reference, cacheDir))
          await loader.load(file),
    ];
  }

  Future<SelectionResult> _select(
    DatFile dat,
    RunOptions options,
    List<String> wishlist,
  ) async {
    final config = await _repo.config();
    final (name, flavor) = (dat.header.name, dat.header.flavor);
    return const GameSelector().select(
      dat: dat,
      config: config,
      scoring: ScoringConfig(
        languagePriority: options.languages,
        regionPriority: options.regions.isEmpty
            ? config.defaultRegionOrder
            : options.regions,
        languageFallback: config.defaultLanguageOrder,
        regionFallback: config.defaultRegionOrder,
        priority: options.priority,
        langCount: options.langCount,
        supersets: options.supersets,
        compilations: options.compilations,
      ),
      wishlist: wishlist,
      wishlistMode: options.wishlistMode,
      achievements: options.achievements,
      exclude: options.exclude,
      cloneList: await _repo.cloneList(name, flavor),
      metadata: await _repo.metadata(name, flavor),
      ra: await _repo.retroAchievements(name, dat: dat),
      mias: await _repo.mias(name, flavor),
    );
  }
}

/// The DAT files [reference] names: an existing file, every `.dat` under an
/// existing folder, or the newest cached DAT of a system — `Sony - PlayStation`
/// or, to pick one source, `redump:Sony - PlayStation`.
///
/// Throws [FileSystemException] when nothing matches.
Future<List<File>> locateDats(String reference, String cacheDir) async {
  switch (FileSystemEntity.typeSync(reference)) {
    case FileSystemEntityType.file:
      return [File(reference)];
    case FileSystemEntityType.directory:
      return await _datsIn(Directory(reference), recursive: true);
    default:
  }
  final (source, system) = switch (reference.split(':')) {
    [final source, final system] when _datSources.contains(source) => (
      source,
      system,
    ),
    _ => (null, reference),
  };
  const resolver = SystemNameResolver();
  final wanted = system.trim().toLowerCase();
  final found = <File>[];
  for (final folder in source == null ? _datSources : [source]) {
    final matches = [
      for (final file in await _datsIn(Directory(p.join(cacheDir, folder))))
        if (resolver
                .baseSystem(p.basenameWithoutExtension(file.path))
                .toLowerCase() ==
            wanted)
          file,
    ]..sort((a, b) => a.path.compareTo(b.path));
    if (matches.isNotEmpty) found.add(matches.last);
  }
  if (found.isEmpty) {
    throw FileSystemException('No DAT found for "$reference"', cacheDir);
  }
  return found;
}

const _datSources = ['nointro', 'mame-redump', 'redump'];

Future<List<File>> _datsIn(
  Directory directory, {
  bool recursive = false,
}) async {
  if (!await directory.exists()) return const [];
  return [
    await for (final entity in directory.list(recursive: recursive))
      if (entity is File && p.extension(entity.path).toLowerCase() == '.dat')
        entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
}
