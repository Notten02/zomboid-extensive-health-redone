#!/usr/bin/env bash
# Starts a local, non-Steam dedicated server from the game install with this mod, for a load test with
# tools/mp-client.sh. It never touches ~/Zomboid: the server has its own cache dir.
#
#   tools/mp-server.sh            deploy the mod, write or patch the server config, start the server (foreground)
#
# Stop it with `quit` on its console. Settings (environment variables, all optional):
#   EHR_MPTEST_DIR      root of the test cache dirs        default: <repo>/.cache/mptest (git-ignored)
#   EHR_SERVER_NAME     server name (config file names)    default: ehrload
#   EHR_ADMIN_PASSWORD  password of the "admin" account    default: admin
#   EHR_MOD_ID          the Mods= entry                     default: ExtensiveHealthRedone (see Untested below)
#   EHR_SERVER_DEBUG    1 passes -debug to the server       default: 1
#   PZ_GAME_DIR         the game's projectzomboid folder    default: under /mnt/games/Steam (see GAME below)
#
# What it does on every start:
#   1. tools/deploy-dev.sh into <cache>/Workshop, so the server and every client load the same copy;
#   2. <cache>/Server/<name>.ini: written with our keys on the first start, patched on later starts (Mods,
#      WorkshopItems, Open, Public, MaxPlayers, PauseEmpty);
#   3. <cache>/Server/<name>_SandboxVars.lua: ExtensiveHealthRework.DebugMode = true once the server has written the
#      file (the first start writes it; stop the server and run this script again to switch debug mode on).
#
# Untested assumptions:
#   - that 42.21 keeps a hand-written partial ini and fills in the missing keys (if it overwrites it, the patch step
#     of the next start sets our keys again);
#   - the Mods= format. Vanilla's settings screen writes the plain mod ids joined with ';'. B42 mod.info files refer to
#     other mods as "\ModId"; if the server log says our mod is not found, try EHR_MOD_ID='\ExtensiveHealthRedone';
#   - the SandboxVars layout (4-space indented blocks closed by "    },"), which the DebugMode edit relies on;
#   - that -debug on the dedicated server is harmless and lets -debug clients join.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${EHR_MPTEST_DIR:-$REPO/.cache/mptest}"
NAME="${EHR_SERVER_NAME:-ehrload}"
ADMIN_PASSWORD="${EHR_ADMIN_PASSWORD:-admin}"
MOD_ID="${EHR_MOD_ID:-ExtensiveHealthRedone}"
GAME="${PZ_GAME_DIR:-/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid}"
CACHE="$ROOT/server"
INI="$CACHE/Server/$NAME.ini"
SANDBOX="$CACHE/Server/${NAME}_SandboxVars.lua"

if [ ! -x "$GAME/start-server.sh" ]; then
    echo "no start-server.sh in $GAME (set PZ_GAME_DIR)" >&2
    exit 1
fi

mkdir -p "$CACHE/Server"
ZOMBOID_DIR="$CACHE" "$REPO/tools/deploy-dev.sh"
# A non-Steam dedicated server doesn't look in Workshop/ (42.21: "required mod ... not found"); it finds local mods
# in <cache>/mods/<id>. A copy again, never a symlink (see tools/deploy-dev.sh).
mkdir -p "$CACHE/mods/ExtensiveHealthRedone"
rsync -a --delete "$REPO/Contents/mods/ExtensiveHealthRedone/" "$CACHE/mods/ExtensiveHealthRedone/"
echo "copied the mod -> $CACHE/mods/ExtensiveHealthRedone"

# key=value in the ini: replace the line, or append it when the key is missing.
set_key() {
    local key="$1" value="$2"
    if grep -q "^$key=" "$INI"; then
        # '|' as the sed delimiter; escape backslashes and '&' in the value for the replacement.
        local escaped
        escaped="$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')"
        sed -i "s|^$key=.*|$key=$escaped|" "$INI"
    else
        printf '%s=%s\n' "$key" "$value" >> "$INI"
    fi
}

if [ ! -f "$INI" ]; then
    echo "writing a new $INI (the server adds its other defaults on start)"
    printf '# Written by tools/mp-server.sh for the EHR load test.\n' > "$INI"
fi
set_key Mods "$MOD_ID"
set_key WorkshopItems ""             # non-Steam server: the mod comes from the cache dir's Workshop folder
set_key Open true                    # accounts are created on first login
set_key Public false
set_key MaxPlayers 8
set_key PauseEmpty true              # idle time between runs costs nothing

if [ -f "$SANDBOX" ]; then
    # Only inside the ExtensiveHealthRework = { ... } block.
    if grep -q "ExtensiveHealthRework" "$SANDBOX"; then
        sed -i '/ExtensiveHealthRework = {/,/^    },/ s/DebugMode = false/DebugMode = true/' "$SANDBOX"
        if grep -A200 "ExtensiveHealthRework = {" "$SANDBOX" | grep -q "DebugMode = true"; then
            echo "sandbox: ExtensiveHealthRework.DebugMode = true"
        else
            echo "WARNING: could not find ExtensiveHealthRework.DebugMode in $SANDBOX; set it by hand" >&2
        fi
    else
        echo "WARNING: $SANDBOX has no ExtensiveHealthRework options: is the mod loaded? (check Mods= in $INI)" >&2
    fi
else
    echo "first start: $SANDBOX does not exist yet. Let the server start, type 'quit', and run this script again"
    echo "so it can switch ExtensiveHealthRework.DebugMode on (the debug window and the perf commands need it)."
fi

ARGS=(-cachedir="$CACHE" -servername "$NAME" -adminusername admin -adminpassword "$ADMIN_PASSWORD")
if [ "${EHR_SERVER_DEBUG:-1}" = "1" ]; then
    ARGS+=(-debug)
fi

cat <<EOF

Server '$NAME', cache dir $CACHE
  log:        $CACHE/server-console.txt  (rotated logs in $CACHE/Logs/)
  config:     $INI
  sandbox:    $SANDBOX
  admin:      admin / $ADMIN_PASSWORD
  clients:    tools/mp-client.sh 1, tools/mp-client.sh 2, ... then Join -> 127.0.0.1, port 16261
  ready when: grep 'authority started' $CACHE/server-console.txt
  stop:       type 'quit' here

EOF

cd "$GAME"
exec ./start-server.sh "${ARGS[@]}"
