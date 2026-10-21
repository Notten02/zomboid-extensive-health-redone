-- Disease group: Food. Lists this group's conditions (data and behaviour in one definition per id, see
-- Conditions/Engine for the fields) and its simulation systems (exposure meters, triggers). Conditions/Registry and
-- Systems.lua pick both up; nothing else needs editing to add a disease here.
-- Systems: { name, order (310-390 triggers before the engine, 410-790 after), update(p, dt, defs) }.
--
-- Food-borne diseases and dysentery. The triggers (eating, drinking) are game events: Server/Food reads the item or
-- water source and calls Diseases/Food/Risk. The one system here decays the food risk accumulator.

local Risk = require "ExtensiveHealthRedone/Diseases/Food/Risk"

return {
    conditions = {
        food_poisoning = require "ExtensiveHealthRedone/Diseases/Food/FoodPoisoning",
        gastroenteritis = require "ExtensiveHealthRedone/Diseases/Food/Gastroenteritis",
        trichinosis = require "ExtensiveHealthRedone/Diseases/Food/Trichinosis",
        toxin_poisoning = require "ExtensiveHealthRedone/Diseases/Food/ToxinPoisoning",
        dysentery = require "ExtensiveHealthRedone/Diseases/Food/Dysentery",
    },
    systems = {
        { name = "foodRisk", order = 320, update = function(p, dt, _) Risk.update(p, dt) end },
    },
}
