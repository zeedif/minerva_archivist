import 'dart:io';

import 'package:minerva_archivist/minerva_archivist.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
