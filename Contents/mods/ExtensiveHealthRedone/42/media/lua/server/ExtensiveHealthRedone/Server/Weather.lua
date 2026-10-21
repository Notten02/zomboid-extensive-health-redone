-- Wires the environmental diseases (Diseases/Weather) to the authority: the facts they need beyond Server/Facts
-- (a lit heat source nearby, headwear), the cold bath commands, and debug commands. An MP client loads this file too
-- and stops at the first line.
--
-- Cold bath: the client's timed action asks to start at a bathtub, sends a heartbeat every few game minutes and says
-- when it stops. The server checks the tub, the water (8 units, used up at the start) and the distance, and the
-- simulation (Diseases/Weather/Exposure) runs the 3 hours and cures heat stroke at the end. v0.9 never used water and
-- never checked it on the server.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local Meters = require "ExtensiveHealthRedone/Diseases/Weather/Meters"
local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"

local log = Env.logger("Weather")

local Weather = {}

-- Facts -----------------------------------------------------------------------------------------------------------

local HEAT_SPRITES = { "fireplace", "campfire", "stove", "oven" }

local function isHeatSource(object)
    if instanceof(object, "IsoFire") then
        return true
    elseif instanceof(object, "IsoFireplace") or instanceof(object, "IsoBarbecue") then
        return object:isLit()
    elseif instanceof(object, "IsoStove") then
        return object:Activated()
    end
    return false
end

-- A lit heat source within one square (v0.9 EHR_EnvironmentalDiseases.lua:795-844), campfires included.
function Weather.nearHeat(player)
    local square = player:getCurrentSquare()
    if not square then
        return false
    end
    local cell = getCell()
    local campfires = SCampfireSystem and SCampfireSystem.instance
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if sq then
                if campfires then
                    local campfire = campfires:getLuaObjectOnSquare(sq)
                    ---@diagnostic disable-next-line: undefined-field
                    if campfire and campfire.isLit then
                        return true
                    end
                end
                local objects = sq:getObjects()
                for i = 0, objects:size() - 1 do
                    if isHeatSource(objects:get(i)) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Any worn item on a head location: hats, full hats, hoods, helmets (v0.9 matched location names the same way; its
-- item-name matching gave false hits such as "Capacitor" and is gone).
function Weather.headwear(player)
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local location = tostring(worn:get(i):getLocation()):lower():gsub("^base:", ""):gsub("[%s_%-]", "")
        if location:find("hat", 1, true) or location:find("head", 1, true) then
            return true
        end
    end
    return false
end

Facts.extend("weather", function(player, facts)
    facts.weather = { nearHeat = Weather.nearHeat(player), headwear = Weather.headwear(player) }
end)

-- Cold bath ---------------------------------------------------------------------------------------------------------

-- Bathtub sprites: the main half of each tub (v0.9 EHR_HeatStrokeBath.lua:26-35).
Weather.TUB_SPRITES = {
    fixtures_bathroom_01_25 = true, fixtures_bathroom_01_26 = true,
    fixtures_bathroom_01_52 = true, fixtures_bathroom_01_55 = true,
}
Weather.TUB_RANGE = 3

-- The main half of a bathtub on a square, or nil.
function Weather.tubOn(square)
    if not square then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local sprite = object:getSprite()
        if sprite and Weather.TUB_SPRITES[sprite:getName()] then
            return object
        end
    end
    return nil
end

local function notice(player, key)
    Transport.toClient(player, "notice", { key = key, owner = PlayerKey.of(player) })
end

local function closeEnough(player, x, y, z)
    if math.floor(player:getZ()) ~= z then
        return false
    end
    local dx, dy = player:getX() - (x + 0.5), player:getY() - (y + 0.5)
    return dx * dx + dy * dy <= Weather.TUB_RANGE * Weather.TUB_RANGE
end

local tubArgs = {
    x = { type = "number", integer = true },
    y = { type = "number", integer = true },
    z = { type = "number", integer = true, min = -32, max = 32 },
}

Runtime.registry:register("weather.bathStart", {
    args = tubArgs,
    rate = { count = 3, seconds = 10 },
    handler = function(ctx, args)
        local player = ctx.actor.player
        local state = Runtime.store:get(ctx.actor.key)
        if not (state and state.conditions.active.heat_stroke) then
            return
        end
        local tub = Weather.tubOn(getCell():getGridSquare(args.x, args.y, args.z))
        if not tub or not closeEnough(player, args.x, args.y, args.z) or not tub:hasWater()
            or tub:getFluidAmount() < Data.heatStroke.BATH_WATER then
            return notice(player, "UI_EHR_Weather_BathNotHere")
        end
        tub:useFluid(Data.heatStroke.BATH_WATER)
        Runtime.applyNow(ctx.actor.key, function(p)
            Meters.weather(p).bath = { left = Data.heatStroke.BATH_HEARTBEAT_MINUTES, elapsed = 0,
                x = args.x, y = args.y, z = args.z }
        end)
        log:info(ctx.actor.key, "starts a cold bath at", args.x, args.y, args.z)
    end,
})

Runtime.registry:register("weather.bathBeat", {
    rate = { count = 6, seconds = 10 },
    handler = function(ctx)
        local player = ctx.actor.player
        Runtime.applyNow(ctx.actor.key, function(p)
            local bath = Meters.weather(p).bath
            if not bath then
                return
            end
            if closeEnough(player, bath.x, bath.y, bath.z) then
                bath.left = Data.heatStroke.BATH_HEARTBEAT_MINUTES
            else
                Meters.weather(p).bath = nil
            end
        end)
    end,
})

Runtime.registry:register("weather.bathStop", {
    rate = { count = 3, seconds = 10 },
    handler = function(ctx)
        Runtime.applyNow(ctx.actor.key, function(p)
            Meters.weather(p).bath = nil
        end)
    end,
})

-- Debug ----------------------------------------------------------------------------------------------------------------

Runtime.registry:register("debug.weatherMeter", {
    args = {
        meter = { type = "string", oneOf = { cold = true, heat = true } },
        percent = { type = "number", min = 0, max = 125 },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local w = Meters.weather(p)
            if args.meter == "cold" then
                w.coldH = Data.cold.READY_FREEZING_H * args.percent / 100
                w.soakedH = Data.cold.READY_SOAKED_H * args.percent / 100
                w.timers.coldRoll = nil
            else
                w.heatH = Meters.hoursToFull(p) * args.percent / 100
                w.timers.strokeRoll = nil
            end
        end)
        log:info(ctx.actor.key, "debug:", args.meter, "meter set to", args.percent, "%")
    end,
})

log:info("weather diseases loaded")

return Weather
