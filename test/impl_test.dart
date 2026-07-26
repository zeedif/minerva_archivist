import 'dart:io';

import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

const _noIntroXml = '''
<?xml version="1.0"?>
<datafile>
  <header><name>Nintendo - Pokemon Mini (Parent-Clone)</name><url>https://www.no-intro.org</url></header>
  <game name="Tetris (World)">
    <release name="Tetris (World)" region="USA"/>
    <rom name="Tetris (World).min" size="5" crc="3610a686" md5="5d41402abc4b2a76b9719d911017c592" sha1="aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"/>
  </game>
</datafile>
''';

const _mameXml = '''
<?xml version="1.0"?>
<datafile>
  <header><name>Sony - PlayStation</name><author>MAME Redump</author></header>
  <machine name="Some Game (Japan)">
    <disk name="Some Game (Japan).chd" sha1="306b65cb7fa6fb4f15d1b093d01f9d3f92e4a153"/>
  </machine>
</datafile>
''';

const _redumpXml = '''
<?xml version="1.0"?>
<datafile>
  <header><name>Sony - PlayStation</name><homepage>redump.org</homepage></header>
  <game name="Bushido Blade 2 (USA)">
    <rom name="Bushido Blade 2 (USA).cue" size="87" crc="94f839cf" sha1="02906efdf44d234aa0ad15872f69e150c551c2a0"/>
    <rom name="Bushido Blade 2 (USA).bin" size="100" crc="deadbeef" sha1="1111111111111111111111111111111111111111"/>
  </game>
</datafile>
''';

Future<DatFile> _parse(String xml) async {
  final d = await const LogiqxDatParser().parse(xml);
  return DatFile(
    header: d.header.copyWith(flavor: detectDatFlavor(d.header, d.games)),
    games: d.games,
  );
}

void main() {
  group('parser + flavor detector', () {
    test('No-Intro cartridge', () async {
      final dat = await _parse(_noIntroXml);
      expect(dat.header.flavor, DatFlavor.noIntro);
      final g = dat.games.single;
      expect(g.roms.single.format, RomFormat.cartridge);
      expect(g.metadata.regions, ['USA']);
    });

    test('MAME-Redump CHD via <disk>', () async {
      final dat = await _parse(_mameXml);
      expect(dat.header.flavor, DatFlavor.mameRedump);
      final g = dat.games.single;
      expect(g.roms, isEmpty);
      expect(g.chdRoms.single.format, RomFormat.chd);
      expect(g.chdRoms.single.sha1, '306b65cb7fa6fb4f15d1b093d01f9d3f92e4a153');
    });

    test('Redump disc tracks', () async {
      final dat = await _parse(_redumpXml);
      expect(dat.header.flavor, DatFlavor.redump);
      expect(dat.games.single.roms.length, 2);
      expect(dat.games.single.roms.first.format, RomFormat.raw);
    });
  });

  group('hasher + auditor', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('minerva_test_');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('streams digests for a file ("hello")', () async {
      final f = File('${tmp.path}/hello.min')..writeAsStringSync('hello');
      final h = await const StreamingHasher().hashFile(f);
      expect(h.size, 5);
      expect(h.crc32, '3610a686');
      expect(h.md5, '5d41402abc4b2a76b9719d911017c592');
      expect(h.sha1, 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d');
    });

    test('classifies present vs missing by hash', () async {
      File('${tmp.path}/Have (World).min').writeAsStringSync('hello');
      final dat = DatFile(
        header: const DatHeader(name: 'T', flavor: DatFlavor.noIntro),
        games: const [
          DatGame(
            name: 'Have (World)',
            roms: [
              RomEntry(
                name: 'Have (World).min',
                size: 5,
                format: RomFormat.cartridge,
                sha1: 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d',
              ),
            ],
            metadata: GameMetadata(),
          ),
          DatGame(
            name: 'Missing (World)',
            roms: [
              RomEntry(
                name: 'Missing (World).min',
                size: 9,
                format: RomFormat.cartridge,
                sha1: '0000000000000000000000000000000000000000',
              ),
            ],
            metadata: GameMetadata(),
          ),
        ],
      );

      final report = await const RomAuditor().audit(dat: dat, romRoot: tmp);
      expect(report.present.length, 1);
      expect(report.present.single.game.name, 'Have (World)');
      expect(report.missing.length, 1);
      expect(report.missing.single.game.name, 'Missing (World)');
    });

    // No-Intro writes unknown digests as sha1="" instead of omitting them.
    // Keeping '' made the entry look hashed: it indexed under an empty key no
    // real digest could match, and suppressed the CRC fallback it needed — so
    // a correct file was reported unknown and pruned into .trash.
    test('blank hash attributes are parsed as absent, not as ""', () async {
      final datFile = File('${tmp.path}/blank.dat')..writeAsStringSync('''
<?xml version="1.0"?>
<datafile>
  <header><name>Blank - Hashes</name><url>https://www.no-intro.org</url></header>
  <game name="CrcOnly (Europe)">
    <rom name="CrcOnly (Europe).ipf" size="5" crc="3610a686" md5="" sha1=""/>
  </game>
</datafile>
''');
      final dat = (await const DatLoader().loadPath(datFile.path)).single;
      final rom = dat.games.single.roms.single;
      expect(rom.sha1, isNull);
      expect(rom.md5, isNull);
      expect(rom.crc32, '3610a686');

      File('${tmp.path}/CrcOnly (Europe).ipf').writeAsStringSync('hello');
      final report = await const RomAuditor().audit(dat: dat, romRoot: tmp);
      expect(report.present.length, 1, reason: 'CRC-only entry must match');
      expect(report.unknownFiles, isEmpty, reason: 'must not be pruned');
    });

    test('audit ignores the .trash quarantine', () async {
      final trash = Directory('${tmp.path}/$trashFolderName')
        ..createSync(recursive: true);
      File('${trash.path}/Have (World).min').writeAsStringSync('hello');
      final dat = DatFile(
        header: const DatHeader(name: 'T', flavor: DatFlavor.noIntro),
        games: const [
          DatGame(
            name: 'Have (World)',
            roms: [
              RomEntry(
                name: 'Have (World).min',
                size: 5,
                format: RomFormat.cartridge,
                sha1: 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d',
              ),
            ],
            metadata: GameMetadata(),
          ),
        ],
      );
      final report = await const RomAuditor().audit(dat: dat, romRoot: tmp);
      expect(report.present, isEmpty, reason: 'a trashed copy is not owned');
      expect(report.missing.length, 1);
      expect(report.unknownFiles, isEmpty);
    });
  });
}
