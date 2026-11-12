# Species Unknown Mods

Mods for [Species Unknown](https://store.steampowered.com/app/2747330/Species_Unknown/), in one repository.

## Mods

| Mod | What it does | Who installs it | Status |
|-----|--------------|-----------------|--------|
| [Unlimited Lobby Size](mods/unlimited-lobby-size/README.md) | Raises the four-player cap to the EOS lobby limit, with standing room in the shuttle | Host only | Awaiting first playtest |
| [Controllable Entity](mods/controllable-entity/README.md) | One player becomes the monster: the squid, Mike or the Terminator | Everyone | The squid playtested alone; co-op, Mike and the Terminator next |
| [Multi Entity](mods/multi-entity/README.md) | Contracts can carry a second and a third entity, for extra bounty | Host; everyone for the bounty | Awaiting first playtest |

## Installing

Each release on the [Releases page](https://github.com/JalapenoLabs/SpeciesUnknownMods/releases) has one zip per mod.
Mods with a pak need it on every machine that installs the mod; the table above says who installs each.

1. **Find the game's folder:** in Steam, right-click Species Unknown, then Manage, then Browse local files. It is the
   folder that holds `SpeciesUnknown/`.
2. **Install UE4SS**, the mod loader, once. Download
   [`UE4SS_v3.0.1-1218-g560411f1.zip`](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental2) (the build
   these mods are tested with; the stable `v3.0.1` release predates the game's engine and won't load) and extract it
   into `SpeciesUnknown/Binaries/Win64/`, next to `SpeciesUnknown-Win64-Shipping.exe`. You should now have
   `Win64/dwmapi.dll` and a `Win64/ue4ss/` folder.
3. **Extract each mod's zip into the game's folder** (the one holding `SpeciesUnknown/`), merging folders. A zip holds
   the mod's Lua under `SpeciesUnknown/Binaries/Win64/ue4ss/Mods/` and, when it has one, its pak under
   `SpeciesUnknown/Content/Paks/~mods/`.
4. **On Linux or a Steam Deck** (Proton), also set the game's launch options in Steam to
   `WINEDLLOVERRIDES="dwmapi=n,b" %command%`, or Proton loads its own `dwmapi.dll` instead of UE4SS. Windows needs
   nothing more.
5. **Play in Solo or Private sessions.** With mods installed, the game disables public lobbies itself.

To check it worked, launch the game and open `SpeciesUnknown/Binaries/Win64/ue4ss/UE4SS.log`: each mod logs a line
when it loads (Controllable Entity's starts `[ControllableEntity] Loaded.`). To remove a mod, delete its folder under
`ue4ss/Mods/` and its `_P` files under `Content/Paks/~mods/`; to play without any mods, add `--disable-ue4ss` to the
launch options. Developers working from this repository install differently (each mod's README).

## Modding docs

| Doc | Covers |
|-----|--------|
| [game-internals.md](docs/game-internals.md) | Engine version, containers, key assets, install paths |
| [ue4ss.md](docs/ue4ss.md) | Installing UE4SS under Proton, writing and debugging Lua mods |
| [pak-mods.md](docs/pak-mods.md) | Asset and Blueprint mods as IoStore containers |
| [multiplayer.md](docs/multiplayer.md) | The online stack, and when a mod can be host-only |
| [reverse-engineering.md](docs/reverse-engineering.md) | Finding hook targets: binary strings, UE4SS dumps, unpacking assets |
| [repository.md](docs/repository.md) | How this repository is laid out and the conventions each mod follows |
