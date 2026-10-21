-- Disease group: Corpse (corpse exposure illness, cadaveric aspergillosis, and their two exposure meters).
-- Lists this group's conditions (data and behaviour in one definition per id, see Conditions/Engine for the fields)
-- and its simulation systems. Conditions/Registry and Systems.lua pick both up.
-- Systems: { name, order (310-390 triggers before the engine, 410-790 after), update(p, dt, defs) }.

local Exposure = require "ExtensiveHealthRedone/Diseases/Corpse/Exposure"

return {
    conditions = {
        corpse_sickness = require "ExtensiveHealthRedone/Diseases/Corpse/CorpseSickness",
        cadaveric_aspergillosis = require "ExtensiveHealthRedone/Diseases/Corpse/Aspergillosis",
    },
    systems = { Exposure.system },
}
