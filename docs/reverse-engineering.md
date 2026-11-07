# Reverse engineering

How to find out what the game does before modding it. Three sources, from cheapest to most complete.

## 1. Strings in the executable (no tools)

The shipping executable holds every native class, function and property name as plain strings. It is the fastest
way to confirm a native hook target exists, and it doesn't touch the running game:

```bash
exe="<install>/SpeciesUnknown/Binaries/Win64/SpeciesUnknown-Win64-Shipping.exe"
nice -n 19 strings -n 6 "$exe" > exe-ascii.txt
nice -n 19 strings -n 6 -e l "$exe" > exe-utf16.txt   # FNames and engine text are UTF-16
grep -h -E "NumPublicConnections|__Store__" exe-*.txt | sort -u
```

What it shows:

- Native module paths (`/Script/OnlineSubsystemBlueprints`) and class names without their `U`/`A` prefix.
- `__Store__<Param>` property names on async Blueprint nodes (see [ue4ss.md](ue4ss.md#changing-what-an-async-blueprint-node-does)).
- Console variable names (`net.MaxPlayersOverride`).
- The engine version (`++UE5+Release-5.7-CL-...`).

What it can't show: anything in the game's Blueprints. Those live in the Oodle-compressed IoStore container.

## 2. UE4SS dumps (game running)

Install UE4SS and use its Live View or `DumpJMAP()` to see every loaded Blueprint class with its functions,
parameters and properties (see [ue4ss.md](ue4ss.md#discovering-what-to-hook)). This gives exact hook paths and
parameter names, but not the logic inside a function.

## 3. Unpacking assets (full Blueprint logic)

| Tool | Use |
|------|-----|
| [retoc](https://github.com/trumank/retoc) | Reads and writes IoStore. `retoc to-legacy` turns the game's container into loose `.uasset` files; `retoc to-zen` builds mod containers |
| [repak](https://github.com/trumank/repak) | Lists and unpacks the legacy `.pak` (config `.ini` files) |
| [kismet-analyzer](https://github.com/trumank/kismet-analyzer) | Parses a Blueprint's Kismet bytecode into JSON (see below) |
| [UAssetGUI](https://github.com/atenfyr/UAssetGUI) | Views and edits single assets (Windows; runs under Wine) |
| [FModel](https://fmodel.app) | Browses the whole container with previews (Windows; heavier) |

### Converting assets with retoc

retoc converts only the assets whose path matches `--filter`, in about a second, so there's no need to unpack the
whole 6.6 GB container. Point it at the `Paks` directory, not a single `.utoc`: the script objects every asset
imports live in `global.utoc`, and a lone game `.utoc` fails with `does not contain ... ScriptObjects`.

```bash
paks="<install>/SpeciesUnknown/Content/Paks/"
nice -n 19 ionice -c3 retoc to-legacy --version UE5_7 --no-shaders --no-parallel \
  --filter "Blueprints/Core/" "$paks" extracted/legacy
```

### Reading a Blueprint's names without a parser

A converted `.uasset` holds the asset's name table: every function, variable, called node, local and string
literal it uses. `strings` on the `.uasset`/`.uexp` pair answers "what does this Blueprint touch?" before any
bytecode tool is involved:

```bash
strings -n 4 BP_LobbyGameMode.uasset BP_LobbyGameMode.uexp | grep -i -E "lobby|session|kick|max" | sort -u
```

It shows names, not control flow. To see which value a check compares against, read the bytecode.

### Reading Blueprint bytecode

[kismet-analyzer](https://github.com/trumank/kismet-analyzer) (the `latest` development build) converts an asset to
JSON with every function's bytecode parsed into expression trees. Two catches with this game's assets:

- **Exports stay raw without mappings.** With unversioned properties and no `.usmap`, every export comes back as
  `RawExport` and there is no bytecode. Function exports have no tagged properties, so a mappings file with empty
  schemas for the `Object -> Field -> Struct -> Function` and `Class -> BlueprintGeneratedClass` chain is enough:
  `scripts/make_minimal_usmap.py` writes one. Class and CDO exports stay raw, so default values (such as a
  variable's starting value) still need a real `.usmap` dumped by UE4SS.
- **`gen-cfg` needs a parsed class export**, so it prints `No ClassExport` and writes empty graphs. Use `to-json`
  and `scripts/kismet_pseudocode.py` instead.

```bash
scripts/make_minimal_usmap.py minimal.usmap
kismet-analyzer --ue-version VER_UE5_7 -m minimal.usmap to-json extracted/legacy/.../BP_LobbyGameMode.uasset \
  > BP_LobbyGameMode.json
scripts/kismet_pseudocode.py BP_LobbyGameMode.json "More Than 4"
```

The pseudo-code prints one statement per line, resolves called functions and objects by name, and shows jumps as
byte offsets. Latent nodes and the event graph (`ExecuteUbergraph_*`) jump around a lot; read events through the
small stub functions (`K2_PostLogin`, custom events) that call into it with an entry offset.

### Facts that save time

- **No AES key needed.** The containers aren't encrypted (see [game-internals.md](game-internals.md)).
- **Oodle.** Every tool needs the Oodle decompressor. retoc and FModel download it on first run; nothing in Python's
  standard library can read these files.
- **Unversioned properties.** Cooked assets omit property names, so readers need the game's `.usmap` mappings
  file. Dump it with UE4SS (`DumpUSMAP()`, or the GUI's Dumpers tab) and pass it to the tool.
- **UE4SS source is partly private.** UE4SS's Unreal layer (UEPseudo) is a private repository, so how hooks expose
  the parameters of a native function called from Blueprint can't be checked in source. Prefer hooks that read
  object properties, or call UFunctions from Lua, over hooks that read call parameters.
- **Engine version.** Tell tools the game is `UE5_7`.

Unpack into a scratch directory outside this repository; extracted game assets are never committed.

## What to read first

For lobby and session work: `BP_MyGameInstance`, `BP_Lobby_FunctionLibrairy`, `BP_LobbyGameMode` and
`BP_PlayableGameMode` under `/Game/Blueprints/`. Search the manifest for others:

```bash
grep -i -E "lobby|session|gamemode" "<install>/Manifest_UFSFiles_Win64.txt"
```
