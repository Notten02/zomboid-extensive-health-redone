-- How a fever feels to the character (order 796, after Body/Temperature and the pre-disease stages): what "Check for
-- Fever" says (Actions/CheckFever, Server/Temperature), and the character's own remarks while a fever lasts.
--
-- Body temperature alone can't tell: while Real Room Temperature's cold model owns the body, our fever is not on
-- vanilla's TEMPERATURE (Game/RealRoomTemperature). So the felt temperature is the fever we keep (state.temperature
-- .fever) when there is one, else the body's. A fever the body doesn't show (the body HIDDEN_GAP or more below it)
-- feels like chills: burning up and shivering at once.
--
-- Remarks (scaled by DialogueFrequency, never asleep): one line when a fever comes on and one when it ends, and in
-- between a line on average every LINE_MINUTES at Normal frequency, once the fever reaches REMARK_FROM.
--
-- State, in state.temperature: feverOn (a fever was there at the last update; nil in saves from before, as false).

local Speech = require "ExtensiveHealthRedone/Core/Speech"

local FeverFeel = {}

FeverFeel.COLD = 35.8           -- deg C under which a check without a fever says "just cold" (the Chilly stage)
FeverFeel.BANDS = {             -- felt deg C from which each check result starts, highest first
    { from = 40.0, band = "burning" },
    { from = 39.0, band = "high" },
    { from = 38.0, band = "fever" },
    { from = 37.5, band = "warm" },
}
FeverFeel.HIDDEN_GAP = 0.5      -- deg C the body may be under the fever before the fever feels like chills
FeverFeel.REMARK_FROM = 37.5
FeverFeel.LINE_MINUTES = 90

local K = "UI_EHR_Fever_Check_"
FeverFeel.CHECK = {
    cold = K .. "Cold",
    normal = K .. "Normal",
    warm = K .. "Warm",
    fever = K .. "Fever",
    high = K .. "High",
    burning = K .. "Burning",
}
FeverFeel.CHILLS = "UI_EHR_Fever_Chills"
FeverFeel.START = "UI_EHR_Text_FeverComingOn"
FeverFeel.END = "UI_EHR_Text_TheFeverIsBreaking"
FeverFeel.REMARKS = {
    warm = { "UI_EHR_Text_IFeelFeverish" },
    fever = { "UI_EHR_Text_IFeelFeverish", "UI_EHR_Text_IFeelFeverishAndWeak" },
    high = { "UI_EHR_Text_ImBurningUp", "UI_EHR_Text_IFeelFeverishAndWeak" },
    burning = { "UI_EHR_Text_ImBurningUp" },
}

-- The temperature the character feels (deg C): the fever when there is one, else the body's.
function FeverFeel.felt(t, body)
    local fever = type(t) == "table" and t.fever or false
    if fever and fever > body then
        return fever
    end
    return body
end

-- Whether a fever is there that the body doesn't show.
function FeverFeel.hidden(t, body)
    local fever = type(t) == "table" and t.fever or false
    return fever ~= false and body <= fever - FeverFeel.HIDDEN_GAP
end

-- The band of a felt temperature: "burning" | "high" | "fever" | "warm" | "normal" | "cold".
function FeverFeel.band(felt)
    for _, b in ipairs(FeverFeel.BANDS) do
        if felt >= b.from then
            return b.band
        end
    end
    return felt < FeverFeel.COLD and "cold" or "normal"
end

-- What the character says after checking themselves for a fever (a translation key).
function FeverFeel.check(t, body)
    local band = FeverFeel.band(FeverFeel.felt(t, body))
    if band ~= "normal" and band ~= "cold" and FeverFeel.hidden(t, body) then
        return FeverFeel.CHILLS
    end
    return FeverFeel.CHECK[band]
end

local function bodyOf(p)
    return p.facts.stats and p.facts.stats.TEMPERATURE or 37
end

function FeverFeel.update(p, dt)
    local t = p.state.temperature
    local on = t.fever ~= false and t.fever ~= nil
    local was = t.feverOn == true
    t.feverOn = on
    if p.facts.asleep then
        return
    end
    if on ~= was then
        Speech.stage(p, on and FeverFeel.START or FeverFeel.END)
        return
    end
    if not on then
        return
    end
    local body = bodyOf(p)
    local felt = FeverFeel.felt(t, body)
    if felt < FeverFeel.REMARK_FROM then
        return
    end
    local keys = FeverFeel.hidden(t, body) and { FeverFeel.CHILLS } or FeverFeel.REMARKS[FeverFeel.band(felt)]
    if keys then
        Speech.maybePick(p, keys, FeverFeel.LINE_MINUTES, dt)
    end
end

FeverFeel.system = { name = "feverFeel", order = 796, update = function(p, dt) FeverFeel.update(p, dt) end }

return FeverFeel
