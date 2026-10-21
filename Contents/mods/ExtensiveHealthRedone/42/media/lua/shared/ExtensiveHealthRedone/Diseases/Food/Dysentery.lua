-- Dysentery: from drinking contaminated water (Diseases/Food/Risk). Thirst and hunger capped low at stage 1;
-- heavier drain, abdominal pain and some blood loss at stage 2; dangerous dehydration, frequent vomiting, a movement
-- penalty and noticeable blood loss at stage 3; recovery at stage 4. Lethal mainly through dehydration (vanilla
-- thirst). From v0.9 EHR_DiseaseDefinitions.lua:250-358 and EHR_EnvironmentalDiseases.lua:3139-3206.
-- Changes from v0.9: relief medicine slows the drain but never lifts the caps (W30); the stage-3 slowdown ends with
-- stage 3 (v0.9's speed mod stuck); the abdominal pain goes away on every kind of ending (it stayed after natural
-- recovery). The lines are v0.9's older dysentery set, which has translations.
--
-- Treatment (Phase 5): cure Oral Rehydration Kit (48 h, 8 doses), Broad Spectrum or Plant-Based Antibiotics,
-- IV Antibiotics, IV Metronidazole, IV Ciprofloxacin.
-- Relief: Anti-Diarrheal (diarrhea .85, bathroomNeed .85), Electrolyte Powder (dehydration), Anti-Nausea (vomiting).
-- Lifestyle: Hobbies (Phase 10): dysentery raises its bathroom need (BLADDER_RATE points per game hour by stage, v0.9
-- EHR_LifestyleCompat.lua:61-66), less with relief; an anti-diarrheal also drains the need that is there. The client
-- adds it to Lifestyle's own number (Client/Lifestyle); without Lifestyle nobody reads it.

local Data = require "ExtensiveHealthRedone/Diseases/Food/Data"
local Common = require "ExtensiveHealthRedone/Diseases/Food/Common"

local ID = "dysentery"

-- Per v0.9 environmental tick (DYS_TICK per game minute). Caps are fractions of the stat's range (1 = none); blood
-- loss in mL per tick, never taking blood below floor mL; pain on Torso_Lower.
local ROWS = {
    [1] = { thirst = 0.0003, thirstCap = 0.10, hunger = 0.0002, hungerCap = 0.10, vomit = 0 },
    [2] = { thirst = 0.0025, thirstCap = 0.50, hunger = 0.0015, hungerCap = 0.50, vomit = 0.00035, blood = 0.05,
            bloodFloor = 4550, pain = 18 },
    [3] = { thirst = 0.0065, thirstCap = 1, hunger = 0.0035, hungerCap = 1, vomit = 0.004, blood = 0.18,
            bloodFloor = 3850, pain = 28, speed = 0.7 },
    [4] = { thirst = 0.0003, thirstCap = 0.10, hunger = 0.0002, hungerCap = 0.10, vomit = 0 },
}
local VOMIT_HUNGER, VOMIT_THIRST = 0.06, 0.08
local BLADDER_RATE = { [1] = 2, [2] = 14, [3] = 26, [4] = 2 }
local BLADDER_RELIEF_DRAIN = 35     -- points per game hour taken off by full bathroom relief
local BLOOD_SYNC_ML = 10        -- sync the blood section when the loss since the last sync reaches this

local def = {
    enabledOption = "DysenteryEnabled", speedOption = "DiseaseSpeed",
    incubation = { 6, 12 }, duration = { 72, 120 }, baseSeverity = 0.6,
    effectsInStage1 = true,     -- v0.9: the stage-1 caps already apply during the incubation
    name = "UI_EHR_Disease_dysentery", knowledge = ID,
    lines = {
        stage = {
            [2] = "UI_EHR_Text_OhNoIShouldntHaveDrunkThatWater",
            [3] = "UI_EHR_Text_GrippingStomachTheCrampsAreUnbearable",
            [4] = "UI_EHR_Text_IThinkTheWorstIsPassing",
        },
        random = {
            [1] = { "UI_EHR_Text_MyStomachIsRumbling", "UI_EHR_Text_SomethingIsntRight",
                "UI_EHR_Text_ThatWaterTastedFunny" },
            [2] = { "UI_EHR_Text_RunsToBushes", "UI_EHR_Text_ICantStopGoing", "UI_EHR_Text_SoThirsty" },
            [3] = { "UI_EHR_Text_ImLosingSoMuchFluid", "UI_EHR_Text_BloodyStool", "UI_EHR_Text_ImDyingOfThirst",
                "UI_EHR_Text_ICantTakeThisAnymore", "UI_EHR_Text_Retches" },
            [4] = { "UI_EHR_Text_SlowlyRecovering", "UI_EHR_Text_NeedToStayHydrated" },
        },
        every = Data.LINE_EVERY,
    },
    onEnd = Common.onEnd,
}

local function clamp(v)
    return math.max(0.02, math.min(1, v))
end

-- Blood lost to bloody diarrhoea, never below the stage's floor.
local function loseBlood(p, c, mL, floor)
    local b = p.state.blood
    local loss = math.min(mL, b.volume - floor)
    if loss <= 0 then
        return
    end
    b.volume = b.volume - loss
    c.data.bloodUnsynced = (c.data.bloodUnsynced or 0) + loss
    if c.data.bloodUnsynced >= BLOOD_SYNC_ML then
        c.data.bloodUnsynced = 0
        p.dirty("blood")
    end
end

function def.effects(p, c, dt)
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local t = p.treatment
    local sm = Common.symptomMult(p, ID)
    local diarrhea = clamp(sm * (1 - t:relief(ID, "diarrhea")))
    local hydration = clamp(1 - t:relief(ID, "dehydration"))
    local vomitMult = clamp(sm * (1 - t:relief(ID, "vomiting")))
    local k = Data.DYS_TICK * dt

    local bathRelief = t:relief(ID, "bathroomNeed")
    local pressure = BLADDER_RATE[c.stage] * clamp(diarrhea * math.max(0.05, 1 - bathRelief))
    p.fx:bladder(ID, pressure - BLADDER_RELIEF_DRAIN * bathRelief)

    local thirst = row.thirst * diarrhea * hydration * k
    local hunger = row.hunger * diarrhea * k
    if row.vomit > 0 and Common.symptom(p, c, "vomitIn", row.vomit * vomitMult, 0, dt, Data.DYS_TICK) then
        Common.vomit(p, ID, 0, 0)
        thirst, hunger = thirst + VOMIT_THIRST, hunger + VOMIT_HUNGER
    end
    -- W30: the caps hold whatever relief is active. A cap never lowers a stat that is already above it.
    p.stats:raiseF("THIRST", ID, row.thirstCap, thirst)
    p.stats:raiseF("HUNGER", ID, row.hungerCap, hunger)

    if row.blood then
        loseBlood(p, c, row.blood * diarrhea * k, row.bloodFloor)
    end
    if row.pain then
        p.body:pain("Torso_Lower", ID, row.pain * math.max(0.25, sm))
    end
    if row.speed then
        p.fx:speed(ID, row.speed)
    end
end

return def
