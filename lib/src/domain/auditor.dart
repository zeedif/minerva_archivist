/// Disk audit: compares a DAT against files on disk and classifies each game.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/file_scanner.dart';
import '../models/dat.dart';

/// Quarantine folder under the ROM root: written by `TrashPruner`, skipped by
/// [RomAuditor.audit].
const trashFolderName = '.trash';

enum RomStatus {
  /// Found on disk with matching hashes.
  present,

  /// Expected by the DAT, absent on disk.
  missing,

  /// Present but hashes don't match (bad/incomplete dump).
  badDump,

  /// Correct bytes, wrong filename.
  wrongName,

  /// Missing, but listed as Missing-In-Action upstream (informational).
  mia,

  /// A file on disk that no DAT entry claims.
  unknown,
}

final class AuditedRom {
  const AuditedRom({
    required this.game,
    required this.status,
    this.location,
    this.foundFormat,
  });

  final DatGame game;
  final RomStatus status;
  final File? location;

  /// The format actually found — e.g. a `.chd` matched for a raw Redump entry.
  final RomFormat? foundFormat;
}

final class AuditReport {
  const AuditReport({
    required this.dat,
    required this.results,
    this.unknownFiles = const [],
  });

  final DatFile dat;
  final List<AuditedRom> results;
  final List<File> unknownFiles;

  Iterable<AuditedRom> get present =>
      results.where((r) => r.status == RomStatus.present);
  Iterable<AuditedRom> get missing =>
      results.where((r) => r.status == RomStatus.missing);
  Iterable<AuditedRom> get badDumps =>
      results.where((r) => r.status == RomStatus.badDump);
}

typedef _RomRef = ({DatGame game, RomEntry rom});
typedef _Match = ({File file, String foundName, RomFormat foundFormat});

/// Hash-index auditor: builds SHA-1/MD5/CRC indices from the DAT, hashes each
/// file on disk (loose or inside a `.zip`), and classifies every game.
final class RomAuditor {
  const RomAuditor({
    this.hasher = const StreamingHasher(),
    this.scanner = const DirectoryFileScanner(),
  });

  final Hasher hasher;
  final FileScanner scanner;

  static const _discExtensions = {
    '.cue', '.bin', '.iso', '.gdi', '.img', '.toc', '.ccd', '.sub', '.mds',
    '.mdf', '.raw', '.chd',
  };
  static const _ignoreExtensions = {
    '.txt', '.xml', '.dat', '.m3u', '.jpg', '.jpeg', '.png', '.nfo', '.sfv',
    '.md', '.json', '.db', '.ini', '.log',
  };

  Future<AuditReport> audit({
    required DatFile dat,
    required Directory romRoot,

    /// Accept a local `.chd` for a raw Redump entry via unified hashes.
    bool matchChd = true,

    /// When false, do a fast name/size-only pass (no hashing).
    bool computeHashes = true,
  }) async {
    final indexRoms = <_RomRef>[
      for (final g in dat.games) ...[
        for (final r in g.roms) (game: g, rom: r),
        if (matchChd)
          for (final r in g.chdRoms) (game: g, rom: r),
      ],
    ];

    // SHA-1 is universal across No-Intro/Redump/MAME-Redump; only fall back to
    // CRC/MD5 for entries that lack it.
    final needCrc = indexRoms.any((e) => e.rom.sha1 == null && e.rom.crc32 != null);
    final needMd5 = indexRoms.any((e) => e.rom.sha1 == null && e.rom.md5 != null);

    String keyOf(DatGame g, RomEntry r) =>
        r.sha1 ?? r.md5 ?? r.crc32 ?? '${g.name}::${r.name}';

    final bySha1 = <String, String>{};
    final byMd5 = <String, String>{};
    final byCrc = <String, String>{};
    for (final ref in indexRoms) {
      final key = keyOf(ref.game, ref.rom);
      if (ref.rom.sha1 != null) bySha1[ref.rom.sha1!] = key;
      if (ref.rom.md5 != null) byMd5[ref.rom.md5!] = key;
      if (ref.rom.crc32 != null) byCrc[ref.rom.crc32!] = key;
    }

    final matches = <String, _Match>{};
    final unknown = <File>[];

    bool tryMatch(File file, FileHashes h, String foundName, RomFormat fmt) {
      var key = h.sha1 != null ? bySha1[h.sha1!] : null;
      key ??= h.md5 != null ? byMd5[h.md5!] : null;
      key ??= h.crc32 != null ? byCrc[h.crc32!] : null;
      if (key == null) return false;
      matches.putIfAbsent(key, () => (file: file, foundName: foundName, foundFormat: fmt));
      return true;
    }

    if (computeHashes) {
      await for (final sf in scanner.scan(romRoot)) {
        // Quarantined files are not part of the collection: counting them would
        // report a pruned game as present and stop it being re-downloaded.
        if (p.split(sf.relativePath).first == trashFolderName) continue;
        final ext = p.extension(sf.file.path).toLowerCase();
        if (ext == '.zip') {
          final entries = await hasher.hashArchive(
            sf.file,
            crc32: needCrc,
            md5: needMd5,
            sha1: true,
          );
          var any = false;
          for (final e in entries.entries) {
            if (tryMatch(sf.file, e.value, p.basename(e.key), _formatFor(e.key))) {
              any = true;
            }
          }
          if (!any) unknown.add(sf.file);
        } else if (!_ignoreExtensions.contains(ext)) {
          final h = await hasher.hashFile(
            sf.file,
            crc32: needCrc,
            md5: needMd5,
            sha1: true,
          );
          if (!tryMatch(sf.file, h, p.basename(sf.file.path), _formatFor(sf.file.path))) {
            unknown.add(sf.file);
          }
        }
      }
    }

    final results = <AuditedRom>[];
    for (final g in dat.games) {
      final rawKeys = [for (final r in g.roms) keyOf(g, r)];
      final chdKeys = [for (final r in g.chdRoms) keyOf(g, r)];
      final rawPresent = rawKeys.isNotEmpty && rawKeys.every(matches.containsKey);
      final chdPresent =
          matchChd && chdKeys.isNotEmpty && chdKeys.every(matches.containsKey);

      RomStatus status;
      File? location;
      RomFormat? foundFormat;

      if (rawPresent) {
        final m = matches[rawKeys.first]!;
        location = m.file;
        foundFormat = m.foundFormat;
        final wrongName = g.roms.any((r) {
          final mm = matches[keyOf(g, r)];
          return mm != null && mm.foundName != r.name;
        });
        status = wrongName ? RomStatus.wrongName : RomStatus.present;
      } else if (chdPresent) {
        location = matches[chdKeys.first]!.file;
        foundFormat = RomFormat.chd;
        status = RomStatus.present;
      } else {
        status = RomStatus.missing;
      }

      results.add(
        AuditedRom(
          game: g,
          status: status,
          location: location,
          foundFormat: foundFormat,
        ),
      );
    }

    return AuditReport(dat: dat, results: results, unknownFiles: unknown);
  }

  RomFormat _formatFor(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.chd') return RomFormat.chd;
    if (_discExtensions.contains(ext)) return RomFormat.raw;
    return RomFormat.cartridge;
  }
}
