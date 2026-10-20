import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

/// Builds a minimal, valid CHD v5 header (the only bytes [ChdHeader] reads),
/// stamped with the given raw+meta and raw-only SHA-1 identities.
Uint8List _fakeChdV5Header({required String sha1, required String rawSha1}) {
  final header = Uint8List(124);
  header.setRange(0, 8, ascii.encode('MComprHD'));
  ByteData.view(header.buffer).setUint32(8, 124);
  ByteData.view(header.buffer).setUint32(12, 5);
  void putHex(int offset, String hex) {
    for (var i = 0; i < 20; i++) {
      header[offset + i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
  }

  putHex(64, rawSha1);
  putHex(84, sha1);
  return header;
}

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

    group('a dump RetroAchievements validates instead of the DAT one', () {
      const helloSha1 = 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d';
      const worldSha1 = '7c211433f02071597741e6ff5a8ea34789abbf43';

      DatGame title(String name, String sha1, {Set<String> raDumps = const {}}) =>
          DatGame(
            name: name,
            roms: [
              RomEntry(
                name: '$name.min',
                size: 5,
                format: RomFormat.cartridge,
                sha1: sha1,
              ),
            ],
            metadata: const GameMetadata(),
            retroAchievements: raDumps.isEmpty ? RaMatch.none : RaMatch.byName,
            raDumps: raDumps,
          );

      DatFile datOf(List<DatGame> games) => DatFile(
        header: const DatHeader(name: 'T', flavor: DatFlavor.noIntro),
        games: games,
      );

      test('settles a missing game and is not pruned', () async {
        File('${tmp.path}/Rehashed (Japan).min').writeAsStringSync('hello');
        final report = await const RomAuditor().audit(
          dat: datOf([title('Rehashed (Japan)', 'dead', raDumps: {helloSha1})]),
          romRoot: tmp,
        );
        expect(report.present.single.game.name, 'Rehashed (Japan)');
        expect(report.unknownFiles, isEmpty);
      });

      test('is just a stray when RA does not name it for the game', () async {
        File('${tmp.path}/Elsewhere.min').writeAsStringSync('hello');
        final report = await const RomAuditor().audit(
          dat: datOf([title('Rehashed (Japan)', 'dead')]),
          romRoot: tmp,
        );
        expect(report.missing.single.game.name, 'Rehashed (Japan)');
        expect(report.unknownFiles, hasLength(1));
      });

      test('never takes the place of a sibling already on disk', () async {
        File('${tmp.path}/Held (Japan).min').writeAsStringSync('hello');
        File('${tmp.path}/Lacking (Japan).min').writeAsStringSync('world');
        final report = await const RomAuditor().audit(
          dat: datOf([
            title('Held (Japan)', helloSha1, raDumps: {worldSha1}),
            title('Lacking (Japan)', 'dead', raDumps: {worldSha1}),
          ]),
          romRoot: tmp,
        );
        final at = {
          for (final a in report.present) a.game.name: a.location!.path,
        };
        expect(at['Held (Japan)'], endsWith('Held (Japan).min'));
        expect(at['Lacking (Japan)'], endsWith('Lacking (Japan).min'));
        expect(report.unknownFiles, isEmpty);
      });
    });

    // Real chdman builds compress the same source disc into different bytes
    // depending on version/codec/hunk size, so hashing a .chd's own bytes (as
    // every other format is hashed) only recognizes one specific build's
    // output. The header's embedded hashes don't change with compression —
    // see ChdHeader.
    group('CHD header identity', () {
      test('ChdHeader.read parses the embedded v5 hashes', () async {
        final f = File('${tmp.path}/probe.chd')..writeAsBytesSync(
          _fakeChdV5Header(
            sha1: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            rawSha1: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        );
        final header = await ChdHeader.read(f);
        expect(header, isNotNull);
        expect(header!.version, 5);
        expect(header.sha1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
        expect(header.rawSha1, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      });

      test('matches a MAME-Redump chdRoms entry by the CHD identity hash, '
          'even though the file bytes match nothing', () async {
        File('${tmp.path}/Some Game (Japan).chd').writeAsBytesSync(
          _fakeChdV5Header(
            sha1: '306b65cb7fa6fb4f15d1b093d01f9d3f92e4a153',
            rawSha1: '0000000000000000000000000000000000000000'.substring(0, 40),
          ),
        );
        final dat = DatFile(
          header: const DatHeader(name: 'T', flavor: DatFlavor.mameRedump),
          games: const [
            DatGame(
              name: 'Some Game (Japan)',
              roms: [],
              chdRoms: [
                RomEntry(
                  name: 'Some Game (Japan).chd',
                  size: 0,
                  format: RomFormat.chd,
                  sha1: '306b65cb7fa6fb4f15d1b093d01f9d3f92e4a153',
                ),
              ],
              metadata: GameMetadata(),
            ),
          ],
        );

        final report = await const RomAuditor().audit(dat: dat, romRoot: tmp);
        expect(report.present.length, 1);
        expect(report.present.single.foundFormat, RomFormat.chd);
      });

      test('completes a raw Redump entry via the CHD raw-payload hash, and '
          'the extension mismatch this implies is not flagged wrongName', () async {
        File('${tmp.path}/Ape Escape (Europe).chd').writeAsBytesSync(
          _fakeChdV5Header(
            sha1: '0000000000000000000000000000000000000000'.substring(0, 40),
            rawSha1: 'de4aac9bce0481c92fe3e46fece27740f6f02247',
          ),
        );
        final dat = DatFile(
          header: const DatHeader(name: 'T', flavor: DatFlavor.redump),
          games: const [
            DatGame(
              name: 'Ape Escape (Europe)',
              roms: [
                RomEntry(
                  name: 'Ape Escape (Europe).iso',
                  size: 801603584,
                  format: RomFormat.raw,
                  sha1: 'de4aac9bce0481c92fe3e46fece27740f6f02247',
                ),
              ],
              metadata: GameMetadata(),
            ),
          ],
        );

        final report = await const RomAuditor().audit(dat: dat, romRoot: tmp);
        expect(report.present.length, 1, reason: 'the .chd must be recognized');
        expect(report.present.single.foundFormat, RomFormat.chd);
        expect(
          report.results.every((r) => r.status != RomStatus.wrongName),
          isTrue,
        );
      });

      test('matchChd: false disables the raw-payload match too', () async {
        File('${tmp.path}/Ape Escape (Europe).chd').writeAsBytesSync(
          _fakeChdV5Header(
            sha1: '0000000000000000000000000000000000000000'.substring(0, 40),
            rawSha1: 'de4aac9bce0481c92fe3e46fece27740f6f02247',
          ),
        );
        final dat = DatFile(
          header: const DatHeader(name: 'T', flavor: DatFlavor.redump),
          games: const [
            DatGame(
              name: 'Ape Escape (Europe)',
              roms: [
                RomEntry(
                  name: 'Ape Escape (Europe).iso',
                  size: 801603584,
                  format: RomFormat.raw,
                  sha1: 'de4aac9bce0481c92fe3e46fece27740f6f02247',
                ),
              ],
              metadata: GameMetadata(),
            ),
          ],
        );

        final report = await const RomAuditor().audit(
          dat: dat,
          romRoot: tmp,
          matchChd: false,
        );
        expect(report.missing.length, 1);
        expect(report.present, isEmpty);
      });
    });
  });
}
