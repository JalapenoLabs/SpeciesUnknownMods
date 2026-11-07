# Species Unknown Mods

Monorepo of Species Unknown (UE 5.7, Blueprint-only, Redpoint EOS) mods. Read `README.md` and the relevant files in
`docs/` before working on a mod; keep `docs/` current as decisions are made.

- Prefer UE4SS Lua mods; reach for pak mods only when new assets are unavoidable.
- Prefer host-only designs. Each mod's README states who must install it.
- Follow `docs/repository.md` for layout: `mods/<kebab-name>/` with a PascalCase payload folder, `cover.svg` + `cover.png`.
- The user plays the game on this machine. Never launch it, never write into the game install while it runs
  (`pgrep -f SpeciesUnknown-Win64-Shipping`), and run heavy work (Unreal Editor, cooks, big unpacks) only when asked.
- Gameplay verification is done by the user: hand over the mod README's test plan instead of claiming it works.
- Extracted game assets stay outside the repository.
