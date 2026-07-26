import 'dart:io';

import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('minerva_reloc_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('flattens only selected files; discards boundary extras + control files', () async {
    // Simulate aria2 output for a selective download where a shared piece also
    // materialized one unselected ("boundary") file:
    //   <root>/Minerva_Myrient.aria2
    //   <root>/Minerva_Myrient/No-Intro/Atari - 8-bit Family/*.zip (+ .aria2)
    final nested = Directory(
      '${tmp.path}/Minerva_Myrient/No-Intro/Atari - 8-bit Family',
    )..createSync(recursive: true);
    File('${tmp.path}/Minerva_Myrient.aria2').writeAsStringSync('ctrl');
    File('${nested.path}/3-D Tic-Tac-Toe (USA).zip').writeAsStringSync('a'); // selected
    File('${nested.path}/A.E. (USA) (Side A).zip').writeAsStringSync('b'); // selected
    File('${nested.path}/Boundary Extra (USA).zip').writeAsStringSync('x'); // NOT selected
    File('${nested.path}/A.E. (USA) (Side A).zip.aria2').writeAsStringSync('c');

    final result = await const TorrentRelocator().flatten(
      romRoot: tmp,
      topDir: 'Minerva_Myrient',
      keepBasenames: {
        '3-d tic-tac-toe (usa).zip',
        'a.e. (usa) (side a).zip',
      },
    );

    expect(result.moved.length, 2);
    expect(result.discarded, 1);
    expect(result.removedControlFiles, 2); // top-level + nested .aria2
    expect(File('${tmp.path}/3-D Tic-Tac-Toe (USA).zip').existsSync(), isTrue);
    expect(File('${tmp.path}/A.E. (USA) (Side A).zip').existsSync(), isTrue);
    // Boundary file was NOT promoted and was removed with the tree.
    expect(File('${tmp.path}/Boundary Extra (USA).zip').existsSync(), isFalse);
    expect(Directory('${tmp.path}/Minerva_Myrient').existsSync(), isFalse);
    expect(File('${tmp.path}/Minerva_Myrient.aria2').existsSync(), isFalse);
  });

  test('no-op when the nested directory is absent', () async {
    final result = await const TorrentRelocator().flatten(
      romRoot: tmp,
      topDir: 'Minerva_Myrient',
    );
    expect(result.moved, isEmpty);
    expect(result.discarded, 0);
    expect(result.removedControlFiles, 0);
  });
}
