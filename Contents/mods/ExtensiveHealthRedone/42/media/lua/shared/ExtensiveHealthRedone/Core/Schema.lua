-- The versioned shape of a player's health state, and the migration chain that upgrades old saves.
--
-- The whole state is one plain table stored in the player's modData under ROOT_KEY. Each top-level field except
-- `version` is a section: the unit of dirty tracking and sync. Timers inside sections store remaining durations
-- (Core/Timers), never absolute world times, so nothing has to be shifted when a player logs back in.
--
-- Changing the shape: bump VERSION and add MIGRATIONS[oldVersion] = function(state) ... end, which upgrades a state in
-- place from oldVersion to oldVersion + 1. Never edit a released migration. New sections also go into SECTIONS and
-- defaults(). Later phases add their sections this way (blood in Phase 3, diseases in Phase 4, ...).

local BloodTypes = require "ExtensiveHealthRedone/Core/BloodTypes"
local ImmunityData = require "ExtensiveHealthRedone/Data/Immunity"

local Schema = {}

Schema.ROOT_KEY = "ExtensiveHealthRedone"
Schema.VERSION = 5

-- Sync order. Every section is sent to the owning client.
Schema.SECTIONS = { "meta", "identity", "knowledge", "knox", "immunity", "blood", "body", "wounds", "conditions",
    "exposure", "mind", "effects", "meds", "temperature" }

-- The Phase 3 sections, also used by migration 1.
local function bloodDefaults()
    return {
        volume = 5000,          -- mL
        max = 5000,             -- mL
        saline = 0,             -- mL of transfused saline still diluting the blood (hemodilution)
        stage = 4,              -- 4 healthy, 3 mild, 2 moderate, 1 critical (functional: beta blockers shift it)
        bleeding = false,
        lossRate = 0,           -- mL per game minute, for display (negative while regenerating)
        blackout = false,       -- asleep because of a blood-loss blackout
        blackoutFor = 0,        -- game minutes since the blackout began
        timers = {},            -- regenDelay, blackoutCooldown (minutes left)
    }
end

local function bodyDefaults()
    return {
        healLock = {},          -- [part] = HP the part may not heal past while healing is slowed or blocked
        painApplied = {},       -- [part] = extra pain we have added and will remove again
        healing = { blocked = false, reason = nil },   -- conditional healing status, for the UI
    }
end

local function woundsDefaults()
    return {
        parts = {},             -- [part] = wound infection: { phase = "incubating"|"infected", stage, left, ... }
        tetanus = { glass = {}, dirty = {}, seen = {} },   -- tetanus trigger bookkeeping per part
    }
end

local function conditionsDefaults()
    return {
        active = {},            -- [conditionId] = { stage, left, duration, severity, data } (Conditions/Engine)
        timers = {},            -- e.g. sepsisBlock (minutes left)
    }
end

-- The Phase 4 sections, also used by migration 2.
local function exposureDefaults()
    return {
        cold = 0,               -- 0-100 cold-and-wet exposure (common cold)
        heat = 0,               -- 0-100 heat exposure (heat exhaustion, heat stroke)
        corpse = 0,             -- 0-100 corpse exposure (corpse illness)
        spores = 0,             -- 0-100 spore exposure (cadaveric aspergillosis)
        timers = {},            -- trigger cadences and cooldowns (minutes left)
        data = {},              -- per-trigger scratch (Exposure/*)
    }
end

local function mindDefaults()
    return {
        stressFor = 0,          -- game minutes stress has been at its maximum (delirium)
        tiredFor = 0,           -- game minutes awake with fatigue above the insomnia threshold
        painkiller = {          -- painkiller dependency (painkiller addiction)
            risk = 0,           -- 0-100; addiction starts at 100
            doses = {},         -- minutes since each dose in the last 24 h, newest last
            clean = 0,          -- minutes since the last dose
        },
    }
end

local function knoxActiveDefaults(knox)
    knox.boosterLeft = 0            -- minutes of immunobooster protection left
    knox.boosterCooldown = 0        -- minutes until another immunobooster can be taken
    knox.phalanxUses = 0            -- Phalanx doses taken (each resets progress less)
    knox.effects = {}               -- [effect] = minutes left (W33 side effects)
end

local function effectsDefaults()
    return { speed = 1, noSprint = false, blur = 0, tint = 0, noSleep = false, sleepBy = false, attackSpeed = 1,
        boost = 1, bladder = 0 }
end

-- The Phase 5 section, also used by migration 3 (Medication/Doses).
local function medsDefaults()
    return {
        doses = {},             -- [medId] = { since = minutes since the last dose }
        courses = {},           -- [medId] = { count, elapsed = minutes since the first dose, cured = {} }
        effects = {},           -- [effectId] = { left = minutes, data } (Medication/Effects)
        side = {},              -- [sideEffectId] = { left = minutes, data } (Medication/SideEffects)
        overdose = false,       -- { level, left, early } while overdosed (Medication/Overdose)
        pairs = {},             -- [interactionId] = true while it has fired (Medication/Interactions)
        xpCooldown = {},        -- [medId] = minutes until a dose gives First Aid XP again
    }
end

-- The Phase 6 immunity fields (Immunity/Immunity). target stays false until the first update.
local function immunityDefaults(score)
    return {
        score = score,          -- 0-100
        target = false,         -- 0-100 after suppression; false until the first update
        trend = "stable",       -- "recovering", "declining", "stable" or "disabled"
        factors = {},           -- nutrition, hydration, rest, stressControl, bloodCondition, healthReserve (0-100)
        hygiene = {},           -- dirtiness, bloodiness (0-100), dirtPenalty, bloodPenalty, penalty
        pressures = {},         -- antibiotic, immunosuppression, phalanx (points) while they apply
        tick = 0,               -- game minutes until the next update
    }
end

-- The Phase 6 body temperature hold (Body/Temperature).
local function temperatureDefaults()
    return {
        fever = false,          -- deg C of the fever, or false
        source = false,         -- what asked for the highest fever target
        warm = false,           -- deg C the Warming Pack holds, or false
        food = { hot = false, cold = false },   -- hot and cold food effects
        floor = false,          -- deg C vanilla's TEMPERATURE is held at or above, or false
        ceiling = false,        -- deg C it is held at or below, or false
        shown = false,          -- floor/ceiling rounded to 0.1 at the last sync
        cold = 0, hot = 0,      -- pre-disease stages 0-4 (Body/TemperatureStages)
        lineIn = 0,             -- game minutes until the next pre-disease line
        lastThirst = false,     -- THIRST expected after the last write (very-hot thirst drain)
    }
end

-- [fromVersion] = function(state) that upgrades to fromVersion + 1.
Schema.MIGRATIONS = {
    -- 1 -> 2 (Phase 3): blood, body, wounds and conditions sections.
    [1] = function(state)
        state.blood = bloodDefaults()
        state.body = bodyDefaults()
        state.wounds = woundsDefaults()
        state.conditions = conditionsDefaults()
    end,
    -- 2 -> 3 (Phase 4): exposure meters, the mind section, Knox item state, and the client effects.
    [2] = function(state)
        state.exposure = exposureDefaults()
        state.mind = mindDefaults()
        knoxActiveDefaults(state.knox)
        state.effects = effectsDefaults()
    end,
    -- 3 -> 4 (Phase 5): medication. The new client effect fields are filled in by fillDefaults.
    [3] = function(state)
        state.meds = medsDefaults()
    end,
    -- 4 -> 5 (Phase 6): the immune system and the fever hold. The saved score is kept.
    [4] = function(state)
        local score = type(state.immunity) == "table" and tonumber(state.immunity.score) or ImmunityData.START
        state.immunity = immunityDefaults(score)
        state.temperature = temperatureDefaults()
    end,
}

-- Defaults for every section. bloodType is filled in by new().
function Schema.defaults()
    return {
        version = Schema.VERSION,
        meta = {
            createdAs = "new",      -- "new" or "imported"
            importedFrom = nil,     -- mod ID of the original when imported
        },
        identity = {
            bloodType = nil,        -- "O-" ... "AB+" (Data/BloodTypes)
        },
        knowledge = {
            diseases = {},          -- [knowledgeId] = true, e.g. common_cold = true
            knoxHerald = false,     -- read the Kentucky Herald (needed for knox_infection knowledge)
            wildPlants = false,     -- read the medical wild plants guide
            professionGrant = nil,  -- profession whose disease knowledge was granted ("ehrdoctor", "ehrsurgeon")
            radioHeard = {},        -- [broadcast slot key] = true, so a broadcast rewards once
        },
        knox = {
            geneTherapyImmune = false,
            immunityTraitGranted = false,
            patientZeroTraitSource = false,
            boosterLeft = 0, boosterCooldown = 0, phalanxUses = 0, effects = {},   -- see knoxActiveDefaults
        },
        immunity = immunityDefaults(ImmunityData.START),
        blood = bloodDefaults(),
        body = bodyDefaults(),
        wounds = woundsDefaults(),
        conditions = conditionsDefaults(),
        exposure = exposureDefaults(),
        mind = mindDefaults(),
        effects = effectsDefaults(),
        meds = medsDefaults(),
        temperature = temperatureDefaults(),
    }
end

-- A fresh copy of one section's defaults (Admin/FullHeal resets sections one by one). Errors on an unknown name.
function Schema.sectionDefaults(name)
    local section = Schema.defaults()[name]
    if type(section) ~= "table" then
        error("unknown state section " .. tostring(name), 2)
    end
    return section
end

function Schema.new(rng)
    local state = Schema.defaults()
    state.identity.bloodType = BloodTypes.roll(rng)
    return state
end

-- Adds sections and fields missing from a state, without touching what is there. Defaults only fill gaps one level
-- deep: section fields, not their contents.
function Schema.fillDefaults(state)
    local defaults = Schema.defaults()
    for _, name in ipairs(Schema.SECTIONS) do
        local section = defaults[name] --[[@as table]]
        if type(state[name]) ~= "table" then
            state[name] = section
        else
            for field, value in pairs(section) do
                if state[name][field] == nil then
                    state[name][field] = value
                end
            end
        end
    end
end

-- Upgrades a saved state in place. Returns true, or false and a reason when the state can't be used: it has no
-- version, a migration is missing, or it was saved by a newer version of the mod (left untouched, never downgraded).
-- migrations and target default to the module's own; tests pass their own chain. Callers follow a successful upgrade
-- with fillDefaults.
function Schema.upgrade(state, migrations, target)
    migrations = migrations or Schema.MIGRATIONS
    target = target or Schema.VERSION
    if type(state) ~= "table" or type(state.version) ~= "number" then
        return false, "state has no version"
    end
    if state.version > target then
        return false, "state is schema version " .. state.version .. ", newer than this mod's " .. target
    end
    while state.version < target do
        local migrate = migrations[state.version]
        if not migrate then
            return false, "no migration from schema version " .. state.version
        end
        migrate(state)
        state.version = state.version + 1
    end
    return true
end

return Schema
