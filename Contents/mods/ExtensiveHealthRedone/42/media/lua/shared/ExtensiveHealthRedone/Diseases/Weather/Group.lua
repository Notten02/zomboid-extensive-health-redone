-- Disease group: Weather. Common cold, pneumonia, hypothermia, heat exhaustion and heat stroke, plus the cold and heat
-- exposure meters that start them (Diseases/Weather/Exposure). Conditions/Registry and Systems.lua pick both up.
-- Systems: { name, order (310-390 triggers before the engine, 410-790 after), update(p, dt, defs) }.

local Exposure = require "ExtensiveHealthRedone/Diseases/Weather/Exposure"

return {
    conditions = {
        common_cold = require "ExtensiveHealthRedone/Diseases/Weather/CommonCold",
        pneumonia = require "ExtensiveHealthRedone/Diseases/Weather/Pneumonia",
        hypothermia = require "ExtensiveHealthRedone/Diseases/Weather/Hypothermia",
        heat_exhaustion = require "ExtensiveHealthRedone/Diseases/Weather/HeatExhaustion",
        heat_stroke = require "ExtensiveHealthRedone/Diseases/Weather/HeatStroke",
    },
    systems = Exposure.systems,
}
