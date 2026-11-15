import 'dart:io';

import 'package:minerva_core/minerva_core.dart';

import 'options.dart';
import 'render.dart';

final class RunCommand extends MinervaCommand with RunOptionsCommand {
  RunCommand() {
    argParser.addFlag(
      'apply',
      negatable: false,
      help: 'Download, move and write. Without it the run only reports.',
    );
    addRunOptions();
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Select the wanted games, audit the collection against them, download '
      'what is missing, lay it out, write playlists and prune the rest.';

  @override
  String get invocation => 'minerva run [profile ...] [options]';

  @override
  Future<int> run() async {
    final apply = argResults!.flag('apply');
    final pipeline = Pipeline(cacheDir: cacheDir);
    var failed = false;
    try {
      for (final (:name, :options) in await resolveRuns()) {
        if (name.isNotEmpty) stdout.writeln('\n##### $name');
        final renderer = EventRenderer(apply: apply, root: options.root);
        await pipeline.run(options, apply: apply).forEach(renderer.render);
        failed |= renderer.failed;
      }
    } finally {
      pipeline.close();
    }
    return failed ? 1 : 0;
  }
}

final class SelectCommand extends MinervaCommand with RunOptionsCommand {
  SelectCommand() {
    argParser
      ..addFlag('list', negatable: false, help: 'Print every selected game.')
      ..addMultiOption(
        'explain',
        valueHelp: 'text',
        help:
            'For every DAT game containing this text, show its clone groups, '
            'its achievement match and whether it won.',
      );
    addRunOptions();
  }

  @override
  String get name => 'select';

  @override
  String get description =>
      'Compute the selection only, to see what a run would want and why.';

  @override
  String get invocation => 'minerva select [profile ...] [options]';

  @override
  Future<int> run() async {
    final list = argResults!.flag('list');
    final explain = argResults!.multiOption('explain');
    final pipeline = Pipeline(cacheDir: cacheDir);
    try {
      for (final (name: _, :options) in await resolveRuns()) {
        await for (final SelectionFinished(:dat, :selection) in pipeline.select(
          options,
        )) {
          stdout.writeln(
            '${dat.header.name} [${dat.header.flavor.name}]: '
            '${EventRenderer.funnel(selection)}',
          );
          for (final entry in selection.unmatchedWishlist) {
            stdout.writeln('  ? wishlist entry matches nothing: $entry');
          }
          if (list) {
            for (final game in selection.games) {
              stdout.writeln('  ${game.name}');
            }
          }
          final winners = {for (final game in selection.games) game.name};
          for (final probe in explain) {
            stdout.writeln('  --- $probe');
            for (final game in dat.games.where((g) => g.name.contains(probe))) {
              final groups = selection.groups[game.name]?.join(' + ');
              final achievements = switch (selection.raMatches[game.name]) {
                RaMatch.byHash => '  ra:hash',
                RaMatch.byNameRegion => '  ra:name+region',
                RaMatch.byName => '  ra:name',
                RaMatch.none || null => '',
              };
              stdout.writeln(
                '      ${winners.contains(game.name) ? "WIN " : "    "}'
                '${game.name}  [${groups ?? "filtered out"}]$achievements',
              );
            }
          }
        }
      }
    } finally {
      pipeline.close();
    }
    return 0;
  }
}

final class SyncCommand extends MinervaCommand {
  SyncCommand() {
    argParser
      ..addFlag(
        'force',
        negatable: false,
        help: 'Fetch every metadata file again.',
      )
      ..addMultiOption(
        'system',
        valueHelp: 'name',
        help:
            'Also fetch the Redump and MAME-Redump DAT of this system, e.g. '
            '"Sega - Saturn". Those already cached are updated regardless.',
      );
  }

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Update clonelists, metadata, RetroAchievements and MIA data, and the '
      'cached Redump and MAME-Redump DATs.';

  @override
  Future<int> run() async {
    final repo = RemoteMetadataRepository(cacheDir: cacheDir);
    final mirror = DatMirror(cacheDir: cacheDir);
    void progress(String message) => stdout.writeln('  $message');
    try {
      final reports = [
        await repo.sync(force: argResults!.flag('force'), onProgress: progress),
        await mirror.sync(
          systems: argResults!.multiOption('system').toSet(),
          onProgress: progress,
        ),
      ];
      final errors = [for (final r in reports) ...r.errors];
      stdout.writeln(
        '${reports.fold(0, (n, r) => n + r.downloaded)} downloaded, '
        '${reports.fold(0, (n, r) => n + r.upToDate)} up to date, '
        '${reports.fold(0, (n, r) => n + r.removed)} stale removed, '
        '${errors.length} error(s).',
      );
      for (final error in errors) {
        stderr.writeln('  ! $error');
      }
      return errors.isEmpty ? 0 : 1;
    } finally {
      repo.close();
      mirror.close();
    }
  }
}

final class ProfilesCommand extends MinervaCommand {
  @override
  String get name => 'profiles';

  @override
  String get description => 'List the profiles and what each one targets.';

  @override
  Future<int> run() async {
    if (!await profilesFile.exists()) {
      usageException('No profiles file at ${profilesFile.path}.');
    }
    final profiles = await Profiles.load(profilesFile);
    for (final name in profiles.names) {
      final options = profiles.resolve(name);
      stdout.writeln(
        '${name.padRight(24)} ${options.root ?? "(no root)"}  '
        '<- ${options.dats.join(' + ')}',
      );
    }
    return 0;
  }
}
