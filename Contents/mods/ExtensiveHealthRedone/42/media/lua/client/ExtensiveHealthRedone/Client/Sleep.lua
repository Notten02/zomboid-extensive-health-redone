-- Refuses to fall asleep while the server says natural sleep is blocked (state.effects.noSleep: insomnia from stage
-- 2 without a sleep aid, caffeine, beta blockers, a medication's insomnia side effect; state.effects.sleepBy names
-- the one to mention). Every vanilla way to sleep (bed, ground, vehicle seat, controller
-- prompt) ends in ISWorldObjectContextMenu.onSleepWalkToComplete, so one intercept covers them all (42.21 no longer
-- uses ISSleepDialog). Like the stitch minigame and lockjaw, this is one of the few intercepts
-- Core/PatchPoints allows. Vanilla's forced sleep at exhaustion and our own blackouts don't pass through it.

local Patches = require "ExtensiveHealthRedone/Game/Patches"
local Client = require "ExtensiveHealthRedone/Client/Client"

local Sleep = {}

function Sleep.blocked(player)
    local effects = Client.section(player, "effects")
    return effects ~= nil and effects.noSleep == true
end

-- What the character says, by the source that blocks sleep (Core/ClientEffects.SLEEP_ORDER picks one).
Sleep.REASONS = {
    caffeine = "UI_EHR_Caffeine_NoSleep",
    betaBlocker = "UI_EHR_BetaBlocker_NoSleep",
    medInsomnia = "UI_EHR_Sleep_CantSleep",
    insomnia = "UI_EHR_Insomnia_NoSleep",
}

-- The line for an add-on's noSleep source (Core/ClientEffects:noSleep).
function Sleep.registerReason(source, key)
    if type(source) ~= "string" or type(key) ~= "string" or Sleep.REASONS[source] then
        error("sleep reason " .. tostring(source) .. " is already registered", 2)
    end
    Sleep.REASONS[source] = key
end

-- The reason to show: the blocking source's own line, else insomnia's when that's active.

function Sleep.reason(player)
    local effects = Client.section(player, "effects")
    local by = effects and effects.sleepBy
    if by and Sleep.REASONS[by] then
        return Sleep.REASONS[by]
    end
    local conditions = Client.section(player, "conditions")
    local insomnia = conditions and conditions.active and conditions.active.insomnia
    if insomnia and (tonumber(insomnia.stage) or 0) >= 2 then
        return "UI_EHR_Insomnia_NoSleep"
    end
    return "UI_EHR_Sleep_CantSleep"
end

Patches.on("sleepWalkToComplete", {
    name = "insomnia",
    intercept = function(playerNum)
        local player = getSpecificPlayer(playerNum)
        if not (player and Sleep.blocked(player)) then
            return false
        end
        HaloTextHelper.addBadText(player, getText(Sleep.reason(player)))
        return true
    end,
})

return Sleep
