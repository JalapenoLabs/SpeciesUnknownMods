#!/usr/bin/env bash
# Copyright © 2026 Jalapeno Labs
#
# Syntax-checks every mod's Lua and runs every mod's offline tests (mods/*/tests/*_test.lua) against the fake
# UE4SS in mods/controllable-entity/tests/fake_ue4ss.lua. They prove each mod's wiring and rules; only a playtest
# proves the game agrees.
#
# Usage: scripts/test-mods.sh
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repository_root"

shopt -s nullglob globstar
lua_files=(mods/*/*/Scripts/**/*.lua)
luac -p "${lua_files[@]}"
echo "Syntax OK: ${#lua_files[@]} Lua files"

failures=0
for test_file in mods/*/tests/*_test.lua; do
  if ! lua "$test_file" | grep -v -E '^\[[A-Za-z]+\]|^$'; then
    echo "FAILED: $test_file" >&2
    failures=$((failures + 1))
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "$failures test file(s) failed" >&2
  exit 1
fi
