-- Insomnia: 12 hours awake at very high fatigue (or, rarely, a stimulant crash) breaks sleep. Stage 1: sleep stops
-- restoring properly. Stage 2 (about 24 h later): natural sleep is blocked; only a sleep aid lets the character sleep.
-- Stage 3 (about 24 h after that): persists until DORA or antidepressants cure it. Stress, unhappiness and a headache
-- grow with each stage.
--
-- Recovery: stages 1 and 2 recover with a consistent sleep
-- pattern. A good night is 6+ hours asleep (at stage 2 only with a sleep aid active, since natural sleep is blocked);
-- with tea before sleeping it counts as two. Three good nights in a row drop one stage (2 -> 1, 1 -> cured); more than
-- 30 hours without a good night breaks the streak. Each good night also restarts the current stage's clock, and the
-- stage can't worsen while the last good night is less than 30 hours ago, so a character who sleeps well every night
-- doesn't slide on to the next stage because one night came a little late.
--
-- Treatment hooks:
--   p.treatment:active("sleepAid")         sleeping pills, DORA, antidepressants: sleep allowed, fatigue not pushed,
--                                          stress, unhappiness and headache capped low
--   p.treatment:active("sleepTea")         tea drunk before sleeping (herbal teas, vanilla tea): the night counts double
--   p.treatment:relief("insomnia", "symptoms")   0-1 relief of the stress, unhappiness and fatigue push
--   p.treatment:curing("insomnia")         DORA (8 doses / 96 h) or antidepressants (14 doses / 168 h) cure it

local Data = require("ExtensiveHealthRedone/Diseases/Mind/Data").insomnia
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local Insomnia = {}

Insomnia.STAGE_LINES = {
    [1] = "UI_EHR_Insomnia_Stage1",
    [2] = "UI_EHR_Insomnia_Stage2",
    [3] = "UI_EHR_Insomnia_Stage3",
}

local LINES = {
    [1] = { "UI_EHR_Insomnia_S1_1", "UI_EHR_Insomnia_S1_2", "UI_EHR_Insomnia_S1_3" },
    [2] = { "UI_EHR_Insomnia_S2_1", "UI_EHR_Insomnia_S2_2", "UI_EHR_Insomnia_S2_3" },
    [3] = { "UI_EHR_Insomnia_S3_1", "UI_EHR_Insomnia_S3_2", "UI_EHR_Insomnia_S3_3" },
}
local AID_LINES = { "UI_EHR_Insomnia_Aid_1", "UI_EHR_Insomnia_Aid_2", "UI_EHR_Insomnia_Aid_3" }

-- Fatigue trigger (a system step): continuous minutes awake at the threshold; sleep or a lower sample resets it.
function Insomnia.trigger(p, defs, dt)
    local mind = p.state.mind
    if mind.stimulantCooldown and mind.stimulantCooldown > 0 then
        mind.stimulantCooldown = math.max(0, mind.stimulantCooldown - dt)
    end
    if p.state.conditions.active.insomnia then
        mind.tiredFor = 0
        return
    end
    if not p.facts.asleep and (p.facts.norm.FATIGUE or 0) >= Data.FATIGUE_THRESHOLD then
        mind.tiredFor = mind.tiredFor + dt
    else
        mind.tiredFor = 0
    end
    if mind.tiredFor >= Data.TRIGGER_MINUTES and Engine.contract(p, defs, "insomnia", { source = "fatigue" }) then
        mind.tiredFor = 0
        Speech.stage(p, Insomnia.STAGE_LINES[1])
    end
end

-- A stimulant wore off (caffeine pills, combat stimulants, nitric oxide booster; the medication rules call this): a
-- 10% chance of insomnia, rolled at most once every 12 game hours. Returns the new condition or nil.
function Insomnia.stimulantCrash(p, defs, source)
    local mind = p.state.mind
    if p.state.conditions.active.insomnia or (mind.stimulantCooldown or 0) > 0 then
        return nil
    end
    mind.stimulantCooldown = Data.STIMULANT_COOLDOWN
    if not Chance.roll(p.rng, Data.STIMULANT_CHANCE) then
        return nil
    end
    local c = Engine.contract(p, defs, "insomnia", { source = source })
    if c then
        Speech.stage(p, Insomnia.STAGE_LINES[1])
    end
    return c
end

-- One stage better: 2 -> 1, or 1 -> cured.
local function improve(p, c, defs)
    if c.stage <= 1 then
        Engine.finish(p, defs, "insomnia", "recovered")
        Speech.stage(p, "UI_EHR_Insomnia_Recovered")
        return
    end
    c.stage = c.stage - 1
    c.left = Engine.stageMinutes(c, c.stage)
    p.dirty("conditions")
    Speech.stage(p, "UI_EHR_Insomnia_Improving")
end

-- Good-night bookkeeping in c.data: slept (minutes of this sleep), counted, aid, tea, streak, sinceGood.
function Insomnia.recovery(p, c, dt, defs)
    local d = c.data
    if d.sinceGood then
        d.sinceGood = d.sinceGood + dt
        if d.sinceGood > Data.STREAK_GAP then
            d.streak = 0
        end
    end
    if not p.facts.asleep then
        d.slept, d.counted, d.aid, d.tea = 0, false, false, false
        return
    end
    d.slept = (d.slept or 0) + dt
    d.aid = d.aid or p.treatment:active("sleepAid")
    d.tea = d.tea or p.treatment:active("sleepTea")
    if d.counted or d.slept < Data.GOOD_SLEEP or c.stage >= 3 or (c.stage == 2 and not d.aid) then
        return
    end
    d.counted = true
    d.sinceGood = 0
    d.streak = (d.streak or 0) + (d.tea and Data.TEA_NIGHTS or 1)
    c.left = Engine.stageMinutes(c, c.stage)
    if d.streak >= Data.GOOD_NIGHTS then
        d.streak = 0
        improve(p, c, defs)
    end
end

function Insomnia.effects(p, c, dt, curing, defs)
    local row = Data.STAGES[c.stage]
    local t = p.treatment
    local aid = t:active("sleepAid")
    local sev = c.severity
    local k = Symptoms.TICK * dt
    local mult = 1 - t:relief("insomnia", "symptoms")
    -- Stage 1's "sleep doesn't restore": fatigue is pushed up even while asleep, fighting vanilla's recovery.
    if not aid then
        p.stats:raiseF("FATIGUE", "insomnia", row.fatigue, Data.FATIGUE_STEP * sev * math.max(0.25, mult) * k)
    end
    local stress = row.stress * math.max(0.35, mult)
    local unhappiness = row.unhappiness * math.max(0.35, mult)
    local headPain = row.headPain
    if aid then
        stress = math.min(stress, Data.SLEEP_AID.stress)
        unhappiness = math.min(unhappiness, Data.SLEEP_AID.unhappiness)
        headPain = math.min(headPain, Data.SLEEP_AID.headPain)
    end
    p.stats:raiseF("STRESS", "insomnia", stress, Data.STRESS_STEP * sev * k)
    p.stats:raiseF("UNHAPPINESS", "insomnia", unhappiness, Data.UNHAPPINESS_STEP * sev * k)
    p.body:pain("Head", "insomnia", headPain)
    if c.stage >= 2 and not aid then
        p.fx:noSleep("insomnia")
    end
    if not p.facts.asleep then
        Speech.maybePick(p, aid and AID_LINES or LINES[c.stage], Data.LINE_EVERY[c.stage], dt)
    end
    Insomnia.recovery(p, c, dt, defs)
end

-- The stage holds while the character keeps a sleep pattern (Engine hold).
function Insomnia.hold(_, c)
    local since = c.data.sinceGood
    return c.stage < 3 and since ~= nil and since <= Data.STREAK_GAP
end

function Insomnia.onEnd(p)
    p.state.mind.tiredFor = 0
end

Insomnia.def = {
    enabledOption = "InsomniaEnabled",
    knowledge = "insomnia",
    selfEvident = true,
    name = "UI_EHR_Disease_insomnia",
    baseSeverity = 0.65,
    -- Not scaled by DiseaseSpeed.
    stages = { [1] = { 24, 24 }, [2] = { 24, 24 } },
    persistsAt = 3,
    hold = Insomnia.hold,
    effectsInStage1 = true,
    lines = { stage = { [2] = Insomnia.STAGE_LINES[2], [3] = Insomnia.STAGE_LINES[3] } },
    effects = Insomnia.effects,
    onEnd = Insomnia.onEnd,
}

return Insomnia
