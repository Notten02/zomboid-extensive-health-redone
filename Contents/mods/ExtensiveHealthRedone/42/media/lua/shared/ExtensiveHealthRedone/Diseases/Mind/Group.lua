-- Disease group: Mind. Delirium (prolonged maximum stress), insomnia (prolonged exhaustion, stimulant crashes) and
-- painkiller addiction (dose risk), plus pain sounds. Lists this group's conditions (data and behaviour in one
-- definition per id, see Conditions/Engine for the fields) and its simulation systems. Conditions/Registry and
-- Systems.lua pick both up; nothing else needs editing to add a disease here.
-- Systems: { name, order (310-390 triggers before the engine, 410-790 after), update(p, dt, defs) }.

local Delirium = require "ExtensiveHealthRedone/Diseases/Mind/Delirium"
local Insomnia = require "ExtensiveHealthRedone/Diseases/Mind/Insomnia"
local Addiction = require "ExtensiveHealthRedone/Diseases/Mind/Addiction"
local PainSounds = require "ExtensiveHealthRedone/Diseases/Mind/PainSounds"

return {
    conditions = {
        delirium = Delirium.def,
        insomnia = Insomnia.def,
        painkiller_addiction = Addiction.def,
    },
    systems = {
        -- Triggers: stress for delirium, fatigue for insomnia, the painkiller dose window and risk decay.
        {
            name = "mind",
            order = 350,
            update = function(p, dt, defs)
                Delirium.trigger(p, defs, dt)
                Insomnia.trigger(p, defs, dt)
                Addiction.update(p, dt)
            end,
        },
        { name = "painSounds", order = 450, update = function(p, dt) PainSounds.update(p, dt) end },
    },
}
