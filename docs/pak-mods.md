# Pak mods (assets and Blueprints)

A pak mod ships cooked assets that the game mounts on top of its own. Use one when a mod needs content that Lua
can't create: new or replaced meshes, textures, sounds, widgets or Blueprint classes. For behaviour changes, prefer
a [UE4SS Lua mod](ue4ss.md); it needs no editor and survives game patches better.

No pak mod exists in this repository yet. This page records the format the game needs, so the first one starts
from the right place.

## Format the game loads

The game is UE 5.7 with IoStore (see [game-internals.md](game-internals.md)). A mod container is therefore the
same three-file set as the game's own, with the `_P` suffix that makes it win over the base game:

```text
SpeciesUnknown/Content/Paks/~mods/
  MyMod_P.pak     small pak, holds the container's metadata
  MyMod_P.utoc    IoStore table of contents
  MyMod_P.ucas    IoStore asset data
```

- The game's containers are unencrypted and unsigned, so mod containers need no key and no signature.
- A legacy `.pak` full of `.uasset` files doesn't load on its own in an IoStore game. Convert it to IoStore with
  [retoc](https://github.com/trumank/retoc) (`retoc to-zen`), or have the editor write IoStore output directly.
- Asset paths must match the game's (`/Game/...`) to replace an asset. A new asset goes under a mod-specific path
  such as `/Game/Mods/<ModName>/`.

## Building one

1. Make an empty UE **5.7** project named `SpeciesUnknown`, so cooked paths come out as `/Game/...` under the
   right project. The engine version must match: assets cooked by another version won't load.
2. Recreate any game asset the mod replaces at the same path. A placeholder is fine for anything only referenced.
3. Cook for Windows, then package the mod's directory into an IoStore container. Use chunk assignment
   (Primary Asset Labels) so only mod assets go into the mod container.
4. Copy the `_P` triple into `Content/Paks/~mods/`.

Building needs the Unreal Editor and a shader cook, which uses a lot of CPU and GPU. Don't do it while the game
is running.

## Blueprint logic mods

UE4SS's bundled **BPModLoaderMod** loads Blueprint actors from paks in `Content/Paks/LogicMods/`, spawns each mod's
`ModActor` and calls into it. That lets a Blueprint-authored mod run code without replacing any game asset. Use it
when a mod's logic is easier to build in Blueprint than in Lua, for example UI built from game widgets.

## Who needs the mod

A pak mod that changes anything replicated (actor classes, their properties, RPCs) must be installed by every
player, or clients and host disagree on the class layout and the connection breaks. Purely cosmetic replacements
(a texture, a sound) can be installed by individual players. See [multiplayer.md](multiplayer.md).
