#!/usr/bin/env bash
# Copyright © 2026 Jalapeno Labs
#
# Renders every mods/*/cover.svg to a 1920x1080 cover.png beside it (docs/repository.md#covers).
# Runs at the lowest CPU priority so it never competes with a running game.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

shopt -s nullglob
cover_sources=("$repository_root"/mods/*/cover.svg)
if [[ ${#cover_sources[@]} -eq 0 ]]; then
  echo "No mods/*/cover.svg found" >&2
  exit 1
fi

for cover_source in "${cover_sources[@]}"; do
  cover_render="${cover_source%.svg}.png"
  nice -n 19 rsvg-convert --width 1920 --height 1080 "$cover_source" --output "$cover_render"
  echo "Rendered ${cover_render#"$repository_root"/}"
done
