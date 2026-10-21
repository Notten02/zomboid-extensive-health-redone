-- Adds new translation keys to one category file (default UI.json) in all 9 languages, keeping existing keys
-- untouched. Run through tools/translations/add-keys.sh, which serialises concurrent runs with a lock.
--
--   lua5.1 tools/translations/add-keys.lua <keys.lua> [Category]
--
-- keys.lua returns a list: { { "UI_EHR_Food_Vomit", "*vomits*", FR = "*vomit*", ... }, ... }. A language without
-- its own text gets the English one, for translators to replace. A key that already exists in a language is left
-- as it is there (re-running is safe). Keys and their order are appended at the end of each file.

local ROOT = "Contents/mods/ExtensiveHealthRedone/42/media/lua/shared/Translate/"
local LANGS = { "CH", "CN", "EN", "ES", "FR", "IT", "JP", "PTBR", "UA" }

local keysFile, category = arg[1], arg[2] or "UI"
if not keysFile then
    io.stderr:write("usage: add-keys.lua <keys.lua> [Category]\n")
    os.exit(2)
end
local entries = dofile(keysFile)

local function jsonString(s)
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\t', '\\t')
    return '"' .. s .. '"'
end

for _, e in ipairs(entries) do
    assert(type(e[1]) == "string" and e[1]:match("^[%w_]+$"), "bad key " .. tostring(e[1]))
    assert(type(e[2]) == "string", "missing English text for " .. e[1])
end

local added = 0
for _, lang in ipairs(LANGS) do
    local path = ROOT .. lang .. "/" .. category .. ".json"
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    local lines = {}
    for _, e in ipairs(entries) do
        if not text:find('"' .. e[1] .. '"%s*:') then
            lines[#lines + 1] = "    " .. jsonString(e[1]) .. ": " .. jsonString(e[lang] or e[2])
        end
    end
    if #lines > 0 then
        local body, tail = text:match("^(.-)%s*}%s*$")
        assert(body, path .. " does not end with }")
        if not body:match("{%s*$") then
            body = body .. ","
        end
        text = body .. "\n" .. table.concat(lines, ",\n") .. "\n}\n"
        f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
        added = added + #lines
    end
end
print(("added %d entries to %s.json across %d languages"):format(added, category, #LANGS))
