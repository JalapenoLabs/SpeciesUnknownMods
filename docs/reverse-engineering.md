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
| [kismet-analyzer](https://github.com/trumank/kismet-analyzer) | Turns a Blueprint's Kismet bytecode into readable graphs |
| [UAssetGUI](https://github.com/atenfyr/UAssetGUI) | Views and edits single assets (Windows; runs under Wine) |
| [FModel](https://fmodel.app) | Browses the whole container with previews (Windows; heavier) |

Facts that save time:

- **No AES key needed.** The containers aren't encrypted (see [game-internals.md](game-internals.md)).
- **Oodle.** Every tool needs the Oodle decompressor. retoc and FModel download it on first run; nothing in Python's
  standard library can read these files.
- **Unversioned properties.** Cooked assets omit property names, so readers need the game's `.usmap` mappings
  file. Dump it with UE4SS (`DumpUSMAP()`) and pass it to the tool.
- **Engine version.** Tell tools the game is `UE5_7`.

Unpack into a scratch directory outside this repository; extracted game assets are never committed.

## What to read first

For lobby and session work: `BP_MyGameInstance`, `BP_Lobby_FunctionLibrairy`, `BP_LobbyGameMode` and
`BP_PlayableGameMode` under `/Game/Blueprints/`. Search the manifest for others:

```bash
grep -i -E "lobby|session|gamemode" "<install>/Manifest_UFSFiles_Win64.txt"
```
