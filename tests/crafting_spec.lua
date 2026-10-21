-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The homemade supplies (syringe pack, IV kit, plastic strips, blood bag) and their recipes:
--   * every item a recipe names exists (ours in our scripts; Base items and tags in the installed game's scripts,
--     when the game is found: set PZ_MEDIA to its media folder, or the default Steam path is tried);
--   * wherever a recipe or the Lua accepts a standard syringe, IV kit or empty bag, the homemade one works too;
--   * the prepared homemade blood bag cooks into the homemade empty bag.
local LuaSource = require("LuaSource")
local Supplies = require("ExtensiveHealthRedone/Data/MedicalSupplies")

local SCRIPTS = "Contents/mods/ExtensiveHealthRedone/42/media/scripts/"
local VANILLA = (os.getenv("PZ_MEDIA") or "/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid/media")
    .. "/scripts"

local function readAll(dir)
    local parts = {}
    local p = io.popen('find "' .. dir .. '" -name "*.txt" 2>/dev/null | sort')
    if not p then
        return ""
    end
    for path in p:lines() do
        parts[#parts + 1] = LuaSource.read(path)
    end
    p:close()
    return table.concat(parts, "\n")
end

local ours = readAll(SCRIPTS)
local vanilla = readAll(VANILLA)

local function defines(text, name)
    return text:find("item%s+" .. name:gsub("%p", "%%%0") .. "%s*\n?%s*{") ~= nil
end

-- Every recipe's inputs and outputs: { name, lines = { "item 5 [A;B] ...", ... } }
local function recipes(text)
    local list = {}
    for name, body in text:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        local lines = {}
        for line in body:gmatch("item%s+%d+[^\n]*") do
            lines[#lines + 1] = line
        end
        list[#list + 1] = { name = name, lines = lines }
    end
    return list
end

describe("homemade supplies", function()
    local all = recipes(ours)

    it("have recipes", function()
        assert.is_true(#all >= 7)
    end)

    it("name only items that exist", function()
        for _, recipe in ipairs(all) do
            for _, line in ipairs(recipe.lines) do
                for fullType in line:gmatch("([%w_]+%.[%w_]+)") do
                    local module, name = fullType:match("^([%w_]+)%.([%w_]+)$")
                    if module == "ExtensiveHealth" then
                        assert.is_true(defines(ours, name), recipe.name .. ": no item " .. fullType)
                    elseif vanilla ~= "" then
                        assert.is_true(defines(vanilla, name), recipe.name .. ": no vanilla item " .. fullType)
                    end
                end
            end
        end
    end)

    it("use only tags vanilla defines", function()
        if vanilla == "" then
            ---@diagnostic disable-next-line: missing-parameter
            pending("game scripts not found; set PZ_MEDIA")
            return
        end
        for _, recipe in ipairs(all) do
            for _, line in ipairs(recipe.lines) do
                for tags in line:gmatch("tags%[([^%]]+)%]") do
                    for tag in tags:gmatch("[^;]+") do
                        assert.truthy(vanilla:find(tag, 1, true), recipe.name .. ": unknown tag " .. tag)
                    end
                end
            end
        end
    end)

    it("accept the homemade version wherever a recipe takes the standard one", function()
        local pairs_ = {
            ["ExtensiveHealth.Syringe"] = "ExtensiveHealth.HomemadeSyringe",
            ["ExtensiveHealth.IVKit"] = "ExtensiveHealth.HomemadeIVKit",
            ["ExtensiveHealth.EmptyBloodBag"] = "ExtensiveHealth.HomemadeEmptyBloodBag",
        }
        for _, recipe in ipairs(all) do
            for _, line in ipairs(recipe.lines) do
                local list = line:match("%[([^%]]+)%]")
                if list and not line:find("tags%[") then
                    for standard, homemade in pairs(pairs_) do
                        if (";" .. list .. ";"):find(";" .. standard .. ";", 1, true) then
                            assert.truthy(list:find(homemade, 1, true), recipe.name .. " takes " .. standard
                                .. " but not " .. homemade)
                        end
                    end
                end
            end
        end
    end)

    it("count as the standard supply in the transfusion and blood draw code", function()
        assert.is_true(Supplies.ivKit["ExtensiveHealth.HomemadeIVKit"])
        assert.is_true(Supplies.syringe["ExtensiveHealth.HomemadeSyringe"])
        assert.is_true(Supplies.emptyBag["ExtensiveHealth.HomemadeEmptyBloodBag"])
        assert.is_nil(Supplies.emptyBag["ExtensiveHealth.PreparedHomemadeBloodBag"])
    end)

    it("cook the prepared blood bag into the homemade empty bag", function()
        local body = ours:match("item%s+PreparedHomemadeBloodBag%s*(%b{})")
        assert.truthy(body)
        assert.truthy(body:find("IsCookable%s*=%s*true"))
        assert.truthy(body:find("ReplaceOnCooked%s*=%s*ExtensiveHealth%.HomemadeEmptyBloodBag"))
    end)
end)
