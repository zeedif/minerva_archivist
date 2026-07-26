import 'package:minerva_archivist/minerva_archivist.dart';
import 'package:test/test.dart';

void main() {
  const r = SystemNameResolver();

  group('baseSystem strips DAT-tooling suffixes, keeps platform qualifiers', () {
    test('Parent-Clone + Retool', () {
      expect(
        r.baseSystem('Atari - 8-bit Family (Parent-Clone) (Retool)'),
        'Atari - 8-bit Family',
      );
    });

    test('single Parent-Clone', () {
      expect(r.baseSystem('Sega - Game Gear (Parent-Clone)'), 'Sega - Game Gear');
    });

    test('keeps a real variant qualifier', () {
      expect(
        r.baseSystem('Nintendo - Nintendo DS (Decrypted) (Parent-Clone)'),
        'Nintendo - Nintendo DS (Decrypted)',
      );
    });

    test('keeps a multi-qualifier platform', () {
      expect(
        r.baseSystem('IBM - PC and Compatibles (Digital) (Misc) (Parent-Clone)'),
        'IBM - PC and Compatibles (Digital) (Misc)',
      );
    });

    test('strips bracket tags', () {
      expect(r.baseSystem('Foo [noIntro]'), 'Foo');
    });

    test('strips a trailing date stamp', () {
      expect(r.baseSystem('Bar (Parent-Clone) (20260222-023943)'), 'Bar');
    });
  });

  group('assetFile', () {
    test('flavor suffix for clonelists, base name for RA', () {
      const name = 'Atari - 8-bit Family (Parent-Clone) (Retool)';
      expect(
        r.assetFile(name, DatFlavor.noIntro, MetadataAsset.cloneLists),
        'Atari - 8-bit Family (No-Intro).json',
      );
      expect(
        r.assetFile(name, DatFlavor.noIntro, MetadataAsset.retroAchievements),
        'Atari - 8-bit Family.json',
      );
    });
  });

  group('metadataSystem drops datFileTags that MiNERVA folder names keep', () {
    // A representative slice of `internal-config.json`'s datFileTags.
    final tagged = r.withDatFileTags(const [
      'BIN',
      'J64',
      'LYX',
      'FDS',
      'Decrypted',
      'Deprecated',
      'Headered',
      'BigEndian',
      'Parent-Clone',
    ]);

    test('a dump-format qualifier is stripped for assets, kept for MiNERVA', () {
      const name = 'Atari - Atari 7800 (BIN) (Parent-Clone)';
      expect(tagged.metadataSystem(name), 'Atari - Atari 7800');
      expect(tagged.baseSystem(name), 'Atari - Atari 7800 (BIN)');
      expect(
        tagged.assetFile(name, DatFlavor.noIntro, MetadataAsset.cloneLists),
        'Atari - Atari 7800 (No-Intro).json',
      );
    });

    test('strips tags from the middle, keeping untagged qualifiers', () {
      // `Digital` is not a datFileTag, so the 3DS Digital clonelist still wins.
      expect(
        tagged.metadataSystem(
          'Nintendo - Nintendo 3DS (Digital) (Deprecated) (Parent-Clone)',
        ),
        'Nintendo - Nintendo 3DS (Digital)',
      );
    });

    test('is case-sensitive, as Retool\'s tag list distinguishes casings', () {
      expect(
        tagged.metadataSystem('Foo - Bar (bin)'),
        'Foo - Bar (bin)',
      );
    });

    test('without tags loaded it is a no-op over baseSystem', () {
      const name = 'Atari - Atari 7800 (BIN) (Parent-Clone)';
      expect(r.metadataSystem(name), r.baseSystem(name));
    });
  });
}
