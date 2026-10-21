-- Disease group: Concussion (falls and vehicle crashes).
-- Lists this group's conditions (data and behaviour in one definition per id, see Conditions/Engine for the fields)
-- and its simulation systems. Conditions/Registry and Systems.lua pick both up.
-- Systems: { name, order (310-390 triggers before the engine, 410-790 after), update(p, dt, defs) }.

local Concussion = require "ExtensiveHealthRedone/Diseases/Concussion/Concussion"

return {
    conditions = { concussion = Concussion.def },
    systems = { Concussion.system },
}
