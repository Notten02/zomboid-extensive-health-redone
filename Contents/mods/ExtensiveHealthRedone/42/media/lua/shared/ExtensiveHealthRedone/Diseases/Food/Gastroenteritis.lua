-- Gastroenteritis: from eating with bloody or dirty hands (Diseases/Food/Risk). Appetite loss, nausea and
-- dehydration, peak vomiting and weakness, recovery. No health damage. Incubation 4-12 h, then 1-3 days. Washing
-- hands prevents it (Server/Food, Client/WashHands).
--
-- Treatment: cure Antiviral Capsules (48 h course), IV Ciprofloxacin (fast).
-- Relief: Anti-Nausea, Electrolyte Powder.

local Data = require "ExtensiveHealthRedone/Diseases/Food/Data"
local Common = require "ExtensiveHealthRedone/Diseases/Food/Common"

local ID = "gastroenteritis"

local STAGE_MULT = { [2] = 0.45, [3] = 1.0, [4] = 0.25 }
local VOMIT = { [2] = 0.002, [3] = 0.006, [4] = 0.0006 }
-- SICKNESS floors keep the stage's moodle (stage 3: Nauseous), lowered by relief.
local FLOOR = { [2] = 0.31, [3] = 0.56, [4] = 0.18 }
local VOMIT_COOLDOWN = 10.8     -- game minutes

local def = {
    enabledOption = "GastroenteritisEnabled", speedOption = "DiseaseSpeed",
    incubation = { 4, 12 }, duration = { 24, 72 }, baseSeverity = 0.6,
    name = "UI_EHR_Disease_gastroenteritis", knowledge = ID,
    lines = {
        stage = {
            [2] = "UI_EHR_Text_ThisStomachBugIsGettingWorse",
            [3] = "UI_EHR_Text_GroansICantKeepAnythingDown",
            [4] = "UI_EHR_Text_IThinkMyStomachIsFinallySettling",
        },
        random = {
            [2] = { "UI_EHR_Text_IFeelTerrible", "UI_EHR_Text_MyGutIsOnFire",
                "UI_EHR_Text_UghIShouldntHaveEatenWithDirtyHands" },
            [3] = { "UI_EHR_Text_Vomits", "UI_EHR_Text_ICantStandUpStraight", "UI_EHR_Text_MakeItStop" },
            [4] = { "UI_EHR_Text_GettingBetterSlowly", "UI_EHR_Text_AtLeastICanEatAgain" },
        },
        every = Data.LINE_EVERY,
    },
    onEnd = Common.onEnd,
}

function def.effects(p, c, dt)
    local sm = STAGE_MULT[c.stage]
    if not sm then
        return
    end
    local sev = c.severity
    local m = Common.mults(p, ID)
    local k = Data.TICK * dt
    Common.drainEndurance(p, ID, 0.003 * sev * sm * m.weakness, 0.30, dt)
    p.stats:addF("THIRST", ID, 0.0011 * sev * sm * m.hydration * k)
    p.stats:addF("HUNGER", ID, 0.00045 * sev * sm * m.vomit * k)
    if Common.symptom(p, c, "vomitIn", VOMIT[c.stage] * sev * m.vomit, VOMIT_COOLDOWN, dt) then
        Common.vomit(p, ID, 0.10, 0.15)
    end
    local relief = math.max(p.treatment:relief(ID, "nausea"), 1 - m.symptom)
    local floor = math.max(c.stage == 3 and 0.35 or 0.12, FLOOR[c.stage] * math.max(0.5, 1 - relief))
    Common.nausea(p, ID, c, dt, m, floor)
end

return def
