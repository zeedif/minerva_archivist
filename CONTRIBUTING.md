# Contributing

## Setup

```sh
dart pub get
dart run apps/cli/bin/minerva.dart sync   # fills .minerva-cache/
dart test packages/minerva_core
dart analyze
```

## Layout

```text
packages/minerva_core/lib/src/
  models/   DAT and Retool metadata entities
  data/     I/O: DAT parsing, hashing, metadata mirror, MiNERVA, torrent engine
  domain/   selection, auditor, organize, options and profiles, pipeline
apps/cli/       argument parsing and event rendering only
apps/desktop/   Flutter front end; runs the pipeline on a worker isolate
```

Front ends hold no logic. `Pipeline.run` takes a `RunOptions` and emits sealed `PipelineEvent`s; a front end switches over them exhaustively, so a new event fails to compile until every front end handles it. An option is added once, in `RunOptions.fromJson`, under the name the CLI and the profiles file share.

## Selection

`GameSelector.select()` runs in Retool's order: enrich each game from tags and metadata, group clones, exclude, pick one winner per group, then apply the wishlist and achievement sets. It returns the games plus a `SelectionStats` funnel that attributes every dropped title to one reason.

`SystemNameResolver` exposes two names that are not interchangeable: `baseSystem()` is the MiNERVA platform folder and keeps dump-format qualifiers; `metadataSystem()` is the Retool asset name and strips them. Using one for the other resolves to no clonelist.

## Testing

Plain `package:test`. Filesystem tests work in a temp directory created in `setUp`. A bug fix comes with the case that reproduces it.

Before changing selection, capture `minerva select --list` over every cached DAT and compare it afterwards: an unintended change in which dump wins shows up as a diff.

## Style

Doc comments state what the code does not: contracts, units, invariants. No history, no narrative, no concrete game names. Paths go through `package:path`; use `p.posix` for torrent and URL paths, whose separator is fixed by the format.

Commits follow [Conventional Commits](https://www.conventionalcommits.org); write the body as unwrapped paragraphs.
