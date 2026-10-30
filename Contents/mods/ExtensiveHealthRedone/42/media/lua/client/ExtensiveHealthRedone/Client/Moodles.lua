-- EHR's five moodles through MoodleFramework, when that mod is active (no native fallback: MoodleFramework's
-- licence allows using it only as an optional dependency through its public API). Without it this
-- file does nothing: vanilla's stat moodles and the EHR Monitor carry the information.
-- The levels come from the mirror (UI/MoodleLevels); they are re-applied after every sync and every game minute, for
-- each local player (split screen). The ShowEHRMoodles mod option hides them all; the mechanics are untouched.
-- MoodleFramework API used (v2.8): createMoodle, getMoodle, setThresholds, setChevronCount, setBackground,
-- setPicture, setTitle, setDescription, setValue.
--
-- Add-on mods show their own bad moodles the same way (Moodles.register): EHR owns the MoodleFramework calls, so an
-- add-on stays optional on MoodleFramework too.

local Env = require "ExtensiveHealthRedone/Game/Env"
local MoodleLevels = require "ExtensiveHealthRedone/UI/MoodleLevels"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Options = require "ExtensiveHealthRedone/Client/Options"
local Text = require "ExtensiveHealthRedone/Client/Text"

local log = Env.logger("Moodles")

local Moodles = {}

-- Our MoodleFramework names, by MoodleLevels id (the original mod's names, so a player sees the same moodles).
Moodles.NAMES = {
    medical = "EHR_MedicalAlert",
    corpse = "EHR_CorpseExposure",
    cadaveric = "EHR_CadavericExposure",
    heat = "EHR_HeatExposure",
    cold = "EHR_ColdExposure",
}

Moodles.ICONS = {
    medical = "media/textures/EHR_Disease_UnknownMoodle.png",
    corpse = "media/textures/EHR_Disease_CorpseSicknessMoodle.png",
    cadaveric = "media/textures/EHR_Disease_CadavericAspergillosisMoodle.png",
    heat = "media/textures/EHR_Disease_HeatExhaustionMoodle.png",
    cold = "media/textures/EHR_Disease_CommonColdMoodle.png",
}

-- Our icons are complete round badges: MoodleFramework's background is replaced by an empty texture.
local BACKGROUND = "media/textures/emptyTexture.png"
local BAD = 2
local NEUTRAL = 0.5
-- Bad-only thresholds and the value for each level.
local THRESHOLDS = { 0.05, 0.15, 0.25, 0.35 }
local VALUE = { 0.35, 0.25, 0.15, 0.05 }

-- Add-on moodles by id, and their ids in registration order.
local addons = {}
local addonOrder = {}

local MF
local registered = false

local function create(name)
    local created, err = pcall(MF.createMoodle, name)
    if not created then
        log:warn("MoodleFramework could not create", name, err)
    end
    return created
end

-- Registers an add-on moodle (bad, levels 1-4, hidden at 0). Call it from client code at load. spec:
--   name       its MoodleFramework name (unique across mods)
--   icon       texture path, e.g. "media/textures/MyAddon_ScurvyMoodle.png" (a round badge like ours)
--   compute(section, player) -> level (0-4), title (translation key), desc (a UI/Text value)
--              section(name) returns a mirrored state section of the player, or nil
-- A failing compute hides the moodle for that update. The ShowEHRMoodles option hides add-on moodles too.
function Moodles.register(id, spec)
    if type(id) ~= "string" or Moodles.NAMES[id] or addons[id] then
        error("moodle " .. tostring(id) .. " is already registered", 2)
    end
    if type(spec) ~= "table" or type(spec.name) ~= "string" or type(spec.compute) ~= "function" then
        error("moodle " .. id .. " needs a name and compute()", 2)
    end
    addons[id] = spec
    addonOrder[#addonOrder + 1] = id
    if registered then
        create(spec.name)
    end
end
local announced = false
local configured = {}   -- moodle object -> true once its look is set

local function active()
    local mods = getActivatedMods()
    return mods:contains("MoodleFramework") or mods:contains("\\MoodleFramework")
end

-- Loads MoodleFramework's public module and registers our moodles once. False when it isn't available.
function Moodles.ready()
    if registered then
        return true
    end
    if not active() then
        -- Once per session: a save has its own mod list, so MF enabled in the main menu may still be off here.
        if not announced then
            announced = true
            log:info("MoodleFramework is not active in this game; EHR moodles are off")
        end
        return false
    end
    local ok = pcall(require, "MF_ISMoodle")
    MF = ok and rawget(_G, "MF") or nil
    if type(MF) ~= "table" or type(MF.createMoodle) ~= "function" or type(MF.getMoodle) ~= "function" then
        log:warn("MoodleFramework is active but its API was not found; EHR moodles are off")
        MF = nil
        return false
    end
    for _, id in ipairs(MoodleLevels.ORDER) do
        if not create(Moodles.NAMES[id]) then
            return false
        end
    end
    for _, id in ipairs(addonOrder) do
        create(addons[id].name)
    end
    registered = true
    log:info("EHR moodles registered with MoodleFramework")
    return true
end

-- Calls a MoodleFramework moodle method by name: a third-party API, which tools/check-api.lua (vanilla stubs) can't
-- know.
local function mf(moodle, method, ...)
    return moodle[method](moodle, ...)
end

local function moodleFor(id, playerNum)
    local name = addons[id] and addons[id].name or Moodles.NAMES[id]
    local ok, moodle = pcall(MF.getMoodle, name, playerNum)
    if not ok or not moodle then
        return nil
    end
    if not configured[moodle] then
        configured[moodle] = true
        mf(moodle, "setThresholds", THRESHOLDS[1], THRESHOLDS[2], THRESHOLDS[3], THRESHOLDS[4], nil, nil, nil, nil)
        mf(moodle, "setChevronCount", 0)
        local background = getTexture(BACKGROUND)
        local icon = getTexture(addons[id] and addons[id].icon or Moodles.ICONS[id])
        for level = 1, 4 do
            if background then
                mf(moodle, "setBackground", BAD, level, background)
            end
            if icon then
                mf(moodle, "setPicture", BAD, level, icon)
            end
        end
    end
    return moodle
end

local function sectionsOf(player)
    return {
        conditions = Client.section(player, "conditions"),
        wounds = Client.section(player, "wounds"),
        meds = Client.section(player, "meds"),
        exposure = Client.section(player, "exposure"),
    }
end

function Moodles.updatePlayer(playerNum)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then
        return
    end
    local show = Options.get("ShowEHRMoodles") ~= false
    local levels = show and MoodleLevels.compute(sectionsOf(player)) or nil
    if levels then
        local section = function(name) return Client.section(player, name) end
        for _, id in ipairs(addonOrder) do
            local ok, level, title, desc = pcall(addons[id].compute, section, player)
            if ok and type(level) == "number" and level >= 1 and level <= 4 then
                levels[id] = { level = math.floor(level), title = title, desc = desc }
            elseif not ok then
                log:debug("moodle", id, "failed:", tostring(level))
            end
        end
    end
    local ids = {}
    for _, id in ipairs(MoodleLevels.ORDER) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(addonOrder) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(ids) do
        local moodle = moodleFor(id, playerNum)
        if moodle then

            local m = levels and levels[id]
            if m and m.level > 0 then
                mf(moodle, "setTitle", BAD, m.level, getText(m.title))
                mf(moodle, "setDescription", BAD, m.level, Text.t(m.desc))
                mf(moodle, "setValue", VALUE[m.level])
            else
                mf(moodle, "setValue", NEUTRAL)
            end
        end
    end
end

function Moodles.updateAll()
    if not Moodles.ready() then
        return
    end
    for playerNum = 0, getNumActivePlayers() - 1 do
        Moodles.updatePlayer(playerNum)
    end
end

-- Registered at load, so MoodleFramework creates our objects on OnCreatePlayer like its own.
Events.OnGameBoot.Add(Moodles.ready)
Events.OnGameStart.Add(Moodles.updateAll)
Events.EveryOneMinute.Add(Moodles.updateAll)
Client.onChange(function()
    Moodles.updateAll()
end)

return Moodles
