import 'dart:io';

import 'package:minerva_cli/minerva_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
