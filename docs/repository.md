# Repository layout

One repository holds every Species Unknown mod. Each mod lives in its own directory under `mods/`, and shared
knowledge lives in `docs/`.

```text
docs/                     how the game works and how to mod it (one file per topic)
mods/<mod-name>/          one directory per mod, kebab-case
  README.md               what it does, install, how it works, test plan
  cover.svg               cover art source
  cover.png               1920x1080 render of cover.svg, used on mod pages
  art/icons/*.svg         HUD icon sources, for mods with a pak (see Icons below)
  <PayloadName>/          exactly what gets installed into the game, PascalCase
    enabled.txt
    Scripts/main.lua
  tests/                  offline tests (*_test.lua), run by scripts/test-mods.sh
scripts/                  repository tooling
```

## Mods

- **The payload directory is the release.** Everything a player installs sits in one directory named after the
  mod in PascalCase, so installing is "copy this folder" and a release zip is that folder alone. Repository files
  (README, cover) stay outside it.
- **The README states who must install it**: host only, or every player. Decide with
  [multiplayer.md](multiplayer.md).
- **The README ends with a test plan** that someone can follow in a real game, because nothing here can be tested
  without running the game.
- Lua files start with `-- Copyright © 2026 Jalapeno Labs`.

## Covers

- 1920x1080 (16:9), so it fits the main image slot on mod sites and still reads as a small thumbnail.
- Hand-written SVG, original art only: no game screenshots, logos or the game's own artwork.
- Render with `scripts/render-covers.sh`, which rebuilds every `mods/*/cover.png` from its SVG. Commit both files.
- Use only fonts that are installed locally (the existing covers use Nimbus Sans Narrow Bold), so the render matches.

## Icons

- Hand-written SVG on a 128x128 view box: a white glyph with a faint dark outline, so it reads over bright and dark
  scenes alike. Cut details (eyes, slats) out of the shape rather than painting them dark.
- Only the SVGs are committed. `scripts/build-mod-assets.sh` renders them to 128-pixel PNGs under
  `unreal/SpeciesUnknown/Saved/ModArt/<mod-name>/` and the asset builder imports those as UI textures.

## Scripts

| Script | What it does |
|--------|--------------|
| `scripts/link-mod.sh <mod-name>` | Symlinks a mod's payload into the game's `ue4ss/Mods/` for development |
| `scripts/render-covers.sh` | Renders every `mods/*/cover.svg` to `cover.png` |
| `scripts/make_minimal_usmap.py <out>` | Writes the mappings file that lets kismet-analyzer parse Blueprint functions |
| `scripts/kismet_pseudocode.py <asset.json>` | Prints a Blueprint's bytecode as pseudo-code |
| `scripts/build-mod-assets.sh` | Renders the HUD icons, compiles the editor-only asset builder and regenerates every mod's assets |
| `scripts/package-mods.sh [--install]` | Generates, cooks and packs every mod's pak into `dist/paks/` (and the game) |
| `scripts/test-mods.sh` | Syntax-checks every mod's Lua and runs every mod's offline tests |

`link-mod.sh` takes the game location from `SPECIES_UNKNOWN_DIR` when it is set, otherwise the Steam library path
in [game-internals.md](game-internals.md#paths-on-this-machine).
