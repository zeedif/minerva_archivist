<h1 align="center">MiNERVA Archivist</h1>

<div align="center">

[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)](#install)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Dart SDK](https://img.shields.io/badge/dart-%E2%89%A53.12-0175C2)](https://dart.dev)

**English** · [Español](README.ES.md)

</div>

<p align="center">
A command-line ROM librarian: it picks one game per title (1G1R), downloads only
what you're missing, and keeps the folder tidy — without you babysitting it.
</p>

---

## What it is

You have DAT files and a ROM folder. MiNERVA Archivist reads the DATs, works out
which single version of each game you actually want, checks what's already on
disk, fetches the rest, and lays everything out.

It carries its own 1G1R engine — a port of [Retool](https://github.com/unexpectedpanda/retool)'s
selection logic — so there's no second tool to run first. Clonelists, metadata,
RetroAchievements and MIA data are pulled straight from
[`retool-clonelists-metadata`](https://github.com/unexpectedpanda/retool-clonelists-metadata)
and cached locally.

## What it does

- **Reads any DAT you throw at it.** No-Intro, Redump and MAME-Redump CHD sets
  are detected from the file itself — no type flags.
- **Picks one game per title.** Clonelist priority → production status →
  language → region → RetroAchievements → revision, using the upstream
  region/language tables.
- **Cuts what you don't want.** Prototypes, betas, demos, pirates, MIA dumps;
  applications, BIOS, manuals, coverdiscs, video; and titles that don't speak
  your languages.
- **Keeps what you do.** A wishlist file (clone-group aware, so naming one title
  pulls its whole group) combined with a RetroAchievements-only filter.
- **Downloads only the gaps.** Matches missing games against the platform-wide
  torrent and hands just those files to `aria2c`.
- **Tidies up afterwards.** Four ES-DE-compatible layouts, `.m3u` playlists for
  multi-disc games, and orphan cleanup that moves files to `.trash` instead of
  deleting them.

Everything that touches your files is a **dry run by default** — add `--apply`
when you're happy with the plan.

## Install

Dart SDK ≥ 3.12.

```sh
dart pub get

# run from source
dart run bin/minerva_archivist.dart <command> [options]

# or compile a standalone binary (faster startup)
dart compile exe bin/minerva_archivist.dart -o minerva_archivist
```

Downloading needs [`aria2c`](https://github.com/aria2/aria2/releases) on `PATH`
or passed via `--aria2 <path>`. Everything else works offline once synced.

## Quick start

```sh
# 1. mirror the metadata locally (re-run anytime; only changed files are fetched)
minerva_archivist sync

# 2. see what the selection looks like — nothing is written
minerva_archivist filter -d <dat-or-folder>

# 3. preview the whole pipeline against your library
minerva_archivist run -d <dat-or-folder> -r <rom-root>

# 4. do it for real
minerva_archivist run -d <dat-or-folder> -r <rom-root> --apply
```

A typical everyday invocation — Spanish first, English as fallback, no demos or
BIOS, downloading whatever's missing:

```sh
minerva_archivist run -d <dat-or-folder> -r <rom-root> \
  -l --lang Es,En,Ja \
  --exclude-status mia,prototype,beta,demo,pirate \
  --exclude-category "Applications,BIOS,Manuals,Video" \
  --with-download --extract --apply
```

Each stage reports what it dropped and why:

```
[select] 404 in DAT -> 309 wanted  (status -89, language -6)
[audit] 0/309 on disk, 309 missing, 0 unknown
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
```

## Commands

| Command | What it does |
|---|---|
| `sync` | Mirror clonelists / metadata / RetroAchievements / MIA locally |
| `filter` | Show the 1G1R selection — offline, read-only |
| `audit` | Compare the selection against what's on disk |
| `download` | Fetch missing games from the platform torrent |
| `organize` | Lay files out in one of four ES-DE layouts |
| `m3u` | Write playlists for multi-disc games |
| `prune` | Move anything unselected to `.trash` |
| `run` | All of the above, in order |

Every flag, every combination, and the wishlist format live in
**[GUIDE.md](GUIDE.md)** ([español](GUIDE.ES.md)).

## Contributing

Architecture, layout conventions and how to run the tests are in
**[CONTRIBUTING.md](CONTRIBUTING.md)**.

## Credits & license

The selection engine follows [Retool](https://github.com/unexpectedpanda/retool)
by unexpectedpanda, and consumes its
[clonelists and metadata](https://github.com/unexpectedpanda/retool-clonelists-metadata).
DAT data comes from the [No-Intro](https://no-intro.org) and
[Redump](http://redump.org) preservation projects. Thanks to all of them.

Licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE).

    MiNERVA Archivist  Copyright (C) 2026  Zeedif
    This program comes with ABSOLUTELY NO WARRANTY.
    This is free software, and you are welcome to redistribute it
    under certain conditions.
