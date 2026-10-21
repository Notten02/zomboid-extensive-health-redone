-- The medication simulation system (order 390, before the conditions so a course cures before the engine steps):
-- dose and course timers, timed effects and their crashes, side effects, overdose, the continuous effects of active
-- flags, and drug interactions. It also installs the treatment provider (Medication/Provider).

local Treatments = require "ExtensiveHealthRedone/Core/Treatments"
local Provider = require "ExtensiveHealthRedone/Medication/Provider"
local Doses = require "ExtensiveHealthRedone/Medication/Doses"
local Effects = require "ExtensiveHealthRedone/Medication/Effects"
local SideEffects = require "ExtensiveHealthRedone/Medication/SideEffects"
local Overdose = require "ExtensiveHealthRedone/Medication/Overdose"
local Interactions = require "ExtensiveHealthRedone/Medication/Interactions"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local System = {}

-- While a dose or course runs, the client's copy of the timers is refreshed this often (game minutes), so its menus
-- and the monitor see roughly current times; everything else syncs on change.
System.SYNC_MINUTES = 10

Treatments.setProvider(Provider.new)

-- Continuous effects of active flags. Sleep aids, analgesics and the rest are read by the conditions themselves.
local function flagEffects(p, flags)
    if flags.betaBlocker then
        p.stats:ceilingF("PANIC", "med:betaBlocker", 0)
        p.fx:noSleep("betaBlocker")
    end
end

function System.update(p, dt, defs)
    local meds = p.state.meds
    Doses.update(p, defs, dt)
    Effects.update(p, defs, dt)
    SideEffects.update(p, dt)
    Overdose.update(p, dt)
    local _, flags, categories = Provider.activeDoses(p.state)
    flagEffects(p, flags)
    Interactions.update(p, categories)
    if not (Tables.isEmpty(meds.doses) and Tables.isEmpty(meds.courses) and Tables.isEmpty(meds.effects)
            and Tables.isEmpty(meds.side)) or meds.overdose then
        meds.syncIn = (meds.syncIn or System.SYNC_MINUTES) - dt
        if meds.syncIn <= 0 then
            meds.syncIn = System.SYNC_MINUTES
            p.dirty("meds")
        end
    end
end

System.system = { name = "medication", order = 390, update = System.update }

return System
