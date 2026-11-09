-- Gangrene: dead tissue on a hand or foot that rots. A part held at stage 4 (necrosis) of trench foot or frostbite
-- for GangreneOnsetHours starts it (Gangrene.onset, called by those conditions); a second part joins the running
-- case. A timed condition like cellulitis: pain and damage on each gangrenous part, then fever, sickness and fatigue.
-- Untreated stage 4 turns into sepsis; it ends only when sepsis actually starts, and while sepsis runs or is blocked
-- it stays and tries again.
--
-- Treatment: an antibiotic course cures it (Medication/Data: prescription, broad-spectrum, plant-based and IV
-- antibiotics; the engine holds the stage meanwhile). The Only Cure: cutting off a gangrenous hand removes that part,
-- and the last part gone cures it (Wounds/Amputation's onCut). Feet can't be amputated, so foot gangrene needs
-- antibiotics. While a part is gangrenous, its trench foot or frostbite stays at stage 4.
--
-- c.data.parts = { [part] = { stage = 1 } } (Diseases/Extremities/Parts, for the label); c.source is the first part.

local Data = require "ExtensiveHealthRedone/Diseases/Extremities/Data"
local Parts = require "ExtensiveHealthRedone/Diseases/Extremities/Parts"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.gangrene
local ID = "gangrene"

-- The conditions whose stage 4 leads here; their parts keep a necrosis timer (hours at stage 4).
local SOURCES = { "trench_foot", "frostbite" }

local LINES = {
    [1] = "UI_EHR_Extremities_GangreneBlackening",
    [2] = "UI_EHR_Extremities_GangreneSmell",
    [3] = "UI_EHR_Extremities_GangreneFever",
}

local Gangrene = {
    enabledOption = "GangreneEnabled",
    speedOption = "DiseaseSpeed",
    stages = D.STAGES,
    persistsAt = 4,
    effectsInStage1 = true,
    baseSeverity = 0.8,
    blockAfterCureHours = D.BLOCK_AFTER_CURE_H,
    knowledge = ID,
    name = "UI_EHR_Disease_gangrene",
    debugSource = "Foot_L",
    lines = {
        random = {
            [2] = { "UI_EHR_Extremities_GangreneSmell", "UI_EHR_Extremities_GangreneThrob" },
            [3] = { "UI_EHR_Extremities_GangreneThrob", "UI_EHR_Extremities_GangreneFever" },
            [4] = { "UI_EHR_Extremities_GangreneFever", "UI_EHR_Extremities_GangreneDying" },
        },
        every = 240,
    },
}

function Gangrene.onsetHours(p)
    local v = tonumber(p.sandbox("GangreneOnsetHours", 24)) or 24
    return math.max(6, math.min(168, v))
end

-- The part has gangrene now.
function Gangrene.has(p, part)
    local c = p.state.conditions.active[ID]
    return c ~= nil and c.data.parts ~= nil and c.data.parts[part] ~= nil
end

-- Starts gangrene on a part, or adds the part to the running case. Returns true when the part is gangrenous now.
function Gangrene.start(p, defs, part)
    local c = p.state.conditions.active[ID]
    if not c then
        c = Engine.contract(p, defs, ID, { source = part })
        if not c then
            return false
        end
        Speech.stage(p, LINES[1])
    end
    Parts.setStage(p, c, part, 1)
    return true
end

-- Called by trench foot and frostbite each step for a part at stage 4: counts the hours there and starts gangrene
-- once they reach GangreneOnsetHours. entry is that condition's part entry (Parts.get).
function Gangrene.onset(p, defs, part, entry, h)
    if Gangrene.has(p, part) or not Engine.enabled(p, defs[ID]) then
        return
    end
    entry.necrosis = (entry.necrosis or 0) + h
    if entry.necrosis >= Gangrene.onsetHours(p) then
        Gangrene.start(p, defs, part)
    end
end

-- A part left stage 4 (or the condition ended): the necrosis count starts over.
function Gangrene.resetOnset(entry)
    if entry then
        entry.necrosis = nil
    end
end

-- Removes a part (amputated). The last part gone cures it: XP only when the cut was known to EHR (not a cut it found
-- already made, Wounds/Amputation).
function Gangrene.dropPart(p, defs, part, known)
    local c = p.state.conditions.active[ID]
    if not c or not Parts.drop(p, c, part) then
        return
    end
    if c.source == part then
        local _, worst = Parts.worst(c)
        c.source = worst
    end
    if Parts.worst(c) == 0 then
        Engine.finish(p, defs, ID, known and "cured" or "debug")
        Speech.stage(p, "UI_EHR_Extremities_GangreneCutAway")
    end
end

-- Untreated stage 4: hand off to sepsis (like cellulitis).
local function handOff(p, c, defs)
    if Engine.contract(p, defs, "sepsis", { source = c.source }) then
        Engine.finish(p, defs, ID, "complication")
        Speech.stage(p, "UI_EHR_Extremities_GangreneSpreads")
        return true
    end
    return false
end

function Gangrene.onStage(p, c, stage)
    Speech.stage(p, LINES[stage])
    -- A debug start has no parts yet: it lands on its source.
    Parts.seed(p, c, Gangrene.debugSource, function(_, cc, part) Parts.setStage(p, cc, part, 1) end)
end

function Gangrene.effects(p, c, dt, curing, defs)
    Parts.seed(p, c, Gangrene.debugSource, function(_, cc, part) Parts.setStage(p, cc, part, 1) end)
    if c.stage == 4 and not curing and handOff(p, c, defs) then
        return
    end
    local row = D.ROWS[c.stage]
    if not row then
        return
    end
    local t = p.treatment
    local sev = c.severity or 1
    local treat = curing and 0.4 or 1
    local painRelief = math.max(t:relief(ID, "pain"), 0.85 * t:relief(ID, "inflammation"))
    local painMult = math.max(curing and 0.2 or 0.4, treat * (1 - 1.3 * painRelief))
    local h = dt / 60
    for _, e in ipairs(Parts.list(c)) do
        p.body:pain(e.part, ID, row.pain * painMult)
        p.body:partDamage(e.part, ID, row.damage * treat * h)
        p.body:healFactor(e.part, ID, 0)
    end
    if row.fever then
        local k = Symptoms.TICK * dt
        p.stats:raiseF("SICKNESS", ID, row.sickness, 0.0028 * sev * k)
        p.stats:raiseF("FATIGUE", ID, row.fatigue, 0.0014 * sev * k)
        local target, step = row.fever, row.feverStep * sev * k
        if curing then
            target = math.min(target, 37.6)
        end
        target, step = Symptoms.fever(target, step, t:relief(ID, "fever"))
        Symptoms.applyFever(p, ID, target, step)
    end
end

-- Ending (cure, sepsis, amputation, admin): the trench foot and frostbite parts start their necrosis count over, so
-- a part still at stage 4 needs the full onset time again.
function Gangrene.onEnd(p, c, reason)
    for _, id in ipairs(SOURCES) do
        local other = p.state.conditions.active[id]
        if other and other.data.parts then
            for part in pairs(c.data.parts or {}) do
                Gangrene.resetOnset(other.data.parts[part])
            end
        end
    end
    if reason == "cured" then
        Speech.stage(p, "UI_EHR_Extremities_GangreneStopped")
    end
end

function Gangrene.monitorRow(row, c, known)
    if not known.name then
        return
    end
    row.description = Parts.label(c)
    row.descriptionColor = "red"
end

return Gangrene
