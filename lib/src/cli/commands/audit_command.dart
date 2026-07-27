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
        help:
            'Verify by hashing. --no-hash skips reading the disk entirely, so '
            'every game reports as missing and no folder counts as curated: it '
            'is only useful to see the selection funnel.',
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
        catalog: t.dat,
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
      stdout.writeln('  ${report.library.summary}');
      for (final entry in report.library.curated) {
        stdout.writeln(
          '  curated: ${entry.name}  '
          '(${entry.roms.length} rom(s), ${entry.extras.length} of your own)',
        );
      }
      final settled = t.settledByCuratedGroup(report);
      for (final a in report.missing) {
        if (settled.contains(a.game.name)) {
          stdout.writeln(
            '  settled elsewhere, will not be fetched: ${a.game.name}',
          );
        }
      }
    }
    stdout.writeln('Total: $totalPresent present, $totalMissing missing.');
    return 0;
  }
}
