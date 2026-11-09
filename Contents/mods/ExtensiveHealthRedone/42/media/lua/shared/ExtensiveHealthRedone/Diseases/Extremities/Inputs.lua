-- What the cold and wet injuries of the hands and feet read from the facts (Server/Extremities fills
-- facts.extremities): which parts are there, how wet the feet are, the footwear, and the skin temperature. Pure; no
-- game objects. Without facts.extremities (a test context, an old reader) nothing is available and no meter moves.

local Temperature = require "ExtensiveHealthRedone/Body/Temperature"

local Inputs = {}

Inputs.HANDS = { "Hand_L", "Hand_R" }
Inputs.FEET = { "Foot_L", "Foot_R" }
Inputs.ALL = { "Hand_L", "Hand_R", "Foot_L", "Foot_R" }

function Inputs.available(p)
    return p.facts.extremities ~= nil
end

-- The part is read and not amputated.
function Inputs.present(p, part)
    local e = p.facts.extremities
    if not (e and e.parts and e.parts[part]) then
        return false
    end
    return not (p.facts.missing and p.facts.missing[part])
end

-- How wet the feet are, 0-1. Socks hold the water against the skin; without socks the inside of the shoes does (less
-- what their water resistance keeps out); barefoot, the body's own wetness.
function Inputs.feetWet(p)
    local e = p.facts.extremities
    if not e then
        return 0
    end
    if e.socks then
        return e.socks.wet
    elseif e.shoes then
        return e.shoes.wet * (1 - e.shoes.waterRes)
    end
    return p.facts.env.wetness or 0
end

-- How wet the hands are, 0-1: wet gloves, else the body's wetness.
function Inputs.handsWet(p)
    local e = p.facts.extremities
    if e and e.gloves then
        return e.gloves.wet
    end
    return p.facts.env.wetness or 0
end

function Inputs.wet(p, part)
    if part == "Foot_L" or part == "Foot_R" then
        return Inputs.feetWet(p)
    end
    return Inputs.handsWet(p)
end

function Inputs.isFoot(part)
    return part == "Foot_L" or part == "Foot_R"
end

-- The footwear: { socks, shoes (booleans), socksHoles, shoesHoles, shoeWear (share of condition left, 1 without shoes) }.
function Inputs.footwear(p)
    local e = p.facts.extremities or {}
    return {
        socks = e.socks ~= nil,
        shoes = e.shoes ~= nil,
        socksHoles = e.socks and e.socks.holes or 0,
        shoesHoles = e.shoes and e.shoes.holes or 0,
        shoeWear = e.shoes and e.shoes.wear or 1,
    }
end

-- The part's skin temperature (deg C), or nil when unknown.
function Inputs.skinC(p, part)
    local e = p.facts.extremities
    local r = e and e.parts and e.parts[part]
    return r and r.skinC or nil
end

-- The clothing insulation over the part (vanilla's thermal node), or 0.
function Inputs.insulation(p, part)
    local e = p.facts.extremities
    local r = e and e.parts and e.parts[part]
    return r and r.insulation or 0
end

-- A lit heat source within reach (Server/Weather's nearHeat).
function Inputs.nearHeat(p)
    return p.facts.weather ~= nil and p.facts.weather.nearHeat == true
end

-- An active Warming Pack (only while the body temperature system is on).
function Inputs.warmingPack(p)
    return Temperature.enabled(p) and Temperature.warmingActive(p.state)
end

-- A room counts as warm from this air temperature (Indoor Climate Redone can leave a house below freezing).
Inputs.WARM_ROOM_C = 15

-- Warm surroundings for recovering hands and feet: a heat source, a Warming Pack, or a warm room.
function Inputs.warm(p)
    local env = p.facts.env
    return Inputs.nearHeat(p) or Inputs.warmingPack(p) or (env.indoors == true and env.airC >= Inputs.WARM_ROOM_C)
end

function Inputs.resting(p)
    return p.facts.asleep or p.facts.inVehicle or not p.facts.env.moving
end

return Inputs
