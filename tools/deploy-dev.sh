#!/usr/bin/env bash
# Copies the working copy into ~/Zomboid/Workshop so the game loads it as a local mod. Run it again after every change
# (the game reads the files at startup, and Lua again on a reload).
#
# A copy, not a symlink: through a symlink the game builds doubled paths and fails to read our scripts (found in
# Phase 3), and the mod list does not show it. Only Contents/ is copied: the repo's docs, tests, tools and competability/
# notes stay out.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${ZOMBOID_DIR:-$HOME/Zomboid}/Workshop/ExtensiveHealthRedone"

# Replace a symlink left by the old tools/link-dev.sh (removes the link only, never what it points to).
if [ -L "$TARGET" ]; then
    rm "$TARGET"
    echo "removed the old symlink $TARGET"
fi

mkdir -p "$TARGET"
rsync -a --delete "$REPO/Contents/" "$TARGET/Contents/"
echo "copied $REPO/Contents -> $TARGET/Contents"
