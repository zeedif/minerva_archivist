import 'dart:io';

import '../../models/dat.dart';
import '../runner.dart';
import '../selection_options.dart';

class FilterCommand extends ArchivistCommand with SelectionCommand {
  FilterCommand() {
    argParser
      ..addFlag(
        'list',
        negatable: false,
        help: 'Print the name of every selected game.',
      )
      ..addMultiOption(
        'explain',
        valueHelp: 'text',
        help:
            'For every game whose name contains this text, print the clone '
            'group it competed in and whether it won the 1G1R slot. Use it to '
            'see why two dumps did or did not knock each other out.',
      );
    argParser.addSelectionFlags();
  }

  @override
  String get name => 'filter';

  @override
  String get description =>
      'Compute the 1G1R selection and apply wishlist / RetroAchievements / '
      'status / category filters.';

  @override
  Future<int> run() async {
    requireDatPaths();
    final list = argResults!.flag('list');
    final explain = argResults!.multiOption('explain');

    var totalGames = 0;
    var totalSelected = 0;
    for (final t in await loadSelectedTargets()) {
      totalGames += t.dat.games.length;
      totalSelected += t.games.length;
      stdout.writeln(
        '${t.dat.header.name} [${t.dat.header.flavor.name}]: ${t.funnel}',
      );

      if (list) {
        for (final g in t.games) {
          stdout.writeln('  ${g.name}');
        }
      }

      final selected = {for (final g in t.games) g.name};
      for (final probe in explain) {
        stdout.writeln('  --- $probe');
        final matching = t.dat.games.where((g) => g.name.contains(probe));
        if (matching.isEmpty) stdout.writeln('      (no game matches)');
        for (final g in matching) {
          final group = t.selection.groups[g.name];
          stdout.writeln(
            '      ${selected.contains(g.name) ? "WIN " : "    "}${g.name}  '
            '[${group ?? "excluded before 1G1R"}]'
            // Which join a dump got decides the group whenever two of them carry
            // achievements, so the explanation is incomplete without it.
            '${switch (t.selection.raMatches[g.name]) {
              RaMatch.byHash => '  ra:hash',
              RaMatch.byName => '  ra:name',
              _ => '',
            }}',
          );
        }
      }
    }
    stdout.writeln('Total: $totalGames games -> $totalSelected selected.');
    return 0;
  }
}
