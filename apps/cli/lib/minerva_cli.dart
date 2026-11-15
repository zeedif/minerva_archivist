import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/commands.dart';

/// Runs the CLI and returns its exit code: 0 on success, 1 when a stage
/// failed, 64 for a usage or configuration error.
Future<int> runCli(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'minerva',
          'Curate ROM collections against No-Intro and Redump DATs: pick one '
              'dump per game, fetch what is missing from the MiNERVA Archive '
              'and keep the folder tidy.',
        )
        ..addCommand(RunCommand())
        ..addCommand(SelectCommand())
        ..addCommand(SyncCommand())
        ..addCommand(ProfilesCommand());
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 64;
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}${e.path == null ? "" : ": ${e.path}"}');
    return 64;
  }
}
