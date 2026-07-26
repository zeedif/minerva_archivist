import 'dart:io';

import '../../domain/auditor.dart';
import '../../domain/organize.dart';
import '../runner.dart';
import '../selection_options.dart';

class OrganizeCommand extends ArchivistCommand with SelectionCommand {
  OrganizeCommand() {
    argParser
      ..addFlag(
        'folder-as-file',
        negatable: false,
        help: 'Give each game its own folder (ES-DE folder-as-file). '
            'Off = flat layout.',
      )
      ..addFlag(
        'extract',
        negatable: false,
        help: 'Unzip archives. Off = keep the .zip as-is. '
            '(folder-as-file × extract) selects one of the 4 layout modes.',
      )
      ..addMultiOption(
        'protect',
        help: 'Folder names to never touch (mods/hacks/patches).',
      )
      ..addFlag(
        'apply',
        negatable: false,
        help: 'Actually move/extract files (default is a dry run).',
      );
    argParser.addSelectionFlags();
  }

  @override
  String get name => 'organize';

  @override
  String get description =>
      'Organize the filtered game set on disk across the 4 layout modes '
      '(EmulationStation-DE compatible).';

  @override
  Future<int> run() async {
    requireDatPaths();
    final root = requireRomRoot();
    final r = argResults!;
    final apply = r.flag('apply');
    final config = OrganizeConfig(
      layout: r.flag('folder-as-file')
          ? FolderLayout.folderAsFile
          : FolderLayout.flat,
      extract: r.flag('extract'),
      protectedFolders: r.multiOption('protect').toSet(),
    );

    const auditor = RomAuditor();
    const organizer = EsdeRomOrganizer();

    for (final t in await loadSelectedTargets()) {
      final report = await auditor.audit(
        dat: t.target,
        romRoot: root,
      );
      final actions = await organizer.organize(
        present: report.present,
        romRoot: root,
        config: config,
        dryRun: !apply,
      );
      stdout.writeln(
        '${t.dat.header.name}: ${actions.summary}'
        '${apply ? "" : " (dry run)"}',
      );
      for (final f in actions.where((a) => a.op == OrganizeOp.failed)) {
        stderr.writeln('  ! ${f.game}: ${f.error}');
      }
    }
    return 0;
  }
}
