-- Medication side effects: time-limited effects a dose (or a crash) starts, held every simulation step while they run.
-- Stat values are fractions of each stat's range; pain is body-part pain (0-100), which vanilla turns into the PAIN
-- stat.
--
-- State: state.meds.side[id] = { left = minutes, data = {} }. A side effect that is already running is not
-- restarted by another dose, unless forced (the crashes).
--
--   SideEffects.start(p, id, { force = true, hours = 3 })
--   SideEffects.update(p, dt)          -- once per step (Medication/System)

local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local SideEffects = {}

local LIMBS = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "UpperLeg_L", "UpperLeg_R",
    "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R" }
local WHOLE_BODY = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper",
    "Torso_Lower", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R" }

local function src(id)
    return "med:" .. id
end

local function painOn(p, parts, id, amount)
    for _, part in ipairs(parts) do
        p.body:pain(part, src(id), amount)
    end
end

-- Thirst that rises by `now` at once and then by `perHour`, never above `ceiling` and never lowered by this.
local function timedThirst(p, s, id, now, perHour, ceiling, dt)
    local current = p.facts.norm and p.facts.norm.THIRST or 0
    local add = s.data.thirstStarted and perHour * dt / 60 or now
    s.data.thirstStarted = true
    add = math.min(add, math.max(0, ceiling - current))
    if add > 0 then
        p.stats:addF("THIRST", src(id), add)
    end
end

-- Tendon weakness falls: rolled once per game minute after a 5-12 minute grace, by
-- how fast the character moves, with a 30 minute cooldown after a fall.
SideEffects.TENDON = {
    FIRST = { 5, 12 },
    COOLDOWN = 30,
    CHANCE = { standing = 0.06, walking = 0.22, running = 0.45, sprinting = 0.65 },
    LINES = { "UI_EHR_Text_MyLegJustGaveOut", "UI_EHR_Text_MyTendonsFeelWeak", "UI_EHR_Text_ICantTrustMyLegs",
        "UI_EHR_Text_MyKneesBuckled" },
}

local function movement(env)
    if env.sprinting then
        return "sprinting"
    elseif env.running then
        return "running"
    elseif env.moving then
        return "walking"
    end
    return "standing"
end

local function tendon(p, s, dt)
    p.stats:ceilingF("ENDURANCE", src("tendon_weakness"), 0.70)
    local d = s.data
    local T = SideEffects.TENDON
    if d.next == nil then
        d.next = Chance.between(p.rng, T.FIRST[1], T.FIRST[2])
    end
    d.next = d.next - dt
    if d.next > 0 or p.facts.asleep or p.facts.inVehicle then
        return
    end
    d.next = 1
    local env = p.facts.env or {}
    local how = movement(env)
    if Chance.roll(p.rng, T.CHANCE[how]) then
        d.next = T.COOLDOWN
        local fallType = (how == "running" or how == "sprinting") and "pushedBehind" or "pushedFront"
        p.client("fall", { reason = "tendonWeakness", fallType = fallType })
        local line = T.LINES[p.rng.int(1, #T.LINES)]
        if line ~= d.lastLine then
            p.say(line)
        end
        d.lastLine = line
    end
end

-- id -> { hours, name (UI_SideEffect_*), update(p, s, dt) }
SideEffects.DEFS = {
    nausea = { hours = 4, name = "UI_SideEffect_Nausea", update = function(p)
        p.stats:floorF("SICKNESS", src("nausea"), 0.28)
        p.stats:floorF("FOOD_SICKNESS", src("nausea"), 0.32)
    end },
    headache = { hours = 6, name = "UI_SideEffect_Headache", update = function(p)
        p.body:pain("Head", src("headache"), 35)
        p.stats:floorF("STRESS", src("headache"), 0.12)
    end },
    dizziness = { hours = 3, name = "UI_SideEffect_Dizziness", update = function(p, s, dt)
        p.stats:ceilingF("ENDURANCE", src("dizziness"), 0.85)
        p.stats:floorF("DISCOMFORT", src("dizziness"), 0.45)
        -- One blur episode of 10-20 minutes when it starts.
        local d = s.data
        if d.blur == nil then
            d.blur = Chance.between(p.rng, 10, 20)
        end
        if d.blur > 0 then
            d.blur = d.blur - dt
            p.fx:blur(src("dizziness"), 0.6)
        end
    end },
    fatigue = { hours = 8, name = "UI_SideEffect_Fatigue", update = function(p)
        p.stats:floorF("FATIGUE", src("fatigue"), 0.42)
        p.stats:ceilingF("ENDURANCE", src("fatigue"), 0.78)
    end },
    -- Not the insomnia disease: natural sleep is blocked while it runs.
    insomnia = { hours = 12, name = "UI_SideEffect_Insomnia", update = function(p)
        p.fx:noSleep("medInsomnia")
    end },
    metallic_taste = { hours = 4, name = "UI_SideEffect_MetallicTaste", update = function(p)
        p.stats:floorF("UNHAPPINESS", src("metallic_taste"), 0.22)
    end },
    injection_site_pain = { hours = 6, name = "UI_SideEffect_InjectionSitePain", update = function(p)
        p.body:pain("UpperArm_L", src("injection_site_pain"), 25)
    end },
    abdominal_pain = { hours = 4, name = "UI_SideEffect_AbdominalPain", update = function(p)
        p.body:pain("Torso_Lower", src("abdominal_pain"), 38)
        p.stats:floorF("FOOD_SICKNESS", src("abdominal_pain"), 0.20)
        p.stats:floorF("SICKNESS", src("abdominal_pain"), 0.18)
    end },
    dehydration = { hours = 8, name = "UI_SideEffect_Dehydration", update = function(p, s, dt)
        p.stats:ceilingF("ENDURANCE", src("dehydration"), 0.78)
        timedThirst(p, s, "dehydration", 0.14, 0.14, 0.76, dt)
    end },
    lower_back_pain = { hours = 8, name = "UI_SideEffect_LowerBackPain", update = function(p)
        p.body:pain("Torso_Lower", src("lower_back_pain"), 24)
        p.stats:floorF("DISCOMFORT", src("lower_back_pain"), 0.18)
    end },
    -- Lifestyle: Hobbies' bathroom need rises 18 points per game hour; the client adds it (Client/Lifestyle).
    -- Without Lifestyle it is only shown.
    diuretic_urination = { hours = 8, name = "UI_SideEffect_DiureticUrination", update = function(p)
        p.fx:bladder("diuretic_urination", 18)
    end },
    fever = { hours = 6, name = "UI_SideEffect_Fever", update = function(p, _, dt)
        p.stats:raise("TEMPERATURE", src("fever"), 38.2, 0.01 * dt)
        p.stats:floorF("FATIGUE", src("fever"), 0.32)
    end },
    severe_fatigue = { hours = 12, name = "UI_SideEffect_SevereFatigue", update = function(p)
        p.stats:floorF("FATIGUE", src("severe_fatigue"), 0.75)
        p.stats:floorF("SICKNESS", src("severe_fatigue"), 0.22)
        p.stats:ceilingF("ENDURANCE", src("severe_fatigue"), 0.50)
    end },
    tendon_weakness = { hours = 24, name = "UI_SideEffect_TendonWeakness", update = tendon },
    red_man_syndrome = { hours = 2, name = "UI_SideEffect_RedManSyndrome", update = function(p)
        p.body:pain("Torso_Upper", src("red_man_syndrome"), 25)
        p.stats:floorF("DISCOMFORT", src("red_man_syndrome"), 0.55)
        p.stats:floorF("STRESS", src("red_man_syndrome"), 0.35)
    end },
    kidney_stress = { hours = 18, name = "UI_SideEffect_KidneyStress", update = function(p)
        p.body:pain("Torso_Lower", src("kidney_stress"), 18)
        p.stats:floorF("FATIGUE", src("kidney_stress"), 0.38)
        p.stats:floorF("SICKNESS", src("kidney_stress"), 0.16)
        p.stats:ceilingF("ENDURANCE", src("kidney_stress"), 0.78)
    end },
    -- Suppresses immunity like a systemic antibiotic while it runs (Immunity/Immunity reads it).
    immunosuppression = { hours = 48, name = "UI_SideEffect_Immunosuppression", update = function() end },
    caffeine_crash = { hours = 2, name = "UI_SideEffect_CaffeineCrash", update = function(p)
        p.stats:floorF("FATIGUE", src("caffeine_crash"), 0.85)
        p.stats:ceilingF("ENDURANCE", src("caffeine_crash"), 0.55)
    end },
    combat_stimulant_crash = { hours = 6, name = "UI_SideEffect_CombatStimulantCrash", update = function(p, s, dt)
        painOn(p, LIMBS, "combat_stimulant_crash", 16)
        p.stats:floorF("FATIGUE", src("combat_stimulant_crash"), 0.80)
        timedThirst(p, s, "combat_stimulant_crash", 0.08, 0.075, 1, dt)
    end },
    whole_body_muscle_pain = { hours = 6, name = "UI_SideEffect_WholeBodyMusclePain", update = function(p)
        painOn(p, WHOLE_BODY, "whole_body_muscle_pain", 18)
    end },
    last_chance_headache = { hours = 3, name = "UI_SideEffect_LastChanceEpinephrineHeadache", update = function(p)
        p.body:pain("Head", src("last_chance_headache"), 22)
    end },
    last_chance_severe_headache = { hours = 3, name = "UI_SideEffect_LastChanceEpinephrineSevereHeadache",
        update = function(p)
            p.body:pain("Head", src("last_chance_severe_headache"), 75)
        end },
    last_chance_thirst = { hours = 3, name = "UI_SideEffect_LastChanceEpinephrineThirst", update = function(p, s, dt)
        timedThirst(p, s, "last_chance_thirst", 0.10, 0.12, 0.85, dt)
    end },
}

-- Starts a side effect. Returns true when it started (false: already running and not forced).
function SideEffects.start(p, id, opts)
    local def = SideEffects.DEFS[id]
    if not def then
        error("unknown side effect " .. tostring(id), 2)
    end
    opts = opts or {}
    local side = p.state.meds.side
    if side[id] and not opts.force then
        return false
    end
    side[id] = { left = (opts.hours or def.hours) * 60, data = {} }
    p.dirty("meds")
    return true
end

function SideEffects.active(state, id)
    return state.meds.side[id] ~= nil
end

-- Holds every running side effect for this step and counts it down; expired ones end.
function SideEffects.update(p, dt)
    local side = p.state.meds.side
    for _, id in ipairs(Tables.sortedKeys(side)) do
        local s = side[id]
        local def = SideEffects.DEFS[id]
        if def then
            def.update(p, s, dt)
        end
        s.left = s.left - dt
        if s.left <= 0 or not def then
            side[id] = nil
            p.dirty("meds")
        end
    end
end

return SideEffects
