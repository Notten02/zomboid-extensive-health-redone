-- Applies Data/ItemTweaks to the loaded item scripts.
-- Lives in shared/ because item scripts exist in every Lua VM: single player, MP client and dedicated server.
-- OnGameBoot fires on all of them after the scripts are loaded.

local ItemTweaks = require "ExtensiveHealthRedone/Core/ItemTweaks"
local tweaks = require "ExtensiveHealthRedone/Data/ItemTweaks"

local Tweaks = {}

local booted = false

-- Adds a tweak from an add-on mod (the Core/ItemTweaks entry format). Call it from shared code at load: tweaks are
-- applied at OnGameBoot, and the whole list is validated then, so two mods changing the same item property fail
-- loudly. Errors after the tweaks were applied.
function Tweaks.add(tweak)
    if booted then
        error("item tweaks are applied at OnGameBoot; add them at load", 2)
    end
    tweaks[#tweaks + 1] = tweak
end

local function getItem(fullType)
    return ScriptManager.instance:getItem(fullType)
end

local function onGameBoot()
    booted = true
    local result = ItemTweaks.apply(tweaks, getItem)
    for _, tweak in ipairs(result.missing) do
        print("[ExtensiveHealthRedone] item tweak skipped, no item " .. tweak.item .. " (" .. tweak.property .. ")")
    end
    if #result.applied > 0 then
        print("[ExtensiveHealthRedone] applied " .. #result.applied .. " item tweak(s)")
    end
end

Events.OnGameBoot.Add(onGameBoot)

return Tweaks

