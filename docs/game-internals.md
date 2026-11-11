# Game internals

What Species Unknown is built from, as far as it matters for modding. Everything here was read from the
installed build of 2026-11-06 (Steam app `2747330`). Re-check after a game update.

## Engine and build

- **Unreal Engine 5.7**, changelist `++UE5+Release-5.7-CL-51494982` (from the shipping executable).
- **Shipping build.** The in-game console is compiled out and the game writes no log to `Saved/Logs`.
  UE4SS restores both (see [ue4ss.md](ue4ss.md)).
- **Blueprint-only gameplay.** The executable has no `/Script/SpeciesUnknown` module: every game system is a
  Blueprint under `/Game/...`. In practice:
  - Lua mods hook engine and plugin functions (`/Script/Engine...`, `/Script/OnlineSubsystemBlueprints...`) or
    the game's Blueprint functions (`/Game/...`).
  - There is no game C++ to read; game logic is Kismet bytecode inside the cooked assets.
- **Native plugins compiled in** (from reflection strings): Redpoint EOS Online Framework (`RedpointEOS*`,
  `OnlineSubsystemRedpointEOS`), OnlineSubsystemBlueprints, OnlineSubsystemSteam, VaRest, StateTree, Sentry crash
  reporting, MetaHuman SDK runtime.
- **No mod loader or mod SDK ships with the game.** Mods load through stock UE pak loading and the community
  UE4SS loader.
- **The game detects UE4SS.** The title screen's play page (`WBP_TitleScreen_PlayPage`) calls `IsUsingUE4SS()`. When
  it's true, the page shows the `ST_MainMenu.MODWrningMsg` banner ("Installed mods detected. Mods are not supported
  yet, please only play with mods in solo or private sessions...") and disables the Public button; Solo and Private
  stay available. This repository's mods respect that: play them solo or in private sessions. The executable references EOS Anti-Cheat functions (part of the Redpoint plugin), but no anti-cheat
  binaries are installed, so nothing blocks DLL injection or extra paks.

## Content containers

All in `SpeciesUnknown/Content/Paks/`:

| File | Format | Holds |
|------|--------|-------|
| `SpeciesUnknown-Windows.pak` | Pak v12, Oodle | Config `.ini` files and other loose (non-asset) files |
| `SpeciesUnknown-Windows.utoc` / `.ucas` | IoStore TOC v8, Oodle | Every cooked asset (~25,000 chunks) |
| `global.utoc` / `global.ucas` | IoStore | Script objects shared by all containers |

- **Not encrypted.** The pak's encryption key GUID is all zeros, its index is unencrypted, and the IoStore container
  flags are `Compressed | Indexed` with no `Encrypted` or `Signed` bit. No AES key is needed to read assets or to
  load new paks.
- **Oodle compressed.** Reading assets needs a tool that bundles or downloads the Oodle decompressor (see
  [reverse-engineering.md](reverse-engineering.md)).
- **File list without unpacking.** `Manifest_UFSFiles_Win64.txt` in the install root lists every packaged path.
  `grep` it to find assets by name.

## Assets worth knowing

| Asset | Role |
|-------|------|
| `/Game/Blueprints/Core/BP_MyGameInstance` | Game instance; persists across travel |
| `/Game/Blueprints/Core/BP_MainMenuGameMode` | Main menu |
| `/Game/Blueprints/Core/BP_LobbyGameMode` | The ship hub players gather in before a contract; a subclass of `BP_PlayableGameMode`, so "a playable game mode exists" is true in the lobby too |
| `/Game/Blueprints/Core/BP_PlayableGameMode` | Missions |
| `/Game/Blueprints/Core/BP_FirstPersonGameMode` | Base first-person mode |
| `/Game/Blueprints/Lobby/BP_Lobby_FunctionLibrairy` | Lobby helper functions (the misspelling is the game's) |
| `/Game/Blueprints/BPI/BPI_GameInstance` | Interface the game instance implements |
| `/Game/Blueprints/Online/BP_Online_FunctionLibrary` | Builds session settings (main, private by code, public) |

## Gameplay state worth knowing

Read from the Blueprint bytecode; the mods that rely on each fact link back here.

- **The ship's power** is `BP_MyGameState.LightStatut` (`LightStatutEnum`, replicated): 0 on, 1 off, 2 evacuation
  (self destruct armed; `CanLightOff` is false), 3 limited (emergency power, dimmed). `BP_GameManager` sets it at
  mission start: off, unless the contract has `PowerAtStart` (then it stays on, or limited with `EmergencyPower`).
  `OnRep_LightStatut` runs on every machine when it changes.
- **Vents** are `BP_Vent_Up` actors (`BP_Vent_Up_POLAR` on Polar): vertical shafts from a room's ceiling into the
  ducts, standing on the room's floor. Up to four billboard components (`Point1Component` to `Point4Component`) mark
  spots beside each shaft's top, inside the duct; `BPI_Vent_GetAllpointLocation` returns them. Crossing a shaft's
  `BoxOverlap` sets the monster's `InVent` (`BPI_Monster_SetInVent`, which also crouches it to fit the ducts).
  Hawking's persistent level `Maps/SpaceShip` places 265 shafts and about 970 vent navigation links
  (`Nav_Link_VentPoint_*`); its sublevels add decoration only (`BP_VentWall`, `BP_VentDoor`).
- **The camera ignores the view target.** The player camera manager (`Character_CameraBP`) overrides
  `BlueprintUpdateCamera`: while its cached crew body (`Player`) is valid, the camera sits at that body's `Camera`
  component, whatever `SetViewTarget` says. The engine's built-in `CameraStyle` values (`FreeCam`, `ThirdPerson`,
  `FirstPerson`) bypass the override, since the engine only calls it for the default style.
- **Monsters respawn when stuck.** `BP_BaseMonster."Check If Stuck"` runs every second once an AI controller
  possesses the monster. After 20 seconds without moving it calls `BP_GameManager.InitMonster(false, ...)`, which
  destroys the monster and spawns a new one. `ShouldCheckIfStuck` turns the check off.

## Paths on this machine

| What | Path |
|------|------|
| Install | `/mnt/FreightBay/SteamLibrary/steamapps/common/Species Unknown` |
| Executable | `<install>/SpeciesUnknown/Binaries/Win64/SpeciesUnknown-Win64-Shipping.exe` |
| Proton prefix | `/mnt/FreightBay/SteamLibrary/steamapps/compatdata/2747330/pfx` |
| Saved (config, saves) | `<prefix>/drive_c/users/steamuser/AppData/Local/SpeciesUnknown/Saved` |

The game runs under Proton Experimental with `-nohmd -dx11` (the launch arguments Steam passes).
