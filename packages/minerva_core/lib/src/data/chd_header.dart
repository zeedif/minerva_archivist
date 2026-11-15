/// Reads the identity hashes embedded in a CHD header, without touching any
/// compressed hunk data.
library;

import 'dart:io';
import 'dart:typed_data';

/// The hashes a CHD ("Compressed Hunks of Data") container carries in its own
/// header — set once by the tool that created it, independent of whichever
/// codec, hunk size, or chdman version later shaped the compressed bytes that
/// follow.
///
/// Hashing the file's own bytes (what the default `Hasher` does for every
/// other format) only recognizes a byte-identical copy of one specific
/// chdman build's output; two people compressing the same disc with
/// different chdman versions or codecs get different files. Reading this
/// embedded hash instead recognizes any CHD holding the same source disc,
/// however it was compressed.
///
/// Layout reference: MAME `src/lib/util/chd.h`, mirrored in libchdr's
/// `include/libchdr/chd.h`.
final class ChdHeader {
  const ChdHeader({required this.version, this.sha1, this.rawSha1, this.md5});

  final int version;

  /// The identity MAME and MAME-Redump DATs publish as `<disk sha1>`: the raw
  /// payload's own hash for v3, the combined raw+metadata hash for v4/v5.
  /// `null` for v1/v2, which predate SHA-1 support in the format.
  final String? sha1;

  /// SHA-1 of the raw (uncompressed) payload alone — v4/v5 only (v3's single
  /// [sha1] field already carries this value, so it is mirrored there too).
  ///
  /// For a disc chdman stores as a flat byte stream — PSP, GameCube, Wii,
  /// Xbox — this equals the original dump's own SHA-1 one-for-one, so it can
  /// be checked directly against a raw Redump DAT even when no MAME-Redump
  /// entry exists for the same disc. It will *not* match a CD-based Redump
  /// dump (PS1, PS2, Saturn, Dreamcast...): chdman resectors CD tracks before
  /// hashing them, so only the combined [sha1] — matched against a
  /// MAME-Redump DAT — identifies those.
  final String? rawSha1;

  /// MD5 of the raw payload — v1-v3 only.
  final String? md5;

  static const _magic = [0x4d, 0x43, 0x6f, 0x6d, 0x70, 0x72, 0x48, 0x44]; // 'MComprHD'
  static const _headerLengthByVersion = {1: 76, 2: 80, 3: 120, 4: 108, 5: 124};

  /// Parses [file]'s header, or `null` if it isn't a CHD this understands
  /// (bad magic, unsupported version, or a truncated read).
  static Future<ChdHeader?> read(File file) async {
    final raf = await file.open();
    try {
      final probe = await raf.read(16);
      if (probe.length < 16) return null;
      for (var i = 0; i < _magic.length; i++) {
        if (probe[i] != _magic[i]) return null;
      }

      final version = _u32(probe, 12);
      final length = _headerLengthByVersion[version];
      if (length == null) return null;

      await raf.setPosition(0);
      final header = await raf.read(length);
      if (header.length < length) return null;
      return _parse(version, header);
    } finally {
      await raf.close();
    }
  }

  static ChdHeader _parse(int version, Uint8List h) => switch (version) {
    1 || 2 => ChdHeader(version: version, md5: _hex(h, 44, 16)),
    3 => ChdHeader(
      version: version,
      sha1: _hex(h, 80, 20),
      rawSha1: _hex(h, 80, 20),
      md5: _hex(h, 44, 16),
    ),
    4 => ChdHeader(version: version, sha1: _hex(h, 48, 20), rawSha1: _hex(h, 88, 20)),
    _ => ChdHeader(version: version, sha1: _hex(h, 84, 20), rawSha1: _hex(h, 64, 20)),
  };

  static int _u32(Uint8List b, int offset) =>
      (b[offset] << 24) | (b[offset + 1] << 16) | (b[offset + 2] << 8) | b[offset + 3];

  static String _hex(Uint8List b, int offset, int length) {
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(b[offset + i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
