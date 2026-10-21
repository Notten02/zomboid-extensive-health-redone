-- Renders view-model text (UI/Text) with the game's translations.

local UiText = require "ExtensiveHealthRedone/UI/Text"

local Text = {}

local function translate(key, ...)
    if select("#", ...) == 0 then
        return getText(key)
    end
    ---@diagnostic disable-next-line: redundant-parameter
    return getText(key, ...)
end

function Text.t(t)
    return UiText.render(t, translate)
end

return Text
