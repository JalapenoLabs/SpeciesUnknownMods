"""Build every mod's generated Blueprint assets, from inside the Unreal editor.

The assets themselves are defined in C++ (Source/SpeciesUnknownModKit); this script only runs those builders.
Run it through scripts/build-mod-assets.sh at the repository root, which starts a headless editor for it.
"""

from __future__ import annotations

import sys

import unreal

# Each mod's build function on unreal.ModAssetBuildLibrary, so adding a mod is one line. Names, not function
# objects: an Unreal object still referenced from module scope when the editor exits crashes Python's shutdown
# (Py_FinalizeEx), after the asset has already been saved.
_MOD_BUILDER_NAMES = {
    "ControllableEntity": "build_controllable_entity_assets",
}


def main() -> None:
    """Build each mod's assets, then exit non-zero if any mod failed so the calling script fails loudly."""
    failed_mods: list[str] = []
    for mod_name, builder_name in _MOD_BUILDER_NAMES.items():
        unreal.log(f"[build_mod_assets] Building {mod_name}")
        build = getattr(unreal.ModAssetBuildLibrary, builder_name)
        if not build():
            failed_mods.append(mod_name)

    if failed_mods:
        unreal.log_error(f"[build_mod_assets] Failed: {', '.join(failed_mods)}")
        sys.exit(1)

    unreal.log(f"[build_mod_assets] Built {len(_MOD_BUILDER_NAMES)} mod(s)")


main()
