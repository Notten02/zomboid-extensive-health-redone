-- Wound infection, per body part. A vanilla-infected open wound starts an incubation (12 h / WoundInfectionSpeed);
-- the immune system gets one roll to contain it; otherwise the part goes through stages 1-3 (12/24/48 h), and when
-- stage 3 runs out untreated the infection reaches the blood: sepsis. Disinfecting during the incubation prevents it.
-- From v0.9 EHR_WoundInfection_V2.lua (docs/porting/phase3/wound-infection-sepsis-tetanus.md, part 1). Changes:
--   * disinfecting an active infection no longer restarts its stage (v0.9 let you stall it forever)
--   * antiseptic cream prevents new infections while active, instead of deferring them
--   * the healing penalty per stage exists (W21)
-- State per part, state.wounds.parts[part]:
--   { phase = "incubating", left = minutes, immune = score at detection, rolled = bool }
--   { phase = "infected", stage = 1..3, left = minutes in the stage }

local Data = require("ExtensiveHealthRedone/Data/Wounds").infection
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Risk = require "ExtensiveHealthRedone/Conditions/Risk"

local Infection = {}

local function speed(p)
    local s = tonumber(p.sandbox("WoundInfectionSpeed", 1.0)) or 1
    if s < 0.1 then s = 0.1 end
    if s > 10 then s = 10 end
    return s
end

local function stageMinutes(p, stage)
    return Data.STAGE_HOURS[stage] * 60 / speed(p)
end

-- Chance the immune system contains an incubating infection, from the immunity score (0-100) and the effect strength
-- (Conditions/Risk.strength, default 1; 0 when immunity has no gameplay effects).
function Infection.containChance(score, strength)
    strength = strength or 1
    if score <= Data.CONTAIN_FROM or strength <= 0 then
        return 0
    end
    return math.min(Data.CONTAIN_MAX, (score - Data.CONTAIN_FROM) / Data.CONTAIN_SPAN * Data.CONTAIN_SCALE * strength)
end

local function contained(p, e)
    local score = ((e.immune or 50) + (p.state.immunity.score or 50)) / 2
    return Chance.roll(p.rng, Infection.containChance(score, Risk.strength(p)))
end

local function remove(p, parts, name)
    parts[name] = nil
    p.body:disinfect(name, "woundInfection")
    p.dirty("wounds")
end

local function becomeInfected(p, parts, name)
    parts[name] = { phase = "infected", stage = 1, left = stageMinutes(p, 1) }
    Speech.stage(p, Data.LINES[1])
    p.dirty("wounds")
end

-- The end of stage 3, untreated: sepsis. The part stays at stage 3 and its timer restarts (v0.9).
local function handOff(p, e, defs)
    e.left = stageMinutes(p, 3)
    if Engine.contract(p, defs, "sepsis", { source = "woundInfection" }) then
        Speech.stage(p, Data.SEPSIS_LINE)
    end
end

local function progress(p, parts, name, e, dt, curing, defs)
    if e.phase == "incubating" then
        local fact = p.facts.parts[name] or {}
        e.left = e.left - dt
        local healed = not fact.wound
        if not e.rolled and (healed or e.left <= 0) then
            e.rolled = true
            if contained(p, e) then
                remove(p, parts, name)
                return
            end
        end
        if e.left <= 0 then
            becomeInfected(p, parts, name)
        end
        return
    end
    if curing then
        return
    end
    e.left = e.left - dt
    if e.left > 0 then
        return
    end
    if e.stage < 3 then
        e.stage = e.stage + 1
        e.left = e.left + stageMinutes(p, e.stage)
        Speech.stage(p, Data.LINES[e.stage])
        p.dirty("wounds")
    else
        handOff(p, e, defs)
    end
end

local function effects(p, name, e)
    if e.phase ~= "infected" then
        return
    end
    local relief = p.treatment:relief("woundInfection", "pain")
    local pain = Data.PAIN[e.stage] * (1 - relief)
    if pain > 0 then
        p.body:pain(name, "woundInfection", pain)
    end
    p.body:healFactor(name, "woundInfection", Data.HEAL_FACTOR[e.stage])
end

local function fever(p, worst, dt)
    if worst >= Data.FEVER_STAGE then
        local target, step = Data.FEVER_C, Data.FEVER_STEP * dt
        local relief = p.treatment:relief("woundInfection", "fever")
        if relief >= 0.6 then
            target = math.max(37.0, target - 2.0)
        elseif relief > 0 then
            target = math.max(37.3, target - math.min(0.8, relief * 1.2))
        end
        p.stats:raise("TEMPERATURE", "woundInfection", target, step * math.max(0.35, 1 - relief))
    end
end

function Infection.update(p, dt, defs)
    if p.sandbox("WoundInfectionEnabled", true) == false then
        return
    end
    local parts = p.state.wounds.parts
    local facts = (p.facts and p.facts.parts) or {}
    local antiseptic = p.treatment:active("antiseptic")
    local curing = p.treatment:curing("woundInfection")
    local worst = 0
    for _, name in ipairs(BodyParts.names) do
        local fact = facts[name] or {}
        local e = parts[name]
        if fact.infected and not e then
            if antiseptic or not fact.wound then
                -- Prevented by antiseptic cream, or vanilla residue on a healed part.
                p.body:disinfect(name, "woundInfection")
            else
                parts[name] = { phase = "incubating", left = Data.INCUBATION_HOURS * 60 / speed(p),
                    immune = p.state.immunity.score, rolled = false }
                p.dirty("wounds")
            end
        elseif e then
            progress(p, parts, name, e, dt, curing, defs)
            e = parts[name]
            if e then
                effects(p, name, e)
                if e.phase == "infected" and e.stage > worst then
                    worst = e.stage
                end
            end
        end
    end
    fever(p, worst, dt)
end

-- A wound on this part was disinfected (vanilla ISDisinfect, or an alcoholic bandage). Returns what happened:
-- "prevented" (an incubation stopped), "cleaned" (vanilla residue removed), "stillInfected" or "none".
function Infection.disinfected(p, name)
    local parts = p.state.wounds.parts
    local e = parts[name]
    local fact = ((p.facts and p.facts.parts) or {})[name] or {}
    if e and e.phase == "incubating" then
        remove(p, parts, name)
        Speech.stage(p, Data.PREVENTED_LINE)
        return "prevented"
    end
    if e then
        Speech.stage(p, Data.STILL_INFECTED_LINE)
        return "stillInfected"
    end
    if fact.infected then
        p.body:disinfect(name, "woundInfection")
        Speech.stage(p, Data.PREVENTED_LINE)
        return "cleaned"
    end
    return "none"
end

-- A dose of vanilla antibiotics: every infected part drops one stage; below stage 1 it is cured. Incubations are
-- untouched (v0.9). Returns the number of parts improved.
function Infection.antibiotics(p)
    local parts = p.state.wounds.parts
    local improved = 0
    for _, name in ipairs(BodyParts.names) do
        local e = parts[name]
        if e and e.phase == "infected" then
            improved = improved + 1
            if e.stage <= 1 then
                remove(p, parts, name)
            else
                e.stage = e.stage - 1
                e.left = stageMinutes(p, e.stage)
                p.dirty("wounds")
            end
        end
    end
    return improved
end

-- Removes every wound infection (a completed course in Phase 5, admin heal, debug).
function Infection.cureAll(p)
    local parts = p.state.wounds.parts
    for _, name in ipairs(BodyParts.names) do
        if parts[name] then
            remove(p, parts, name)
        end
    end
end

-- Starts an infection directly (debug): an incubation, or a stage.
function Infection.start(p, name, stage)
    local parts = p.state.wounds.parts
    if stage and stage >= 1 then
        parts[name] = { phase = "infected", stage = math.min(3, stage), left = stageMinutes(p, math.min(3, stage)) }
    else
        parts[name] = { phase = "incubating", left = Data.INCUBATION_HOURS * 60 / speed(p),
            immune = p.state.immunity.score, rolled = false }
    end
    p.dirty("wounds")
end

return Infection
