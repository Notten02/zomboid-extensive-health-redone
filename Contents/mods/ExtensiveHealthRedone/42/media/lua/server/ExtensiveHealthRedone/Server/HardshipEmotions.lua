-- Hardship: Emotions (Workshop 3811647387) beside us. Its Extensive Health Rework integration was written for the
-- original mod: every hook waits for a global EHR table and reads that mod's player modData. While Emotions is on,
-- this file gives it both, backed by our own systems (authority only):
--
--   * EHR.Medication: UseConsumedMedication(player, fullType) is called for every dose that counted (Server/
--     Medication, through ServerEmotions.medicationTaken). Emotions wraps it and classifies the drug through
--     Database[fullType].displayName and DrugCategories[displayName]: our medication id and its category under the
--     original's name (Game/HardshipEmotions.CATEGORIES). The functions here only answer; the dose itself is ours.
--   * EHR.CorpseSickness.GetEnvironmentMultiplier / GetFungalEnvironment and EHR.Disease.TryContract: Emotions
--     multiplies what they return for a hungover or dizzy character. They return 1 (and the chance as given), so
--     asking them each step gives Emotions' factors, which go into facts.corpseRisk for Diseases/Corpse/Exposure.
--   * Player modData in the original's shape, rewritten every game minute: EHR_Blood (currentVolume, maxVolume),
--     EHR_Disease.active (every active condition with its stage and severity; Emotions reads the concussion and leaves
--     nausea to us while anything is active) and EHR_CorpseSickness (corpse exposure). Each carries MIRROR_FLAG so the
--     one-time import (Core/Importer) never takes them for the original mod's data.
--
-- Beside that stand-in, three generic ties through Emotions' own public API (the HardshipEmotions global, 2.22+),
-- for every condition we have, the ones the original never had included:
--   * strain (HE.registerStrain, what its Sanity reads as "how broken the body is"): our medical alert level
--     (UI/MoodleLevels.medical, without medication side effects) as STRAIN[level];
--   * focus block (HE.registerBlock, "focus" = Concentrating): from medical alert level FOCUS_FROM, or while dizzy;
--   * dizziness (HE.addDizzy): every game minute our vision blur is on (every dizzy spell, a toxin's blurred vision
--     and the dizziness side effect go through it, Core/ClientEffects), light, or strong from DIZZY_STRONG.
-- A tie whose function this Emotions version lacks is skipped and logged once.
--
-- Its Knox option (no instant Knox diagnosis) wraps the original's UI, which we don't have: Server/Knox reads that
-- option instead and Diseases/Knox/Infection holds the display back (Game/HardshipEmotions.knoxRevealAt).
--
-- Emotions installs its hooks when its files load, on OnGameStart and on OnServerStarted, so the globals are set when
-- this file loads (a server file: the save's mod list is known by then). A global EHR we didn't make (the original
-- mod, which can't run beside us) is left alone. A failing call into Emotions' wrappers switches the tie off for the
-- session, with one error in the log.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Emotions = require "ExtensiveHealthRedone/Game/HardshipEmotions"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local MedData = require "ExtensiveHealthRedone/Medication/Data"
local Legacy = require "ExtensiveHealthRedone/Data/LegacyEHR"
local MoodleLevels = require "ExtensiveHealthRedone/UI/MoodleLevels"

local log = Env.logger("HardshipEmotions")

local ServerEmotions = {}

ServerEmotions.MIRROR_FLAG = Legacy.MIRROR_FLAG
ServerEmotions.MIRROR_KEYS = { "EHR_Blood", "EHR_Disease", "EHR_CorpseSickness" }
ServerEmotions.CORPSE_DISEASES = { "corpse_sickness", "cadaveric_aspergillosis" }
-- The chance TryContract is asked with to read Emotions' factor: small, so its cap at 1 never cuts the factor.
ServerEmotions.PROBE = 0.01

-- The generic ties.
ServerEmotions.API_ID = "ExtensiveHealthRedone"      -- our provider id in Emotions' registries
ServerEmotions.STRAIN = { 0.15, 0.4, 0.7, 1 }        -- by medical alert level 1-4 (Emotions: 0.4 hurt, 0.7 severe)
ServerEmotions.FOCUS_FROM = 3                        -- medical alert level that blocks Concentrating
ServerEmotions.DIZZY_STRONG = 0.6                    -- blur from which the dizziness is strong (its level 2)
ServerEmotions.DIZZY_MINUTES = 2                     -- per report; we report every minute the blur lasts

local shim          -- the EHR table this file made, or nil
local broken = {}   -- tie -> true after a failed call

local function fail(tie, err)
    if not broken[tie] then
        broken[tie] = true
        log:error("Hardship: Emotions'", tie, "failed, that tie is off for this session:", tostring(err))
    end
end

-- The EHR table -------------------------------------------------------------------------------------------------------

local function buildShim()
    local Medication = {
        -- fullType -> { displayName = our medication id }. Looked up when asked, so add-on medications count too.
        Database = setmetatable({}, { __index = function(_, fullType)
            local med = MedData.byType[fullType]
            return med and { displayName = med.id } or nil
        end }),
        -- medication id -> the original's category name, for the categories Emotions knows.
        DrugCategories = setmetatable({}, { __index = function(_, id)
            local med = MedData.byId[id]
            return med and med.category and Emotions.CATEGORIES[med.category] or nil
        end }),
    }
    -- The dose already happened (ours); these only report it, for Emotions to wrap.
    function Medication.UseConsumedMedication(_, fullType)
        return MedData.byType[fullType] ~= nil
    end
    function Medication.UseMedication(_, item)
        return item ~= nil and MedData.byType[item:getFullType()] ~= nil
    end
    return {
        Redone = true,
        Medication = Medication,
        CorpseSickness = {
            GetEnvironmentMultiplier = function(_) return 1 end,
            GetFungalEnvironment = function(_) return 1, 0, nil end,
        },
        Disease = {
            TryContract = function(_, _, chance) return chance end,
        },
    }
end

-- Sets the global EHR table, once, when Emotions is on. Returns true when ours is in place.
function ServerEmotions.install()
    if shim then
        ServerEmotions.register()
        return true
    end
    if not Emotions.active() then
        return false
    end
    if EHR ~= nil then
        log:warn("a global EHR table already exists; Hardship: Emotions' EHR integration is left to it")
        return false
    end
    shim = buildShim()
    EHR = shim
    log:info("Hardship: Emotions found: its Extensive Health Rework integration now reads Extensive Health Redone")
    ServerEmotions.register()
    return true
end

local function ours()
    return shim ~= nil and EHR == shim and Emotions.integrated()
end

-- Medication ----------------------------------------------------------------------------------------------------------

-- A dose that counted (Doses.take's "taken"), for the patient. Called by Server/Medication.
function ServerEmotions.medicationTaken(player, med)
    if broken.medication or not ours() or not player or not med then
        return
    end
    local ok, err = pcall(EHR.Medication.UseConsumedMedication, player, med.fullType)
    if not ok then
        fail("medication", err)
    end
end

-- Corpse diseases -----------------------------------------------------------------------------------------------------

local function factor(v)
    v = tonumber(v)
    if not v or v ~= v or v <= 0 then
        return 1
    end
    return v
end

-- Emotions' factors for this player: { corpse = n, spores = n, chance = { [diseaseId] = n } }.
function ServerEmotions.corpseRisk(player)
    local corpse = factor(EHR.CorpseSickness.GetEnvironmentMultiplier(player))
    local spores = factor((EHR.CorpseSickness.GetFungalEnvironment(player)))
    local chance = {}
    for _, id in ipairs(ServerEmotions.CORPSE_DISEASES) do
        chance[id] = factor(EHR.Disease.TryContract(player, id, ServerEmotions.PROBE)) / ServerEmotions.PROBE
    end
    return { corpse = corpse, spores = spores, chance = chance }
end

-- Runs after Facts' "corpses" reader (name order). Nothing to ask with no corpse around.
Facts.extend("emotions", function(player, facts)
    if broken.corpses or not ours() then
        return
    end
    local seen = facts.corpses
    if not seen or (seen.fresh or 0) + (seen.decomposing or 0) + (seen.rotten or 0) <= 0 then
        return
    end
    local ok, risk = pcall(ServerEmotions.corpseRisk, player)
    if ok then
        facts.corpseRisk = risk
    else
        fail("corpses", risk)
    end
end)

-- Generic ties (Emotions' public API) --------------------------------------------------------------------------------

local function medicalLevel(state)
    return (MoodleLevels.medical(state.conditions, state.wounds, nil))
end

-- Strain 0-1 for Emotions' Sanity: the medical alert level, medication side effects left out.
function ServerEmotions.strainFor(state)
    return ServerEmotions.STRAIN[medicalLevel(state)] or 0
end

-- Dizziness level for Emotions (1 light, 2 strong), or nil while our vision blur is off.
function ServerEmotions.dizzyFor(state)
    local blur = state.effects and tonumber(state.effects.blur) or 0
    if blur <= 0 then
        return nil
    end
    return blur >= ServerEmotions.DIZZY_STRONG and 2 or 1
end

-- Whether Concentrating is blocked: a severe illness, or dizziness.
function ServerEmotions.focusBlockedFor(state)
    return medicalLevel(state) >= ServerEmotions.FOCUS_FROM or ServerEmotions.dizzyFor(state) ~= nil
end

local function stateOf(player)
    local key = player and PlayerKey.of(player)
    return key and Runtime.store:get(key) or nil
end

-- Emotions calls these (each in its own pcall, cached about a second per player).
local function strainProvider(player)
    local state = ours() and stateOf(player) or nil
    if not state then
        return nil
    end
    return ServerEmotions.strainFor(state)
end

local function blocker(player, what)
    local state = what == "focus" and ours() and stateOf(player) or nil
    if not state then
        return false
    end
    return ServerEmotions.focusBlockedFor(state)
end

local API = {
    { fn = "registerStrain", tie = "strain", provider = strainProvider },
    { fn = "registerBlock", tie = "focus block", provider = blocker },
}

local registered = false

-- Registers our providers with Emotions, once. Its registries take the same id again as a replacement.
function ServerEmotions.register()
    local HE = HardshipEmotions
    if registered or type(HE) ~= "table" then
        return registered
    end
    registered = true
    for _, api in ipairs(API) do
        if type(HE[api.fn]) == "function" then
            HE[api.fn](ServerEmotions.API_ID, api.provider)
        else
            log:warn("this Hardship: Emotions version has no", api.fn .. "; the", api.tie, "tie is off")
        end
    end
    return true
end

-- Reports our dizziness for one player (every game minute while it lasts).
function ServerEmotions.reportDizzy(player, state)
    local level = ServerEmotions.dizzyFor(state)
    local HE = HardshipEmotions
    if level and type(HE) == "table" and type(HE.addDizzy) == "function" then
        HE.addDizzy(player, ServerEmotions.DIZZY_MINUTES, level)
    end
end

-- The original's modData ----------------------------------------------------------------------------------------------

-- The three tables for one state, in the original's shape.
function ServerEmotions.mirror(state)
    local flag = ServerEmotions.MIRROR_FLAG
    local active = {}
    for id, c in pairs(state.conditions.active) do
        active[id] = { stage = c.stage, severity = c.severity }
    end
    local exposure = state.exposure
    local corpse = exposure.data and exposure.data.corpse
    return {
        EHR_Blood = { [flag] = true, currentVolume = state.blood.volume, maxVolume = state.blood.max },
        EHR_Disease = { [flag] = true, active = active },
        EHR_CorpseSickness = { [flag] = true, currentExposure = exposure.corpse,
            lastCorpseCount = corpse and corpse.corpses or 0 },
    }
end

function ServerEmotions.writeMirror(player, state)
    local modData = player:getModData()
    for key, value in pairs(ServerEmotions.mirror(state)) do
        modData[key] = value
    end
end

-- Removes the mirror from a player.
function ServerEmotions.clearMirror(player)
    local modData = player:getModData()
    for _, key in ipairs(ServerEmotions.MIRROR_KEYS) do
        local value = modData[key]
        if type(value) == "table" and value[ServerEmotions.MIRROR_FLAG] then
            modData[key] = nil
        end
    end
end

-- Every game minute on our scheduler (Emotions reads it every minute too): rewrites the mirror and reports dizziness.
-- With IntegrateEHR switched off mid-game, the mirror is removed instead. A save that drops Emotions keeps its last
-- mirror, which nothing reads.
local function everyMinute()
    if shim == nil or EHR ~= shim then
        return
    end
    local on = Emotions.integrated()
    Runtime.eachAttached(function(key, player, state)
        if not broken.mirror then
            local ok, err = pcall(on and ServerEmotions.writeMirror or ServerEmotions.clearMirror, player, state)
            if not ok then
                fail("mirror", tostring(key) .. ": " .. tostring(err))
            end
        end
        if on and not broken.dizzy then
            local ok, err = pcall(ServerEmotions.reportDizzy, player, state)
            if not ok then
                fail("dizzy", tostring(key) .. ": " .. tostring(err))
            end
        end
    end)
end

-- Forgets the install (tests, and a new game in the same session).
function ServerEmotions.reset()
    if shim and EHR == shim then
        EHR = nil
    end
    shim = nil
    broken = {}
    if registered and type(HardshipEmotions) == "table" then
        for _, api in ipairs(API) do
            if type(HardshipEmotions[api.fn]) == "function" then
                HardshipEmotions[api.fn](ServerEmotions.API_ID, nil)
            end
        end
    end
    registered = false
    Emotions.reset()
end

ServerEmotions.install()
Events.OnGameStart.Add(ServerEmotions.install)
Events.OnServerStarted.Add(ServerEmotions.install)
Runtime.scheduler:every("emotionsMirror", 1, everyMinute, { coalesce = true })

return ServerEmotions
