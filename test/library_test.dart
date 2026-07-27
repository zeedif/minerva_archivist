import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A DAT entry describing exactly the bytes [content] would be written as, so
/// the real hasher matches the file the fixture writes for it.
RomEntry _rom(String name, String content) => RomEntry(
  name: name,
  size: utf8.encode(content).length,
  format: RomFormat.cartridge,
  sha1: crypto.sha1.convert(utf8.encode(content)).toString(),
);

DatGame _game(String name, List<RomEntry> roms) =>
    DatGame(name: name, roms: roms, metadata: const GameMetadata());

DatFile _dat(List<DatGame> games) => DatFile(
  header: const DatHeader(name: 't', flavor: DatFlavor.noIntro),
  games: games,
);

void main() {
  late Directory tmp;
  const auditor = RomAuditor();

  setUp(() async => tmp = await Directory.systemTemp.createTemp('minerva_lib_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String relativePath, String content) {
    final file = File(p.join(tmp.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  group('curated-folder detection', () {
    test('a folder holding a dump plus content of your own is curated', () async {
      write('Body Harvest (USA)/Body Harvest (USA).z64', 'body-harvest');
      write('Body Harvest (USA)/translations/patch (T-Es).z64', 'patched');
      write('Body Harvest (USA)/translations/readme.txt', 'notes');

      final dat = _dat([
        _game('Body Harvest (USA)', [
          _rom('Body Harvest (USA).z64', 'body-harvest'),
        ]),
      ]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);

      expect(report.library.curatedFolders, {'Body Harvest (USA)'});
      expect(report.library.curatedGames, {'Body Harvest (USA)'});
      expect(report.present.single.game.name, 'Body Harvest (USA)');
    });

    test('a folder holding nothing but dumps is not curated', () async {
      write('Some Folder/Alpha (USA).z64', 'alpha');
      write('Some Folder/Beta (USA).z64', 'beta');

      final dat = _dat([
        _game('Alpha (USA)', [_rom('Alpha (USA).z64', 'alpha')]),
        _game('Beta (USA)', [_rom('Beta (USA).z64', 'beta')]),
      ]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);

      expect(report.library.curatedFolders, isEmpty);
      expect(report.library.completeGames, {'Alpha (USA)', 'Beta (USA)'});
    });

    test('saves and playlists do not make a folder curated', () async {
      write('Alpha (USA)/Alpha (USA).z64', 'alpha');
      write('Alpha (USA)/Alpha (USA).srm', 'save');
      write('Alpha (USA)/Alpha (USA).state1', 'state');
      write('Alpha (USA)/Alpha (USA).m3u', 'playlist');

      final dat = _dat([_game('Alpha (USA)', [_rom('Alpha (USA).z64', 'alpha')])]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);

      expect(report.library.curatedFolders, isEmpty);
    });

    test('a loose file is never curated, whatever sits beside it', () async {
      write('Alpha (USA).z64', 'alpha');
      write('random-notes.txt', 'hello');

      final dat = _dat([_game('Alpha (USA)', [_rom('Alpha (USA).z64', 'alpha')])]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);

      expect(report.library.curatedFolders, isEmpty);
    });

    test('a half-present multi-ROM game is partial, not settled', () async {
      write('Disc Game (USA)/Disc Game (USA).cue', 'cue');
      write('Disc Game (USA)/notes.txt', 'mine');

      final dat = _dat([
        _game('Disc Game (USA)', [
          _rom('Disc Game (USA).cue', 'cue'),
          _rom('Disc Game (USA).bin', 'bin'),
        ]),
      ]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);
      final entry = report.library.entryFor('Disc Game (USA)')!;

      expect(entry.isCurated, isTrue);
      expect(entry.completeGames, isEmpty);
      expect(entry.partialGames, {'Disc Game (USA)'});
      // Still missing, so the download stage can finish it off.
      expect(report.missing.single.game.name, 'Disc Game (USA)');
    });
  });

  group('recognizing dumps that lost the 1G1R slot', () {
    // A curated folder holds one dump, 1G1R picks its sibling: fetching that
    // sibling would land it beside a patch built for the one already there.
    final europe = _game('007 (Europe)', [_rom('007 (Europe).z64', 'eu')]);
    final usa = _game('007 (USA)', [_rom('007 (USA).z64', 'us')]);

    test('the catalog identifies it, so it is not read as junk', () async {
      write('007 (Europe)/007 (Europe).z64', 'eu');
      write('007 (Europe)/translations/007 (T-Es).z64', 'patched');

      final report = await auditor.audit(
        dat: _dat([usa]), // 1G1R kept only the USA dump
        romRoot: tmp,
        catalog: _dat([europe, usa]),
      );

      expect(report.library.curatedGames, {'007 (Europe)'});
      // The Europe dump still isn't part of the selected set, so it stays
      // prunable in principle...
      expect(
        report.unknownFiles.map((f) => p.basename(f.path)),
        contains('007 (Europe).z64'),
      );
      // ...but never actually prunable, because it sits in a curated folder.
      expect(report.prunable(tmp), isEmpty);
    });

    test('the pruner leaves the whole curated folder alone', () async {
      write('007 (Europe)/007 (Europe).z64', 'eu');
      write('007 (Europe)/translations/007 (T-Es).z64', 'patched');
      final orphan = write('junk.z64', 'junk');

      final report = await auditor.audit(
        dat: _dat([usa]),
        romRoot: tmp,
        catalog: _dat([europe, usa]),
      );
      final moved = await const TrashPruner().prune(
        report: report,
        romRoot: tmp,
        protectedFolders: report.library.curatedFolders,
      );

      expect(moved.length, 1);
      expect(orphan.existsSync(), isFalse);
      expect(File(p.join(tmp.path, '007 (Europe)', '007 (Europe).z64')).existsSync(), isTrue);
      expect(
        File(p.join(tmp.path, '007 (Europe)', 'translations', '007 (T-Es).z64')).existsSync(),
        isTrue,
      );
    });

    test('the organizer does not drag the dump out to the root', () async {
      write('007 (Europe)/007 (Europe).z64', 'eu');
      write('007 (Europe)/translations/007 (T-Es).z64', 'patched');

      final report = await auditor.audit(
        dat: _dat([europe]),
        romRoot: tmp,
        catalog: _dat([europe, usa]),
      );
      final actions = await const EsdeRomOrganizer().organize(
        present: report.present,
        romRoot: tmp,
        config: OrganizeConfig(
          protectedFolders: report.library.curatedFolders,
        ),
      );

      expect(actions.single.op, OrganizeOp.skippedProtected);
      expect(File(p.join(tmp.path, '007 (Europe)', '007 (Europe).z64')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, '007 (Europe).z64')).existsSync(), isFalse);
    });

    test('an unprotected runner-up is still pruned', () async {
      // Same duplicate, but with nothing of the user's around it there is no
      // reason to keep a second dump of one game.
      write('007 (Europe).z64', 'eu');
      write('007 (USA).z64', 'us');

      final report = await auditor.audit(
        dat: _dat([usa]),
        romRoot: tmp,
        catalog: _dat([europe, usa]),
      );
      await const TrashPruner().prune(
        report: report,
        romRoot: tmp,
        protectedFolders: report.library.curatedFolders,
      );

      expect(File(p.join(tmp.path, '007 (USA).z64')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, '007 (Europe).z64')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, '.trash', '007 (Europe).z64')).existsSync(), isTrue);
    });

    test('a folder emptied by pruning goes with it', () async {
      write('007 (Europe)/007 (Europe).z64', 'eu');
      write('007 (USA).z64', 'us');

      final report = await auditor.audit(
        dat: _dat([usa]),
        romRoot: tmp,
        catalog: _dat([europe, usa]),
      );
      await const TrashPruner().prune(report: report, romRoot: tmp);

      expect(Directory(p.join(tmp.path, '007 (Europe)')).existsSync(), isFalse);
      expect(
        File(p.join(tmp.path, '.trash', '007 (Europe)', '007 (Europe).z64')).existsSync(),
        isTrue,
      );
    });
  });

  group('redundant copies of a dump the collection already holds', () {
    final sagaia = _game('Sagaia (Japan) (En)', [
      _rom('Sagaia (Japan) (En).gb', 'sagaia'),
    ]);

    test('a loose copy of a curated dump is pruned, the curated one kept', () async {
      // Curation protects the folder, not the bytes in it.
      write('Sagaia (Japan) (En)/Sagaia (Japan) (En).gb', 'sagaia');
      write('Sagaia (Japan) (En)/translations/sagaia (T-Es).ips', 'patch');
      write('Sagaia (Japan) (En).gb', 'sagaia');

      final report = await auditor.audit(dat: _dat([sagaia]), romRoot: tmp);

      // Recognized, so not a stray; the duplication is what condemns it. The
      // patch beside it is a stray, but a curated one, so it stays.
      expect(
        report.unknownFiles.map((f) => p.basename(f.path)),
        isNot(contains('Sagaia (Japan) (En).gb')),
      );
      expect(
        report.redundantFiles.map((f) => p.relative(f.path, from: tmp.path)),
        ['Sagaia (Japan) (En).gb'],
      );

      await const TrashPruner().prune(
        report: report,
        romRoot: tmp,
        protectedFolders: report.library.curatedFolders,
      );

      expect(File(p.join(tmp.path, 'Sagaia (Japan) (En).gb')).existsSync(), isFalse);
      expect(
        File(p.join(tmp.path, 'Sagaia (Japan) (En)', 'Sagaia (Japan) (En).gb')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(tmp.path, 'Sagaia (Japan) (En)', 'translations', 'sagaia (T-Es).ips'))
            .existsSync(),
        isTrue,
      );
    });

    test('the curated copy wins however the disk was read', () async {
      // The root copy sorts first; the keeper must still be the curated one.
      write('AAA copy.gb', 'sagaia');
      write('Sagaia (Japan) (En)/Sagaia (Japan) (En).gb', 'sagaia');
      write('Sagaia (Japan) (En)/notes.txt', 'mine');

      final report = await auditor.audit(dat: _dat([sagaia]), romRoot: tmp);

      expect(
        report.redundantFiles.map((f) => p.basename(f.path)),
        ['AAA copy.gb'],
      );
      expect(
        p.basename(report.present.single.location!.parent.path),
        'Sagaia (Japan) (En)',
      );
    });

    test('with no folder curated the canonically-named copy keeps the slot', () async {
      write('Sagaia (Japan) (En).gb', 'sagaia');
      write('spare/whatever.gb', 'sagaia');

      final report = await auditor.audit(dat: _dat([sagaia]), romRoot: tmp);

      expect(
        report.redundantFiles.map((f) => p.basename(f.path)),
        ['whatever.gb'],
      );
    });

    test('two curated folders holding it are reported, never touched', () async {
      // Which set of patches to keep is a judgement about content, so both stay.
      write('Ocarina ES/Legend of Zelda (USA).z64', 'oot');
      write('Ocarina ES/translations/oot (T-Es).bps', 'patch-es');
      write('Ocarina FR/Legend of Zelda (USA).z64', 'oot');
      write('Ocarina FR/translations/oot (T-Fr).bps', 'patch-fr');

      final dat = _dat([
        _game('Legend of Zelda (USA)', [_rom('Legend of Zelda (USA).z64', 'oot')]),
      ]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);

      expect(report.redundantFiles, hasLength(1));
      expect(report.duplicatesInCuratedFolders(tmp), hasLength(1));
      expect(report.prunable(tmp), isEmpty);

      await const TrashPruner().prune(
        report: report,
        romRoot: tmp,
        protectedFolders: report.library.curatedFolders,
      );
      expect(File(p.join(tmp.path, 'Ocarina ES', 'Legend of Zelda (USA).z64')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, 'Ocarina FR', 'Legend of Zelda (USA).z64')).existsSync(), isTrue);
    });

    test('a copy condemned twice over is still listed once', () async {
      // The loose copy is both a dump the audited set dropped and a duplicate of
      // the curated one. Listed twice, the pruner's second move finds it gone.
      write('Sagaia (Japan) (En)/Sagaia (Japan) (En).gb', 'sagaia');
      write('Sagaia (Japan) (En)/translations/sagaia (T-Es).ips', 'patch');
      write('Sagaia (Japan) (En).gb', 'sagaia');
      final other = _game('Sagaia (USA)', [_rom('Sagaia (USA).gb', 'usa')]);

      final report = await auditor.audit(
        dat: _dat([other]), // 1G1R kept the USA dump, not this one
        romRoot: tmp,
        catalog: _dat([sagaia, other]),
      );

      expect(
        report.prunable(tmp).map((f) => p.relative(f.path, from: tmp.path)),
        ['Sagaia (Japan) (En).gb'],
      );
    });

    test('different dumps of one game in separate folders are not duplicates', () async {
      // The Ocarina case the user actually curates: three regional dumps, each
      // with its own translation. Different bytes, so nothing is redundant.
      write('OoT USA/Zelda (USA).z64', 'us');
      write('OoT USA/translations/a.bps', 'p1');
      write('OoT Europe/Zelda (Europe).z64', 'eu');
      write('OoT Europe/translations/b.bps', 'p2');

      final dat = _dat([
        _game('Zelda (USA)', [_rom('Zelda (USA).z64', 'us')]),
        _game('Zelda (Europe)', [_rom('Zelda (Europe).z64', 'eu')]),
      ]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);

      expect(report.redundantFiles, isEmpty);
      expect(report.library.curatedFolders, {'OoT USA', 'OoT Europe'});
    });
  });

  group('in-place canonicalisation of curated folders', () {
    test('a misnamed single-game folder is renamed', () async {
      write('Zelda/Legend of Zelda, The - Ocarina of Time (USA).z64', 'oot');
      write('Zelda/translations/oot (T-Es).bps', 'patch');

      final dat = _dat([
        _game('Legend of Zelda, The - Ocarina of Time (USA)', [
          _rom('Legend of Zelda, The - Ocarina of Time (USA).z64', 'oot'),
        ]),
      ]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);
      final actions = await const CuratedFolderRenamer().rename(
        report: report,
        romRoot: tmp,
      );

      expect(actions.single.op, OrganizeOp.renamed);
      final renamed = Directory(
        p.join(tmp.path, 'Legend of Zelda, The - Ocarina of Time (USA)'),
      );
      expect(renamed.existsSync(), isTrue);
      // The user's own content moved with it, still beside the dump.
      expect(
        File(p.join(renamed.path, 'translations', 'oot (T-Es).bps')).existsSync(),
        isTrue,
      );
    });

    test('a ROM is renamed to its DAT name without leaving the folder', () async {
      write('Alpha (USA)/whatever-i-called-it.z64', 'alpha');
      write('Alpha (USA)/notes.txt', 'mine');

      final dat = _dat([_game('Alpha (USA)', [_rom('Alpha (USA).z64', 'alpha')])]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);
      final actions = await const CuratedFolderRenamer().rename(
        report: report,
        romRoot: tmp,
      );

      expect(actions.every((a) => a.op == OrganizeOp.renamed), isTrue);
      expect(
        File(p.join(tmp.path, 'Alpha (USA)', 'Alpha (USA).z64')).existsSync(),
        isTrue,
      );
      expect(File(p.join(tmp.path, 'Alpha (USA)', 'notes.txt')).existsSync(), isTrue);
    });

    test('a folder holding two games keeps its name', () async {
      write('My Pair/Alpha (USA).z64', 'alpha');
      write('My Pair/Beta (USA).z64', 'beta');
      write('My Pair/notes.txt', 'mine');

      final dat = _dat([
        _game('Alpha (USA)', [_rom('Alpha (USA).z64', 'alpha')]),
        _game('Beta (USA)', [_rom('Beta (USA).z64', 'beta')]),
      ]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);
      final actions = await const CuratedFolderRenamer().rename(
        report: report,
        romRoot: tmp,
      );

      expect(actions.where((a) => a.op == OrganizeOp.renamed), isEmpty);
      expect(Directory(p.join(tmp.path, 'My Pair')).existsSync(), isTrue);
    });

    test('an explicit --protect name is not even renamed', () async {
      write('mods/Alpha (USA).z64', 'alpha');
      write('mods/notes.txt', 'mine');

      final dat = _dat([_game('Alpha (USA)', [_rom('Alpha (USA).z64', 'alpha')])]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);
      final actions = await const CuratedFolderRenamer().rename(
        report: report,
        romRoot: tmp,
        config: const OrganizeConfig(protectedFolders: {'mods'}),
      );

      expect(actions.single.op, OrganizeOp.skippedProtected);
      expect(Directory(p.join(tmp.path, 'mods')).existsSync(), isTrue);
    });

    test('a rename that would overwrite something is refused', () async {
      write('Zelda/Alpha (USA).z64', 'alpha');
      write('Zelda/notes.txt', 'mine');
      write('Alpha (USA)/placeholder.txt', 'in the way');

      final dat = _dat([_game('Alpha (USA)', [_rom('Alpha (USA).z64', 'alpha')])]);
      final report = await auditor.audit(dat: dat, romRoot: tmp);
      final actions = await const CuratedFolderRenamer().rename(
        report: report,
        romRoot: tmp,
      );

      final failed = actions.where((a) => a.op == OrganizeOp.failed);
      expect(failed, isNotEmpty);
      expect(failed.first.error, 'already exists');
      expect(Directory(p.join(tmp.path, 'Zelda')).existsSync(), isTrue);
    });
  });
}
