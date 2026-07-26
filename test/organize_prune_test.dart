import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

AuditedRom _present(String game, File file) => AuditedRom(
  game: DatGame(name: game, roms: const [], metadata: const GameMetadata()),
  status: RomStatus.present,
  location: file,
);

File _makeZip(String path, Map<String, String> entries) {
  final archive = Archive();
  entries.forEach(
    (name, content) => archive.addFile(ArchiveFile.bytes(name, utf8.encode(content))),
  );
  File(path).writeAsBytesSync(ZipEncoder().encode(archive));
  return File(path);
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('minerva_org_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('organizer — 4-mode (layout x extract) matrix', () {
    test('Mode 1 Archived Flat: canonical .zip at root', () async {
      final src = _makeZip('${tmp.path}/raw.zip', {'Metroid (USA).nes': 'x'});
      final actions = await const EsdeRomOrganizer().organize(
        present: [_present('Metroid (USA)', src)],
        romRoot: tmp,
        config: const OrganizeConfig(layout: FolderLayout.flat),
      );
      expect(actions.single.op, OrganizeOp.moved);
      expect(File('${tmp.path}/Metroid (USA).zip').existsSync(), isTrue);
      expect(src.existsSync(), isFalse);
    });

    test('Mode 2 Smart Flat: single-file cart unzipped to root', () async {
      final src = _makeZip(
        '${tmp.path}/Super Mario (USA).zip',
        {'Super Mario (USA).nes': 'rom'},
      );
      final actions = await const EsdeRomOrganizer().organize(
        present: [_present('Super Mario (USA)', src)],
        romRoot: tmp,
        config: const OrganizeConfig(layout: FolderLayout.flat, extract: true),
      );
      expect(actions.single.op, OrganizeOp.extracted);
      expect(File('${tmp.path}/Super Mario (USA).nes').readAsStringSync(), 'rom');
      expect(src.existsSync(), isFalse);
    });

    test('Mode 2 Smart Flat: multi-file disc unzipped into a folder', () async {
      final src = _makeZip('${tmp.path}/Silent Hill (USA).zip', {
        'Silent Hill (USA).cue': 'cue',
        'Silent Hill (USA).bin': 'bin',
      });
      final actions = await const EsdeRomOrganizer().organize(
        present: [_present('Silent Hill (USA)', src)],
        romRoot: tmp,
        config: const OrganizeConfig(layout: FolderLayout.flat, extract: true),
      );
      expect(actions.single.op, OrganizeOp.extracted);
      expect(
        File('${tmp.path}/Silent Hill (USA)/Silent Hill (USA).cue').existsSync(),
        isTrue,
      );
      expect(
        File('${tmp.path}/Silent Hill (USA)/Silent Hill (USA).bin').existsSync(),
        isTrue,
      );
      expect(src.existsSync(), isFalse);
    });

    test('Mode 3 Archived in Folder: .zip inside a game folder', () async {
      final src = _makeZip('${tmp.path}/Tetris (USA).zip', {'Tetris (USA).nes': 'x'});
      await const EsdeRomOrganizer().organize(
        present: [_present('Tetris (USA)', src)],
        romRoot: tmp,
        config: const OrganizeConfig(layout: FolderLayout.folderAsFile),
      );
      expect(
        File('${tmp.path}/Tetris (USA)/Tetris (USA).zip').existsSync(),
        isTrue,
      );
    });

    test('Mode 4 Extracted Folder-as-File: <game>.ext/<game>.ext', () async {
      final src = _makeZip('${tmp.path}/Zelda (USA).zip', {'Zelda (USA).nes': 'rom'});
      await const EsdeRomOrganizer().organize(
        present: [_present('Zelda (USA)', src)],
        romRoot: tmp,
        config: const OrganizeConfig(
          layout: FolderLayout.folderAsFile,
          extract: true,
        ),
      );
      expect(
        File('${tmp.path}/Zelda (USA).nes/Zelda (USA).nes').readAsStringSync(),
        'rom',
      );
      expect(src.existsSync(), isFalse);
    });

    test('protection: skips a game whose target folder holds user patches', () async {
      Directory('${tmp.path}/Zelda (USA).nes').createSync();
      File('${tmp.path}/Zelda (USA).nes/Zelda (USA).ips').writeAsStringSync('patch');
      final src = _makeZip('${tmp.path}/Zelda (USA).zip', {'Zelda (USA).nes': 'rom'});
      final actions = await const EsdeRomOrganizer().organize(
        present: [_present('Zelda (USA)', src)],
        romRoot: tmp,
        config: const OrganizeConfig(
          layout: FolderLayout.folderAsFile,
          extract: true,
        ),
      );
      expect(actions.single.op, OrganizeOp.skippedProtected);
      expect(
        File('${tmp.path}/Zelda (USA).nes/Zelda (USA).ips').existsSync(),
        isTrue,
      );
      expect(src.existsSync(), isTrue); // source preserved, not extracted
    });

    // A target path that can't be listed or written (gone, unreadable, or an
    // existing file) is reported per game instead of aborting the run.
    test('an unusable target path fails that game only', () async {
      File('${tmp.path}/Metroid (USA).nes').writeAsStringSync('not a directory');
      final blocked = _makeZip('${tmp.path}/Metroid (USA).zip', {
        'Metroid (USA).nes': 'rom',
      });
      final fine = _makeZip('${tmp.path}/Tetris (USA).zip', {
        'Tetris (USA).nes': 'rom',
      });

      final actions = await const EsdeRomOrganizer().organize(
        present: [
          _present('Metroid (USA)', blocked),
          _present('Tetris (USA)', fine),
        ],
        romRoot: tmp,
        config: const OrganizeConfig(
          layout: FolderLayout.folderAsFile,
          extract: true,
        ),
      );

      final byGame = {for (final a in actions) a.game: a};
      expect(byGame['Metroid (USA)']!.op, OrganizeOp.failed);
      expect(byGame['Metroid (USA)']!.error, isNotNull);
      expect(
        byGame['Tetris (USA)']!.op,
        OrganizeOp.extracted,
        reason: 'later games must still be processed',
      );
      expect(actions.summary, contains('failed'));
    });

    test('protection: explicit protectedFolders name', () async {
      final src = _makeZip('${tmp.path}/Tetris (USA).zip', {'Tetris (USA).nes': 'x'});
      final actions = await const EsdeRomOrganizer().organize(
        present: [_present('Tetris (USA)', src)],
        romRoot: tmp,
        config: const OrganizeConfig(
          layout: FolderLayout.folderAsFile,
          protectedFolders: {'Tetris (USA)'},
        ),
      );
      expect(actions.single.op, OrganizeOp.skippedProtected);
    });
  });

  group('m3u + prune', () {
    test('m3u groups multi-disc sets and orders discs', () async {
      final d1 = File('${tmp.path}/Game (USA) (Disc 1).chd')..writeAsStringSync('a');
      final d2 = File('${tmp.path}/Game (USA) (Disc 2).chd')..writeAsStringSync('b');
      final solo = File('${tmp.path}/Solo (USA).chd')..writeAsStringSync('c');
      final written = await const DiscM3uGenerator().generate(
        present: [
          _present('Game (USA) (Disc 2)', d2),
          _present('Game (USA) (Disc 1)', d1),
          _present('Solo (USA)', solo),
        ],
        romRoot: tmp,
      );
      expect(written.length, 1);
      final lines = File('${tmp.path}/Game (USA).m3u')
          .readAsLinesSync()
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines.first, contains('Disc 1'));
      expect(lines[1], contains('Disc 2'));
    });

    test('pruner moves unknown files to .trash, sparing protected folders', () async {
      final orphan = File('${tmp.path}/junk.bin')..writeAsStringSync('x');
      Directory('${tmp.path}/mods').createSync();
      final modFile = File('${tmp.path}/mods/hack.bin')..writeAsStringSync('y');
      final report = AuditReport(
        dat: const DatFile(
          header: DatHeader(name: 't', flavor: DatFlavor.noIntro),
          games: [],
        ),
        results: const [],
        unknownFiles: [orphan, modFile],
      );
      final moved = await const TrashPruner().prune(
        report: report,
        romRoot: tmp,
        protectedFolders: {'mods'},
      );
      expect(moved.length, 1);
      expect(File('${tmp.path}/.trash/junk.bin').existsSync(), isTrue);
      expect(orphan.existsSync(), isFalse);
      expect(modFile.existsSync(), isTrue);
    });
  });
}
