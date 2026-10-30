-- Hyperkeratotic scabies: mites from sitting still on natural ground (dirt, grass). Stage 1 (1-2 h): an itching bite;
-- stage 2: fever, health held at 60 at most, a scratch wound every 3 h; stage 3: high fever, health held at 30, a
-- scratch every hour; stage 4 untreated: a health drain with no floor (lethal). Scratches never hit the
-- head or neck and never carry Knox (Core/BodyAggregator scratch). A curative course stops the drain, the cap and
-- the scratches, and softens pain and fever. The stage-1 bite hurts.
--
-- Treatment: cure - Topical Permethrin (normal or homemade), Antiparasitic Pills. Relief - Antipyretic
-- ("fever"); also read: "pain", "inflammation", "healthDrain".

local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Risk = require "ExtensiveHealthRedone/Conditions/Risk"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local Episodes = require "ExtensiveHealthRedone/Diseases/Corpse/Episodes"

local ID = "hyperkeratotic_scabies"

local Scabies = {}

Scabies.ROLL_EVERY = 15         -- game minutes of continuous sitting per roll
Scabies.CHANCE = 0.03           -- per roll, x ScabiesChanceMultiplier, then immunity
Scabies.WINTER = { [12] = true, [1] = true, [2] = true }

-- [stage] = { pain on the bite, fever target and step, scratch every N hours, health floor, damage HP and every N h }
local ROWS = {
    [1] = { pain = 8 },
    [2] = { pain = 18, fever = 38.0, feverStep = 0.035, scratchEvery = 3, floor = 60,
            hp = { 0.75, 1.25 }, every = 0.55 },
    [3] = { pain = 30, fever = 40.0, feverStep = 0.060, scratchEvery = 1, floor = 30,
            hp = { 1.15, 2.00 }, every = 0.35 },
    [4] = { pain = 24, fever = 40.0, feverStep = 0.060, hp = { 1.35, 2.65 }, every = 0.28 },
}

local SCRATCH_LINES = { "UI_EHR_Text_IScratchedMyselfOpenAgain", "UI_EHR_Text_ICantStopScratching" }
local ITCH_LINES = { "UI_EHR_Text_ItItches", "UI_EHR_Text_INeedToStopScratching", "UI_EHR_Text_ThisRashIsGettingWorse" }
local ITCH_COOLDOWN = { [1] = 1.25, [2] = 0.85, [3] = 0.60, [4] = 0.60 }

Scabies.def = {
    enabledOption = "HyperkeratoticScabiesEnabled", speedOption = "DiseaseSpeed",
    incubation = { 1, 2 }, duration = { 96, 168 }, baseSeverity = 0.75,
    effectsInStage1 = true,
    knowledge = "hyperkeratotic_scabies",
    name = "UI_EHR_Disease_hyperkeratotic_scabies",
    lines = {
        stage = {
            [1] = "UI_EHR_Text_SomethingBitMeItItchesAlready",
            [2] = "UI_EHR_Text_ThisItchingIsSpreadingMySkinFeelsHot",
            [3] = "UI_EHR_Text_ICantStopScratchingMySkinIsBurning",
            [4] = "UI_EHR_Text_ThisIsTearingMeApartINeedTreatment",
        },
        random = {
            [1] = { "UI_EHR_Text_ItItches", "UI_EHR_Text_SomethingIsCrawlingOnMySkin",
                    "UI_EHR_Text_INeedToStopScratching" },
            [2] = { "UI_EHR_Text_ThisRashIsGettingWorse", "UI_EHR_Text_MySkinIsOnFire",
                    "UI_EHR_Text_IScratchedMyselfOpenAgain" },
            [3] = { "UI_EHR_Text_ICantStopScratching", "UI_EHR_Text_ItFeelsLikeBugsUnderMySkin",
                    "UI_EHR_Text_MyWholeBodyIsBurningAndItching" },
            [4] = { "UI_EHR_Text_ThisWontStop", "UI_EHR_Text_ImScratchingMyselfRaw", "UI_EHR_Text_MySkinFeelsRuined" },
        },
        every = 168,
    },
}

local function randomPart(p)
    return BodyParts.muscles[p.rng.int(1, #BodyParts.muscles)]
end

function Scabies.def.effects(p, c, dt, curing)
    Episodes.tick(c, dt)
    local row = ROWS[c.stage]
    local t = p.treatment
    local sev = c.severity
    local k = Symptoms.TICK * dt
    if not c.data.bite then
        c.data.bite = randomPart(p)       -- the initial bite (also when started from the debug menu)
        p.body:scratch(c.data.bite, ID)
    end

    local painRelief = math.max(t:relief(ID, "pain"), 0.65 * t:relief(ID, "inflammation"))
    local painMult = math.max(curing and 0.12 or 0.35, (curing and 0.35 or 1) * (1 - 1.5 * painRelief))
    p.body:pain(c.data.bite, ID, math.max(curing and 2 or 5, row.pain * painMult))

    if row.fever then
        local target, step = row.fever, row.feverStep * sev * k
        if curing then
            target, step = math.min(target, c.stage == 3 and 38.1 or 37.6), step * 1.5
        end
        target, step = Symptoms.fever(target, step, t:relief(ID, "fever"))
        Symptoms.applyFever(p, ID, target, step)
    end

    if Episodes.try(p, c, "itch", 0.006 * sev, ITCH_COOLDOWN[c.stage], dt) then
        Speech.stage(p, Speech.pick(p, ITCH_LINES))
    end
    if curing then
        c.data.cap, c.data.scratchIn = nil, nil
        return
    end

    if row.scratchEvery then
        c.data.scratchIn = (c.data.scratchIn or row.scratchEvery * 60) - dt
        if c.data.scratchIn <= 0 then
            c.data.scratchIn = row.scratchEvery * 60
            p.body:scratch(randomPart(p), ID)
            Speech.stage(p, Speech.pick(p, SCRATCH_LINES))
        end
    end
    if row.hp then
        local hm = math.max(0.18, 1 - 1.4 * t:relief(ID, "healthDrain"))
        local hp = row.hp[1] + row.hp[2] * sev * hm
        if c.stage == 4 then
            hp = (row.hp[1] + row.hp[2] * sev) * math.max(0.15, hm)
            c.data.cap = nil
            p.body:damage(ID, hp / (row.every * 60) * dt, 0)
        else
            Episodes.healthCap(p, c, ID, row.floor, hp / (row.every * 60), dt)
        end
    end
end

-- The trigger: sitting still on natural ground, rolled every 15 minutes of it.
local function sittingOnGround(p)
    local env = p.facts.env
    local natural = env.naturalFloor or (p.facts.ground ~= nil and p.facts.ground.natural)
    return env.sitOnGround and natural and not (env.moving or env.running or env.sprinting or p.facts.inVehicle)
end

local function blocked(p)
    local env = p.facts.env
    return (p.sandbox("ScabiesWinterBlock", true) ~= false and Scabies.WINTER[env.month])
        or (p.sandbox("ScabiesSnowBlock", true) ~= false and env.groundSnow)
end

function Scabies.update(p, dt, defs)
    local d = p.state.exposure.data
    local def = defs[ID]
    if not def or not Engine.enabled(p, def) or p.state.conditions.active[ID]
        or not sittingOnGround(p) or blocked(p) then
        d.scabiesSat = nil
        return
    end
    d.scabiesSat = (d.scabiesSat or 0) + dt
    if d.scabiesSat < Scabies.ROLL_EVERY then
        return
    end
    d.scabiesSat = d.scabiesSat - Scabies.ROLL_EVERY
    local mult = math.max(0, math.min(5, tonumber(p.sandbox("ScabiesChanceMultiplier", 1)) or 1))
    local chance = Risk.chance(p, ID, math.min(1, Scabies.CHANCE * mult))
    if Chance.roll(p.rng, chance) then
        local c = Engine.contract(p, defs, ID, { source = "natural_ground" })
        if c then
            d.scabiesSat = nil
            Speech.stage(p, def.lines.stage[1])
        end
    end
end

Scabies.system = { name = "scabiesTrigger", order = 340, update = Scabies.update }

return Scabies
