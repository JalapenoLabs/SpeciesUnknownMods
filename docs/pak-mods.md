# Pak mods (assets and Blueprints)

A pak mod ships cooked assets that the game mounts on top of its own. Use one when a mod needs content that Lua
can't create: new or replaced meshes, textures, sounds, widgets or Blueprint classes. For behaviour changes, prefer
a [UE4SS Lua mod](ue4ss.md); it needs no editor and survives game patches better.

## Format the game loads

The game is UE 5.7 with IoStore (see [game-internals.md](game-internals.md)). A mod container is the same
three-file set as the game's own, with the `_P` suffix that makes it win over the base game:

```text
SpeciesUnknown/Content/Paks/~mods/
  MyMod_P.pak     empty pak; the engine only finds a .utoc through a mounted .pak of the same name
  MyMod_P.utoc    IoStore table of contents, with its own directory index
  MyMod_P.ucas    IoStore package data
```

- The game's containers are unencrypted and unsigned, so mod containers need no key and no signature.
- Asset paths must match the game's (`/Game/...`) to replace an asset. A new asset goes under
  `/Game/Mods/<ModName>/`.

## Building

Everything lives in `unreal/SpeciesUnknown/`, a UE **5.7.4** project named after the game so cooked paths come
out as `/Game/...`. 5.7.4 is the game's exact engine build (changelist 51494982). One command does the whole build:

```bash
scripts/package-mods.sh            # writes dist/paks/<Mod>_P.{pak,utoc,ucas}
scripts/package-mods.sh --install  # also copies them into the game's Content/Paks/~mods/ (game must be closed)
```

What it does:

1. **Generates the assets** from code (`scripts/build-mod-assets.sh`): an editor-only C++ module,
   `Source/SpeciesUnknownModKit`, turns each mod's asset specs into assets under `Content/Mods/<Mod>/`: network
   actors, widgets (text, bars, images, key caps and rows of them) and UI textures imported from the mod's rendered
   icons. Those assets are build output and are not committed; the C++ and the SVGs are the source.
2. **Cooks for Linux**, unversioned, in a headless editor. The Linux engine build can't cook for Windows, and it
   doesn't need to: Blueprints and uncompressed UI textures (`TC_EditorIcon`, no mips) cook the same for both
   desktop platforms, and IoStore containers are platform-neutral. Compressed textures would need checking first.
   `Config/DefaultGame.ini` tells the cooker to include `/Game/Mods`, which nothing else references.
3. **Packs one container per mod** with `UnrealPak`, the packager that built the game, using the same commands UAT
   runs for a packaged build (`-CreateGlobalContainer` with a `-Commands` file). The global container it also
   writes is discarded; the game ships its own.
4. **Writes an empty `.pak`** beside each container.

Packages a mod ships may import only native classes that exist in the game. A container can be checked against the
game's own script objects by converting it back with retoc next to the game's `global.utoc` (see
[reverse-engineering.md](reverse-engineering.md)): any unresolved import fails the conversion.

`retoc to-zen` cannot build these containers: release v0.1.5 doesn't read the UE 5.7 `ImportTypeHierarchies`
summary field that 5.7.4 cooks write. Its master branch has the fix, but there's no release with it yet.

## Blueprint logic mods

UE4SS's bundled **BPModLoaderMod** loads Blueprint actors from paks in `Content/Paks/LogicMods/`, spawns each mod's
`ModActor` and calls into it. That lets a Blueprint-authored mod run code without replacing any game asset. Use it
when a mod's logic is easier to build in Blueprint than in Lua, for example UI built from game widgets.

## Who needs the mod

A pak mod that changes anything replicated (actor classes, their properties, RPCs) must be installed by every
player, or clients and host disagree on the class layout and the connection breaks. Purely cosmetic replacements
(a texture, a sound) can be installed by individual players. See [multiplayer.md](multiplayer.md).
