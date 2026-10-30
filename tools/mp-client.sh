#!/usr/bin/env bash
# Starts game client N for a load test against tools/mp-server.sh, in the background, with its own cache dir
# (<root>/client<N>) and its own deployed copy of the mod.
#
#   tools/mp-client.sh 1          client 1 (log in as admin), then tools/mp-client.sh 2, 3 for the other players
#
# Settings (environment variables, all optional):
#   EHR_MPTEST_DIR     root of the test cache dirs          default: <repo>/.cache/mptest (same as mp-server.sh)
#   EHR_CLIENT_MODE    launcher | java                      default: launcher
#       launcher: ProjectZomboid64 -nosteam, as projectzomboid.sh starts the game. It reads ProjectZomboid64.json,
#                 which may also load a Java agent an install added there (e.g. ProjectRemnants' NPCFW.jar).
#       java:     the JVM directly with the stock arguments (those of an unmodified ProjectZomboid64.json) and
#                 -Dzomboid.steam=0, without any Java agent: cleaner numbers, changes nothing in the game folder.
#   EHR_CLIENT_XMX     client heap for java mode            default: 3072m
#   EHR_CLIENT_DEBUG   1 passes -debug (Lua console, F11)   default: 1
#   PZ_GAME_DIR        the game's projectzomboid folder     default: under /mnt/games/Steam (see GAME below)
#
# Untested assumptions:
#   - launcher mode: that -nosteam on the command line overrides the JSON's -Dzomboid.steam=1 (if it doesn't, the
#     connection to the non-Steam server fails at once; use java mode);
#   - java mode as a whole: the main class and arguments are copied from ProjectZomboid64.json, the library setup
#     from projectzomboid.sh; the native launcher may do more than that;
#   - that several clients can run at once from one install with separate -cachedir folders.
set -euo pipefail

N="${1:-}"
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
    echo "usage: tools/mp-client.sh N   (N = 1, 2, 3, ...)" >&2
    exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${EHR_MPTEST_DIR:-$REPO/.cache/mptest}"
GAME="${PZ_GAME_DIR:-/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid}"
MODE="${EHR_CLIENT_MODE:-launcher}"
CACHE="$ROOT/client$N"
OUT="$CACHE/stdout.log"

if [ ! -x "$GAME/ProjectZomboid64" ]; then
    echo "no ProjectZomboid64 in $GAME (set PZ_GAME_DIR)" >&2
    exit 1
fi

mkdir -p "$CACHE"
# The same files as the server, or the server refuses the client for a checksum mismatch.
ZOMBOID_DIR="$CACHE" "$REPO/tools/deploy-dev.sh"

GAME_ARGS=(-cachedir="$CACHE")
if [ "${EHR_CLIENT_DEBUG:-1}" = "1" ]; then
    GAME_ARGS+=(-debug)
fi

cd "$GAME"
export LD_LIBRARY_PATH="$GAME/natives:$GAME:$GAME/jre64/lib:${LD_LIBRARY_PATH:-}"
export PATH="$GAME/jre64/bin:$PATH"
PRELOAD="${LD_PRELOAD:-}:libjsig.so:libPZXInitThreads64.so"

case "$MODE" in
    launcher)
        XMODIFIERS= LD_PRELOAD="$PRELOAD" nohup ./ProjectZomboid64 -nosteam "${GAME_ARGS[@]}" > "$OUT" 2>&1 &
        ;;
    java)
        XMODIFIERS= LD_PRELOAD="$PRELOAD" nohup "$GAME/jre64/bin/java" \
            -cp ".:projectzomboid.jar" \
            -Djava.awt.headless=true \
            --enable-native-access=ALL-UNNAMED \
            --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED \
            -Xmx"${EHR_CLIENT_XMX:-3072m}" \
            -Dzomboid.steam=0 \
            -Dzomboid.znetlog=1 \
            -Djava.library.path=natives/ \
            -Djava.security.egd=file:/dev/./urandom \
            -XX:+UseZGC \
            -XX:-OmitStackTraceInFastThrow \
            zombie/gameStates/MainScreenState -nosteam "${GAME_ARGS[@]}" > "$OUT" 2>&1 &
        ;;
    *)
        echo "EHR_CLIENT_MODE must be launcher or java, not $MODE" >&2
        exit 1
        ;;
esac
PID=$!

if [ "$N" = "1" ]; then
    LOGIN="admin / ${EHR_ADMIN_PASSWORD:-admin} (the server's admin account)"
else
    LOGIN="any new name and password, e.g. player$N / player$N (the server is open)"
fi

cat <<EOF
Client $N started ($MODE mode), pid $PID, cache dir $CACHE
  game log:   $CACHE/console.txt
  stdout:     $OUT
  connect:    Join -> server 127.0.0.1, port 16261
  log in as:  $LOGIN
  tip:        Options -> Display: windowed 1280x720, lowest graphics, 30 FPS cap
EOF
