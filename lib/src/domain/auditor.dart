/// Disk audit: compares a DAT against files on disk and classifies each game.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/file_scanner.dart';
import '../models/dat.dart';
import 'library.dart';

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

  /// Missing, but listed as Missing-In-Action (informational).
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
    this.redundantFiles = const [],
    this.library = const LibraryIndex.empty(),
  });

  final DatFile dat;
  final List<AuditedRom> results;

  /// Files no entry of the audited set claims. A dump of a non-selected variant
  /// counts as unknown — that is how a runner-up gets pruned — so this is not the
  /// same as "absent from the DAT".
  final List<File> unknownFiles;

  /// Second and later copies of a dump held elsewhere in the root. Each is
  /// recognized, so none is an [unknownFiles] stray; what condemns it is that
  /// another file already answers for the same ROM.
  final List<File> redundantFiles;

  /// How the root is laid out and which folders the user has curated, resolved
  /// against the full catalog when one was supplied so a folder holding a
  /// 1G1R runner-up is still understood.
  final LibraryIndex library;

  Iterable<AuditedRom> get present =>
      results.where((r) => r.status == RomStatus.present);
  Iterable<AuditedRom> get missing =>
      results.where((r) => r.status == RomStatus.missing);
  Iterable<AuditedRom> get badDumps =>
      results.where((r) => r.status == RomStatus.badDump);

  /// Files to prune: strays and redundant copies alike, minus anything under a
  /// curated folder, which is never ours to move.
  ///
  /// Curation protects a folder, not the bytes in it, so a loose copy of a
  /// curated dump is still redundant. Only a duplicate that is itself curated
  /// survives — see [duplicatesInCuratedFolders].
  List<File> prunable(Directory romRoot) {
    // Deduplicated: the two lists can condemn one copy for two reasons, and the
    // second move would fail on a file already gone.
    final seen = <String>{};
    return [
      for (final f in [...unknownFiles, ...redundantFiles])
        if (!library.isCuratedPath(p.relative(f.path, from: romRoot.path)) &&
            seen.add(p.canonicalize(f.path)))
          f,
    ];
  }

  /// Redundant copies left untouched because they are themselves curated: the
  /// same dump under two folders, where merging is the user's call.
  List<File> duplicatesInCuratedFolders(Directory romRoot) => [
    for (final f in redundantFiles)
      if (library.isCuratedPath(p.relative(f.path, from: romRoot.path))) f,
  ];
}

typedef _RomRef = ({DatGame game, RomEntry rom});
typedef _Match = ({File file, String foundName, RomFormat foundFormat});

/// One file's claim on one ROM. [relativePath] is carried because choosing among
/// identical copies is a question about where they sit.
typedef _Claim = ({
  File file,
  String relativePath,
  String foundName,
  RomFormat foundFormat,
});

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

    /// The full, unfiltered DAT. Files are recognized against this, so a dump
    /// that lost its 1G1R slot is identified rather than read as junk. Defaults
    /// to [dat], i.e. recognize only the selected set.
    DatFile? catalog,

    /// Accept a local `.chd` for a raw Redump entry via unified hashes.
    bool matchChd = true,

    /// When false, do a fast name/size-only pass (no hashing).
    bool computeHashes = true,
  }) async {
    final recognized = catalog ?? dat;
    final indexRoms = <_RomRef>[
      for (final g in recognized.games) ...[
        for (final r in g.roms) (game: g, rom: r),
        if (matchChd)
          for (final r in g.chdRoms) (game: g, rom: r),
      ],
    ];

    // Keys claimed by the audited set, so a file matching only the wider catalog
    // still counts as unknown and stays prunable.
    final selectedKeys = <String>{
      for (final g in dat.games) ...[
        for (final r in g.roms) _key(g, r),
        for (final r in g.chdRoms) _key(g, r),
      ],
    };

    // SHA-1 is universal across No-Intro/Redump/MAME-Redump; only fall back to
    // CRC/MD5 for entries that lack it.
    final needCrc = indexRoms.any((e) => e.rom.sha1 == null && e.rom.crc32 != null);
    final needMd5 = indexRoms.any((e) => e.rom.sha1 == null && e.rom.md5 != null);

    final bySha1 = <String, _RomRef>{};
    final byMd5 = <String, _RomRef>{};
    final byCrc = <String, _RomRef>{};
    for (final ref in indexRoms) {
      if (ref.rom.sha1 != null) bySha1.putIfAbsent(ref.rom.sha1!, () => ref);
      if (ref.rom.md5 != null) byMd5.putIfAbsent(ref.rom.md5!, () => ref);
      if (ref.rom.crc32 != null) byCrc.putIfAbsent(ref.rom.crc32!, () => ref);
    }

    // Every claimant per ROM, not just the first: a duplicate can be scanned
    // before the copy that earns the slot, so the choice waits for the full scan.
    final claimants = <String, List<_Claim>>{};
    final unknown = <File>[];
    final library = LibraryIndexBuilder();

    _RomRef? lookup(FileHashes h) {
      if (h.sha1 != null) {
        final hit = bySha1[h.sha1!];
        if (hit != null) return hit;
      }
      if (h.md5 != null) {
        final hit = byMd5[h.md5!];
        if (hit != null) return hit;
      }
      return h.crc32 != null ? byCrc[h.crc32!] : null;
    }

    if (computeHashes) {
      await for (final sf in scanner.scan(romRoot)) {
        // Quarantined files are not part of the collection: counting them would
        // report a pruned game as present and stop it being re-downloaded.
        if (p.split(sf.relativePath).first == trashFolderName) continue;
        final ext = p.extension(sf.file.path).toLowerCase();
        if (_ignoreExtensions.contains(ext)) {
          // Not worth hashing, but it still tells us whether a folder is curated.
          library.add(sf.file, sf.relativePath, null);
          continue;
        }

        // A loose file is read as a one-entry archive, so both kinds take the same
        // path: an archive can hold several ROMs and needs all of them claimed.
        final entries = ext == '.zip'
            ? await hasher.hashArchive(
                sf.file,
                crc32: needCrc,
                md5: needMd5,
                sha1: true,
              )
            : {
                sf.file.path: await hasher.hashFile(
                  sf.file,
                  crc32: needCrc,
                  md5: needMd5,
                  sha1: true,
                ),
              };

        // Claimed by the wider catalog is not claimed by the audited set: a file
        // matching only the catalog stays unknown, and so stays prunable.
        var claimedHere = false;
        LocatedRom? located;
        for (final e in entries.entries) {
          final ref = lookup(e.value);
          if (ref == null) continue;
          located ??= LocatedRom(game: ref.game, rom: ref.rom, file: sf.file);
          final key = _key(ref.game, ref.rom);
          claimants
              .putIfAbsent(key, () => [])
              .add((
                file: sf.file,
                relativePath: sf.relativePath,
                foundName: p.basename(e.key),
                foundFormat: _formatFor(e.key),
              ));
          claimedHere |= selectedKeys.contains(key);
        }
        library.add(sf.file, sf.relativePath, located);
        if (!claimedHere) unknown.add(sf.file);
      }
    }

    final libraryIndex = library.build();

    // One keeper per ROM; a file keeping none of the ROMs it claims holds only
    // bytes the collection already has elsewhere. Keeping the test that broad
    // spares an archive still needed for one of its other entries.
    final matches = <String, _Match>{};
    final keepers = <String>{};
    final byPath = <String, File>{};
    for (final entry in claimants.entries) {
      final keeper = _pickKeeper(entry.value, libraryIndex);
      matches[entry.key] = (
        file: keeper.file,
        foundName: keeper.foundName,
        foundFormat: keeper.foundFormat,
      );
      keepers.add(keeper.relativePath);
      for (final c in entry.value) {
        byPath[c.relativePath] = c.file;
      }
    }
    // A losing copy of a dump the audited set already dropped is condemned twice
    // over; the stray reading wins so it is only ever listed once.
    final strays = {for (final f in unknown) p.canonicalize(f.path)};
    final redundant = [
      for (final e in byPath.entries)
        if (!keepers.contains(e.key) &&
            !strays.contains(p.canonicalize(e.value.path)))
          e.value,
    ];

    final results = <AuditedRom>[];
    for (final g in dat.games) {
      final rawKeys = [for (final r in g.roms) _key(g, r)];
      final chdKeys = [for (final r in g.chdRoms) _key(g, r)];
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
          final mm = matches[_key(g, r)];
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

    return AuditReport(
      dat: dat,
      results: results,
      unknownFiles: unknown,
      redundantFiles: redundant,
      library: libraryIndex,
    );
  }

  /// Which of several files holding the same ROM keeps the slot.
  ///
  /// A curated folder wins outright — it is the copy the user built around — then
  /// the file already carrying its DAT name, then the shallowest path. The last
  /// two also make the choice independent of the order the disk was read in.
  static _Claim _pickKeeper(List<_Claim> claims, LibraryIndex library) {
    if (claims.length == 1) return claims.first;
    // Ascending, so 0 is the best claim on each criterion.
    int rank(_Claim c) =>
        (library.isCuratedPath(c.relativePath) ? 0 : 2) +
        (c.foundName == p.basename(c.relativePath) ? 0 : 1);
    return ([...claims]..sort((a, b) {
      final preferred = rank(a).compareTo(rank(b));
      if (preferred != 0) return preferred;
      final depth = p
          .split(a.relativePath)
          .length
          .compareTo(p.split(b.relativePath).length);
      return depth != 0 ? depth : a.relativePath.compareTo(b.relativePath);
    })).first;
  }

  /// Identity of a DAT entry: its strongest digest, so the same bytes described
  /// by two DATs resolve to one key. Falls back to the name for hashless
  /// entries, which can then only match themselves.
  static String _key(DatGame g, RomEntry r) =>
      r.sha1 ?? r.md5 ?? r.crc32 ?? '${g.name}::${r.name}';

  RomFormat _formatFor(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.chd') return RomFormat.chd;
    if (_discExtensions.contains(ext)) return RomFormat.raw;
    return RomFormat.cartridge;
  }
}
