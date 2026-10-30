-- An admin's full heal and state reset (/ehrfullheal, /ehrreset, the debug menu's Full heal and Reset state), decided
-- here and applied by Server/Admin inside Runtime.applyNow. Pure: it changes the state and states its wishes through
-- p.stats and p.body like any system, so the stat and body writers do the vanilla side.
--
-- Two commands:
--   "heal"   every health part of the state back to normal, the identity kept: blood type, knowledge, permanent
--            Knox immunity and its source, Knox item history (last test, survivor, immunobooster protection and
--            cooldown, Phalanx doses), the immunity score (recomputed on the next step), First Aid XP cooldowns and the
--            re-catch blocks.
--   "reset"  the whole state back to a new character's, keeping only meta, blood type, knowledge and permanent Knox
--            immunity with its source. The vanilla side is the same as a full heal.
-- Both: an active Knox infection is cured, every condition ends through the engine with the reason "admin" (no First
-- Aid XP, the normal re-catch blocks), wound infections are cured, every body part is restored, and the needs and
-- health stats are zeroed (with vanilla's Knox infection stats).
-- Add-on sections (Core/Schema.registerSection): a reset puts them back to their defaults; a heal only those
-- registered with resetOnHeal. Listeners (FullHeal.onHeal) run last, inside the same step, for anything else an
-- add-on keeps.

local Schema = require "ExtensiveHealthRedone/Core/Schema"
local Tables = require "ExtensiveHealthRedone/Core/Tables"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Infection = require "ExtensiveHealthRedone/Wounds/Infection"
local KnoxItems = require "ExtensiveHealthRedone/Diseases/Knox/Items"

local FullHeal = {}

local healListeners = {}

-- fn(p, mode) after a full heal or reset ("heal" or "reset") changed the state, before the writers run.
function FullHeal.onHeal(fn)
    healListeners[#healListeners + 1] = fn
end

local function healsAddon(name)
    local spec = Schema.ADDONS[name]
    return spec ~= nil and spec.resetOnHeal
end

-- The source of every wish and the reason conditions end with.
FullHeal.SOURCE = "admin"
FullHeal.REASON = "admin"

-- Stats driven to the bottom of their range: needs and health, plus vanilla's Knox infection.
FullHeal.ZEROED_STATS = {
    "HUNGER", "THIRST", "FATIGUE", "BOREDOM", "UNHAPPINESS", "PAIN", "PANIC", "STRESS", "SICKNESS", "FOOD_SICKNESS",
    "POISON", "ZOMBIE_INFECTION", "ZOMBIE_FEVER",
}

-- Sections a full heal puts back to their defaults as a whole.
FullHeal.HEAL_SECTIONS = { "body", "wounds", "exposure", "mind", "effects", "temperature" }

-- Sections a reset keeps as they are; knox keeps only KNOX_IDENTITY.
FullHeal.RESET_KEEPS = { meta = true, identity = true, knowledge = true }
FullHeal.KNOX_IDENTITY = { "geneTherapyImmune", "immunityTraitGranted", "patientZeroTraitSource" }

-- Conditions may hand off to others while ending (onEnd); a few passes end those too.
local MAX_PASSES = 5

local function endConditions(p, defs)
    local ended = 0
    for _ = 1, MAX_PASSES do
        local ids = Tables.sortedKeys(p.state.conditions.active)
        if #ids == 0 then
            break
        end
        for _, id in ipairs(ids) do
            if Engine.finish(p, defs, id, FullHeal.REASON) then
                ended = ended + 1
            end
        end
    end
    return ended
end

local function countWoundInfections(state)
    local n = 0
    for _ in pairs(state.wounds.parts) do
        n = n + 1
    end
    return n
end

local function zeroStats(p)
    for _, stat in ipairs(FullHeal.ZEROED_STATS) do
        -- A stat the game no longer has is left out by the stat writer's ranges; skip it rather than fail the heal.
        if p.stats.ranges[stat] then
            p.stats:ceilingF(stat, FullHeal.SOURCE, 0)
        end
    end
end

-- The health sections of a full heal, after the conditions have ended (their onEnd may still write to them).
local function resetHealth(p)
    local state = p.state
    local max = state.blood.max
    state.blood = Schema.sectionDefaults("blood")
    state.blood.max = max
    state.blood.volume = max
    for _, name in ipairs(FullHeal.HEAL_SECTIONS) do
        state[name] = Schema.sectionDefaults(name)
    end
    for _, name in ipairs(Schema.SECTIONS) do
        if healsAddon(name) then
            state[name] = Schema.sectionDefaults(name)
        end
    end
    local xpCooldown = state.meds.xpCooldown
    state.meds = Schema.sectionDefaults("meds")
    state.meds.xpCooldown = xpCooldown or {}
    state.knox.effects = {}
    state.immunity.tick = 0     -- recompute now that meds, Knox and the body are clear
end

local function resetAll(p)
    local state = p.state
    for _, name in ipairs(Schema.SECTIONS) do
        if not FullHeal.RESET_KEEPS[name] then
            local fresh = Schema.sectionDefaults(name)
            if name == "knox" then
                for _, field in ipairs(FullHeal.KNOX_IDENTITY) do
                    fresh[field] = state.knox[field]
                end
            end
            state[name] = fresh
        end
    end
end

-- Sections the mode changes, in sync order.
function FullHeal.touched(mode)
    local list = {}
    for _, name in ipairs(Schema.SECTIONS) do
        if mode == "reset" then
            if not FullHeal.RESET_KEEPS[name] then
                list[#list + 1] = name
            end
        elseif name ~= "meta" and name ~= "identity" and name ~= "knowledge"
            and (not Schema.ADDONS[name] or healsAddon(name)) then
            list[#list + 1] = name
        end
    end
    return list
end

-- mode: "heal" (default) or "reset". Returns { conditions = ended, woundInfections = cured }.
function FullHeal.apply(p, defs, mode)
    if mode ~= "reset" then
        mode = "heal"
    end
    local summary = { woundInfections = countWoundInfections(p.state) }
    KnoxItems.clearInfection(p, FullHeal.SOURCE)
    Infection.cureAll(p)
    summary.conditions = endConditions(p, defs)
    if mode == "reset" then
        resetAll(p)
    else
        resetHealth(p)
    end
    zeroStats(p)
    p.body:fullRestore(FullHeal.SOURCE)
    for _, fn in ipairs(healListeners) do
        fn(p, mode)
    end

    for _, name in ipairs(FullHeal.touched(mode)) do
        p.dirty(name)
    end
    return summary
end

return FullHeal
