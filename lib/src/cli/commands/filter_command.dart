import 'dart:io';

import '../runner.dart';
import '../selection_options.dart';

class FilterCommand extends ArchivistCommand with SelectionCommand {
  FilterCommand() {
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

    var totalGames = 0;
    var totalSelected = 0;
    for (final t in await loadSelectedTargets()) {
      totalGames += t.dat.games.length;
      totalSelected += t.games.length;
      stdout.writeln(
        '${t.dat.header.name} [${t.dat.header.flavor.name}]: ${t.funnel}',
      );
    }
    stdout.writeln('Total: $totalGames games -> $totalSelected selected.');
    return 0;
  }
}
