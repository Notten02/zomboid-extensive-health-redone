-- Wires body temperature (Body/Temperature) to the authority: the per-tick hold, and food temperature from the eat
-- and drink actions. An MP client loads this file too and stops at the first line.
--
-- The hold: vanilla's thermoregulator pulls TEMPERATURE back toward 37 deg C between our once-a-minute simulation
-- steps, and keeps only half of a single write. So every tick, TEMPERATURE is put back inside the floor and ceiling
-- the simulation keeps. Not while Real Room Temperature's cold model owns the body (Server/RealRoomTemperature): it
-- faults on any foreign TEMPERATURE write.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local StatWriter = require "ExtensiveHealthRedone/Server/StatWriter"
local Food = require "ExtensiveHealthRedone/Server/Food"
local Temperature = require "ExtensiveHealthRedone/Body/Temperature"
local ServerRRT = require "ExtensiveHealthRedone/Server/RealRoomTemperature"
local FeverFeel = require "ExtensiveHealthRedone/Body/FeverFeel"

local log = Env.logger("Temperature")

local ServerTemperature = {}

local function hold()
    Runtime.eachAttached(function(key, player, state)
        local t = state.temperature
        if t and (t.floor or t.ceiling) and not player:isDead() and not ServerRRT.yields(key, player) then
            StatWriter.holdTemperature(key, player, t.floor, t.ceiling)
        end
    end)
end

Events.OnTick.Add(hold)

-- Check for Fever ----------------------------------------------------------------------------------------------------

-- Only Actions/CheckFever's EHRCheckFeverAction runs it, when its time is up (`action = true`). The character says how
-- warm they feel: our fever, which a body under Real Room Temperature's cold model doesn't show, or the body's
-- temperature (Body/FeverFeel). Said even with dialogue off: the player asked.
Runtime.registry:register("temperature.checkFever", {
    args = {},
    action = true,
    rate = { count = 2, seconds = 5 },
    handler = function(ctx)
        Runtime.applyNow(ctx.actor.key, function(p)
            local body = p.facts.stats and p.facts.stats.TEMPERATURE or Temperature.NORMAL
            local line = FeverFeel.check(p.state.temperature, body)
            p.say(line)
            log:debug(ctx.actor.key, "checked for fever:", line, "body", body, "fever", p.state.temperature.fever)
        end)
    end,
})

-- Food temperature ---------------------------------------------------------------------------------------------------

-- Vanilla's own rule for how hot an item is (ISDrinkFluidAction:start): food and drainables carry a heat value, other
-- items (a mug holding a fluid) an item heat. 1.0 is room temperature.
function ServerTemperature.describe(item, liquid)
    if not item then
        return nil
    end
    local heat
    if item:IsFood() or item:IsDrainable() then
        heat = item:getHeat()
    else
        heat = item:getItemHeat()
    end
    return {
        heat = tonumber(heat) or 1,
        frozen = instanceof(item, "Food") and item:isFrozen() or false,
        liquid = liquid or item:getFluidContainer() ~= nil,
        fullType = item:getFullType(),
    }
end

local function consumed(player, info, portion)
    local key = Runtime.attach(player)
    if not key or not info or portion <= 0 then
        return
    end
    info.portion = portion
    local effect = Runtime.applyNow(key, function(p)
        return Temperature.eat(p, info)
    end)
    if effect then
        log:debug(key, "food temperature", info.fullType, effect.kind, effect.add, "for", effect.minutes, "min")
    end
end

Patches.on("eatComplete", {
    name = "foodTemperature",
    before = function(action)
        action.ehrTemp = ServerTemperature.describe(action.item, false)
    end,
    after = function(results, action)
        if results[1] ~= false then
            consumed(action.character, action.ehrTemp, tonumber(action.percentage) or 1)
        end
    end,
})

Patches.on("eatServerStop", {
    name = "foodTemperature",
    before = function(action)
        local portion = Food.stopPortion(action)
        if portion then
            consumed(action.character, ServerTemperature.describe(action.item, false), portion)
        end
    end,
})

-- Drinks: the heat is read when the action is made, before any of it is drunk (vanilla resets a poured mug's heat).
Patches.on("drinkFluidNew", {
    name = "foodTemperature",
    after = function(results)
        local action = results[1]
        if type(action) == "table" then
            action.ehrTemp = ServerTemperature.describe(action.item, true)
        end
    end,
})

Patches.on("drinkFluidComplete", {
    name = "foodTemperature",
    before = function(action)
        if action.ehrTemp == nil then
            action.ehrTemp = ServerTemperature.describe(action.item, true)
        end
    end,
    after = function(results, action)
        if results[1] ~= false then
            consumed(action.character, action.ehrTemp, tonumber(action.percentage) or 1)
        end
    end,
})

log:info("temperature loaded")

return ServerTemperature
