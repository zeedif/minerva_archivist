import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;

/// What a run has reported about one DAT so far.
final class PlatformProgress {
  PlatformProgress(this.name);

  final String name;
  SelectionResult? selection;
  AuditReport? audit;
  DownloadPlanned? download;
  TransferSnapshot? transfer;
  int? fetched;
  List<OrganizeAction>? organized;
  int? playlists;
  PruneFinished? pruned;
  final failures = <String>[];
}

/// Loads profiles and runs one of them on a worker isolate, exposing the
/// events it reports as state the UI can draw.
final class RunController extends ChangeNotifier {
  RunController(this.cacheDir);

  String cacheDir;
  Profiles? profiles;
  String? loadError;
  String? selected;
  RunOptions? options;

  bool running = false;
  bool applied = false;
  final platforms = <PlatformProgress>[];
  String? syncSummary;

  SendPort? _control;

  File get profilesFile => File(p.join(cacheDir, 'profiles.jsonc'));

  Future<void> load() async {
    profiles = null;
    selected = null;
    options = null;
    try {
      profiles = await Profiles.load(profilesFile);
      loadError = null;
      if (profiles!.names.firstOrNull case final first?) select(first);
    } on FileSystemException {
      loadError = 'No profiles file at ${profilesFile.path}';
    } on FormatException catch (e) {
      loadError = e.message;
    }
    notifyListeners();
  }

  void select(String name) {
    selected = name;
    try {
      options = profiles!.resolve(name);
      loadError = null;
    } on FormatException catch (e) {
      options = null;
      loadError = '$name: ${e.message}';
    }
    if (!running) platforms.clear();
    notifyListeners();
  }

  Future<void> start({required bool apply}) async {
    final options = this.options;
    if (running || options == null) return;
    running = true;
    applied = apply;
    syncSummary = null;
    platforms.clear();
    notifyListeners();

    final events = ReceivePort();
    final worker = await Isolate.spawn(_work, (
      events.sendPort,
      p.absolute(cacheDir),
      options,
      apply,
    ), onExit: events.sendPort);
    await for (final message in events) {
      switch (message) {
        case SendPort():
          _control = message;
        case PipelineEvent():
          _reduce(message);
          notifyListeners();
        case null:
          events.close();
      }
    }
    worker.kill();
    _control = null;
    running = false;
    notifyListeners();
  }

  /// Asks the worker to stop; partial downloads are kept for the next run.
  void stop() => _control?.send(null);

  void _reduce(PipelineEvent event) {
    final current = platforms.lastOrNull;
    switch (event) {
      case SyncFinished(:final report):
        syncSummary =
            '${report.downloaded} metadata file(s) updated'
            '${report.errors.isEmpty ? "" : ", ${report.errors.length} error(s)"}';
      case PlatformStarted(:final dat):
        platforms.add(PlatformProgress(dat.header.name));
      case SelectionFinished(:final selection):
        current?.selection = selection;
      case AuditFinished(:final report):
        current?.audit = report;
      case DownloadPlanned():
        current?.download = event;
      case DownloadProgress(:final snapshot):
        current?.transfer = snapshot;
      case DownloadFinished(:final files):
        current?.fetched = files.length;
      case OrganizeFinished(:final actions):
        current?.organized = actions;
      case PlaylistsFinished(:final playlists):
        current?.playlists = playlists.length;
      case PruneFinished():
        current?.pruned = event;
      case StageFailed(:final stage, :final message):
        final target = current ?? PlatformProgress('Run');
        if (current == null) platforms.add(target);
        target.failures.add('${stage.name}: $message');
    }
  }

  static Future<void> _work(
    (SendPort events, String cacheDir, RunOptions options, bool apply) args,
  ) async {
    final (events, cacheDir, options, apply) = args;
    final control = ReceivePort();
    events.send(control.sendPort);
    final pipeline = Pipeline(cacheDir: cacheDir);
    final done = Completer<void>();
    final subscription = pipeline
        .run(options, apply: apply)
        .listen(
          events.send,
          onError: (Object error) =>
              events.send(StageFailed(Stage.sync, '$error')),
          onDone: done.complete,
        );
    control.listen((_) async {
      await subscription.cancel();
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    control.close();
    pipeline.close();
    events.send(null);
  }
}
