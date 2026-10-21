-- Every simulation system, in one list. Server/Health registers them with the runtime; tests run them directly.
-- Order: blood (200), wounds (300: infection, tetanus triggers), disease triggers and exposure meters (310-390),
-- medication (390: doses, courses and their cures), immunity (395), conditions (400), effects that read the conditions (410-789),
-- body temperature (790: takes every TEMPERATURE contribution), pre-disease stages (795), healing (800), and the
-- monitor's timer refresh (990).

local Blood = require "ExtensiveHealthRedone/Blood/Blood"
local Healing = require "ExtensiveHealthRedone/Body/Healing"
local Temperature = require "ExtensiveHealthRedone/Body/Temperature"
local TemperatureStages = require "ExtensiveHealthRedone/Body/TemperatureStages"
local Infection = require "ExtensiveHealthRedone/Wounds/Infection"
local TetanusTriggers = require "ExtensiveHealthRedone/Wounds/Tetanus"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Groups = require "ExtensiveHealthRedone/Diseases/Groups"
local Medication = require "ExtensiveHealthRedone/Medication/System"
local Immunity = require "ExtensiveHealthRedone/Immunity/Immunity"
local Refresh = require "ExtensiveHealthRedone/Conditions/Refresh"

local systems = {
    Blood.system,
    {
        name = "wounds",
        order = 300,
        update = function(p, dt)
            Infection.update(p, dt, defs)
            TetanusTriggers.update(p, dt, defs, not p.fresh)
        end,
    },
    {
        name = Medication.system.name,
        order = Medication.system.order,
        update = function(p, dt)
            Medication.system.update(p, dt, defs)
        end,
    },
    Immunity.system,
    {
        name = "conditions",
        order = 400,
        update = function(p, dt)
            Engine.step(p, defs, dt)
        end,
    },
    Temperature.system,
    TemperatureStages.system,
    Healing.system,
    Refresh.system,
}

for _, group in ipairs(Groups) do
    -- Group systems get the condition definitions as a third argument (a group can't require the registry: the
    -- registry requires the groups).
    for _, system in ipairs(group.systems) do
        local update = system.update ---@type fun(p: table, dt: number, defs: table)
        systems[#systems + 1] = {
            name = system.name,
            order = system.order,
            update = function(p, dt) update(p, dt, defs) end,
        }
    end
end

return systems
