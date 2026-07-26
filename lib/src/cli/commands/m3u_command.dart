import 'dart:io';

import '../../domain/auditor.dart';
import '../../domain/organize.dart';
import '../runner.dart';
import '../selection_options.dart';

class M3uCommand extends ArchivistCommand with SelectionCommand {
  M3uCommand() {
    argParser.addFlag(
      'apply',
      negatable: false,
      help: 'Actually write .m3u files (default is a dry run).',
    );
    argParser.addSelectionFlags();
  }

  @override
  String get name => 'm3u';

  @override
  String get description =>
      'Generate .m3u playlists for multi-disc / multi-side games in the '
      'filtered set.';

  @override
  Future<int> run() async {
    requireDatPaths();
    final root = requireRomRoot();
    final apply = argResults!.flag('apply');

    const auditor = RomAuditor();
    const generator = DiscM3uGenerator();

    var total = 0;
    for (final t in await loadSelectedTargets()) {
      final report = await auditor.audit(
        dat: t.target,
        romRoot: root,
      );
      final written = await generator.generate(
        present: report.present,
        romRoot: root,
        dryRun: !apply,
      );
      total += written.length;
      stdout.writeln(
        '${t.dat.header.name}: ${written.length} playlist(s)'
        '${apply ? "" : " (dry run)"}',
      );
    }
    stdout.writeln('Total: $total playlist(s).');
    return 0;
  }
}
