-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Consistency checks for the imported assets: translations, item scripts and mod.info.
local json = require("dkjson")

local MOD = "Contents/mods/ExtensiveHealthRedone/"
local MEDIA = MOD .. "42/media/"
local COMMON = MOD .. "common/media/"
local TRANSLATE = MEDIA .. "lua/shared/Translate/"
local LANGS = { "EN", "CH", "CN", "ES", "FR", "IT", "JP", "PTBR", "RU", "UA" }
local FILES = { "IG_UI", "ItemName", "Recipes", "Sandbox", "Tooltip", "UI" }

local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
    end
    return f ~= nil
end

local function readScripts()
    local all = {}
    local p = assert(io.popen('find "' .. MEDIA .. 'scripts" -name "*.txt" | sort'))
    for path in p:lines() do
        all[#all + 1] = read(path)
    end
    p:close()
    return table.concat(all, "\n")
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

describe("translations", function()
    local decoded = {}
    for _, lang in ipairs(LANGS) do
        for _, file in ipairs(FILES) do
            local data, _, err = json.decode(read(TRANSLATE .. lang .. "/" .. file .. ".json"))
            decoded[lang .. "/" .. file] = data or err
        end
    end

    it("are valid JSON objects", function()
        for name, data in pairs(decoded) do
            assert.is_table(data, name)
        end
    end)

    it("have the same keys in every language", function()
        for _, file in ipairs(FILES) do
            local expected = sortedKeys(decoded["EN/" .. file])
            for _, lang in ipairs(LANGS) do
                assert.same(expected, sortedKeys(decoded[lang .. "/" .. file]), lang .. "/" .. file)
            end
        end
    end)

    it("contain no hashed UI_EHR_Line_ keys", function()
        for name, data in pairs(decoded) do
            for key in pairs(data) do
                assert.is_nil(key:match("^UI_EHR_Line_"), name .. ": " .. key)
            end
        end
    end)
end)

describe("item scripts", function()
    local scripts = readScripts()

    it("keep the original item module", function()
        assert.truthy(scripts:find("module ExtensiveHealth%s*{"))
    end)

    it("do not reference models that are missing in 42.21", function()
        assert.is_nil(scripts:find("InjectorBase", 1, true))
        assert.is_nil(scripts:find("Magazine_Ground", 1, true))
    end)

    it("define models whose mesh and texture ship with the mod", function()
        for block in scripts:gmatch("model%s+[%w_]+%s*(%b{})") do
            local mesh = block:match("mesh%s*=%s*([^,%s]+)")
            local texture = block:match("texture%s*=%s*([^,%s]+)")
            assert.truthy(exists(COMMON .. "models_X/" .. mesh .. ".fbx"), "mesh " .. mesh)
            assert.truthy(exists(COMMON .. "textures/" .. texture .. ".png"), "texture " .. texture)
        end
    end)

    it("reference sound files that ship with the mod", function()
        for file in scripts:gmatch("file%s*=%s*([^,%s]+)") do
            assert.truthy(exists(MOD .. "common/" .. file), file)
        end
    end)
end)

describe("item icons", function()
    -- Width and height from the PNG IHDR chunk (big-endian, bytes 17-24).
    local function pngSize(path)
        local header = read(path):sub(17, 24)
        local function u32(s)
            local a, b, c, d = s:byte(1, 4)
            return ((a * 256 + b) * 256 + c) * 256 + d
        end
        return u32(header:sub(1, 4)), u32(header:sub(5, 8))
    end

    -- Vanilla's texture packs store 4425 of 4455 item icons on a 32x32 canvas (the rest are 1 px off).
    it("are 32x32 like vanilla's", function()
        local p = assert(io.popen('find "' .. COMMON .. 'textures" -name "Item_*.png" | sort'))
        for path in p:lines() do
            local w, h = pngSize(path)
            assert.truthy(w == 32 and h == 32, string.format("%s is %dx%d", path, w, h))
        end
        p:close()
    end)
end)

describe("mod.info", function()
    local info = {}
    for key, value in read(MOD .. "42/mod.info"):gmatch("([%w]+)=([^\n]*)") do
        info[key] = value
    end

    it("declares the mod ID and minimum game version", function()
        assert.equal("ExtensiveHealthRedone", info.id)
        assert.equal("42.21.0", info.versionMin)
    end)

    it("is incompatible with the original mods", function()
        assert.truthy(info.incompatible:find("\\ExtensiveHealthReworkEvolved", 1, true))
        assert.truthy(info.incompatible:find("\\EHR", 1, true))
    end)
end)
