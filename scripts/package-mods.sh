#!/usr/bin/env bash
# Copyright © 2026 Jalapeno Labs
#
# Builds every mod's pak: regenerates the Blueprint assets, cooks them, and packs each mod's
# unreal/SpeciesUnknown/Content/Mods/<Mod>/ folder into its own IoStore container, <Mod>_P.{pak,utoc,ucas}, in
# dist/paks/. With --install, also copies the paks into the game's Content/Paks/~mods/ (only while the game is closed).
#
# Usage: scripts/package-mods.sh [--install] [Mod ...]   (payload folder names; every mod by default). Each mod is
# built and packed on its own, so one failing still leaves the others packed (and installed); the script then fails.
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
requested_mods=()
for argument in "$@"; do
  case "$argument" in
    --install) should_install=true ;;
    -*) echo "Unknown option: $argument (expected --install)" >&2; exit 2 ;;
    *) requested_mods+=("$argument") ;;
  esac
done

# /////////////////////// //
#    Assets and cook     #
# /////////////////////// //

# Each mod's assets build on their own; the mods that built go on to be packed, and any that failed are reported at
# the end, after the others are packed and installed
failed_mods=()
built_list="$project_directory/Saved/ModPackaging/built-mods.txt"
if ! "$repository_root/scripts/build-mod-assets.sh" "${requested_mods[@]}"; then
  failed_mods+=("assets")
fi
mapfile -t built_mods <"$built_list"
if [[ ${#built_mods[@]} -eq 0 ]]; then
  echo "No mod's assets built; nothing to pack" >&2
  exit 1
fi

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
mkdir -p "$output_directory"
empty_response_file="$work_directory/empty.txt"
: >"$empty_response_file"

# Packs one mod's cooked content into its own container, in its own packager run, so one mod's failure leaves the
# others packed.
pack_mod() {
  local mod_name="$1"
  local mod_directory="$mod_content_root/$mod_name"
  local response_file="$work_directory/$mod_name.txt"
  local commands_file="$work_directory/$mod_name-commands.txt"
  local iostore_log="$work_directory/$mod_name-iostore.log"
  if [[ ! -d "$mod_directory" ]]; then
    echo "The cook produced no content for $mod_name under $mod_content_root" >&2
    return 1
  fi
  rm -f "$output_directory/${mod_name}_P".*

  # One line per package: the cooked .uasset and its path inside the game. The packager reads each package's .uexp
  # from beside its .uasset on its own, so .uexp files are not listed.
  while IFS= read -r -d '' package_file; do
    printf '"%s" "../../../SpeciesUnknown/Content/Mods/%s"\n' "$package_file" "${package_file#"$mod_content_root"/}"
  done < <(find "$mod_directory" -name '*.uasset' -print0 | sort -z) >"$response_file"
  printf -- '-Output=%s -ContainerName=%s_P -ResponseFile=%s\n' \
    "$output_directory/${mod_name}_P.utoc" "$mod_name" "$response_file" >"$commands_file"

  if ! nice -n 19 ionice -c 3 "$unreal_pak" "$uproject" -CreateGlobalContainer="$work_directory/$mod_name-global.utoc" \
      -PackageStoreManifest="$cooked_root/SpeciesUnknown/Metadata/packagestore.manifest" \
      -CookedDirectory="$cooked_root" -Commands="$commands_file" \
      -ScriptObjects="$cooked_root/SpeciesUnknown/Metadata/scriptobjects.bin" -unattended \
      >"$iostore_log" 2>&1; then
    grep -E "Error|Warning" "$iostore_log" | tail -20 >&2
    echo "Packing $mod_name failed; full log at $iostore_log" >&2
    return 1
  fi
  if grep -q "Warning:" "$iostore_log"; then
    grep "Warning:" "$iostore_log" >&2
    echo "Packing $mod_name produced warnings; treating them as a failure (log: $iostore_log)" >&2
    return 1
  fi

  # The engine finds a .utoc only through a mounted .pak of the same name, so each container gets an empty one
  "$unreal_pak" "$output_directory/${mod_name}_P.pak" -create="$empty_response_file" -unattended \
    >"$work_directory/$mod_name-pak.log" 2>&1
  echo "Packed dist/paks/${mod_name}_P.{pak,utoc,ucas}"
}

packed_mods=()
for mod_name in "${built_mods[@]}"; do
  if pack_mod "$mod_name"; then
    packed_mods+=("$mod_name")
  else
    failed_mods+=("$mod_name")
  fi
done

# /////////////////////// //
#        Install         #
# /////////////////////// //

if [[ "$should_install" == true && ${#packed_mods[@]} -gt 0 ]]; then
  if pgrep -f SpeciesUnknown-Win64-Shipping >/dev/null; then
    echo "The game is running; not installing. Close it and run with --install again." >&2
    exit 1
  fi
  mods_paks_directory="$game_directory/SpeciesUnknown/Content/Paks/~mods"
  mkdir -p "$mods_paks_directory"
  for mod_name in "${packed_mods[@]}"; do
    cp "$output_directory/${mod_name}_P".* "$mods_paks_directory/"
    echo "Installed ${mod_name}_P into ${mods_paks_directory}"
  done
fi

if [[ ${#failed_mods[@]} -gt 0 ]]; then
  echo "Failed: ${failed_mods[*]}; packed anyway: ${packed_mods[*]:-none}" >&2
  exit 1
fi
