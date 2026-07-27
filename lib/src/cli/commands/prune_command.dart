import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/auditor.dart';
import '../../domain/organize.dart';
import '../runner.dart';
import '../selection_options.dart';

class PruneCommand extends ArchivistCommand with SelectionCommand {
  PruneCommand() {
    argParser
      ..addFlag(
        'apply',
        negatable: false,
        help: 'Actually move files to .trash (default is a dry run).',
      )
      ..addMultiOption(
        'protect',
        help: 'Folder names to never touch (mods/hacks).',
      );
    argParser.addSelectionFlags();
  }

  @override
  String get name => 'prune';

  @override
  String get description =>
      'Move files not in the filtered set to a .trash folder (reversible).';

  @override
  Future<int> run() async {
    requireDatPaths();
    final root = requireRomRoot();
    final apply = argResults!.flag('apply');
    final protect = argResults!.multiOption('protect').toSet();

    const auditor = RomAuditor();
    const pruner = TrashPruner();

    var total = 0;
    for (final t in await loadSelectedTargets()) {
      final report = await auditor.audit(
        dat: t.target,
        romRoot: root,
        catalog: t.dat,
      );
      final moved = await pruner.prune(
        report: report,
        romRoot: root,
        protectedFolders: {...protect, ...report.library.curatedFolders},
        dryRun: !apply,
      );
      total += moved.length;
      stdout.writeln(
        '${t.dat.header.name}: ${moved.length} orphan(s)'
        '${apply ? " moved" : " (dry run)"}',
      );
      for (final f in moved) {
        stdout.writeln('  - ${p.relative(f.path, from: p.join(root.path, trashFolderName))}');
      }
      final twinned = report.duplicatesInCuratedFolders(root);
      if (twinned.isNotEmpty) {
        stdout.writeln(
          '  ${twinned.length} duplicate(s) left alone inside curated folders '
          '— merge them by hand to drop the extra copy:',
        );
        for (final f in twinned) {
          stdout.writeln('  = ${p.relative(f.path, from: root.path)}');
        }
      }
    }
    stdout.writeln('Total: $total orphan(s).');
    return 0;
  }
}
