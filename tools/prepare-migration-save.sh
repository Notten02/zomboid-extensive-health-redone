#!/usr/bin/env bash
# Prepares a COPY of a save made with the original mod (Extensive Health Rework Evolved) for the one-time import into
# Extensive Health Redone, so the maintainer can try the migration without risking the real save.
#
#   tools/prepare-migration-save.sh [--dry-run] SAVE_NAME
#
# SAVE_NAME is a folder under ~/Zomboid/Saves/Sandbox (override the Saves/Sandbox folder with SANDBOX_DIR, which is
# also how the rewrite is tested). The script:
#   1. copies the whole folder to "<SAVE_NAME>-redone-migration" next to it, and refuses when that already exists;
#   2. rewrites only the copy's mods.txt: every original mod entry (ExtensiveHealthReworkEvolved or EHR, with or
#      without a leading backslash) becomes ExtensiveHealthRedone. All other lines and the formatting stay as they
#      are. A second original entry, or one next to an existing ExtensiveHealthRedone entry, is removed instead of
#      renamed, so the mod is listed once.
# The source folder is only read. --dry-run copies nothing and prints the planned mods.txt change as a diff.
# Close the game first: a running game keeps writing to the save.
set -euo pipefail

NEW_ID="ExtensiveHealthRedone"
DRY_RUN=0
NAME=""

usage() {
    echo "usage: $0 [--dry-run] SAVE_NAME" >&2
    exit 2
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help) usage ;;
        -*) echo "unknown option: $arg" >&2; usage ;;
        *) [ -z "$NAME" ] || usage; NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || usage

case "$NAME" in
    */* | . | .. | "") echo "SAVE_NAME must be a folder name under the Sandbox folder, not a path: $NAME" >&2; exit 2 ;;
esac

SANDBOX="${SANDBOX_DIR:-$HOME/Zomboid/Saves/Sandbox}"
SRC="$SANDBOX/$NAME"
DST="$SANDBOX/$NAME-redone-migration"

[ -d "$SRC" ] || { echo "no such save: $SRC" >&2; exit 1; }
[ -f "$SRC/mods.txt" ] || { echo "$SRC has no mods.txt, so it is not a modded save" >&2; exit 1; }
if [ "$DRY_RUN" -eq 0 ] && [ -e "$DST" ]; then
    echo "refusing: $DST already exists (remove it yourself if you want to start over)" >&2
    exit 1
fi

# Rewrites a mods.txt on stdin to stdout. Keeps the line's indentation, spacing, trailing comma and line ending.
rewrite_mods() {
    awk -v new_id="$NEW_ID" '
        # Entry lines look like "    mod = \ExtensiveHealthReworkEvolved,". Capture prefix, id and suffix.
        function parse(line) {
            return match(line, /^[ \t]*mod[ \t]*=[ \t]*\\?[^ \t,\r]+/)
        }
        { lines[NR] = $0 }
        END {
            have_new = 0
            for (i = 1; i <= NR; i++) {
                if (parse(lines[i])) {
                    id = lines[i]
                    sub(/^[ \t]*mod[ \t]*=[ \t]*\\?/, "", id)
                    sub(/[ \t,\r].*$/, "", id)
                    if (id == new_id) have_new = 1
                }
            }
            for (i = 1; i <= NR; i++) {
                line = lines[i]
                if (parse(line)) {
                    id = line
                    sub(/^[ \t]*mod[ \t]*=[ \t]*\\?/, "", id)
                    sub(/[ \t,\r].*$/, "", id)
                    if (id == "ExtensiveHealthReworkEvolved" || id == "EHR") {
                        if (have_new) continue
                        have_new = 1
                        # Keep everything before the id (indentation, "mod = ", an optional backslash is dropped:
                        # our id is not an exclusion) and everything after it (comma, CR).
                        match(line, /^[ \t]*mod[ \t]*=[ \t]*/)
                        prefix = substr(line, 1, RLENGTH)
                        suffix = line
                        sub(/^[ \t]*mod[ \t]*=[ \t]*\\?[^ \t,\r]+/, "", suffix)
                        line = prefix new_id suffix
                    }
                }
                print line
            }
        }
    '
}

PLANNED="$(mktemp)"
trap 'rm -f "$PLANNED"' EXIT
rewrite_mods < "$SRC/mods.txt" > "$PLANNED"

if ! grep -Eq '^[[:space:]]*mod[[:space:]]*=[[:space:]]*\\?(ExtensiveHealthReworkEvolved|EHR)[[:space:]]*,?[[:space:]]*$' "$SRC/mods.txt"; then
    echo "$SRC/mods.txt lists neither ExtensiveHealthReworkEvolved nor EHR, so there is nothing to migrate." >&2
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry run: nothing is copied. Planned change to mods.txt of $DST:"
    diff -u --label "$SRC/mods.txt" --label "$DST/mods.txt" "$SRC/mods.txt" "$PLANNED" || true
    exit 0
fi

# -a keeps timestamps and the journal file; nothing under $SRC is modified.
cp -a -- "$SRC" "$DST"
cp -- "$PLANNED" "$DST/mods.txt"

echo "copied $SRC"
echo "     -> $DST"
echo "mods.txt of the copy changed:"
diff -u --label "$SRC/mods.txt" --label "$DST/mods.txt" "$SRC/mods.txt" "$DST/mods.txt" || true
cat <<EOF

Next steps (the original save was not touched):
  1. Deploy the current mod (tools/deploy-dev.sh) and make sure the original mods are not enabled for this save.
  2. Start the game and load "$NAME-redone-migration" from the Sandbox load list. Do not load the original.
  3. Expect on the first load: the character keeps blood type, disease knowledge (flyers read, wild plants), immunity
     score and Knox flags; illnesses, medication, wound infections and other active state are gone and blood is full.
  4. Look for the line "imported from Extensive Health Rework:" in ~/Zomboid/console.txt. It reports the blood type,
     the number of diseases known, the immunity score and how many old keys were removed.
  5. Save and reload once: the line must not appear again (the old EHR_ data was removed from the character).
EOF
