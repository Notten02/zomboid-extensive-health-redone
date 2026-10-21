#!/usr/bin/env bash
# Runs the offline checks: the Kahlua subset check, the game API check (tools/check-api.lua), then the busted specs
# under Lua 5.1.
# Extra arguments go to busted, e.g. `tools/test.sh --filter=scheduler`.
# tests/load_spec.lua (tag #load) runs a short synthetic load by default (well under a second):
# `tools/test.sh --exclude-tags=load` skips it, `tools/test.sh --tags=load` runs only it, and
# `EHR_LOAD_FULL=1 tools/test.sh --tags=load` runs 1 to 32 players for 60 game minutes each.
set -euo pipefail
cd "$(dirname "$0")/.."

for cmd in lua5.1 luac5.1; do
    command -v "$cmd" >/dev/null || { echo "missing $cmd (Arch: pacman -S lua51)" >&2; exit 1; }
done
if ! lua5.1 -e 'require("busted.runner")' 2>/dev/null; then
    echo "busted for Lua 5.1 not found (Arch: pacman -S lua51-busted)" >&2
    exit 1
fi

lua5.1 tools/check-kahlua.lua
lua5.1 tools/check-api.lua
lua5.1 tools/busted51.lua "$@"
