import 'dart:io';

import '../../domain/auditor.dart';
import '../runner.dart';
import '../selection_options.dart';

class AuditCommand extends ArchivistCommand with SelectionCommand {
  AuditCommand() {
    argParser
      ..addFlag(
        'hash',
        defaultsTo: true,
        help: 'Verify by hashing (use --no-hash for a fast name/size pass).',
      )
      ..addFlag(
        'chd',
        defaultsTo: true,
        help: 'Accept local .chd files for raw Redump entries.',
      );
    argParser.addSelectionFlags();
  }

  @override
  String get name => 'audit';

  @override
  String get description =>
      'Audit your ROM directory against the filtered (1G1R) game set.';

  @override
  Future<int> run() async {
    requireDatPaths();
    final root = requireRomRoot();
    final matchChd = argResults!.flag('chd');
    final computeHashes = argResults!.flag('hash');
    const auditor = RomAuditor();

    var totalPresent = 0;
    var totalMissing = 0;
    for (final t in await loadSelectedTargets()) {
      final report = await auditor.audit(
        dat: t.target,
        romRoot: root,
        matchChd: matchChd,
        computeHashes: computeHashes,
      );
      totalPresent += report.present.length;
      totalMissing += report.missing.length;
      stdout.writeln(
        '${t.dat.header.name} [${t.dat.header.flavor.name}]: '
        '${t.funnel} — '
        '${report.present.length} present, ${report.missing.length} missing, '
        '${report.unknownFiles.length} unknown',
      );
    }
    stdout.writeln('Total: $totalPresent present, $totalMissing missing.');
    return 0;
  }
}
