import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;

import 'settings.dart';

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

/// The values a cache folder offers the profile editor.
final class CacheCatalog {
  const CacheCatalog({
    this.dats = const [],
    this.languages = const {},
    this.regions = const [],
  });

  /// Reads the cached DATs and Retool's `config/internal-config.json`.
  static Future<CacheCatalog> load(String cacheDir) async {
    final dats = await cachedDatReferences(cacheDir);
    final config = File(p.join(cacheDir, 'config', 'internal-config.json'));
    Map<String, Object?> json = const {};
    try {
      if (jsonDecode(await config.readAsString())
          case final Map<String, Object?> decoded) {
        json = decoded;
      }
    } on FileSystemException {
      // No config yet: only the catch-all values are offered.
    } on FormatException {
      // Unreadable config: likewise.
    }
    final languages = <String, String>{};
    if (json['languages'] case final Map<String, Object?> named) {
      for (final MapEntry(:key, :value) in named.entries) {
        if (value is! String) continue;
        for (final alternative in value.split('|')) {
          final code = _code.firstMatch(alternative)?.group(0);
          if (code != null) languages.putIfAbsent(code, () => key);
        }
      }
    }
    languages[PriorityList.other] = 'Any other language';
    final regions = [
      if (json['defaultRegionOrder'] case final Map<String, Object?> order)
        ...order.keys,
    ];
    for (final extra in [PriorityList.other, PriorityList.unknown]) {
      if (!regions.contains(extra)) regions.add(extra);
    }
    return CacheCatalog(dats: dats, languages: languages, regions: regions);
  }

  static final _code = RegExp('^[A-Za-z]{2}(?:-[A-Za-z]{2,4})?');

  /// `source:system` references of the DATs already in the cache.
  final List<String> dats;

  /// Language code to its English name.
  final Map<String, String> languages;
  final List<String> regions;
}

/// Loads a cache folder's profiles, edits one as a draft and runs it on a
/// worker isolate, exposing the events it reports as state the UI can draw.
final class RunController extends ChangeNotifier {
  RunController(String cacheDir, {this.settings})
    : cacheDir = p.normalize(p.absolute(cacheDir));

  final AppSettings? settings;

  /// The folder loaded, or about to be loaded first.
  String cacheDir;
  bool loading = false;
  Profiles? profiles;
  CacheCatalog catalog = const CacheCatalog();

  /// Why the cache folder or its profiles cannot be used.
  String? cacheError;

  /// Why the last load, save or delete failed.
  String? actionError;

  /// The profile name typed by the user; it names what Load, Save and Delete
  /// act on.
  String name = '';

  /// The editor's values, keyed like [RunOptions.toJson].
  Map<String, Object?> draft = const RunOptions(dats: []).toJson();
  RunOptions? options = const RunOptions(dats: []);
  String? optionsError;

  /// Whether the draft was edited or loaded, so a cache folder no longer
  /// replaces it with its defaults.
  bool _touched = false;

  bool running = false;
  bool applied = false;
  final platforms = <PlatformProgress>[];
  String? syncSummary;

  SendPort? _control;
  int _loadRequest = 0;

  File get profilesFile => File(p.join(cacheDir, 'profiles.jsonc'));

  /// Whether [name] is a stored profile, so it can be loaded or deleted.
  bool get nameExists => profiles?.names.contains(name.trim()) ?? false;

  bool get canSave =>
      !running && profiles != null && options != null && name.trim().isNotEmpty;

  /// Whether [directory] is the folder already loaded.
  bool isCurrent(String directory) =>
      profiles != null &&
      p.equals(p.normalize(p.absolute(directory)), cacheDir);

  /// Loads [directory], or the current folder again when omitted. A folder
  /// that is already loaded is not read twice.
  Future<void> load({String? directory}) async {
    if (running || (directory != null && isCurrent(directory))) return;
    final target = p.normalize(p.absolute(directory ?? cacheDir));
    final request = ++_loadRequest;
    loading = true;
    notifyListeners();
    final file = File(p.join(target, 'profiles.jsonc'));
    Profiles? loaded;
    String? error;
    var catalog = const CacheCatalog();
    try {
      loaded = await file.exists()
          ? await Profiles.load(file)
          : Profiles.empty(file);
      catalog = await CacheCatalog.load(target);
    } on FileSystemException catch (e) {
      error = 'Cannot read ${file.path}: ${e.message}';
    } on FormatException catch (e) {
      error = '${file.path}: ${e.message}';
    }
    if (request != _loadRequest) return;
    cacheDir = target;
    profiles = loaded;
    this.catalog = catalog;
    cacheError = error;
    actionError = null;
    loading = false;
    if (!_touched) draft = _defaults();
    _validate();
    notifyListeners();
    if (await Directory(target).exists()) await settings?.setCacheDir(target);
  }

  /// The DATs of [profile], or why it does not resolve.
  String summary(String profile) {
    try {
      return profiles!.resolve(profile).dats.join(' + ');
    } on FormatException catch (e) {
      return e.message;
    }
  }

  void rename(String value) {
    name = value;
    notifyListeners();
  }

  /// Replaces the draft with the stored profile [name].
  void loadProfile() {
    final profiles = this.profiles;
    if (running || profiles == null || !nameExists) return;
    try {
      draft = profiles.resolve(name.trim()).toJson();
      _touched = true;
      actionError = null;
      _validate();
      platforms.clear();
    } on FormatException catch (e) {
      actionError = '${name.trim()}: ${e.message}';
    }
    notifyListeners();
  }

  /// Sets one option. Naming langcount in the priority picks a direction for
  /// it; leaving it out clears the direction.
  void edit(String key, Object? value) {
    draft = {...draft, key: value};
    _touched = true;
    if (key == 'priority' && value is List) {
      final byCount = value.contains(ScoreAxis.langcount.name);
      if (byCount && draft['langcount'] == null) {
        draft['langcount'] = LangCount.most.name;
      } else if (!byCount) {
        draft['langcount'] = null;
      }
    }
    _validate();
    notifyListeners();
  }

  /// Stores the draft as [name], replacing a profile of that name.
  Future<void> saveProfile() async {
    final profiles = this.profiles;
    final options = this.options;
    if (!canSave || profiles == null || options == null) return;
    try {
      await profiles.save(name.trim(), options);
      actionError = null;
    } on FileSystemException catch (e) {
      actionError = 'Cannot save ${profilesFile.path}: ${e.message}';
    } on FormatException catch (e) {
      actionError = e.message;
    }
    notifyListeners();
  }

  /// Removes the stored profile [name]; the draft stays as it is.
  Future<void> deleteProfile() async {
    final profiles = this.profiles;
    if (running || profiles == null || !nameExists) return;
    try {
      await profiles.delete(name.trim());
      actionError = null;
    } on FileSystemException catch (e) {
      actionError = 'Cannot save ${profilesFile.path}: ${e.message}';
    } on FormatException catch (e) {
      actionError = e.message;
    }
    notifyListeners();
  }

  Map<String, Object?> _defaults() {
    try {
      return profiles?.defaults.toJson() ?? const RunOptions(dats: []).toJson();
    } on FormatException {
      return const RunOptions(dats: []).toJson();
    }
  }

  void _validate() {
    try {
      options = RunOptions.fromJson(draft, baseDir: cacheDir);
      optionsError = null;
    } on FormatException catch (e) {
      options = null;
      optionsError = e.message;
    }
  }

  Future<void> start({required bool apply}) async {
    final options = this.options;
    if (running || loading || options == null || options.dats.isEmpty) return;
    running = true;
    applied = apply;
    syncSummary = null;
    platforms.clear();
    notifyListeners();

    final events = ReceivePort();
    final worker = await Isolate.spawn(_work, (
      events.sendPort,
      cacheDir,
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
