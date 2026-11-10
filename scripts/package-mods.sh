#!/usr/bin/env bash
# Copyright © 2026 Jalapeno Labs
#
# Builds every mod's pak: regenerates the Blueprint assets, cooks them, and packs each mod's
# unreal/SpeciesUnknown/Content/Mods/<Mod>/ folder into its own IoStore container, <Mod>_P.{pak,utoc,ucas}, in
# dist/paks/. With --install, also copies the paks into the game's Content/Paks/~mods/ (only while the game is closed).
#
# Usage: scripts/package-mods.sh [--install]
#
# How and why (docs/pak-mods.md):
# - The Linux engine build can only cook for Linux. Blueprint-only mods cook identically for both desktop platforms,
#   and IoStore containers are platform-neutral, so the Linux cook loads in the Windows game.
# - Containers are written by UnrealPak, the same packager that built the game. A global container is a byproduct of
#   that command and is discarded: the game ships its own.
# - Each container's .pak is empty. The engine finds a .utoc only through a mounted .pak of the same name.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
engine_root="${UE_5_7_ROOT:-/mnt/FreightBay/UnrealEngine/UE_5.7}"
game_directory="${SPECIES_UNKNOWN_DIR:-/mnt/FreightBay/SteamLibrary/steamapps/common/Species Unknown}"
project_directory="$repository_root/unreal/SpeciesUnknown"
uproject="$project_directory/SpeciesUnknown.uproject"
cooked_root="$project_directory/Saved/Cooked/Linux"
output_directory="$repository_root/dist/paks"
work_directory="$project_directory/Saved/ModPackaging"
unreal_pak="$engine_root/Engine/Binaries/Linux/UnrealPak"

should_install=false
for argument in "$@"; do
  case "$argument" in
    --install) should_install=true ;;
    *) echo "Unknown argument: $argument (expected --install)" >&2; exit 2 ;;
  esac
done

# /////////////////////// //
#    Assets and cook     #
# /////////////////////// //

"$repository_root/scripts/build-mod-assets.sh"

mkdir -p "$work_directory"
echo "Cooking mod content"
if ! nice -n 19 ionice -c 3 "$engine_root/Engine/Binaries/Linux/UnrealEditor-Cmd" "$uproject" -run=cook \
    -targetplatform=Linux -unversioned -unattended -nosplash -nullrhi -stdout -CrashForUAT \
    >"$work_directory/cook.log" 2>&1; then
  grep -E "Error" "$work_directory/cook.log" | tail -20 >&2
  echo "Cook failed; full log at $work_directory/cook.log" >&2
  exit 1
fi

# /////////////////////// //
#       Containers       #
# /////////////////////// //

mod_content_root="$cooked_root/SpeciesUnknown/Content/Mods"
shopt -s nullglob
mod_directories=("$mod_content_root"/*/)
if [[ ${#mod_directories[@]} -eq 0 ]]; then
  echo "The cook produced no mod content under $mod_content_root" >&2
  exit 1
fi

rm -rf "$output_directory"
mkdir -p "$output_directory"
commands_file="$work_directory/commands.txt"
: >"$commands_file"
for mod_directory in "${mod_directories[@]}"; do
  mod_name="$(basename "$mod_directory")"
  response_file="$work_directory/$mod_name.txt"

  # One line per package: the cooked .uasset and its path inside the game. The packager reads each package's .uexp
  # from beside its .uasset on its own, so .uexp files are not listed.
  while IFS= read -r -d '' package_file; do
    printf '"%s" "../../../SpeciesUnknown/Content/Mods/%s"\n' "$package_file" "${package_file#"$mod_content_root"/}"
  done < <(find "$mod_directory" -name '*.uasset' -print0 | sort -z) >"$response_file"

  printf -- '-Output=%s -ContainerName=%s_P -ResponseFile=%s\n' \
    "$output_directory/${mod_name}_P.utoc" "$mod_name" "$response_file" >>"$commands_file"
done

echo "Packing ${#mod_directories[@]} mod container(s)"
if ! nice -n 19 ionice -c 3 "$unreal_pak" "$uproject" -CreateGlobalContainer="$work_directory/global.utoc" \
    -PackageStoreManifest="$cooked_root/SpeciesUnknown/Metadata/packagestore.manifest" \
    -CookedDirectory="$cooked_root" -Commands="$commands_file" \
    -ScriptObjects="$cooked_root/SpeciesUnknown/Metadata/scriptobjects.bin" -unattended \
    >"$work_directory/iostore.log" 2>&1; then
  grep -E "Error|Warning" "$work_directory/iostore.log" | tail -20 >&2
  echo "Packing failed; full log at $work_directory/iostore.log" >&2
  exit 1
fi

if grep -q "Warning:" "$work_directory/iostore.log"; then
  grep "Warning:" "$work_directory/iostore.log" >&2
  echo "Packing produced warnings; treating them as failures (log: $work_directory/iostore.log)" >&2
  exit 1
fi

empty_response_file="$work_directory/empty.txt"
: >"$empty_response_file"
for mod_directory in "${mod_directories[@]}"; do
  mod_name="$(basename "$mod_directory")"
  "$unreal_pak" "$output_directory/${mod_name}_P.pak" -create="$empty_response_file" -unattended \
    >"$work_directory/$mod_name-pak.log" 2>&1
  echo "Packed dist/paks/${mod_name}_P.{pak,utoc,ucas}"
done

# /////////////////////// //
#        Install         #
# /////////////////////// //

if [[ "$should_install" != true ]]; then
  exit 0
fi

if pgrep -f SpeciesUnknown-Win64-Shipping >/dev/null; then
  echo "The game is running; not installing. Close it and run with --install again." >&2
  exit 1
fi

mods_paks_directory="$game_directory/SpeciesUnknown/Content/Paks/~mods"
mkdir -p "$mods_paks_directory"
cp "$output_directory"/*_P.* "$mods_paks_directory/"
echo "Installed into ${mods_paks_directory}"
