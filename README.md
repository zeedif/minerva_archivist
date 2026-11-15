# MiNERVA Archivist

[Español](README.ES.md)

Curates ROM collections against No-Intro and Redump DATs: picks one dump per game (1G1R), downloads what is missing from the [MiNERVA Archive](https://minerva-archive.org), lays the folder out for EmulationStation-DE and quarantines what does not belong. Selection follows [Retool](https://github.com/unexpectedpanda/retool)'s clonelists and metadata.

It is a Dart workspace: `packages/minerva_core` holds all the logic, `apps/cli` is the command line and `apps/desktop` a Flutter front end over the same profiles.

## Build

```sh
dart pub get
cd apps/cli && dart build cli          # build/cli/.../bundle/bin/minerva.exe
cd apps/desktop && flutter build windows
```

The bundle's `lib/` folder carries libtorrent and must stay beside `bin/`. From source, `dart run apps/cli/bin/minerva.dart` works as `minerva`.

## Use

```sh
minerva sync                                   # metadata and Redump/MAME-Redump DATs into .minerva-cache
minerva select -d "Nintendo - Game Boy" --list # what would be wanted; touches nothing
minerva run -d "Nintendo - Game Boy" -r D:/Roms/gb           # report only
minerva run -d "Nintendo - Game Boy" -r D:/Roms/gb --apply   # do it
```

No-Intro DATs are not redistributable: download them from Dat-o-Matic into `.minerva-cache/nointro/`. A DAT is named by its system, so the date stamp in the file name never matters; prefix a source (`redump:Sony - PlayStation`) when two sources share a name. A path to a DAT or a folder of DATs also works.

`run` goes through these stages. Nothing is downloaded, moved or written without `--apply`.

| Stage | What it does |
|---|---|
| select | Applies the options below and keeps one dump per game. |
| audit | Matches files to the selection by hash. Zip entries are identified by the CRC-32 and size in the zip directory, without decompressing. |
| `download` | Fetches missing games from the platform torrent, only the files needed, with per-file progress. Nothing keeps running or seeding afterwards. |
| `organize` | Renames to the DAT name and applies `--layout`. |
| `playlists` | Writes an `.m3u` per multi-disc game. |
| `prune` | Moves unknown and duplicate files to `<root>/.trash`. Never deletes. |

`sync` also runs first as a stage. Leave stages out with `--skip`.

A folder that holds a game next to files of your own (patches, manuals, translations) is left where it is: nothing in it is moved or pruned, and it is only renamed to the game's name when it holds exactly one game. `<root>/.minerva` is the tool's working folder.

## Options

| Option | Meaning |
|---|---|
| `--lang Es,En` | Language priority, best first. A title speaking none of them is dropped. `Other` stands for unlisted languages and `Unknown` for titles with none; `Es` covers `Es-MX`. Default `En`. |
| `--region USA,Europe` | Region priority; restricts like `--lang`. Default: every region. |
| `--priority lang,ra,langcount` | Tie-breaks that choose among the dumps of one game, best first: `lang`, `region`, `ra` (achievements, hash-verified first), `langcount`. Default `lang,region,ra`. |
| `--langcount most\|fewest` | Direction of the `langcount` axis. Required when `--priority` names it, rejected otherwise. |
| `--wishlist file.jsonc` | JSON/JSONC array of game names; any regional spelling works. Entries matching nothing are reported. |
| `--wishlist-mode absolute\|subset` | `absolute`: everything named is selected and the other filters only pick its dump. `subset`: a named title must still pass them. |
| `--achievements any\|approved` | Only titles with RetroAchievements; `approved` keeps just the dumps the set was built on. |
| `--supersets prefer\|ignore` | Whether an edition containing the base game takes its slot. |
| `--compilations never\|fill\|prefer\|first` | What a multi-game pack is worth against the games in it. |
| `--exclude demos,bios,...` | Kinds of dump dropped outright. `minerva run --help` lists them. |
| `--layout` | `zip`, `zip-in-folder`, `extracted`, `extracted-in-folder`. |
| `--protect folder` | Top-level folders never touched. |
| `--depth n` | How many folders below the root are searched; unlimited by default. Useful when the root also holds deep trees that are not ROMs. |

## Profiles

`<cache>/profiles.jsonc` stores options per platform under the same names, so a platform is one word:

```jsonc
{
  "defaults": { "lang": ["Es", "En"], "layout": "extracted", "exclude": ["demos", "bios"] },
  "profiles": {
    "gb":  { "dat": "Nintendo - Game Boy", "root": "D:/Roms/gb", "achievements": "any" },
    "psx": { "dat": ["mame-redump:Sony - PlayStation", "redump:Sony - PlayStation"], "root": "D:/Roms/psx" }
  }
}
```

```sh
minerva profiles            # list them
minerva run gb psx --apply  # run some
minerva run --all           # preview all
```

A profile overrides `defaults` and the command line overrides both. Relative paths resolve against the file. See [examples/profiles.jsonc](examples/profiles.jsonc). The desktop app reads the same file.

## License

GPL-3.0. Clonelists and metadata come from [retool-clonelists-metadata](https://github.com/unexpectedpanda/retool-clonelists-metadata). See [CONTRIBUTING.md](CONTRIBUTING.md) to work on the code.
