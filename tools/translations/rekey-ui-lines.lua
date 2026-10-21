-- One-off: re-key the original mod's hashed `UI_EHR_Line_<djb2>` translation keys to readable keys.
--
-- The original generated a key per English sentence at runtime (EHR_Localization.lua, `EHR.Locale.RawKey`).
-- This script gives every such key a stable name derived from its English text (`UI_EHR_Text_<Slug>`), rewrites
-- UI.json in every language in place (order and all other keys untouched), and writes a porting map so that old
-- `L("English sentence")` call sites can be matched to their new key.
--
-- English comes from EN/UI.json. A few keys exist only in the other languages because the original never added
-- the English line; their English is recovered from the original's Lua string literals and appended to EN.
--
-- Usage (from the repo root):
--   luajit tools/translations/rekey-ui-lines.lua <original-mod>/42/media/lua
-- Runs once; it refuses to run when no hashed keys are left.

local TRANSLATE = "Contents/mods/ExtensiveHealthRedone/42/media/lua/shared/Translate"
local MAP_OUT = "docs/porting/ui-line-key-map.tsv"
local LANGS = { "EN", "CH", "CN", "ES", "FR", "IT", "JP", "PTBR", "UA" }
local PREFIX = "UI_EHR_Text_"
local MAX_SLUG = 48
local HASHED = "^UI_EHR_Line_%x+$"
local originalLuaDir = assert(arg[1], "usage: rekey-ui-lines.lua <path to the original mod's 42/media/lua>")

local function readLines(path)
    local lines = {}
    for line in io.lines(path) do
        lines[#lines + 1] = line
    end
    return lines
end

-- Same hash as the original's EHR.Locale.RawKey.
local function rawKey(text)
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + text:byte(i)) % 4294967296
    end
    return string.format("UI_EHR_Line_%08X", hash)
end

local function unescape(s)
    return (s:gsub("\\(.)", { n = "\n", t = "\t", ['"'] = '"', ["'"] = "'", ["\\"] = "\\", ["/"] = "/" }))
end

local function escapeJson(s)
    return (s:gsub('[\\"]', "\\%0"):gsub("\n", "\\n"):gsub("\t", "\\t"))
end

-- Entries the original extracted from code by mistake (Lua concatenation fragments, dotted identifiers).
local function junkReason(text)
    if text:find(" .. ", 1, true) then
        return "lua code fragment"
    end
    if text:match("^[%w_]+%.[%w_]+[%w_.]*$") then
        return "identifier, not text"
    end
    if not text:gsub("<[^>]*>", ""):find("%a") then
        return "no text"
    end
    return nil
end

local function slugOf(text)
    local cleaned = text:gsub("<[^>]*>", " ")
        :gsub("%%%d", " ")
        :gsub("%%[-+ #0]*%d*%.?%d*[cdeEfgGiouqsxX]", " ")
        :gsub("'", "")
    local parts, len = {}, 0
    for word in cleaned:gmatch("[%w]+") do
        local w = word:sub(1, 1):upper() .. word:sub(2)
        if len > 0 and len + #w > MAX_SLUG then
            break
        end
        parts[#parts + 1] = w
        len = len + #w
    end
    return table.concat(parts)
end

-- Parse a translation JSON file whose entries are one `"key": "value"` per line.
local function parse(path)
    local entries = {}
    for i, line in ipairs(readLines(path)) do
        local key, value = line:match('^%s*"([^"]+)"%s*:%s*"(.*)"%s*,?%s*$')
        if key then
            entries[#entries + 1] = { key = key, value = value }
        elseif not line:match("^%s*[{}]%s*$") and not line:match("^%s*$") then
            error(path .. ":" .. i .. ": unexpected line: " .. line)
        end
    end
    return entries
end

local function write(path, entries)
    local f = assert(io.open(path, "wb"))
    f:write("{\n")
    for i, e in ipairs(entries) do
        f:write('    "', e.key, '": "', e.value, '"', i < #entries and "," or "", "\n")
    end
    f:write("}\n")
    f:close()
end

-- Every string literal in the original Lua, by hash: its text and the files using it.
local function scanOriginalSources(dir)
    local textByKey, filesByKey = {}, {}
    local p = assert(io.popen('find "' .. dir .. '" -name "*.lua"'))
    for path in p:lines() do
        local f = assert(io.open(path, "rb"))
        local src = f:read("*a")
        f:close()
        local name = path:match("([^/]+)%.lua$")
        for _, body in src:gmatch("([\"'])(.-[^\\])%1") do
            local text = unescape(body)
            local key = rawKey(text)
            textByKey[key] = text
            filesByKey[key] = filesByKey[key] or {}
            filesByKey[key][name] = true
        end
    end
    p:close()
    return textByKey, filesByKey
end

local sourceText, sourceFiles = scanOriginalSources(originalLuaDir)

-- 1. Collect hashed keys and their English.
local enPath = TRANSLATE .. "/EN/UI.json"
local en = parse(enPath)
local taken, english, recovered = {}, {}, {}
for _, e in ipairs(en) do
    taken[e.key] = true
    if e.key:match(HASHED) then
        local text = unescape(e.value)
        -- Format strings are stored with `%%` but were hashed with `%`.
        if rawKey(text) ~= e.key and rawKey((text:gsub("%%%%", "%%"))) ~= e.key then
            io.stderr:write("warning: ", e.key, " does not hash from its English text\n")
        end
        english[e.key] = text
    end
end
if not next(english) then
    error("No UI_EHR_Line_* keys left in EN/UI.json; the re-key has already run.")
end
for _, lang in ipairs(LANGS) do
    for _, e in ipairs(parse(TRANSLATE .. "/" .. lang .. "/UI.json")) do
        if e.key:match(HASHED) and not english[e.key] and sourceText[e.key] then
            english[e.key] = sourceText[e.key]
            recovered[e.key] = true
        end
    end
end

-- 2. Assign new keys in sorted old-key order so the result is deterministic.
local sorted = {}
for k in pairs(english) do
    sorted[#sorted + 1] = k
end
table.sort(sorted)

local newKey, dropReason = {}, {}
for _, old in ipairs(sorted) do
    local reason = junkReason(english[old])
    if reason then
        dropReason[old] = reason
    else
        local base = PREFIX .. slugOf(english[old])
        local candidate, n = base, 1
        while taken[candidate] do
            n = n + 1
            candidate = base .. "_" .. n
        end
        taken[candidate] = true
        newKey[old] = candidate
    end
end

-- 3. Rewrite every language. Hashed keys with no known English are stale and dropped.
local stale = {}
for _, lang in ipairs(LANGS) do
    local path = TRANSLATE .. "/" .. lang .. "/UI.json"
    local out = {}
    for _, e in ipairs(parse(path)) do
        if not e.key:match(HASHED) then
            out[#out + 1] = e
        elseif newKey[e.key] then
            out[#out + 1] = { key = newKey[e.key], value = e.value }
        elseif not dropReason[e.key] then
            stale[#stale + 1] = lang .. " " .. e.key .. " = " .. e.value
        end
    end
    if lang == "EN" then
        for _, old in ipairs(sorted) do
            if recovered[old] and newKey[old] then
                out[#out + 1] = { key = newKey[old], value = escapeJson(english[old]) }
            end
        end
    end
    write(path, out)
end

-- 4. Porting map.
local f = assert(io.open(MAP_OUT, "wb"))
f:write("old_key\tnew_key\tenglish\toriginal_files\n")
for _, old in ipairs(sorted) do
    local files = {}
    for name in pairs(sourceFiles[old] or {}) do
        files[#files + 1] = name
    end
    table.sort(files)
    local target = newKey[old] or ("DROPPED: " .. dropReason[old])
    f:write(old, "\t", target, "\t", escapeJson(english[old]), "\t", table.concat(files, ","), "\n")
end
f:close()

-- 5. Report.
local kept, dropped = 0, 0
for _ in pairs(newKey) do
    kept = kept + 1
end
for _, old in ipairs(sorted) do
    if dropReason[old] then
        dropped = dropped + 1
        print("dropped " .. old .. " (" .. dropReason[old] .. "): " .. english[old])
    end
    if recovered[old] then
        print("recovered English from source for " .. old .. " -> " .. tostring(newKey[old]))
    end
end
for _, s in ipairs(stale) do
    print("stale (no English anywhere, dropped): " .. s)
end
print(string.format("re-keyed %d, dropped %d junk entries, %d stale lines", kept, dropped, #stale))
print("map written to " .. MAP_OUT)
