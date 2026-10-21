#!/usr/bin/env bash
# Downloads the Umbrella type stubs for Project Zomboid into .cache/umbrella, where .luarc.json expects them.
# Umbrella (https://github.com/PZ-Umbrella/Umbrella) has no licence file, so it is downloaded per developer
# and never committed or shipped. Pass a release tag to pick another game version.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-42.21.0}"
DEST=.cache/umbrella
rm -rf "$DEST"
mkdir -p "$DEST"
curl -fsSL "https://github.com/PZ-Umbrella/Umbrella/archive/refs/tags/$TAG.tar.gz" \
    | tar -xz -C "$DEST" --strip-components=1
echo "Umbrella $TAG installed in $DEST"
