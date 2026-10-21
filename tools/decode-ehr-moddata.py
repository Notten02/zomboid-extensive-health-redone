#!/usr/bin/env python3
"""Decode the EHR_* player modData of a Project Zomboid (Build 42) save made with the original EHR mod.

Used once to build tests/fixtures/real_saves/*.lua, so the importer is checked against real data instead of
formats inferred from the original's source. Standard library only. Run it with isolated mode, on a COPY of the
save's players.db (never on the save itself; this tool opens the file read-only anyway):

    python3 -I tools/decode-ehr-moddata.py [--lua OUT.lua --month YYYY-MM] COPY_OF_players.db

Without --lua it prints a summary: the keys found, their types and the byte range that was consumed.

Format (inferred from the bytes of eight real saves, B42.21; no game code was read or decompiled).
Table `localPlayers`, column `data` is one serialized IsoPlayer. All numbers are big-endian.
  * The player's modData sits at a fixed spot near the start of the blob (offset 26 in every save seen). It is
    a "present" byte 0x01, an int32 entry count N, then N (key, value) pairs. Nested tables use the same pairs.
  * A value (and a key) is a type byte followed by its payload:
        0x00  string   uint16 length, then that many UTF-8 bytes (Java modified UTF-8; plain for these data)
        0x01  number   IEEE-754 double (8 bytes). Lua has only numbers, so integers are doubles too.
        0x02  table    int32 entry count, then count (key, value) pairs
        0x03  boolean  1 byte, 0 or 1
  * Keys seen are strings; array tables (journal entries, doseHours) use numeric keys.
Validation: each table must consume exactly its declared entry count, every type byte must be known, booleans
must be 0 or 1, and the modData table is found by scanning for the first offset where such a parse succeeds and
contains an EHR_ key. Nothing is guessed: any violation aborts with an error.

Output: only top-level keys that start with "EHR_" are written, sorted, as a Lua file that returns a table.
Nothing else from the player (name, position, inventory, other mods' modData) is decoded into the output. EHR_ keys
that occur elsewhere in the blob (item modData, such as the watch battery) are only counted and reported.
"""
import argparse
import math
import re
import sqlite3
import struct
import sys

PREFIX = "EHR_"


class DecodeError(Exception):
    pass


def read_value(blob, pos, depth=0):
    """Returns (python value, new position). Tables become dicts."""
    if pos >= len(blob):
        raise DecodeError("truncated at %d" % pos)
    kind = blob[pos]
    pos += 1
    if kind == 0x00:
        (length,) = struct.unpack_from(">H", blob, pos)
        pos += 2
        if pos + length > len(blob):
            raise DecodeError("string runs past the end at %d" % pos)
        try:
            return blob[pos:pos + length].decode("utf-8"), pos + length
        except UnicodeDecodeError:
            raise DecodeError("string is not UTF-8 at %d" % pos)
    if kind == 0x01:
        if pos + 8 > len(blob):
            raise DecodeError("truncated number at %d" % pos)
        return struct.unpack_from(">d", blob, pos)[0], pos + 8
    if kind == 0x03:
        if pos >= len(blob) or blob[pos] not in (0, 1):
            raise DecodeError("bad boolean at %d" % pos)
        return blob[pos] == 1, pos + 1
    if kind == 0x02:
        if depth > 16:
            raise DecodeError("tables nested too deep at %d" % pos)
        return read_pairs(blob, pos, depth + 1)
    raise DecodeError("unknown type byte 0x%02x at %d" % (kind, pos - 1))


def read_pairs(blob, pos, depth):
    (count,) = struct.unpack_from(">i", blob, pos)
    pos += 4
    if not 0 <= count <= 100000:
        raise DecodeError("implausible entry count %d at %d" % (count, pos - 4))
    table = {}
    for _ in range(count):
        key, pos = read_value(blob, pos, depth)
        if isinstance(key, (dict, bool)):
            raise DecodeError("table or boolean key at %d" % pos)
        value, pos = read_value(blob, pos, depth)
        table[key] = value
    if len(table) != count:
        raise DecodeError("duplicate keys in a table ending at %d" % pos)
    return table, pos


def find_moddata(blob):
    """Returns (table, start, end) of the player's modData: the first parse that holds an EHR_ key."""
    for start in range(0, len(blob) - 5):
        if blob[start] != 0x01:
            continue
        try:
            table, end = read_pairs(blob, start + 1, 1)
        except (DecodeError, struct.error):
            continue
        if any(isinstance(k, str) and k.startswith(PREFIX) for k in table):
            return table, start, end
    raise DecodeError("no modData table with EHR_ keys found")


def load_blob(path):
    con = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    try:
        rows = con.execute("SELECT data FROM localPlayers").fetchall()
    finally:
        con.close()
    if len(rows) != 1:
        raise DecodeError("expected one local player, found %d" % len(rows))
    return rows[0][0]


# --- Lua output -----------------------------------------------------------------------------------------------

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
LUA_KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
                "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}


def lua_string(text):
    out = ['"']
    for ch in text:
        code = ord(ch)
        if ch == '"' or ch == "\\":
            out.append("\\" + ch)
        elif code < 32 or code == 127:
            out.append("\\%03d" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_number(value):
    if math.isnan(value) or math.isinf(value):
        raise DecodeError("non-finite number")
    if value == int(value) and abs(value) < 1e15:
        return str(int(value))
    return repr(value)


def lua_key(key):
    if isinstance(key, float):
        return "[%s]" % lua_number(key)
    if IDENT.match(key) and key not in LUA_KEYWORDS:
        return key
    return "[%s]" % lua_string(key)


def sort_keys(table):
    numbers = sorted(k for k in table if isinstance(k, float))
    strings = sorted(k for k in table if isinstance(k, str))
    return numbers + strings


def lua_value(value, indent):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return lua_number(value)
    if isinstance(value, str):
        return lua_string(value)
    if not value:
        return "{}"
    pad = "    " * (indent + 1)
    lines = ["{"]
    for key in sort_keys(value):
        lines.append("%s%s = %s," % (pad, lua_key(key), lua_value(value[key], indent + 1)))
    lines.append("    " * indent + "}")
    return "\n".join(lines)


def to_lua(ehr, month):
    header = [
        "-- Real data: the EHR_* keys of one player's modData, decoded by tools/decode-ehr-moddata.py from a save made",
        "-- with the original mod (Extensive Health Rework Evolved) in %s. Nothing else from the player is kept." % month,
        "-- Decoded as is, no edits: do not fix or tidy values here (tests/real_saves_spec.lua depends on them).",
        "",
        "return {",
    ]
    body = ["    %s = %s," % (lua_key(k), lua_value(ehr[k], 1)) for k in sorted(ehr)]
    return "\n".join(header + body + ["}", ""])


def describe(value):
    if isinstance(value, dict):
        return "table(%d)" % len(value)
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, float):
        return "number"
    return "string"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("players_db", help="a COPY of the save's players.db")
    parser.add_argument("--lua", metavar="OUT.lua", help="write the EHR_* keys as a Lua fixture")
    parser.add_argument("--month", default="unknown month", help="source month for the fixture header, YYYY-MM")
    args = parser.parse_args()

    blob = load_blob(args.players_db)
    table, start, end = find_moddata(blob)
    ehr = {k: v for k, v in table.items() if isinstance(k, str) and k.startswith(PREFIX)}
    elsewhere = blob[:start].count(PREFIX.encode()) + blob[end:].count(PREFIX.encode())
    print("modData at bytes %d-%d of %d: %d keys, %d EHR_ keys; %d more EHR_ strings outside it (item modData)"
          % (start, end, len(blob), len(table), len(ehr), elsewhere), file=sys.stderr)
    for key in sorted(ehr):
        print("  %-36s %s" % (key, describe(ehr[key])), file=sys.stderr)
    if args.lua:
        with open(args.lua, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(to_lua(ehr, args.month))


if __name__ == "__main__":
    try:
        main()
    except DecodeError as err:
        sys.exit("decode error: %s" % err)
