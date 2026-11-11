#!/usr/bin/env bash
# Copyright © 2026 Jalapeno Labs
#
# Compiles the editor-only asset builder and regenerates every mod's assets under unreal/SpeciesUnknown/Content/Mods/,
# in a headless UE 5.7 editor (no window; it exits when done). Each mod's HUD icons (mods/<mod>/art/icons/*.svg) are
# rendered to PNGs first, under unreal/SpeciesUnknown/Saved/ModArt/<mod>/, for the builder to import.
#
# Usage: scripts/build-mod-assets.sh
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
engine_root="${UE_5_7_ROOT:-/mnt/FreightBay/UnrealEngine/UE_5.7}"
uproject="$repository_root/unreal/SpeciesUnknown/SpeciesUnknown.uproject"
build_script="$repository_root/unreal/SpeciesUnknown/Scripts/build_mod_assets.py"
log_file="$repository_root/unreal/SpeciesUnknown/Saved/Logs/build-mod-assets.log"
rendered_art_root="$repository_root/unreal/SpeciesUnknown/Saved/ModArt"
# The size each icon is rendered at; the HUD draws them at about a third of this, so they stay sharp on 4K screens.
icon_pixels=128

shopt -s nullglob
for icon_source in "$repository_root"/mods/*/art/icons/*.svg; do
  mod_name="$(basename "$(dirname "$(dirname "$(dirname "$icon_source")")")")"
  mkdir -p "$rendered_art_root/$mod_name"
  nice -n 19 rsvg-convert --width "$icon_pixels" --height "$icon_pixels" "$icon_source" \
    --output "$rendered_art_root/$mod_name/$(basename "${icon_source%.svg}").png"
done

# The real path matters: Unreal's build accelerator fails on projects reached through a symlink.
"$engine_root/Engine/Build/BatchFiles/Linux/Build.sh" SpeciesUnknownEditor Linux Development \
  -project="$uproject" -WaitMutex

mkdir -p "$(dirname "$log_file")"
echo "Generating mod assets (log: ${log_file#"$repository_root"/})"
if ! "$engine_root/Engine/Binaries/Linux/UnrealEditor-Cmd" "$uproject" -run=pythonscript -script="$build_script" \
    -unattended -nosplash -nullrhi -stdout >"$log_file" 2>&1; then
  grep -E "Error|\[build_mod_assets\]|LogSpeciesUnknownModKit" "$log_file" | tail -20 >&2
  echo "Asset generation failed; full log at $log_file" >&2
  exit 1
fi

grep -E "\[build_mod_assets\]|LogSpeciesUnknownModKit" "$log_file"
