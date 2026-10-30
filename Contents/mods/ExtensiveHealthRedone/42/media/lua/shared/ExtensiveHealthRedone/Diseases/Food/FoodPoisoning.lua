-- Food poisoning: from rotten, stale, burned or unsafe uncooked food (Diseases/Food/Risk). Nausea, then vomiting,
-- then peak weakness, then recovery. No health damage.
--
-- Treatment: cure Activated Charcoal, Homemade Activated Charcoal (about 6 h).
-- Relief: Anti-Nausea (nausea .50, vomiting .40), Electrolyte Powder (dehydration, weakness).

local Data = require "ExtensiveHealthRedone/Diseases/Food/Data"
local Common = require "ExtensiveHealthRedone/Diseases/Food/Common"

local ID = "food_poisoning"

-- Per engine check (Data TICK): endurance drain (toward floor), hunger and thirst gain, vomit chance.
local ROWS = {
    [2] = { drain = 0.006, floor = 0.75, vomit = 0.0015 },
    [3] = { drain = 0.018, floor = 0.55, hunger = 0.0005, thirst = 0.001, vomit = 0.004 },
    [4] = { drain = 0.002, floor = 0.85, vomit = 0.0004 },
}
local VOMIT_COOLDOWN = 12       -- game minutes

local def = {
    enabledOption = "FoodPoisoningEnabled", speedOption = "DiseaseSpeed",
    incubation = { 2, 12 }, duration = { 24, 72 }, baseSeverity = 0.5,
    name = "UI_EHR_Disease_food_poisoning", knowledge = ID, selfEvident = true,
    lines = {
        stage = {
            [2] = "UI_EHR_Text_OhNoIThinkImGettingFoodPoisoning",
            [3] = "UI_EHR_Text_GroansThisIsBadICanBarelyStand",
            [4] = "UI_EHR_Text_ExhalesIThinkTheWorstIsOver",
        },
        random = {
            [2] = { "UI_EHR_Text_IThinkImGoingToBeSick", "UI_EHR_Text_MyStomachIsChurning", "UI_EHR_Text_IFeelNauseous" },
            [3] = { "UI_EHR_Text_Retches", "UI_EHR_Text_INeedToSitDown", "UI_EHR_Text_EverythingHurts",
                "UI_EHR_Text_ICanBarelyStand" },
            [4] = { "UI_EHR_Text_IThinkImGettingBetter", "UI_EHR_Text_TheWorstSeemsToBeOver" },
        },
        every = Data.LINE_EVERY,
    },
    onEnd = Common.onEnd,
}

function def.effects(p, c, dt)
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local sev = c.severity
    local m = Common.mults(p, ID)
    Common.drainEndurance(p, ID, row.drain * sev * m.weakness, row.floor, dt)
    if row.hunger then
        p.stats:addF("HUNGER", ID, row.hunger * sev * m.vomit * Data.TICK * dt)
    end
    if row.thirst then
        p.stats:addF("THIRST", ID, row.thirst * sev * m.hydration * Data.TICK * dt)
    end
    if Common.symptom(p, c, "vomitIn", row.vomit * sev * m.vomit, VOMIT_COOLDOWN, dt) then
        Common.vomit(p, ID, 0.10, 0.15)
    end
    Common.nausea(p, ID, c, dt, m)
end

return def
