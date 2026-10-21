#!/usr/bin/env bash
# Adds translation keys to all 9 languages (see add-keys.lua). The lock lets several workers run it at once.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec flock .cache/translations.lock lua5.1 tools/translations/add-keys.lua "$@"
