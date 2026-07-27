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
They decide *which* games a command acts on.

| Option | Meaning |
|---|---|
| `--lang <codes>` | Language priority, best first. Ranks and restricts. Default `En` |
| `--region <names>` | Region priority, best first. Ranks and restricts |
| `--priority <axes>` | Which tie-breaks decide a clone group. Default `lang,region,ra` |
| `--wishlist <path>` | JSON/JSONC array of game names to select |
| `--wishlist-mode absolute\|subset` | What naming a title claims. Default `absolute` |
| `--achievements any\|approved` | Select only titles with achievements |
| `--supersets prefer\|ignore` | What a pack is worth against its contents. Default `prefer` |
| `--exclude <kinds>` | Drop these kinds of dump outright |

### `--lang` and `--region`

Both **rank and restrict**: they order the dumps of a title, and a title that
answers to nothing on the list is dropped. So naming one value gives you that
segment — `--lang Es` is the Spanish set, `--region Spain` the Spanish-release
set — and naming several orders them.

Rather than spell out every value, two entries stand in for the rest and rank
wherever you put them:

| Entry | Covers |
|---|---|
| `Other` | Any value the list doesn't name, plus missing values unless `Unknown` is listed |
| `Unknown` | Titles the DAT says nothing about on that axis |

`Other` is one slot, so values sharing it fall back on a full built-in order —
region on `USA, World, Canada, Europe, UK, …`, language on what that implies —
rather than resolving arbitrarily.

```sh
# only Spanish
minerva_archivist filter -d <dat> --lang Es

# Spanish, then English, then everything else
minerva_archivist filter -d <dat> --lang Es,En,Other

# Spain and the Americas first, the rest still welcome
minerva_archivist filter -d <dat> --region Spain,USA,Europe,Other
```

`--lang` entries cover their subtags: asking for `Es` accepts `Es-MX`. Left unset,
`--region` uses the full built-in order, which lists every region and so drops
nothing; untagged titles count as `Unknown`.

### `--priority`

Language, region and achievements pull against each other: preferring your
language can cost you the dump that carries achievements, and the reverse.
`--priority` says which wins, best first.

| Value | Effect |
|---|---|
| `lang,region,ra` | Default. Your language wins; achievements only break ties |
| `ra,lang` | The dump with achievements wins, even in another language |
| `lang,ra` | Language first, then achievements; region stops outranking either |

`lang` and `ra` left out drop from the ranking entirely. **`region` does not**: it
keeps a fixed place below whatever you did list, because nothing else in the chain
can decide between two regions and a cross-region tie would otherwise be settled
by spelling. Omitting it means it must not outrank your language or achievements.

Worth knowing before you put `ra` first: a Spanish-capable European dump usually
has no achievements — those are validated against the USA release — so `ra,lang`
will pass over the very dump your translation patch was made for.

Below whatever you listed, the order is fixed: supersets, region, clonelist
priority, modern editions (a Virtual Console or console rip loses to the original),
budget editions (a re-release wins; it usually carries the fixes), revision,
`(Alt)`/OEM, then the promotion and demotion lists.

### Wishlist

A JSON/JSONC array of base game names:

```jsonc
[
  "Chrono Trigger",
  "Final Fantasy VII",
  "Bomber Boy"   // any of a title's regional spellings will do
]
```

Matching ignores case, punctuation, a leading/trailing "The", and region/format
tags. It is exact after that, not substring — use full base titles. Naming any
release of a game selects the game, and the orders then pick its best dump, so
your spelling never decides which region you end up with. Naming a multi-game
pack asks for the pack rather than for each title on it.

#### `--wishlist-mode`

A wishlist can be two things, and one answer settles both halves of it.

**`absolute`** (default) — a set of its own, ranked **above** `--lang` and
`--region`. Everything you named is selected; those orders only choose which of
its dumps you get. This is what makes a Japanese-only title survive `--lang Es,En`,
which is exactly what you want when you name it in order to apply a translation
patch. And since it outranks the orders, it would be perverse to then drop it for
carrying no achievements — so `--achievements` **adds** to it instead:

```sh
--wishlist <path> --achievements any   # my wishlist, plus everything with achievements
```

**`subset`** — one condition among the others. A named title still has to speak a
ranked language, come from a ranked region and meet `--achievements`, which
therefore **narrows** the wishlist:

```sh
--wishlist <path> --wishlist-mode subset --achievements any   # only the wishlisted titles that have achievements
```

### `--achievements`

Omit it and achievements restrict nothing — `--priority ra` still ranks them.
Given, it names the set you want, at the scale you want it:

| Value | Keeps |
|---|---|
| `any` | Titles with achievements on any of their dumps, leaving `--priority` to choose which dump represents them |
| `approved` | Only the dumps the achievement set was authored against, so the approved dump is the one that wins its group |

A dump is joined two ways, worth different amounts: a **hash** join proves the set
was authored against exactly those bytes, a **name** join only says a title so
named is covered. `approved` accepts only the first, and the `ra` tie-break
prefers it. `--explain` marks which each dump got:

```
WIN Dragon Quest - The Hand of the Heavenly Bride (Europe)  [...]  ra:name
    Dragon Quest V - Hand of the Heavenly Bride (USA)       [...]
```

Two caveats. RetroAchievements covers no Xbox, Xbox 360, PS3, 3DS or Vita, so
`--achievements` selects nothing there. And on disc systems the sets are hashed
against the disc's executable rather than the image, so every join is by name and
`approved` selects nothing — it is a cartridge-era tool.

### Packs and `--supersets`

A clonelist lists a multi-game pack under **every** group it contains, so the pack
stands for all of them. It competes for the slot of each game inside it and,
winning, fills it — you get the pack, not the pack plus loose copies of what is
already on it.

| Mode | Effect |
|---|---|
| `prefer` | Default. The pack answers for its contents and takes their slots |
| `ignore` | Each group goes to a release of its own; the pack only fills groups nothing else covers |

Naming one of the titles a pack holds gets you the pack under `prefer`, or that
release under `ignore`.

The same applies to a subsuming edition: a deluxe or tournament edition that
contains the original release represents its group and beats a plain release, a
higher revision of one, and a dump from a region you rank above it.

### Re-releases are not separate games

`Mario Kart 64 (USA)` and `Mario Kart 64 (USA) (LodgeNet)` are one game. Edition
tags are stripped when building a clone key, so the two compete for one slot
instead of both being kept and both downloaded — that covers `(LodgeNet)`,
`(Wii Virtual Console)`, `(Switch Online)`, `(Greatest Hits)` and some hundreds
more.

### `--exclude`

Always applies, the wishlist included: naming a game must not quietly re-admit its
prototype or its manual.

Accepts `add-ons`, `applications`, `audio`, `bad-dumps`, `bios`, `bonus-discs`,
`coverdiscs`, `demos`, `educational`, `manuals`, `mia`, `multimedia`, `pirate`,
`preproduction`, `promotional`, `unlicensed`, `video`.

```sh
--exclude mia,preproduction,demos,unlicensed,pirate,bonus-discs,applications,bios,coverdiscs,educational,manuals,multimedia,promotional,video
```

Each kind is recognised three ways at once — the DAT's `<category>`, the
clonelist's, and the name — so a trial disc counts as a demo however it is
spelled, in Japanese or Korean included. That matters because No-Intro DATs carry
no categories at all, leaving the name the only signal. `mia` means the dump is
known to exist but has never been preserved; excluding it stops the tool chasing
files nobody has.
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
minerva_archivist filter -d <dat> --achievements any --lang En,Ja
minerva_archivist filter -d <dat> --wishlist <path> --wishlist-mode subset --achievements any
```

Output is a funnel — the total, the survivors, and what each stage removed:

```
<system> [noIntro]: 404 -> 309  (exclude -89, language -6)
```

| Option | Meaning |
|---|---|
| `--list` | Print every selected game name |
| `--explain <text>` | For each game whose name contains `<text>`, print its clone group and whether it won |

`--explain` answers "why do I have two of these, or none": it shows what
competed for the slot.

```sh
minerva_archivist filter -d <dat> --explain "Bomberman 64"
```

```
  --- Bomberman 64
          Bomberman 64 (Europe)  [bomberman 64]
      WIN Bomberman 64 (USA)  [bomberman 64]
      WIN Bomberman 64 (Japan)  [bomberman 64 japan]
```

Two winners because the clonelist splits the Japanese release into its own
group — it is a different game, not a regional variant.

### `audit`

Compares the selection against `<rom-root>`.

```sh
minerva_archivist audit -d <dat> -r <rom-root>
minerva_archivist audit -d <dat> -r <rom-root> --no-hash --no-chd
```

| Option | Meaning |
|---|---|
| `--[no-]hash` | Verify by hashing. Default on. `--no-hash` reads no files at all, so everything reports as missing — it only shows the selection funnel |
| `--[no-]chd` | Accept a local `.chd` for a raw Redump entry. Default on |

Files inside `.trash` are ignored — a quarantined copy doesn't count as owned.

The audit reads files against the **whole** DAT, not just the selection, so a
dump that lost its 1G1R slot is still identified. That is what makes a
[curated folder](#curated-folders) holding a runner-up legible instead of looking
like a pile of junk. It reports which folders it found, and which games it will
therefore not fetch:

```
  18 curated of 18 folder(s), 9 game(s) settled there
  curated: 007 - The World Is Not Enough (Europe)  (1 rom(s), 2 of your own)
  settled elsewhere, will not be fetched: 007 - The World Is Not Enough (USA)
```

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

A game whose destination can't be written is reported and skipped — it won't
abort the run.

#### Curated folders

A folder is **curated** when it holds a dump *and* files of your own: patches,
translations, manuals, cover scans, a `translations/` subfolder. Saves, states
and `.m3u` playlists don't count — the tool wrote those itself.

```
Body Harvest (USA)/
├── Body Harvest (USA).z64          <- the dump
└── translations/
    ├── ... (v0.98) (T-Es).z64      <- yours
    └── ... (v0.98) (T-Es).txt      <- yours
```

Curated folders are detected by content, on every run, on top of anything
`--protect` names. Nothing is moved out of one and nothing in one is pruned —
those patches only make sense beside the dump they were built against.

Two things still happen, because neither can disturb what you built:

* a folder holding exactly one complete game is renamed to that game's name;
* a ROM inside is renamed to its DAT name, staying in the same folder.

A folder with **no** extra content is not curated: if it holds a dump the
selection doesn't want, it is pruned like any loose file, and the folder goes
with it once empty.

#### Duplicate copies of the same dump

Curation protects a folder, not the bytes inside it. Put a second copy of a
curated dump loose in the root and it is redundant — 1G1R wants one of each —
so it is pruned and the curated copy keeps the slot, patches and all:

```
Sagaia (Japan) (En)/
├── Sagaia (Japan) (En).gb          <- kept
└── translations/sagaia (T-Es).ips
Sagaia (Japan) (En).gb              <- pruned, same bytes
```

Which copy keeps the slot is decided by content, not by scan order: a curated
folder wins outright, then the file already named as the DAT names it, then the
one nearest the root. Different dumps of one game in separate curated folders —
three regional Ocarinas, each with its own translation — are not duplicates and
nothing happens to them.

The one case left alone is the same bytes under **two** curated folders. Which
set of patches to keep is a judgement about your content, so the run only
reports it:

```
[prune] 1 duplicate(s) left alone inside curated folders — merge them by hand
        = Ocarina FR/Legend of Zelda (USA).z64
```

### `m3u`

Writes one `.m3u` per multi-disc or multi-side game, ordered so disc 1 leads.

```sh
minerva_archivist m3u -d <dat> -r <rom-root> --apply
```

### `prune`

Moves anything in `<rom-root>` that isn't part of the selection into `.trash`,
preserving relative layout. It moves, never deletes, and never touches `.trash`
itself, protected folders, or [curated folders](#curated-folders). A folder left
empty by pruning is removed.

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
  --lang Es,En,Ja --wishlist <path> --achievements any \
  --exclude mia,preproduction,demos \
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
[select] 404 in DAT -> 309 wanted  (exclude -89, language -6)
[audit] 0/309 on disk, 309 missing, 0 unknown
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
[audit] 303/309 on disk, 6 missing
[organize] 303 extracted
[prune] 0 orphans
```

- **select** — DAT total, survivors, and one entry per reason that removed
  something. Reasons are `exclude`, `language`, `region`, `1g1r`, `superset` and
  `wishlist/ra`; they always add up to the difference.
- **audit** — `on disk / wanted`. `unknown` counts files present that no selected
  game claims; those are what `prune` would move.
- **download** — how many are missing, how many the archive actually carries, and
  the shortfall listed by name.

## Notes

- Clonelists, metadata, achievement and MIA data are mirrored from the upstream
  project `sync` points at. The 1G1R engine reimplements its grouping and scoring,
  with the tie-break order yours to choose via `--priority`.
- Selection is offline. Only `sync` and `download` need the network.
