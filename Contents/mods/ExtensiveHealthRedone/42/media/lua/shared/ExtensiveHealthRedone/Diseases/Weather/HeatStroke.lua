-- Heat stroke: from a high heat meter (Diseases/Weather/Exposure). It starts at once and runs 4-8 h: very high fever,
-- confusion, dizziness and blur, collapses into a forced sleep, thirst and a health drain from stage 2. It holds at
-- stage 3 (the peak) until the character is cooled, so it never ends on its own in the heat.
-- Cures: the Instant Ice Pack course, a 3 h cold bath (Server/Weather + Client/ColdBath), or 3 h in air
-- at or below 10 deg C (a car with the AC on counts). While a bath or that cold air is cooling the character, the
-- drain, thirst, collapses and episodes stop and the fever falls.
--
-- Treatment (through p.treatment): cure course Instant Ice Pack (4 doses, 1 h apart); relief: the ice pack
-- ("fever", "dehydration", "dizziness", "confusion", "collapse", "healthDrain"), Electrolyte Powder ("dehydration").

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Meters = require "ExtensiveHealthRedone/Diseases/Weather/Meters"
local Episodes = require "ExtensiveHealthRedone/Diseases/Weather/Episodes"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.heatStroke
local K = Data.PER_MINUTE

local CONFUSED = { "UI_EHR_Weather_StumblesWhereAmI", "UI_EHR_Weather_ConfusedWhatWasIDoing",
    "UI_EHR_Weather_DisorientedCantThinkStraight" }
local DIZZY = { "UI_EHR_Text_DizzyWorldsSpinning", "UI_EHR_Weather_Stumbles", "UI_EHR_Weather_SwaysCantFocus" }
local COLLAPSE = { "UI_EHR_Weather_DeliriousTooHot", "UI_EHR_Weather_ConfusedCantStayAwake",
    "UI_EHR_Weather_DazedEverythingIsBurning", "UI_EHR_Dialogue_Blood_Collapse" }

local HeatStroke = {
    enabledOption = "HeatStrokeEnabled", speedOption = "DiseaseSpeed",
    incubation = { 0, 0 }, duration = { 4, 8 }, baseSeverity = 0.95,
    effectsInStage1 = true,
    knowledge = "heat_stroke",
    selfEvident = true,
    name = "UI_EHR_Disease_heat_stroke",
    lines = {
        stage = {
            [1] = "UI_EHR_Weather_HeatStrokeStage1",
            [2] = "UI_EHR_Weather_HeatStrokeStage2",
            [3] = "UI_EHR_Weather_HeatStrokeStage3",
            [4] = "UI_EHR_Weather_HeatStrokeStage4",
        },
        random = {
            [1] = { "UI_EHR_Weather_SoHotCantThink", "UI_EHR_Weather_AirIsShimmering", "UI_EHR_Weather_NeedShadeNow",
                "UI_EHR_Weather_WhyIsEverythingSoBright" },
            [2] = { "UI_EHR_Weather_Panting", "UI_EHR_Weather_CantThink", "UI_EHR_Weather_NeedWaterOrIce",
                "UI_EHR_Weather_TooHotTooHot" },
            [3] = { "UI_EHR_Text_DeliriousMumbling", "UI_EHR_Weather_Help", "UI_EHR_Weather_EverythingsBurning",
                "UI_EHR_Weather_ConfusedWhereAmI" },
            [4] = { "UI_EHR_Weather_StillBurning", "UI_EHR_Weather_KeepCoolingDown",
                "UI_EHR_Weather_CantStayOnMyFeet" },
        },
        every = 100,    -- about 1 in 80-110 per check, with a 0.35 h cooldown
    },
}

-- The peak doesn't give way to recovery while the character is still hot.
function HeatStroke.hold(p, c)
    if c.stage == 3 and not Meters.cooled(p) then
        if not c.data.heldLine then
            c.data.heldLine = true
            Speech.stage(p, "UI_EHR_Text_PantsStillTooHotCantRecover")
        end
        return true
    end
    return false
end

local function coolingNow(p)
    return Meters.bathing(p) or Meters.heatAir(p) <= D.AMBIENT_COOL_C
end

-- Air at or below 10 deg C for 3 h cures it; warmer air lets the progress decay at half speed.
local function ambientCooling(p, c, dt, defs)
    if Meters.heatAir(p) <= D.AMBIENT_COOL_C then
        c.data.coolMinutes = (c.data.coolMinutes or 0) + dt
        if c.data.coolMinutes >= D.AMBIENT_CURE_MINUTES then
            Speech.stage(p, "UI_EHR_Text_FinallyCoolingDownThatWasClose")
            Engine.cure(p, defs, "heat_stroke")
            return true
        end
    elseif c.data.coolMinutes then
        c.data.coolMinutes = math.max(0, c.data.coolMinutes - D.AMBIENT_DECAY * dt)
    end
    return false
end

function HeatStroke.effects(p, c, dt, curing, defs)
    if ambientCooling(p, c, dt, defs) then
        return
    end
    local row = D[c.stage]
    local t = p.treatment
    local function mult(symptom)
        return 1 - t:relief("heat_stroke", symptom)
    end
    p.fx:speed("heat_stroke", row.speed)
    p.fx:noSprint("heat_stroke")
    Episodes.blur(p, c, "heat_stroke", dt)
    Episodes.collapseCooldown(p, c, dt)
    if coolingNow(p) then
        -- A cold bath or cold air: the fever falls and nothing else happens.
        p.stats:lower("TEMPERATURE", "heat_stroke", D.COOLING_FEVER, D.COOLING_STEP * K * dt)
        return
    end
    local target, step = Symptoms.fever(row.fever, row.feverStep * K * dt * c.severity, t:relief("heat_stroke", "fever"))
    Symptoms.applyFever(p, "heat_stroke", target, step)
    if row.drain and not curing and mult("healthDrain") > 0.05 then
        p.body:damage("heat_stroke", row.drain / 60 * dt * mult("healthDrain"), 0)
        p.body:healFactorAll(Symptoms.ALL_PARTS, "heat_stroke", 0)
    end
    if mult("dehydration") > 0.05 then
        p.stats:addF("THIRST", "heat_stroke", row.thirst * K * dt * mult("dehydration"))
    end
    if mult("dizziness") > 0.05 then
        Episodes.dizzy(p, c, row.dizziness * mult("dizziness"), dt, DIZZY, 11)
    end
    if mult("confusion") > 0.05 then
        Episodes.confused(p, c, row.confusion * mult("confusion"), dt, CONFUSED, 12)
    end
    c.data.collapseIn = (c.data.collapseIn or D.COLLAPSE_EVERY) - dt
    if c.data.collapseIn <= 0 then
        c.data.collapseIn = D.COLLAPSE_EVERY
        if mult("collapse") > 0.05 then
            Episodes.collapse(p, c, row.collapse * mult("collapse"), D.COLLAPSE_COOLDOWN, COLLAPSE)
        end
    end
end

function HeatStroke.onEnd(p, c, reason)
    -- The fever, slowdown and drain stop once nothing asks for them; the heat meter starts again from zero.
    Meters.weather(p).heatH = 0
    if reason == "recovered" then
        Speech.stage(p, "UI_EHR_Text_FinallyCoolingDownThatWasClose")
    end
end

-- Contracting: a line, and the meter resets.
function HeatStroke.start(p, defs)
    local c = Engine.contract(p, defs, "heat_stroke", { source = "heat" })
    if c then
        Meters.weather(p).heatH = 0
        Speech.stage(p, HeatStroke.lines.stage[1])
    end
    return c
end

return HeatStroke
