import 'dart:io';

import '../../data/dat_mirror.dart';
import '../../data/metadata_repository.dart';
import '../runner.dart';

class SyncCommand extends ArchivistCommand {
  SyncCommand() {
    argParser
      ..addFlag(
        'force',
        negatable: false,
        help: 'Re-download all assets, ignoring hash.json.',
      )
      ..addMultiOption(
        'only',
        allowed: [
          ...MetadataAsset.values.map((a) => a.name),
          ...DatSource.values.map((s) => s.name),
        ],
        help: 'Limit sync to specific assets or DAT sources.',
      )
      ..addMultiOption(
        'system',
        help:
            'Also fetch the Redump and MAME-Redump DAT of this system, e.g. '
            '"Sega - Saturn". Those already in the cache are updated anyway.',
      );
  }

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Fetch/update metadata, clonelists, RetroAchievements and MIA data '
      'from the Retool source repo, and the Redump and MAME-Redump DATs.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final cache = results['cache'] as String;
    final only = results['only'] as List<String>;
    final assets = only.isEmpty
        ? null
        : {for (final n in only) ?MetadataAsset.values.asNameMap()[n]};
    final sources = only.isEmpty
        ? null
        : {for (final n in only) ?DatSource.values.asNameMap()[n]};

    final repo = RemoteMetadataRepository(cacheDir: cache);
    final mirror = DatMirror(cacheDir: cache);
    stdout.writeln('Syncing into "$cache" ...');
    void progress(String m) => stdout.writeln('  $m');
    final metadata = await repo.sync(
      force: results['force'] as bool,
      only: assets,
      onProgress: progress,
    );
    final dats = await mirror.sync(
      only: sources,
      systems: (results['system'] as List<String>).toSet(),
      onProgress: progress,
    );
    repo.close();
    mirror.close();
    final report = (
      downloaded: metadata.downloaded + dats.downloaded,
      upToDate: metadata.upToDate + dats.upToDate,
      removed: metadata.removed + dats.removed,
      errors: [...metadata.errors, ...dats.errors],
    );

    stdout.writeln(
      'Done: ${report.downloaded} downloaded, ${report.upToDate} up-to-date, '
      '${report.removed} stale removed, ${report.errors.length} error(s).',
    );
    for (final e in report.errors) {
      stderr.writeln('  ! $e');
    }
    return report.ok ? 0 : 1;
  }
}
