import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;

/// Base of every command: the cache location and where profiles live.
abstract class MinervaCommand extends Command<int> {
  MinervaCommand() {
    argParser
      ..addOption(
        'cache',
        defaultsTo: '.minerva-cache',
        help: 'Folder holding DATs, metadata and the profiles file.',
      )
      ..addOption(
        'profiles',
        valueHelp: 'path',
        help: 'Profiles file. Defaults to <cache>/profiles.jsonc.',
      );
  }

  String get cacheDir => argResults!.option('cache')!;

  File get profilesFile => File(
    argResults!.option('profiles') ?? p.join(cacheDir, 'profiles.jsonc'),
  );
}

/// For commands that take run options, from profiles or from the command
/// line. Call [addRunOptions] in the constructor.
mixin RunOptionsCommand on MinervaCommand {
  void addRunOptions() {
    String names<T>(Iterable<T> values, String Function(T) name) =>
        values.map(name).join(', ');
    argParser
      ..addFlag(
        'all',
        negatable: false,
        help: 'Use every profile in the profiles file.',
      )
      ..addSeparator(
        'Options (each overrides the profile; without a profile, --dat is '
        'required):',
      )
      ..addMultiOption(
        'dat',
        abbr: 'd',
        valueHelp: 'ref',
        help:
            'A DAT file, a folder of DATs, or a cached system by name, e.g. '
            '"Nintendo - Game Boy" or "redump:Sony - PlayStation".',
      )
      ..addOption(
        'root',
        abbr: 'r',
        valueHelp: 'path',
        help: 'The ROM collection. Without it only the selection is computed.',
      )
      ..addMultiOption(
        'lang',
        valueHelp: 'code',
        help:
            'Language priority, best first; a title speaking none of them is '
            'dropped. "Other" stands for unlisted languages, "Unknown" for '
            'titles with none. Es covers Es-MX. (default: En)',
      )
      ..addMultiOption(
        'region',
        valueHelp: 'name',
        help:
            'Region priority, best first, restricting like --lang. '
            '(default: every region)',
      )
      ..addMultiOption(
        'priority',
        valueHelp: 'axis',
        allowed: ScoreAxis.values.map((a) => a.name),
        allowedHelp: const {
          'lang': 'The --lang order.',
          'region': 'The --region order. Ranks below the others when omitted.',
          'ra': 'Achievements, a hash-verified dump first.',
          'langcount': 'How many languages a dump carries; needs --langcount.',
        },
        help:
            'Tie-breaks that pick one dump per title, best first. '
            '(default: lang,region,ra)',
      )
      ..addOption(
        'langcount',
        allowed: LangCount.values.map((c) => c.name),
        help: 'Which way the langcount axis ranks. Required with it.',
      )
      ..addOption(
        'wishlist',
        valueHelp: 'path',
        help: 'JSON/JSONC array of game names to select.',
      )
      ..addOption(
        'wishlist-mode',
        allowed: WishlistMode.values.map((m) => m.name),
        allowedHelp: const {
          'absolute':
              'Everything named is selected; --lang and --region only pick '
              'the dump, and --achievements adds to it.',
          'subset': 'A named title must still pass every other filter.',
        },
        help: '(default: absolute)',
      )
      ..addOption(
        'achievements',
        allowed: AchievementScope.values.map((s) => s.name),
        allowedHelp: const {
          'any': 'Titles with achievements on any dump.',
          'approved': 'Only dumps whose hash the achievement set names.',
        },
        help: 'Select only titles with RetroAchievements.',
      )
      ..addOption(
        'supersets',
        allowed: SupersetMode.values.map((m) => m.name),
        help:
            'Whether an edition that subsumes its group takes the slot. '
            '(default: prefer)',
      )
      ..addOption(
        'compilations',
        allowed: CompilationMode.values.map((m) => m.name),
        allowedHelp: const {
          'never': 'A pack never stands in for the games it holds.',
          'fill': 'Only for a game with no release of its own.',
          'prefer': 'It takes their slots, after --priority.',
          'first': 'It takes their slots, before --priority.',
        },
        help: '(default: fill)',
      )
      ..addMultiOption(
        'exclude',
        valueHelp: 'kind',
        allowed: ExcludeKind.values.map((k) => k.cli),
        help: 'Kinds of dump to drop outright, wishlist included.',
      )
      ..addOption(
        'layout',
        allowed: Layout.values.map((l) => l.cli),
        allowedHelp: const {
          'zip': '<root>/<game>.zip',
          'zip-in-folder': '<root>/<game>/<game>.zip',
          'extracted': '<root>/<game>.<ext>',
          'extracted-in-folder': '<root>/<game>.<ext>/<game>.<ext>',
        },
        help: '(default: zip)',
      )
      ..addMultiOption(
        'protect',
        valueHelp: 'folder',
        help: 'Top-level folders never touched.',
      )
      ..addMultiOption(
        'skip',
        valueHelp: 'stage',
        allowed: Stage.values.map((s) => s.name),
        help: 'Stages to leave out: ${names(Stage.values, (s) => s.name)}.',
      )
      ..addOption(
        'depth',
        valueHelp: 'n',
        help:
            'How many folders below the root are searched for ROMs; 0 is the '
            'root alone. (default: unlimited)',
      );
  }

  /// One option set per profile named on the command line (or every profile
  /// with `--all`), or a single one built from the options alone.
  Future<List<({String name, RunOptions options})>> resolveRuns() async {
    final results = argResults!;
    final overrides = <String, Object?>{
      for (final key in RunOptions.keys)
        if (results.wasParsed(key)) key: results[key],
    };
    final all = results.flag('all');
    if (results.rest.isEmpty && !all) {
      final options = RunOptions.fromJson(overrides);
      if (options.dats.isEmpty) {
        usageException('Name a profile, pass --all, or give --dat.');
      }
      return [(name: '', options: options)];
    }
    if (!await profilesFile.exists()) {
      usageException('No profiles file at ${profilesFile.path}.');
    }
    final profiles = await Profiles.load(profilesFile);
    return [
      for (final name in all ? profiles.names : results.rest)
        (name: name, options: profiles.resolve(name, overrides: overrides)),
    ];
  }
}
