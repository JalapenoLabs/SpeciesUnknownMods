# UE4SS (Lua mods)

[RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) injects into the game, finds Unreal's object system and runs Lua
mods that can read and write any reflected property and hook any `UFunction`. It is the default way to mod
Species Unknown: it needs no Unreal editor, and a mod is a folder with a Lua file in it.

Use a Lua mod whenever the change is behaviour: numbers, rules, hooks on game events. Use a
[pak mod](pak-mods.md) only when the change needs new or replaced assets (meshes, textures, Blueprints).

## Installing UE4SS

The 2024 stable release, `v3.0.1`, predates UE 5.7 and will not attach to this game. Use the experimental build.

1. Download the newest non-`zDEV` `UE4SS_v3.0.1-<build>.zip` from the
   [`experimental2` release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental2), which lists UE 5.7
   support. Use the `zDEV-` zip instead when building a mod: it shows the console and the GUI by default.
2. Extract it into `SpeciesUnknown/Binaries/Win64/`. The result:

   ```text
   Win64/
     SpeciesUnknown-Win64-Shipping.exe
     dwmapi.dll                 proxy that loads UE4SS
     ue4ss/
       UE4SS.dll
       UE4SS-settings.ini
       UE4SS.log                written on every launch
       Mods/
         mods.txt
         shared/                UEHelpers and other Lua libraries
         <ModName>/Scripts/main.lua
   ```

3. Proton loads its own `dwmapi.dll` unless told otherwise. In Steam, set the game's launch options to:

   ```text
   WINEDLLOVERRIDES="dwmapi=n,b" %command%
   ```

4. Launch the game and check `ue4ss/UE4SS.log`. A working install finishes its signature scan and lists the Lua
   mods it started. If the log stops during the scan, this build's patterns don't match the game: the community's
   UE 5.7 signature pack on Nexus ([Species Unknown mod 3](https://www.nexusmods.com/speciesunknown/mods/3)) covers
   that case. Its exact contents are still to be documented here.

To launch once without UE4SS while keeping it installed, add `--disable-ue4ss` to the launch options.

For development and playtests, turn on these keys in `ue4ss/UE4SS-settings.ini` (all are 0 in the standard build):

| Key | Gives |
|-----|-------|
| `ConsoleEnabled = 1` | The console window with live mod output |
| `GuiConsoleEnabled = 1`, `GuiConsoleVisible = 1` | The GUI: Live View and the Dumpers tab (`.usmap`, `.jmap`) |
| `EnableHotReloadSystem = 1` | `Ctrl+R` restarts every Lua mod without restarting the game |

## Mod layout

```text
Mods/<ModName>/
  enabled.txt          empty file; enables the mod without editing mods.txt
  Scripts/main.lua     entry point, runs once when UE4SS starts mods
```

- The folder name is the mod's name in logs and in `mods.txt`. Use PascalCase (`UnlimitedLobbySize`).
- `enabled.txt` always loads the mod, whatever `mods.txt` says. That is the simplest install for players. The
  catch is that it gives no load order; if a mod ever depends on another, list both in `mods.txt` instead,
  above the `Keybinds` line.
- `require("UEHelpers")` resolves from `Mods/shared/`. It wraps the usual lookups: `GetWorld()`,
  `GetPlayerController()`, `GetGameModeBase()`, `GetKismetSystemLibrary()` and so on.

## Hooks

`RegisterHook("<function path>", callback)`:

- **Native functions (`/Script/...`)**: the callback runs *before* the function, so it can change inputs. An
  optional second callback runs after.
- **Blueprint functions (`/Game/...`)**: the callback runs *after* the function. There is no pre-hook.
- The callback gets the object the function was called on (`context:get()`) followed by each parameter as a
  remote param (`param:get()`, `param:set(value)`).
- The `UFunction` must already be loaded when `RegisterHook` runs. Engine and plugin functions always are. A
  Blueprint function is loaded only once its asset is, so register those from a `NotifyOnNewObject` callback or a
  `RegisterBeginPlayPostHook` once the owning actor exists.

### Changing what an async Blueprint node does

Most online calls in this game are async Blueprint nodes (OnlineSubsystemBlueprints `CreateSession`,
`FindSessions` and others). Each node class copies its inputs into reflected properties named `__Store__<Param>`
when the Blueprint calls it, and its native `Activate()` reads them back. A pre-hook on
`/Script/Engine.BlueprintAsyncActionBase:Activate` can therefore rewrite any input of any such node, keyed on the
node's class name (`node:GetClass():GetFName():ToString()`). That stays stable across game patches because it
depends on plugin names, not the game's Blueprint names.
[Unlimited Lobby Size](../mods/unlimited-lobby-size/README.md) is the worked example.

## Development loop

- Link a mod from this repository into the game instead of copying it: `scripts/link-mod.sh <mod-directory>`.
  Wine follows the symlink, so edits in the repository are what the game loads.
- Set `EnableHotReloadSystem = 1` in `UE4SS-settings.ini`; then `Ctrl+R` restarts every Lua mod without
  restarting the game. The GUI console's "Restart All Mods" button does the same.
- Anything a mod `print`s goes to `ue4ss/UE4SS.log` and to the UE4SS console. End messages with `\n` and start them
  with `[<ModName>]` so they're easy to grep.
- The bundled `ConsoleEnablerMod` gives the shipping build its console back (`F10` or `@`), which is the quickest
  way to read or set console variables while testing.

## Discovering what to hook

The game's own classes are Blueprints, so their functions and properties only exist once loaded. UE4SS can dump
them from a running game:

- **Live View** (GUI console, `zDEV` build) browses every loaded object, its properties and functions.
- **`DumpJMAP()`** (Lua) or `Ctrl+Numpad 5` writes the whole reflection graph, including Blueprint classes, to a
  `.jmap` JSON file. `grep` it for function names and parameter layouts.
- The `.usmap` dumper writes the mappings file that asset tools need to read unversioned properties (see
  [reverse-engineering.md](reverse-engineering.md)).

The dumps show function signatures only. To read what a Blueprint function actually does, unpack its asset.
