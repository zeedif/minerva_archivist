# Contributing

Notes for working on MiNERVA Archivist. User-facing docs live in
[README.md](README.md) / [README.ES.md](README.ES.md) and
[GUIDE.md](GUIDE.md) / [GUIDE.ES.md](GUIDE.ES.md).

## Getting set up

```sh
dart pub get
dart analyze          # must be clean
dart test             # must be green
dart run bin/minerva_archivist.dart sync   # populate .minerva-cache/
```

`.minerva-cache/` is git-ignored and holds the metadata mirror plus whatever DATs
you point the tool at. Tests don't need it — they build fixtures in a temp dir.

## Layout

```
lib/src/
  models/   dat.dart       ROM entries, games, DAT files, production status
            metadata.dart  clonelists, RA index, MIA lists, internal config
  data/     dat_loader              XML -> models, flavor detection
            metadata_repository     asset fetch/cache + system-name resolution
            file_scanner            directory walk + streaming hasher
            torrent                 bencode inspection
            aria2_client            RPC client
            archive_source          platform -> torrent resolution
  domain/   enrichment    regions, languages, RA tagging, MIA marking
            selection     clone grouping, 1G1R scoring, wishlist/RA filtering
            auditor       DAT vs disk
            download      torrent file selection + post-download relocation
            organize      layouts, m3u, prune
  cli/      runner              command registry + common flags
            selection_options   the shared --lang/--exclude-* option set
            commands/           one file per verb
```

Dependency direction is `cli → domain → data → models`; nothing points back.

**Conventions**

- One file per pipeline stage. Result types live next to the code that produces
  them rather than in a shared types file.
- Interfaces only at real I/O boundaries — `Hasher`, `FileScanner`,
  `MetadataRepository`, `TorrentClient`, `ArchiveSource` — each declared
  alongside its primary implementation. Domain logic stays plain classes.
- Commands that operate on the filtered set mix in `SelectionCommand` and call
  `argParser.addSelectionFlags()`; they get `loadSelectedTargets()` for free.
- Read option values through the typed accessors (`flag`, `option`,
  `multiOption`), and report bad input with `usageException()` so the user sees
  the usage text and the process exits 64.

## The selection pipeline

`GameSelector.select()` runs, in Retool's order:

1. **enrich** — parse region/language tags, merge metadata languages, apply
   region-implied languages, tag RetroAchievements by hash, mark MIA by CRC.
2. **group** — map each title to a clone group. The key is Retool's
   `short_name`: the full name minus region, language, version and ignore tags.
   Edition qualifiers are kept, so titles differing only by edition stay
   distinct.
3. **exclude** — production status, category (DAT `<category>` plus the
   clonelist group's), and optionally language.
4. **1G1R** — one winner per group, ranked by clonelist priority → status →
   language → region → RetroAchievements → revision.
5. **filter** — wishlist and/or RetroAchievements, combined AND/OR.

It returns a `SelectionResult`: the games plus a `SelectionStats` funnel that
attributes every dropped title to exactly one reason. The CLI prints that funnel;
a test asserts it balances.

## Two system names, not one

`SystemNameResolver` exposes both, and they are not interchangeable:

- `baseSystem()` — the MiNERVA platform/torrent folder. Keeps dump-format
  qualifiers, since each is distributed separately.
- `metadataSystem()` — the Retool asset filename. Strips every parenthetical
  listed in the internal config's `datFileTags`.

Using one where the other belongs silently resolves to no clonelist at all.

## Testing

Tests are plain `package:test`, no mocks framework. Filesystem tests create a
temp directory in `setUp` and delete it in `tearDown`.

- `impl_test.dart` — DAT parsing, hashing, auditing
- `scoring_test.dart` — grouping, 1G1R, language filtering, selection stats
- `resolver_test.dart` — system-name resolution
- `organize_prune_test.dart` — the four layout modes, protection, pruning
- `torrent_test.dart`, `relocator_test.dart`, `minerva_sync_test.dart`

When fixing a bug, add the case that reproduces it. Prefer a real assertion over
a smoke test — e.g. that a CRC-only DAT entry matches, not merely that the call
returns.

## Style

Comments explain *why*, not *what* the line already says. Skip concrete DAT or
platform names in doc comments; use `<path>`-style placeholders. Keep them short:
if a comment needs a paragraph, the code probably needs a better name.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org).
