/// CLI entry point: the command runner, common flags, and the command base.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'commands/audit_command.dart';
import 'commands/download_command.dart';
import 'commands/filter_command.dart';
import 'commands/m3u_command.dart';
import 'commands/organize_command.dart';
import 'commands/prune_command.dart';
import 'commands/run_command.dart';
import 'commands/sync_command.dart';

/// Builds the CLI and runs it, returning a process exit code.
Future<int> runCli(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'minerva_archivist',
          'MiNERVA Archivist — audit, filter (1G1R), and selectively '
              'download ROM sets from the MiNERVA Archive.',
        )
        ..addCommand(SyncCommand())
        ..addCommand(AuditCommand())
        ..addCommand(FilterCommand())
        ..addCommand(DownloadCommand())
        ..addCommand(OrganizeCommand())
        ..addCommand(M3uCommand())
        ..addCommand(PruneCommand())
        ..addCommand(RunCommand());

  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64; // EX_USAGE
  }
}

/// Flags shared by every stage command.
extension CommonFlags on ArgParser {
  void addCommonFlags() {
    addMultiOption(
      'dat',
      abbr: 'd',
      help: 'Path to a DAT file or a directory of DATs (flavor auto-detected).',
    );
    addOption(
      'rom-root',
      abbr: 'r',
      help: 'Root directory of your ROM collection.',
    );
    addOption(
      'cache',
      help: 'Metadata cache directory.',
      defaultsTo: '.minerva-cache',
    );
    addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose logging.');
  }
}

/// Base for all archivist subcommands; wires the common flags and exposes them
/// as typed accessors.
abstract class ArchivistCommand extends Command<int> {
  ArchivistCommand() {
    argParser.addCommonFlags();
  }

  List<String> get datPaths => argResults!.multiOption('dat');

  String? get romRoot => argResults!.option('rom-root');

  String get cacheDir => argResults!.option('cache')!;

  bool get verbose => argResults!.flag('verbose');

  /// `--dat` paths, or a usage error when none were given.
  List<String> requireDatPaths() {
    final paths = datPaths;
    if (paths.isEmpty) usageException('Provide at least one --dat.');
    return paths;
  }

  /// `--rom-root` as a directory, or a usage error when it wasn't given.
  Directory requireRomRoot() {
    final root = romRoot;
    if (root == null) usageException('Provide --rom-root.');
    return Directory(root);
  }
}
