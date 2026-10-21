-- The weather group's state and the readings the diseases share: the cold and heat meters, the air the heat meter
-- uses, "cooled" for heat stroke (W32), and the cold bath. Everything lives in state.exposure:
--   exposure.cold / exposure.heat     display percentages (cold: share of "ready"; heat: share of a full meter, max 125)
--   exposure.data.weather = { timers = { cough, coldRoll, strokeRoll }, coldH, soakedH, heatH (meters in hours),
--                             heatFalling (game minutes the heat meter has been falling), bath = { left, elapsed } }

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"

local Meters = {}

function Meters.weather(p)
    local data = p.state.exposure.data
    if not data.weather then
        data.weather = { timers = {}, coldH = 0, soakedH = 0, heatH = 0, heatFalling = 0 }
    end
    return data.weather
end

function Meters.hoursToFull(p)
    local h = tonumber(p.sandbox("HeatExposureHoursToFull", 4.0)) or 4.0
    return math.max(0.25, math.min(24, h))
end

function Meters.threshold(p)
    return tonumber(p.sandbox("HeatExposureTemperatureThreshold", 30.0)) or 30.0
end

-- Share of a full heat meter (uncapped).
function Meters.heatRatio(p)
    return Meters.weather(p).heatH / Meters.hoursToFull(p)
end

-- The air the heat meter feels: a vehicle's interior (heater or AC), else the air around the character.
function Meters.heatAir(p)
    local env = p.facts.env
    return env.vehicleC or env.airC
end

-- W32: cooled = the air is below the heat threshold, or the character is in shade below 35 deg C.
function Meters.cooled(p)
    local air = Meters.heatAir(p)
    return air < Meters.threshold(p) or (p.facts.env.shade and air < Data.heat.SHADE_MAX_C)
end

-- Our cold bath, or a Lifestyle: Hobbies shower or tub (facts.lifestyle.showering, Server/Lifestyle: only believed to a
-- character standing still outside a vehicle).
function Meters.bathing(p)
    local bath = Meters.weather(p).bath
    if bath ~= nil and bath.left > 0 then
        return true
    end
    local lifestyle = p.facts and p.facts.lifestyle
    return lifestyle ~= nil and lifestyle.showering == true
end

return Meters
