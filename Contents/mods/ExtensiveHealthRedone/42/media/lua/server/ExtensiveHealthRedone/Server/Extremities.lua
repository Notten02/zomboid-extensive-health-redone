-- Reads what the cold and wet injuries of the hands and feet need (Diseases/Extremities): the worn socks, shoes and
-- gloves, and per hand and foot the skin temperature and clothing insulation. An MP client loads this file too and
-- stops at the first line.
--
-- facts.extremities = {
--   windChillC,                                  -- the air the character feels outdoors, wind included
--   socks  = { wet 0-1, holes } or nil,          -- nil when none are worn
--   shoes  = { wet 0-1, holes, wear 0-1 (share of condition left), waterRes 0-1 } or nil,
--   gloves = { wet 0-1, holes } or nil,
--   parts  = { [Hand_L|Hand_R|Foot_L|Foot_R] = { skinC, insulation } },
-- }
-- Amputated parts are still read here: readers run in name order and The Only Cure's ("toc") marks facts.missing
-- after this one, so the shared code skips facts.missing parts itself.
--
-- BodyPart:getWetness() is the whole-body wetness on every part, so the feet's wetness comes from the socks and shoes,
-- not the body part. Skin temperature is per part.

if isClient() then
    return
end

local Facts = require "ExtensiveHealthRedone/Server/Facts"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Env = require "ExtensiveHealthRedone/Game/Env"
local Meters = require "ExtensiveHealthRedone/Diseases/Extremities/Meters"
local Data = require "ExtensiveHealthRedone/Diseases/Extremities/Data"
local TrenchFoot = require "ExtensiveHealthRedone/Diseases/Extremities/TrenchFoot"

local log = Env.logger("Extremities")

local Extremities = {}

Extremities.PARTS = { "Hand_L", "Hand_R", "Foot_L", "Foot_R" }

-- Worn item locations, lowercased with "base:" and separators removed.
local SLOTS = { socks = "socks", shoes = "shoes", hands = "gloves", handsleft = "gloves", handsright = "gloves" }

local function slot(worn)
    local location = tostring(worn:getLocation()):lower():gsub("^base:", ""):gsub("[%s_%-]", "")
    return SLOTS[location]
end

local function share(v, max)
    v = tonumber(v) or 0
    return math.max(0, math.min(1, v / max))
end

local function wear(item)
    local max = item:getConditionMax()
    if not max or max <= 0 then
        return 1
    end
    return share(item:getCondition(), max)
end

local function read(item, kind)
    local r = { wet = share(item:getWetness(), 100), holes = item:getHolesNumber() or 0 }
    if kind == "shoes" then
        r.wear = wear(item)
        r.waterRes = share(item:getWaterResistance(), 1)
    end
    return r
end

-- The worn socks, shoes and gloves: { socks = item, shoes = item, gloves = item } (game items).
function Extremities.worn(player)
    local out = {}
    local list = player:getWornItems()
    for i = 0, list:size() - 1 do
        local worn = list:get(i)
        local kind = slot(worn)
        local item = worn:getItem()
        if kind and item and not out[kind] then
            out[kind] = item
        end
    end
    return out
end

local function part(player, name)
    local bp = Facts.bodyPart(player, name)
    if not bp then
        return nil
    end
    local node = bp:getThermalNode()
    return {
        skinC = bp:getSkinTemperature(),
        insulation = node and node:getInsulation() or 0,
    }
end

function Extremities.read(player)
    local items = Extremities.worn(player)
    local e = {
        windChillC = getClimateManager():getAirTemperatureForCharacter(player, true),
        parts = {},
    }
    for kind, item in pairs(items) do
        e[kind] = read(item, kind)
    end
    for _, name in ipairs(Extremities.PARTS) do
        e.parts[name] = part(player, name)
    end
    return e
end

Facts.extend("extremities", function(player, facts)
    facts.extremities = Extremities.read(player)
end)

-- Debug: set a meter to a share of its last stage (friction: burst; wet feet: stage 1; frost: necrosis).
Runtime.registry:register("debug.extremityMeter", {
    args = {
        meter = { type = "string", oneOf = { friction = true, wetFeet = true, frost = true, all = true } },
        percent = { type = "number", min = 0, max = 125 },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local share = args.percent / 100
            local function set(parts, name, full)
                for _, part in ipairs(parts) do
                    Meters.set(p, part, name, full * share)
                end
            end
            local feet, hand = { "Foot_L", "Foot_R" }, { "Hand_L" }
            if args.meter == "friction" or args.meter == "all" then
                set(feet, "frictionH", Data.blisters.STAGE_H[#Data.blisters.STAGE_H])
            end
            if args.meter == "wetFeet" or args.meter == "all" then
                set(feet, "wetColdH", TrenchFoot.hours(p))
            end
            if args.meter == "frost" or args.meter == "all" then
                set(args.meter == "all" and { "Hand_L", "Hand_R", "Foot_L", "Foot_R" } or hand, "frost",
                    Data.frostbite.STAGE[#Data.frostbite.STAGE])
            end
        end)
        log:info(ctx.actor.key, "debug:", args.meter, "meter set to", args.percent, "%")
    end,
})

return Extremities
