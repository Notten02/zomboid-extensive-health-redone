-- Painkiller addiction: a hidden dependency risk builds with every painkiller dose, faster with many doses in a day
-- and with doses taken less than 3 h apart. At 100 the character is addicted: stage 1, stage 2 a day later, stage 3 a
-- day after that, which persists until a buprenorphine course cures it. Withdrawal brings cravings, stress,
-- unhappiness (to the maximum at stage 3) and thirst; an active painkiller or buprenorphine dose suppresses it.
-- From v0.9 EHR_PainkillerAddiction.lua and EHR_Disease.lua:2949-3003 (docs/porting/phase4/mental-knox-sounds.md,
-- section 3). W29: PainkillerAddictionEnabled turns it off. W18: homemade (herbal)
-- painkillers don't count.
--
-- Doses come from the medication rules (Medication/Doses: Base.Pills, med.addiction): Addiction.recordDose(p, defs,
-- fullType).
--
-- Phase 5 treatment hooks:
--   p.treatment:active("analgesic")        a painkiller dose is active (also tracked here from recorded doses: 3 h)
--   p.treatment:active("buprenorphine")    a buprenorphine dose is active: withdrawal suppressed
--   p.treatment:relief("painkiller_addiction", "withdrawal")   0-1 relief of stress, unhappiness and thirst
--   p.treatment:curing("painkiller_addiction")   the buprenorphine course (10 doses, 12 h apart) cures it

local Data = require("ExtensiveHealthRedone/Diseases/Mind/Data").addiction
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local Addiction = {}

local LINES = {
    [1] = { "UI_EHR_Addiction_S1_1", "UI_EHR_Addiction_S1_2" },
    [2] = { "UI_EHR_Addiction_S2_1", "UI_EHR_Addiction_S2_2", "UI_EHR_Addiction_S2_3" },
    [3] = { "UI_EHR_Addiction_S3_1", "UI_EHR_Addiction_S3_2", "UI_EHR_Addiction_S3_3" },
}

-- A painkiller dose taken in the last 3 hours (from recorded doses) or reported active by the medication system.
function Addiction.painkillerActive(p)
    local pk = p.state.mind.painkiller
    return (#pk.doses > 0 and pk.clean < Data.ACTIVE_MINUTES) or p.treatment:active("analgesic")
end

function Addiction.suppressed(p)
    return Addiction.painkillerActive(p) or p.treatment:active("buprenorphine")
end

-- Risk added by one dose: n = doses in the rolling window, this one included; early = within 3 h of the last.
function Addiction.doseRisk(n, early)
    local risk = Data.DOSE_RISK[n] or Data.EXCESS_RISK
    if early then
        risk = risk + Data.EARLY_RISK
    end
    return risk
end

-- A painkiller dose was taken. Returns true when it counted. While addicted, the dose only suppresses withdrawal.
function Addiction.recordDose(p, defs, fullType)
    if not Data.PAINKILLERS[fullType] then
        return false
    end
    local pk = p.state.mind.painkiller
    local recent = #pk.doses > 0
    if recent and pk.clean < Data.DUPLICATE then
        return false
    end
    local early = recent and pk.clean < Data.EARLY_MINUTES
    pk.doses[#pk.doses + 1] = 0
    pk.clean = 0
    if not p.state.conditions.active.painkiller_addiction then
        pk.risk = math.min(Data.THRESHOLD, pk.risk + Addiction.doseRisk(#pk.doses, early))
        if pk.risk >= Data.THRESHOLD then
            Engine.contract(p, defs, "painkiller_addiction", { source = "painkillers" })
        end
    end
    p.dirty("mind")
    return true
end

-- Dose ages, the rolling window, and decay after a clean day (a system step).
function Addiction.update(p, dt)
    local pk = p.state.mind.painkiller
    pk.clean = pk.clean + dt
    local kept = {}
    for _, age in ipairs(pk.doses) do
        if age + dt <= Data.WINDOW then
            kept[#kept + 1] = age + dt
        end
    end
    pk.doses = kept
    if pk.risk > 0 and pk.clean > Data.DECAY_AFTER then
        local minutes = math.min(dt, pk.clean - Data.DECAY_AFTER)
        pk.risk = math.max(0, pk.risk - Data.DECAY_PER_MINUTE * minutes)
    end
end

function Addiction.effects(p, c, dt)
    local row = Data.STAGES[c.stage]
    local sev = c.severity
    local k = Symptoms.TICK * dt
    if Addiction.suppressed(p) then
        local s = Data.SUPPRESSED
        p.stats:lowerF("STRESS", "painkillerAddiction", s.stress, s.step * sev * k)
        p.stats:lowerF("UNHAPPINESS", "painkillerAddiction", s.unhappiness, s.step * sev * k)
        return
    end
    local mult = math.max(0.35, 1 - p.treatment:relief("painkiller_addiction", "withdrawal"))
    p.stats:raiseF("STRESS", "painkillerAddiction", row.stress * mult, Data.STRESS_STEP * sev * k)
    p.stats:raiseF("UNHAPPINESS", "painkillerAddiction", row.unhappiness * mult, Data.UNHAPPINESS_STEP * sev * k)
    p.stats:raiseF("THIRST", "painkillerAddiction", row.thirst * mult, Data.THIRST_STEP * sev * k)
    if not p.facts.asleep then
        Speech.maybePick(p, LINES[c.stage], Data.LINE_EVERY[c.stage], dt)
    end
end

-- Cured (or debug-cleared): the dependency starts from nothing again, as v0.9's ClearAfterCure did.
function Addiction.onEnd(p)
    local pk = p.state.mind.painkiller
    pk.risk = 0
    pk.doses = {}
    p.dirty("mind")
end

Addiction.def = {
    enabledOption = "PainkillerAddictionEnabled",
    knowledge = "painkiller_addiction",
    selfEvident = true,
    name = "UI_EHR_Disease_painkiller_addiction",
    baseSeverity = Data.BASE_SEVERITY,
    -- Not scaled by DiseaseSpeed, as in v0.9.
    stages = { [1] = { 24, 24 }, [2] = { 24, 24 } },
    persistsAt = 3,
    effectsInStage1 = true,
    lines = {
        stage = { [2] = "UI_EHR_Addiction_Stage2", [3] = "UI_EHR_Addiction_Stage3" },
    },
    effects = Addiction.effects,
    onEnd = Addiction.onEnd,
}

return Addiction
