/// A content-based reading of the ROM root: which top-level entries hold DAT
/// dumps, and which of them the user has curated with content of their own.
///
/// A folder holding a dump next to patches, manuals or scans is a unit, not a
/// stray to be flattened into the root. Recognizing which game lives there and
/// leaving the files alone is the only safe move, and every stage downstream
/// depends on this classification to make it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/dat.dart';

/// A file on disk that a DAT entry claims, by hash.
final class LocatedRom {
  const LocatedRom({required this.game, required this.rom, required this.file});

  final DatGame game;
  final RomEntry rom;
  final File file;

  /// Whether the file already carries the name the DAT gives it.
  bool get hasCanonicalName => p.basename(file.path) == rom.name;
}

/// One top-level entry of the ROM root, read by what it contains.
final class LibraryEntry {
  const LibraryEntry({
    required this.name,
    required this.isDirectory,
    this.roms = const [],
    this.extras = const [],
  });

  /// The top-level file or folder name, relative to the ROM root.
  final String name;

  final bool isDirectory;

  /// Files here that a DAT entry claims.
  final List<LocatedRom> roms;

  /// Files here that no DAT entry claims and that aren't incidental — patches,
  /// translations, manuals, readmes, cover scans. Their presence is the whole
  /// signal: someone put them here on purpose.
  final List<File> extras;

  /// A folder is curated when it holds content of the user's own alongside the
  /// dumps. A loose file never is: there is nothing to curate.
  bool get isCurated => isDirectory && extras.isNotEmpty;

  /// Every game with at least one ROM here.
  Set<String> get games => {for (final r in roms) r.game.name};

  /// Games every one of whose ROMs is here — the ones this entry holds outright.
  Set<String> get completeGames {
    final found = <String, ({DatGame game, Set<String> romNames})>{};
    for (final r in roms) {
      found
          .putIfAbsent(r.game.name, () => (game: r.game, romNames: <String>{}))
          .romNames
          .add(r.rom.name);
    }
    return {
      for (final e in found.entries)
        if (_isComplete(e.value.game, e.value.romNames)) e.key,
    };
  }

  /// Games with some but not all of their ROMs here — a multi-track disc that
  /// still needs finishing.
  Set<String> get partialGames => games.difference(completeGames);

  static bool _isComplete(DatGame game, Set<String> foundRomNames) {
    // Either hash set will do: a `.chd` stands in for the raw tracks.
    bool covers(List<RomEntry> expected) =>
        expected.isNotEmpty &&
        expected.every((r) => foundRomNames.contains(r.name));
    return covers(game.roms) || covers(game.chdRoms);
  }
}

/// The ROM root, classified.
final class LibraryIndex {
  LibraryIndex({this.entries = const []})
    : curatedFolders = {
        for (final e in entries)
          if (e.isCurated) e.name,
      };

  /// Nothing scanned, so nothing is curated.
  const LibraryIndex.empty() : entries = const [], curatedFolders = const {};

  final List<LibraryEntry> entries;

  /// Top-level folder names nothing may move, rename or prune. Held rather than
  /// derived on demand: [isCuratedPath] is asked once per scanned file.
  final Set<String> curatedFolders;

  Iterable<LibraryEntry> get curated => entries.where((e) => e.isCurated);

  /// Games held outright inside a curated folder. These are settled: the dump is
  /// there, the user has built on it, and no other dump of the same game should
  /// be fetched to sit beside it.
  Set<String> get curatedGames => {
    for (final e in curated) ...e.completeGames,
  };

  /// Games held outright anywhere in the root, curated or not.
  Set<String> get completeGames => {
    for (final e in entries) ...e.completeGames,
  };

  /// The entry holding [gameName], or null when nothing does.
  LibraryEntry? entryFor(String gameName) {
    for (final e in entries) {
      if (e.games.contains(gameName)) return e;
    }
    return null;
  }

  /// Whether [relativePath] sits under a curated folder.
  bool isCuratedPath(String relativePath) {
    final segments = p.split(relativePath);
    return segments.isNotEmpty && curatedFolders.contains(segments.first);
  }

  String get summary {
    final folders = entries.where((e) => e.isDirectory).length;
    return '${curatedFolders.length} curated of $folders folder(s), '
        '${curatedGames.length} game(s) settled there';
  }
}

/// Builds a [LibraryIndex] from files as they are hashed, so classification
/// costs no extra pass over the disk.
///
/// The auditor drives this: one [add] per file it scans, then [build].
final class LibraryIndexBuilder {
  final _roms = <String, List<LocatedRom>>{};
  final _extras = <String, List<File>>{};
  final _directories = <String>{};
  final _seen = <String>{};

  /// Files whose presence says nothing about whether a folder is curated:
  /// playlists this tool writes itself, emulator saves and states, and DAT
  /// sidecars. Anything else unclaimed counts as the user's own content, which is
  /// the conservative reading — being wrong here only means leaving a folder
  /// alone.
  static const _incidentalExtensions = {
    '.m3u', '.srm', '.sav', '.cht', '.rtc', '.mcr', '.rdb', '.dat', '.xml',
    '.sfv',
  };

  static final _saveState = RegExp(r'^\.state\d*$', caseSensitive: false);

  static bool _isIncidental(String path) {
    if (p.basename(path).startsWith('.')) return true;
    final ext = p.extension(path).toLowerCase();
    return _incidentalExtensions.contains(ext) || _saveState.hasMatch(ext);
  }

  /// Records one scanned file. [match] is the DAT entry claiming it, or null.
  void add(File file, String relativePath, LocatedRom? match) {
    final segments = p.split(relativePath);
    final top = segments.isEmpty ? p.basename(file.path) : segments.first;
    if (segments.length > 1) _directories.add(top);
    _seen.add(top);

    if (match != null) {
      _roms.putIfAbsent(top, () => []).add(match);
    } else if (!_isIncidental(file.path)) {
      _extras.putIfAbsent(top, () => []).add(file);
    }
  }

  LibraryIndex build() => LibraryIndex(
    entries: [
      for (final name in _seen)
        LibraryEntry(
          name: name,
          isDirectory: _directories.contains(name),
          roms: _roms[name] ?? const [],
          extras: _extras[name] ?? const [],
        ),
    ],
  );
}
