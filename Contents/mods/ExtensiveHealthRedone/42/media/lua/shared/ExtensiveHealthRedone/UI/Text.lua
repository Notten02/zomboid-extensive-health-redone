-- Text in the pure view models (UI/*): a translation key with its arguments, or a ready string. The client turns
-- them into strings (Client/Text.lua, through getText); the tests compare the keys. An argument may itself be text,
-- for example a condition name inside a line.
--
--   Text.key("UI_EHR_DoseCount", 2, 4)       -- "Dose 2/4"
--   Text.raw("87%")
--   Text.duration(90)                        -- "1 h 30 min"

local Text = {}

function Text.key(key, ...)
    return { key = key, args = { ... }, n = select("#", ...) }
end

function Text.raw(s)
    return { raw = tostring(s) }
end

function Text.is(t)
    return type(t) == "table" and (t.key ~= nil or t.raw ~= nil)
end

-- "NN%" of a 0-100 value, rounded.
function Text.percent(value)
    return Text.raw(tostring(math.floor((tonumber(value) or 0) + 0.5)) .. "%")
end

-- A game-time span: "45 min", "3 h 20 min", "2 day(s) 4 hr(s)".
function Text.duration(minutes)
    minutes = math.max(0, math.ceil(tonumber(minutes) or 0))
    if minutes < 60 then
        return Text.key("UI_EHR_Med_Tooltip_Minutes", minutes)
    end
    local hours = math.floor(minutes / 60)
    if hours < 24 then
        return Text.key("UI_EHR_Med_Tooltip_HoursMinutes", hours, minutes - hours * 60)
    end
    return Text.key("Tooltip_EHR_Label_DaysHours", math.floor(hours / 24), hours % 24)
end

-- Turns text into a string with a translator (getText in the game, a fake in tests). Arguments that are text are
-- translated first.
function Text.render(t, translate)
    if t == nil then
        return ""
    end
    if type(t) ~= "table" then
        return tostring(t)
    end
    if t.raw then
        return t.raw
    end
    local args = {}
    for i = 1, t.n or #t.args do
        local a = t.args[i]
        args[i] = Text.is(a) and Text.render(a, translate) or a
    end
    return translate(t.key, unpack(args, 1, t.n or #t.args))
end

return Text
