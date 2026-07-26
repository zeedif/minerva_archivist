# Command guide

Every flag, what it does, and how the pieces combine.
**English** · [Español](GUIDE.ES.md) — back to the [README](README.md).

Placeholders: `<dat>` a DAT file or a folder of DATs · `<rom-root>` your ROM
directory · `<path>` any file path.

---

## Common options

Available on every command.

| Option | Meaning |
|---|---|
| `-d, --dat <dat>` | DAT file **or** folder of DATs. Repeatable. Flavor auto-detected |
| `-r, --rom-root <dir>` | Root of your ROM collection |
| `--cache <dir>` | Metadata cache (default `.minerva-cache`) |
| `-v, --verbose` | Verbose logging |
| `-h, --help` | Usage for that command |

Passing several DATs merges them into one run — that's how a MAME-Redump CHD set
and its Redump counterpart get unified:

```sh
minerva_archivist run -d <mame-redump-dat> -d <redump-dat> -r <rom-root>
```

Exit codes: `0` ok · `64` bad usage · `70` runtime failure (e.g. `aria2c` missing).

---

## Selection options

Shared by `filter`, `audit`, `download`, `organize`, `m3u`, `prune` and `run`.
They decide *which* games a command acts on. Multi-value options accept commas
or repetition.

| Option | Meaning |
|---|---|
| `--lang <codes>` | Language priority, best first. Default `En` |
| `-l, --filter-languages` | Also **drop** titles that speak none of `--lang` |
| `--wishlist <path>` | JSON/JSONC array of game names to keep |
| `-a, --retroachievements` | Keep titles with RetroAchievements support |
| `--combine or\|and` | How wishlist and RA combine. Default `or` |
| `--exclude-status <list>` | Drop these production statuses |
| `--exclude-category <list>` | Drop these categories |

### `--lang` and `-l`

On its own, `--lang` only **ranks**: when a group has a Spanish and an English
release, Spanish wins — but a French-only game is still kept, because nothing
better exists in that group.

`-l` turns it into a **filter** as well: titles that speak none of your languages
are removed outright. Titles whose language is unknown are kept, since there's
nothing to judge them on.

```sh
# Spanish preferred, but everything is kept
minerva_archivist filter -d <dat> --lang Es,En

# Spanish or English only — French/German/etc. are dropped
minerva_archivist filter -d <dat> -l --lang Es,En
```

Regional variants match their base code: asking for `Es` accepts `Es-MX`.

### `--exclude-status`

Accepts: `released`, `prototype`, `beta`, `alpha`, `demo`, `sample`, `pirate`,
`unlicensed`, `mia`.

`mia` means the dump is known to exist but has never been preserved — excluding
it stops the tool chasing files nobody has.

```sh
--exclude-status mia,prototype,beta,alpha,demo,sample,unlicensed,pirate
```

### `--exclude-category`

Case-insensitive substring match against a game's categories, which come from the
DAT's `<category>` element **and** from its clonelist group. That second source
matters: No-Intro DATs carry no categories at all, so test cartridges and
utilities are only recognisable via the clonelist.

Common values: `Applications`, `Audio`, `BIOS`, `Bonus Discs`, `Coverdiscs`,
`Demos`, `Educational`, `Games`, `Manuals`, `Multimedia`, `Pirate`,
`Preproduction`, `Promotional`, `Unlicensed`, `Video`.

```sh
--exclude-category "Applications,Audio,BIOS,Coverdiscs,Educational,Manuals,Multimedia,Promotional,Video"
```

### Wishlist

A JSON/JSONC array of base game names:

```jsonc
[
  "Chrono Trigger",
  "Final Fantasy VII",
  "Bomber Boy"   // also pulls its clone group
]
```

Matching ignores case, punctuation, a leading/trailing "The", and region/format
tags. It is exact-after-normalisation, not substring — use full base titles.
Naming any title in a clone group selects the whole group.

Combine with RetroAchievements from the CLI, not the file:

```sh
--wishlist <path> -a --combine or    # wishlisted OR has achievements
--wishlist <path> -a --combine and   # wishlisted AND has achievements
```

---

## Commands

### `sync`

Mirrors clonelists, metadata, RetroAchievements and MIA data locally. Re-run
whenever; only files whose hash changed are fetched.

```sh
minerva_archivist sync
minerva_archivist sync --force
minerva_archivist sync --only clonelists --only retroAchievements
```

`--only` accepts `config`, `cloneLists`, `metadata`, `retroAchievements`, `mias`.

Everything lands under `.minerva-cache/`:

```
.minerva-cache/
├── clonelists/  metadata/  mias/  retroachievements/  config/
└── <your DAT folders>
```

### `filter`

Prints the selection. Offline, reads nothing but the DATs and the cache, writes
nothing.

```sh
minerva_archivist filter -d <dat>
minerva_archivist filter -d <dat> -a -l --lang En,Ja
minerva_archivist filter -d <dat> --wishlist <path> -a --combine and
```

Output is a funnel — the total, the survivors, and what each stage removed:

```
<system> [noIntro]: 404 -> 309  (status -89, language -6)
```

### `audit`

Compares the selection against `<rom-root>`.

```sh
minerva_archivist audit -d <dat> -r <rom-root>
minerva_archivist audit -d <dat> -r <rom-root> --no-hash --no-chd
```

| Option | Meaning |
|---|---|
| `--[no-]hash` | Verify by hashing. `--no-hash` is a fast name/size pass. Default on |
| `--[no-]chd` | Accept a local `.chd` for a raw Redump entry. Default on |

Files inside `.trash` are ignored — a quarantined copy doesn't count as owned.

### `download`

Resolves the platform-wide torrent and fetches only what you're missing. With
`--rom-root` it downloads the gaps; without one, the whole selection.

```sh
minerva_archivist download -d <dat> --dry-run
minerva_archivist download -d <dat> -r <rom-root> --aria2 <path> --seed
minerva_archivist download --torrent <path> -r <rom-root> --aria2 <path>
minerva_archivist download --collection No-Intro --platform "<platform>" --aria2 <path>
```

| Option | Meaning |
|---|---|
| `--collection <name>` | MiNERVA collection. Derived from the DAT if omitted |
| `--platform <name>` | Platform name. Derived from the DAT if omitted |
| `--torrent <path>` | Use a local `.torrent` instead of resolving one |
| `--aria2 <path>` | Path to the `aria2c` binary. Default `aria2c` |
| `--seed` | Keep seeding after the selected files finish |
| `--dry-run` | Show the plan, transfer nothing |

Games the archive doesn't distribute are listed individually, so a shortfall is
never silent:

```
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
           ? not in torrent: <name>.zip
```

Once a download completes, files are flattened out of the torrent's nested
folders up to the ROM root, `.aria2` control files are deleted, and the empty
tree is removed. This avoids Windows `MAX_PATH` problems and leaves a flat layout
for the later stages.

### `organize`

Two flags pick one of four layouts: `--folder-as-file` (folder vs flat) ×
`--extract` (unzip vs keep the archive).

| Flags | Layout | Result |
|---|---|---|
| *(none)* | Archived flat | `<root>/Game.zip` |
| `--extract` | Smart flat | `Game.nes`, or `Game/` for multi-track discs |
| `--folder-as-file` | Archived in folder | `Game/Game.zip` |
| `--folder-as-file --extract` | Extracted folder-as-file | `Game.nes/Game.nes` |

```sh
minerva_archivist organize -d <dat> -r <rom-root> --extract --apply
minerva_archivist organize -d <dat> -r <rom-root> --folder-as-file --extract \
  --protect Hacks --protect Mods --apply
```

| Option | Meaning |
|---|---|
| `--folder-as-file` | Each game gets its own folder |
| `--extract` | Unzip. Off keeps the `.zip` |
| `--protect <name>` | Folder names never to touch. Repeatable |
| `--apply` | Actually move files. Default is a dry run |

Protected means: any folder named in `--protect`, plus any folder already holding
user files (`.ips`, `.bps`, `.sav`, `.state`, …). A game whose destination can't
be written is reported and skipped — it won't abort the run.

### `m3u`

Writes one `.m3u` per multi-disc or multi-side game, ordered so disc 1 leads.

```sh
minerva_archivist m3u -d <dat> -r <rom-root> --apply
```

### `prune`

Moves anything in `<rom-root>` that isn't part of the selection into `.trash`,
preserving relative layout. It moves, never deletes, and never touches `.trash`
itself or protected folders.

```sh
minerva_archivist prune -d <dat> -r <rom-root>
minerva_archivist prune -d <dat> -r <rom-root> --protect Hacks --apply
```

### `run`

The whole pipeline: **sync → select → audit → [download] → organize → m3u → prune**.

Mutating stages are dry-run unless `--apply`; downloading is off unless
`--with-download`.

```sh
# safe preview
minerva_archivist run -d <dat> -r <rom-root>

# the works
minerva_archivist run -d <dat> -r <rom-root> \
  -l --lang Es,En,Ja --wishlist <path> -a --combine or \
  --exclude-status mia,prototype,beta,demo \
  --with-download --aria2 <path> \
  --extract --protect Hacks --apply

# pick your stages
minerva_archivist run -d <dat> -r <rom-root> --only select --only audit
minerva_archivist run -d <dat> -r <rom-root> --skip prune --skip m3u
```

| Option | Meaning |
|---|---|
| `--only <stage>` | Run only these stages. Repeatable |
| `--skip <stage>` | Skip these stages. Repeatable |
| `--with-download` | Enable downloading |
| `--folder-as-file`, `--extract`, `--protect` | Passed to `organize` |
| `--aria2 <path>`, `--seed` | Passed to `download` |
| `--apply` | Apply download / organize / prune |

Stages: `sync`, `select`, `audit`, `download`, `organize`, `m3u`, `prune`.

After a download the pipeline re-audits, so `organize`/`m3u`/`prune` act on the
files that just arrived.

---

## Reading the output

```
[select] 404 in DAT -> 309 wanted  (status -89, language -6)
[audit] 0/309 on disk, 309 missing, 0 unknown
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
[audit] 303/309 on disk, 6 missing
[organize] 303 extracted
[prune] 0 orphans
```

- **select** — DAT total, survivors, and one entry per reason that removed
  something. Reasons are `status`, `category`, `language`, `1g1r`, `wishlist/ra`;
  they always add up to the difference.
- **audit** — `on disk / wanted`. `unknown` counts files present that no selected
  game claims; those are what `prune` would move.
- **download** — how many are missing, how many the archive actually carries, and
  the shortfall listed by name.

## Notes

- The 1G1R engine mirrors Retool's, but Retool's region filter is not
  implemented. If your Retool config restricts regions, use `-l` to get
  equivalent results; a title from an excluded region with no language metadata
  may still slip through.
- Selection is offline. Only `sync` and `download` need the network.
