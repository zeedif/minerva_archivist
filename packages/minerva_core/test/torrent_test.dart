import 'dart:convert';
import 'dart:typed_data';

import 'package:minerva_core/minerva_core.dart';
import 'package:test/test.dart';

Uint8List _bytes(String bencode) => Uint8List.fromList(ascii.encode(bencode));

DatGame _game(String name) =>
    DatGame(name: name, roms: const [], metadata: const GameMetadata());

void main() {
  final torrent = _bytes(
    'd8:announce3:udp4:infod5:filesl'
    'd6:lengthi100e4:pathl2:GB8:Game.zipee'
    'd6:lengthi200e4:pathl2:GB9:other.zipee'
    'e4:name15:Minerva_Myrientee',
  );

  group('TorrentManifest.parse', () {
    test('lists files with 0-based indices and full paths', () {
      final manifest = TorrentManifest.parse(torrent);
      expect(manifest.name, 'Minerva_Myrient');
      expect(
        [for (final f in manifest.files) (f.index, f.path, f.length)],
        [
          (0, 'Minerva_Myrient/GB/Game.zip', 100),
          (1, 'Minerva_Myrient/GB/other.zip', 200),
        ],
      );
      expect(manifest.infoHash, hasLength(40));
    });

    test('reads a single-file torrent', () {
      final manifest = TorrentManifest.parse(
        _bytes('d4:infod6:lengthi7e4:name5:a.zipee'),
      );
      expect(manifest.files.single.path, 'a.zip');
      expect(manifest.files.single.length, 7);
    });

    test('rejects data that is not a torrent', () {
      expect(
        () => TorrentManifest.parse(_bytes('<!doctype html>')),
        throwsFormatException,
      );
      expect(
        () => TorrentManifest.parse(_bytes('d4:infod4:name3:ab')),
        throwsFormatException,
      );
      expect(() => TorrentManifest.parse(_bytes('de')), throwsFormatException);
    });
  });

  group('DownloadPlan.match', () {
    test('selects wanted games by zip name, ignoring case', () {
      final plan = DownloadPlan.match([
        _game('game'),
        _game('missing'),
      ], TorrentManifest.parse(torrent));
      expect(plan.files, {0: 'Game.zip'});
      expect(plan.totalBytes, 100);
      expect(plan.unmatched, ['missing']);
    });
  });
}
