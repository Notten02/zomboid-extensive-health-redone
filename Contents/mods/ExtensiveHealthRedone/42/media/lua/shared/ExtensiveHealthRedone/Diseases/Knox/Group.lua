-- Disease group: Knox. Lists this group's conditions (data and behaviour in one definition per id, see
-- Conditions/Engine for the fields) and its simulation systems (exposure meters, triggers). Conditions/Registry and
-- Systems.lua pick both up; nothing else needs editing to add a disease here.
-- Systems: { name, order (310-390 triggers before the engine, 410-790 after), update(p, dt, defs) }.
--
-- Knox: the knox_infection display condition, and one system for immunity, Knox item side effects and timers
-- (Diseases/Knox/Infection). The items themselves are Diseases/Knox/Items, used by Server/Knox.

local Infection = require "ExtensiveHealthRedone/Diseases/Knox/Infection"

return {
    conditions = {
        knox_infection = Infection.condition,
    },
    systems = {
        Infection.system,
    },
}
