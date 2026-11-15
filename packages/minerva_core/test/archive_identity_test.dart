import 'dart:io';

import 'package:archive/archive.dart';
import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  final content = List<int>.generate(4096, (i) => i % 251);
  final crc = (Crc32()..add(content)).hex;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('minerva_identity_');
    final zip = Archive()
      ..addFile(ArchiveFile('Game.gb', content.length, content));
    await File(
      p.join(root.path, 'Game.zip'),
    ).writeAsBytes(ZipEncoder().encode(zip));
  });

  tearDown(() => root.delete(recursive: true));

  DatFile datWith({required int size}) => DatFile(
    header: const DatHeader(name: 'Test', flavor: DatFlavor.noIntro),
    games: [
      DatGame(
        name: 'Game',
        metadata: const GameMetadata(),
        roms: [
          RomEntry(
            name: 'Game.gb',
            size: size,
            format: RomFormat.cartridge,
            crc32: crc,
          ),
        ],
      ),
    ],
  );

  test('a zip entry is identified by its listed CRC-32 and size', () async {
    final entries = await const StreamingHasher().hashArchive(
      File(p.join(root.path, 'Game.zip')),
    );
    expect(entries['Game.gb']?.crc32, crc);
    expect(entries['Game.gb']?.size, content.length);
    expect(entries['Game.gb']?.sha1, isNull);

    final report = await const RomAuditor().audit(
      dat: datWith(size: content.length),
      romRoot: root,
    );
    expect(report.present, hasLength(1));
  });

  test('a matching CRC-32 with another size is not the same ROM', () async {
    final report = await const RomAuditor().audit(
      dat: datWith(size: content.length + 1),
      romRoot: root,
    );
    expect(report.present, isEmpty);
    expect(report.unknownFiles, hasLength(1));
  });
}
