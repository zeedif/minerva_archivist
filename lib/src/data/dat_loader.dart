/// DAT ingestion: XML parsing, flavor detection, and disk loading.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../models/dat.dart';

/// Parses Logiqx/No-Intro/Redump/MAME-style DAT XML.
///
/// Handles both `<game><rom>` (No-Intro/Redump) and `<machine><disk>`
/// (MAME-Redump CHD) shapes. `<disk>` entries and `.chd` roms are routed to
/// [DatGame.chdRoms]; everything else to [DatGame.roms].
final class LogiqxDatParser {
  const LogiqxDatParser();

  static const _discExtensions = {
    '.cue', '.bin', '.iso', '.gdi', '.img', '.toc', '.ccd', '.sub', '.mds',
    '.mdf', '.raw',
  };

  Future<DatFile> parse(String xml) async {
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;
    final headerEl = root.getElement('header');

    final header = DatHeader(
      name: headerEl?.getElement('name')?.innerText.trim() ?? '',
      flavor: DatFlavor.unknown,
      description: headerEl?.getElement('description')?.innerText.trim(),
      version: headerEl?.getElement('version')?.innerText.trim(),
      homepage: headerEl?.getElement('homepage')?.innerText.trim(),
      url: headerEl?.getElement('url')?.innerText.trim(),
      author: headerEl?.getElement('author')?.innerText.trim(),
    );

    final containers = root.findElements('game').isEmpty
        ? root.findElements('machine')
        : root.findElements('game');

    final games = <DatGame>[];
    for (final el in containers) {
      final name = el.getAttribute('name');
      if (name == null) continue;

      final roms = <RomEntry>[];
      final chdRoms = <RomEntry>[];
      for (final romEl in el.findElements('rom')) {
        final entry = _romFrom(romEl);
        if (entry == null) continue;
        (entry.format == RomFormat.chd ? chdRoms : roms).add(entry);
      }
      for (final diskEl in el.findElements('disk')) {
        final entry = _diskFrom(diskEl);
        if (entry != null) chdRoms.add(entry);
      }

      final regions = <String>[];
      for (final rel in el.findElements('release')) {
        final r = rel.getAttribute('region');
        if (r != null && !regions.contains(r)) regions.add(r);
      }

      games.add(
        DatGame(
          name: name,
          roms: roms,
          chdRoms: chdRoms,
          category: el.getElement('category')?.innerText.trim(),
          cloneGroupId: el.getAttribute('cloneof'),
          metadata: _metadataFrom(name, regions),
        ),
      );
    }

    return DatFile(header: header, games: games);
  }

  /// A hash attribute, or `null` when absent or blank.
  ///
  /// No-Intro writes unknown digests as `sha1=""`. Keeping `''` would make the
  /// entry look hashed: it would index under an empty key no real digest can
  /// match, and suppress the CRC fallback it needs.
  String? _hash(XmlElement el, String attribute) {
    final raw = el.getAttribute(attribute)?.trim();
    return (raw == null || raw.isEmpty) ? null : raw.toLowerCase();
  }

  RomEntry? _romFrom(XmlElement el) {
    final name = el.getAttribute('name');
    if (name == null) return null;
    return RomEntry(
      name: name,
      size: int.tryParse(el.getAttribute('size') ?? '') ?? 0,
      format: _formatFor(name),
      crc32: _hash(el, 'crc'),
      md5: _hash(el, 'md5'),
      sha1: _hash(el, 'sha1'),
      sha256: _hash(el, 'sha256'),
    );
  }

  RomEntry? _diskFrom(XmlElement el) {
    final name = el.getAttribute('name');
    if (name == null) return null;
    final fullName = name.toLowerCase().endsWith('.chd') ? name : '$name.chd';
    return RomEntry(
      name: fullName,
      size: int.tryParse(el.getAttribute('size') ?? '') ?? 0,
      format: RomFormat.chd,
      crc32: _hash(el, 'crc'),
      md5: _hash(el, 'md5'),
      sha1: _hash(el, 'sha1'),
    );
  }

  RomFormat _formatFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot).toLowerCase();
    if (ext == '.chd') return RomFormat.chd;
    if (_discExtensions.contains(ext)) return RomFormat.raw;
    return RomFormat.cartridge;
  }

  GameMetadata _metadataFrom(String name, List<String> releaseRegions) {
    final tags = <String>{};
    for (final m in RegExp(r'\(([^)]*)\)').allMatches(name)) {
      final t = m.group(1);
      if (t != null) tags.add(t.trim());
    }

    var status = ProductionStatus.released;
    for (final t in tags) {
      final lt = t.toLowerCase();
      if (lt.contains('proto')) {
        status = ProductionStatus.prototype;
      } else if (lt.contains('beta')) {
        status = ProductionStatus.beta;
      } else if (lt.contains('alpha')) {
        status = ProductionStatus.alpha;
      } else if (lt.contains('demo')) {
        status = ProductionStatus.demo;
      } else if (lt.contains('sample')) {
        status = ProductionStatus.sample;
      } else if (lt == 'pirate') {
        status = ProductionStatus.pirate;
      } else if (lt == 'unl' || lt.contains('unlicensed') || lt.contains('aftermarket')) {
        status = ProductionStatus.unlicensed;
      }
    }

    var languages = const <String>[];
    for (final t in tags) {
      final parts = t.split(',').map((e) => e.trim()).toList();
      if (parts.isNotEmpty && parts.every((p) => RegExp(r'^[A-Z][a-z]$').hasMatch(p))) {
        languages = parts;
        break;
      }
    }

    String? version;
    var revision = 0;
    for (final t in tags) {
      final rev = RegExp(r'^Rev\s+([0-9A-Za-z]+)$').firstMatch(t);
      if (rev != null) {
        version = t;
        revision = int.tryParse(rev.group(1)!) ?? revision;
        break;
      }
      final v = RegExp(r'^v([0-9]+(?:\.[0-9]+)*)').firstMatch(t);
      if (v != null) {
        version = t;
        revision = int.tryParse(v.group(1)!.replaceAll('.', '')) ?? revision;
        break;
      }
    }

    return GameMetadata(
      regions: releaseRegions,
      languages: languages,
      version: version,
      revision: revision,
      status: status,
      rawTags: tags,
    );
  }
}

/// Detects DAT flavor from header text plus element shape, so the user only
/// ever supplies DAT paths.
///
/// Order matters: MAME-Redump wins first, since its headers also say "redump".
DatFlavor detectDatFlavor(DatHeader header, Iterable<DatGame> sample) {
  final hay = [
    header.name,
    header.description,
    header.author,
    header.homepage,
    header.url,
  ].whereType<String>().join(' ').toLowerCase();

  final sampled = sample.take(50).toList();
  final hasChd = sampled.any((g) => g.chdRoms.any((r) => r.format == RomFormat.chd));

  if (hasChd || hay.contains('mame redump') || hay.contains('mameredump')) {
    return DatFlavor.mameRedump;
  }
  if (hay.contains('redump')) return DatFlavor.redump;
  if (hay.contains('no-intro') ||
      hay.contains('nointro') ||
      hay.contains('datomatic')) {
    return DatFlavor.noIntro;
  }
  if (hay.contains('retool')) return DatFlavor.retool;

  // Structural fallback when the header is uninformative.
  final hasDiscTracks =
      sampled.any((g) => g.roms.any((r) => r.format == RomFormat.raw));
  if (hasDiscTracks) return DatFlavor.redump;
  if (sampled.isNotEmpty) return DatFlavor.noIntro;
  return DatFlavor.unknown;
}

/// Loads DAT files from disk: decode → parse → finalize flavor.
final class DatLoader {
  const DatLoader();

  Future<DatFile> load(File file) async {
    final bytes = await file.readAsBytes();
    final xml = utf8.decode(bytes, allowMalformed: true);
    final parsed = await const LogiqxDatParser().parse(xml);
    final flavor = detectDatFlavor(parsed.header, parsed.games);
    return DatFile(header: parsed.header.copyWith(flavor: flavor), games: parsed.games);
  }

  /// Load a single `.dat` file, or every `.dat` under a directory.
  Future<List<DatFile>> loadPath(String pathOrDir) async {
    final type = FileSystemEntity.typeSync(pathOrDir);
    final files = <File>[];
    if (type == FileSystemEntityType.directory) {
      await for (final e in Directory(pathOrDir).list(recursive: true)) {
        if (e is File && e.path.toLowerCase().endsWith('.dat')) files.add(e);
      }
      files.sort((a, b) => a.path.compareTo(b.path));
    } else if (type == FileSystemEntityType.file) {
      files.add(File(pathOrDir));
    }

    final result = <DatFile>[];
    for (final f in files) {
      result.add(await load(f));
    }
    return result;
  }
}
