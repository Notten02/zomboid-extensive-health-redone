-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Every translation key our Lua code names exists in the English UI translations. Keys built at run time are listed
-- here by hand.
local LuaSource = require("LuaSource")

local LUA = "Contents/mods/ExtensiveHealthRedone/42/media/lua/"
local UI_JSON = LUA .. "shared/Translate/EN/UI.json"

-- Keys the code builds from parts: "UI_EHR_StitchMinigame_" .. key, "UI_EHR_Consent_Ask_" .. purpose, "UI_EHR_Consent_AskItem_" .. purpose.
local BUILT = {
    "UI_EHR_StitchMinigame_Title", "UI_EHR_StitchMinigame_Target", "UI_EHR_StitchMinigame_Hint",
    "UI_EHR_StitchMinigame_Quality", "UI_EHR_StitchMinigame_Misses", "UI_EHR_StitchMinigame_Cancel",
    "UI_EHR_StitchMinigame_Excellent", "UI_EHR_StitchMinigame_Stable", "UI_EHR_StitchMinigame_Rough",
    "UI_EHR_StitchMinigame_Poor", "UI_EHR_StitchMinigame_Steady", "UI_EHR_StitchMinigame_FailLine",
    "UI_EHR_Consent_Ask_transfuse", "UI_EHR_Consent_Ask_medicate", "UI_EHR_Consent_Ask_stitch",
    "UI_EHR_Consent_Ask_exam", "UI_EHR_Consent_AskItem_medicate", "UI_EHR_Consent_AskItem_transfuse",
    -- UI/MiniHealth: "UI_EHR_Mini_DiseaseStage_" .. stage, "UI_EHR_Mini_SepsisStage_" .. stage.
    "UI_EHR_Mini_DiseaseStage_1", "UI_EHR_Mini_DiseaseStage_2", "UI_EHR_Mini_DiseaseStage_3",
    "UI_EHR_Mini_DiseaseStage_4", "UI_EHR_Mini_SepsisStage_1", "UI_EHR_Mini_SepsisStage_2",
    "UI_EHR_Mini_SepsisStage_3", "UI_EHR_Mini_SepsisStage_4",
}

local function readKeys()
    local keys = {}
    for key in LuaSource.read(UI_JSON):gmatch('"([%w_]+)"%s*:') do
        keys[key] = true
    end
    return keys
end

describe("translations", function()
    local keys = readKeys()

    it("have every UI_EHR key the code uses", function()
        for _, path in ipairs(LuaSource.find(LUA)) do
            -- Comments go; strings stay (keys are strings).
            for key in LuaSource.read(path):gmatch('"(UI_EHR_[%w_]+)"') do
                if not key:find("_$") then
                    assert.truthy(keys[key], path:sub(#LUA + 1) .. " uses a missing key " .. key)
                end
            end
        end
    end)

    it("have the ambient speech lines and the Mini Health companion texts in all ten languages", function()
        local langs = { "CH", "CN", "EN", "ES", "FR", "IT", "JP", "PTBR", "RU", "UA" }
        local wanted = {}
        for key in LuaSource.read(UI_JSON):gmatch('"(UI_EHR_Ambient_[%w_]+)"%s*:') do wanted[#wanted + 1] = key end
        for key in LuaSource.read(UI_JSON):gmatch('"(UI_EHR_Mini_[%w_]+)"%s*:') do wanted[#wanted + 1] = key end
        assert.equal(42 + 14 - 1, #wanted)     -- 42 ambient lines, 13 companion texts (title, 4 rows, 8 stages)
        for _, lang in ipairs(langs) do
            local text = LuaSource.read(LUA .. "shared/Translate/" .. lang .. "/UI.json")
            for _, key in ipairs(wanted) do
                local value = text:match('"' .. key .. '"%s*:%s*"([^"]*)"')
                assert.truthy(value and value ~= "", lang .. " lacks " .. key)
            end
        end
    end)

    it("have the keys the code builds at run time", function()
        for _, key in ipairs(BUILT) do
            assert.truthy(keys[key], "missing " .. key)
        end
    end)
end)
