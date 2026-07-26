import 'dart:convert';
import 'dart:typed_data';

import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

void main() {
  // Multi-file torrent: Minerva_Myrient/{game.zip(100), other.zip(200)}.
  final torrent = Uint8List.fromList(
    ascii.encode(
      'd4:infod5:filesl'
      'd6:lengthi100e4:pathl8:game.zipee'
      'd6:lengthi200e4:pathl9:other.zipee'
      'e4:name15:Minerva_Myrientee',
    ),
  );

  test('bencode inspector lists files with 1-based indices + info hash', () async {
    final m = await const BencodeTorrentInspector().read(torrent);
    expect(m.name, 'Minerva_Myrient');
    expect(m.files.length, 2);
    expect(m.files[0].index, 1);
    expect(m.files[0].path, 'Minerva_Myrient/game.zip');
    expect(m.files[0].length, 100);
    expect(m.files[1].path, 'Minerva_Myrient/other.zip');
    expect(m.infoHash.length, 40);
  });

  test('planner selects only wanted files by zip basename', () async {
    final m = await const BencodeTorrentInspector().read(torrent);
    final plan = const DownloadPlanner().plan([
      DatGame(name: 'game', roms: const [], metadata: GameMetadata()),
      DatGame(name: 'missing', roms: const [], metadata: GameMetadata()),
    ], m);
    expect(plan.selectedIndices, [1]);
    expect(plan.totalBytes, 100);
    expect(plan.unmatched, ['missing.zip']);
  });
}
