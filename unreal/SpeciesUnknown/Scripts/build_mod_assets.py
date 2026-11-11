"""Build the mods' generated Blueprint assets, from inside the Unreal editor.

The assets themselves are defined in C++ (Source/SpeciesUnknownModKit); this script only runs those builders.
Run it through scripts/build-mod-assets.sh at the repository root, which starts a headless editor for it.

Arguments: the file to write the names of the mods that built to, then the mods to build (every mod when none are
named). Each mod builds on its own, so one mod failing doesn't stop the others; the caller packs those that built.
"""

from __future__ import annotations

import sys
from pathlib import Path

import unreal

# Each mod's build function on unreal.ModAssetBuildLibrary, so adding a mod is one line. Names, not function
# objects: an Unreal object still referenced from module scope when the editor exits crashes Python's shutdown
# (Py_FinalizeEx), after the asset has already been saved.
_MOD_BUILDER_NAMES = {
    "ControllableEntity": "build_controllable_entity_assets",
}


def main() -> None:
    """Build each asked-for mod, record those that built, and exit non-zero if any failed or is unknown."""
    built_list_path = Path(sys.argv[1])
    asked_mods = sys.argv[2:] or list(_MOD_BUILDER_NAMES)

    built_mods: list[str] = []
    failed_mods: list[str] = []
    for mod_name in asked_mods:
        builder_name = _MOD_BUILDER_NAMES.get(mod_name)
        if builder_name is None:
            unreal.log_error(f"[build_mod_assets] No asset builder for {mod_name}")
            failed_mods.append(mod_name)
            continue
        unreal.log(f"[build_mod_assets] Building {mod_name}")
        build = getattr(unreal.ModAssetBuildLibrary, builder_name)
        if build():
            built_mods.append(mod_name)
        else:
            failed_mods.append(mod_name)

    built_list_path.write_text("".join(f"{mod_name}\n" for mod_name in built_mods))
    unreal.log(f"[build_mod_assets] Built: {', '.join(built_mods) or 'none'}")
    if failed_mods:
        unreal.log_error(f"[build_mod_assets] Failed: {', '.join(failed_mods)}")
        sys.exit(1)


main()
