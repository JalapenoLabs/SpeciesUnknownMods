#!/usr/bin/env bash
# Copyright © 2026 Jalapeno Labs
#
# Symlinks a mod's payload into the game's UE4SS Mods directory, so the game loads it straight from this repository.
# Wine follows the symlink, so there is nothing to copy back and forth while developing.
#
# Usage: scripts/link-mod.sh <mod-name>        e.g. scripts/link-mod.sh unlimited-lobby-size
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
game_directory="${SPECIES_UNKNOWN_DIR:-/mnt/FreightBay/SteamLibrary/steamapps/common/Species Unknown}"
ue4ss_mods_directory="$game_directory/SpeciesUnknown/Binaries/Win64/ue4ss/Mods"

mod_name="${1:-}"
if [[ -z "$mod_name" ]]; then
  echo "Usage: $0 <mod-name>   (a directory under mods/)" >&2
  exit 1
fi

mod_directory="$repository_root/mods/$mod_name"
if [[ ! -d "$mod_directory" ]]; then
  echo "No mod at $mod_directory" >&2
  exit 1
fi

if [[ ! -d "$ue4ss_mods_directory" ]]; then
  echo "UE4SS isn't installed: $ue4ss_mods_directory doesn't exist. See docs/ue4ss.md." >&2
  exit 1
fi

# The payload is the one subdirectory holding Scripts/main.lua (docs/repository.md).
payload_scripts=("$mod_directory"/*/Scripts/main.lua)
if [[ ${#payload_scripts[@]} -ne 1 || ! -f "${payload_scripts[0]}" ]]; then
  echo "Expected exactly one <Payload>/Scripts/main.lua in $mod_directory" >&2
  exit 1
fi
payload_directory="$(dirname "$(dirname "${payload_scripts[0]}")")"
link_path="$ue4ss_mods_directory/$(basename "$payload_directory")"

if [[ -L "$link_path" && "$(readlink "$link_path")" == "$payload_directory" ]]; then
  echo "Already linked: $link_path"
  exit 0
fi

if [[ -e "$link_path" || -L "$link_path" ]]; then
  echo "$link_path already exists and isn't a link to this repository; move it aside first." >&2
  exit 1
fi

ln -s "$payload_directory" "$link_path"
echo "Linked $link_path -> $payload_directory"

if pgrep -f SpeciesUnknown-Win64-Shipping >/dev/null; then
  echo "The game is running; the mod loads on the next launch (or after a UE4SS hot reload)."
fi
