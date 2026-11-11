#!/usr/bin/env bash
# Copyright © 2026 Jalapeno Labs
#
# Packages mods for a release: one zip per mod in dist/release/, laid out from the game's install folder down, so a
# player extracts it straight into "Species Unknown/":
#
#   SpeciesUnknown/Binaries/Win64/ue4ss/Mods/<Mod>/        the Lua (Scripts/ and enabled.txt)
#   SpeciesUnknown/Content/Paks/~mods/<Mod>_P.*            the pak, for mods that have one
#
# It first builds every mod's pak fresh (scripts/package-mods.sh, without installing), so the zips hold paks built from
# the same commit as the Lua. Builds the editor and cooks: run it with the game closed if you're playing on this
# machine. UE4SS itself isn't included: players install the pinned build (README.md).
#
# Usage: scripts/package-release.sh <version> <Mod> ...   (payload folder names, as package-mods.sh takes them)
#   e.g. scripts/package-release.sh v0.1 ControllableEntity UnlimitedLobbySize
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
paks_directory="$repository_root/dist/paks"
release_directory="$repository_root/dist/release"

version="${1:-}"
payload_names=("${@:2}")
if [[ -z "$version" || ${#payload_names[@]} -eq 0 ]]; then
  echo "Usage: $0 <version> <Mod> ...   (payload folder names, e.g. ControllableEntity)" >&2
  exit 2
fi

"$repository_root/scripts/package-mods.sh"

rm -rf "$release_directory"
mkdir -p "$release_directory"
for payload_name in "${payload_names[@]}"; do
  # The payload is a mod's PascalCase folder, the one UE4SS loads (docs/repository.md): mods/<mod>/<Payload>/
  shopt -s nullglob
  payload_directories=("$repository_root"/mods/*/"$payload_name")
  shopt -u nullglob
  if [[ ${#payload_directories[@]} -ne 1 || ! -f "${payload_directories[0]}/enabled.txt" ]]; then
    echo "No mod payload named $payload_name (mods/<mod>/$payload_name/enabled.txt)" >&2
    exit 1
  fi
  payload_directory="${payload_directories[0]}"

  staging_directory="$(mktemp -d)"
  lua_destination="$staging_directory/SpeciesUnknown/Binaries/Win64/ue4ss/Mods/$payload_name"
  mkdir -p "$lua_destination"
  cp -r "$payload_directory/." "$lua_destination/"

  shopt -s nullglob
  pak_files=("$paks_directory/${payload_name}_P".*)
  shopt -u nullglob
  if [[ ${#pak_files[@]} -gt 0 ]]; then
    pak_destination="$staging_directory/SpeciesUnknown/Content/Paks/~mods"
    mkdir -p "$pak_destination"
    cp "${pak_files[@]}" "$pak_destination/"
  fi

  zip_path="$release_directory/$payload_name-$version.zip"
  (cd "$staging_directory" && zip -q -r -X "$zip_path" SpeciesUnknown)
  rm -rf "$staging_directory"
  echo "Packaged ${zip_path#"$repository_root"/} (${#pak_files[@]} pak file(s))"
done
