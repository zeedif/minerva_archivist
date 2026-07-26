import 'dart:io';

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
        allowed: MetadataAsset.values.map((a) => a.name),
        help: 'Limit sync to specific assets.',
      );
  }

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Fetch/update metadata, clonelists, RetroAchievements and MIA data '
      'from the Retool source repo.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final cache = results['cache'] as String;
    final only = results['only'] as List<String>;
    final assets = only.isEmpty
        ? null
        : only.map(MetadataAsset.values.byName).toSet();

    final repo = RemoteMetadataRepository(cacheDir: cache);
    stdout.writeln('Syncing metadata into "$cache" ...');
    final report = await repo.sync(
      force: results['force'] as bool,
      only: assets,
      onProgress: (m) => stdout.writeln('  $m'),
    );
    repo.close();

    stdout.writeln(
      'Done: ${report.downloaded} downloaded, ${report.upToDate} up-to-date, '
      '${report.errors.length} error(s).',
    );
    for (final e in report.errors) {
      stderr.writeln('  ! $e');
    }
    return report.ok ? 0 : 1;
  }
}
