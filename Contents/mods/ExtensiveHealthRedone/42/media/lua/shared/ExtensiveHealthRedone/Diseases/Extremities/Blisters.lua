-- Foot blisters: friction from walking in shoes builds up per foot (frictionH, game hours). Shoes on bare feet, wet
-- socks, worn-out or holed footwear and running build it faster; a blister patch or a clean bandage on the foot slows
-- it, and it falls while the feet rest. Stage 1 hot spot, 2 blister, 3 burst: bursting opens a real (vanilla) scratch
-- on the foot, so bandaging, disinfecting and EHR's wound infection apply to it.
--
-- Blisters heal by themselves: each foot steps down a stage after enough healing hours (Data.blisters.HEAL_H). Rest
-- heals, sleep faster, walking in dry socks and decent shoes slowly (and rubs a blistered foot no further), and bad
-- going (running, wet or no socks, worn or holed shoes) not at all. A blister patch doubles the healing, and a patch cures them within 24 h (Medication/Data).
-- Barefoot walking builds no friction here (vanilla has its own barefoot hazards). Warmth and cold don't affect them.
--
-- A driven condition with one instance for both feet (Diseases/Extremities/Parts): the system below moves the meters
-- and the per-foot stages before the engine; drive() reports the worst foot.

local Data = require "ExtensiveHealthRedone/Diseases/Extremities/Data"
local Inputs = require "ExtensiveHealthRedone/Diseases/Extremities/Inputs"
local Meters = require "ExtensiveHealthRedone/Diseases/Extremities/Meters"
local Parts = require "ExtensiveHealthRedone/Diseases/Extremities/Parts"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.blisters
local ID = "foot_blisters"
local METER = "frictionH"

local STAGE_LINES = {
    [1] = "UI_EHR_Extremities_BlisterHotSpot",
    [2] = "UI_EHR_Extremities_BlisterFormed",
    [3] = "UI_EHR_Extremities_BlisterBurst",
}

local Blisters = {
    enabledOption = "FootBlistersEnabled",
    driven = true,
    knowledge = ID,
    selfEvident = true,
    name = "UI_EHR_Disease_foot_blisters",
    xp = false,
    alertFrom = D.ALERT_FROM,
    debugSource = "Foot_L",
    lines = {
        random = {
            [2] = { "UI_EHR_Extremities_FeetKillingMe", "UI_EHR_Extremities_EveryStepStings" },
            [3] = { "UI_EHR_Extremities_FeetKillingMe", "UI_EHR_Extremities_EveryStepStings",
                "UI_EHR_Extremities_NeedToRestMyFeet" },
        },
        every = 240,
        quiet = function(p) return p.facts.inVehicle or not p.facts.env.moving end,
    },
}

local function multiplier(p)
    local v = tonumber(p.sandbox("FootBlistersFrictionMultiplier", 1)) or 1
    return math.max(0, math.min(5, v))
end

local function patched(p)
    return p.treatment:active("blisterPatch")
end

-- Footwear that rubs: wet or no socks, worn or holed shoes, holed socks. Only with shoes on.
local function badFootwear(p, f)
    return not f.socks or Inputs.feetWet(p) >= D.WET or f.shoeWear < D.WORN or f.shoesHoles > 0
        or f.socksHoles > 0
end

-- On foot and moving (not riding in a vehicle).
function Blisters.walking(p)
    return p.facts.env.moving and not p.facts.inVehicle
end

-- Friction hours gained per hour on this foot right now (0 standing still or barefoot).
function Blisters.gain(p, foot)
    local env = p.facts.env
    local f = Inputs.footwear(p)
    if not Blisters.walking(p) or not f.shoes then
        return 0
    end
    local m = env.sprinting and D.GAIT.sprint or env.running and D.GAIT.run or D.GAIT.walk
    if not f.socks then
        m = m * D.NO_SOCKS
    elseif Inputs.feetWet(p) >= D.WET then
        m = m * D.WET_SOCKS
    end
    if f.shoeWear < D.WORN_OUT then
        m = m * D.WORN_OUT_MULT
    elseif f.shoeWear < D.WORN then
        m = m * D.WORN_MULT
    end
    if f.shoesHoles > 0 then
        m = m * D.SHOE_HOLES
    end
    if f.socks and f.socksHoles > 0 then
        m = m * D.SOCK_HOLES
    end
    if patched(p) then
        m = m * D.PATCH
    end
    local part = p.facts.parts[foot]
    if part and part.bandaged and not part.bandageDirty then
        m = m * D.BANDAGE
    end
    return m * multiplier(p)
end

-- Healing speed of a blistered foot right now (0 = paused).
function Blisters.healRate(p)
    local env = p.facts.env
    local rate
    if p.facts.asleep then
        rate = D.HEAL_SLEEP
    elseif not Blisters.walking(p) then
        rate = D.HEAL_REST
    else
        local f = Inputs.footwear(p)
        if env.running or env.sprinting or (f.shoes and badFootwear(p, f)) then
            rate = 0
        else
            rate = D.HEAL_WALK
        end
    end
    if patched(p) then
        rate = rate * D.HEAL_PATCH
    end
    return rate
end

-- The stage a friction meter reaches (0-3).
function Blisters.stageFor(frictionH)
    for s = #D.STAGE_H, 1, -1 do
        if frictionH >= D.STAGE_H[s] then
            return s
        end
    end
    return 0
end

-- A foot gets worse: the stage, a fresh healing count, the line, and the burst wound.
local function raise(p, c, foot, stage)
    stage = math.min(stage, #D.STAGE_H)
    local before = Parts.stage(c, foot)
    if stage <= before then
        return
    end
    Parts.setStage(p, c, foot, stage)
    Parts.get(c, foot).heal = 0
    Speech.stage(p, STAGE_LINES[stage])
    if stage >= 3 and before < 3 then
        p.body:scratch(foot, ID)
    end
end

-- A foot heals one stage. Friction is set back under the new stage's threshold, so it doesn't jump straight back.
local function lower(p, c, foot)
    local stage = Parts.stage(c, foot) - 1
    Parts.setStage(p, c, foot, stage)
    Parts.get(c, foot).heal = 0
    local cap = stage > 0 and D.STAGE_H[stage] or D.STAGE_H[1] / 2
    Meters.set(p, foot, METER, math.min(Meters.value(p, foot, METER), cap))
end

-- The system: friction per foot, the per-foot stages, and starting the condition.
function Blisters.update(p, dt, defs)
    local def = defs[ID]
    if not Engine.enabled(p, def) or not Inputs.available(p) then
        return
    end
    local h = dt / 60
    local c = p.state.conditions.active[ID]
    for _, foot in ipairs(Inputs.FEET) do
        if not Inputs.present(p, foot) then
            if c then
                Parts.drop(p, c, foot)
            end
        else
            local friction = Meters.value(p, foot, METER)
            local current = c and Parts.stage(c, foot) or 0
            local gain = Blisters.gain(p, foot)
            if current > 0 and Blisters.healRate(p) > 0 then
                gain = 0        -- careful walking in good footwear lets a blister heal and rubs no further
            end
            if gain > 0 then
                friction = friction + gain * h
            elseif not Blisters.walking(p) then
                friction = friction - (p.facts.asleep and D.DECAY_SLEEP or D.DECAY_REST) * h
            end
            Meters.set(p, foot, METER, friction, D.MAX_H)
            local target = Blisters.stageFor(Meters.value(p, foot, METER))
            if target > current then
                if not c then
                    c = Engine.contract(p, defs, ID, { stage = target, source = foot })
                end
                if c then
                    raise(p, c, foot, target)
                end
            elseif c and current > 0 then
                local entry = Parts.get(c, foot)
                entry.heal = (entry.heal or 0) + Blisters.healRate(p) * h
                if entry.heal >= D.HEAL_H[current] then
                    lower(p, c, foot)
                end
            end
        end
    end
end

-- Engine drive: the worst foot, or "recovered". A debug start (no feet yet) lands on its source foot.
function Blisters.drive(p, c)
    if not Engine.enabled(p, Blisters) then
        return "recovered"
    end
    Parts.seed(p, c, Blisters.debugSource, raise)
    return Parts.result(p, c)
end

function Blisters.onStage(p, c, stage)
    Parts.follow(p, c, stage, raise)
end

function Blisters.effects(p, c)
    local relief = 1 - p.treatment:relief(ID, "pain")
    for _, e in ipairs(Parts.list(c)) do
        p.body:pain(e.part, ID, D.PAIN[e.stage] * relief)
    end
    local speed = D.SPEED[c.stage]
    if speed then
        p.fx:speed(ID, speed)
    end
end

function Blisters.onEnd(p, _, reason)
    if reason == "recovered" then
        Speech.stage(p, "UI_EHR_Extremities_FeetFeelBetter")
    else
        -- A cure (patch), a full heal or a debug cure: the feet start over.
        Meters.clear(p, METER)
    end
end

-- The Monitor row: which feet, and whether they are healing.
function Blisters.monitorRow(row, c, known)
    if not known.name then
        return
    end
    row.description = Parts.label(c)
    row.descriptionColor = "dim"
end

Blisters.systems = {
    { name = "footFriction", order = 336, update = Blisters.update },
}

return Blisters
