-- The treatment provider (Core/Treatments): what active medication does for a condition, read from state.meds.
-- Installed by Medication/System; every disease and wound module asks it through p.treatment.
--
--   curing(id)            a course or single-dose cure for the condition is running (it holds the stage)
--   relief(id, symptom)   0-1 relief of a symptom of the condition from the active doses
--   active(flag)          a dose with that flag is active (sleepAid, analgesic, betaBlocker, ...)
--
-- Relief (v0.9, kept by the maintainer in Phase 5): each active dose that treats the condition gives its tier relief
-- (15/40/60/80 %) and its specific relief for the symptom. Several drugs never add up: the best tier and the best
-- specific value count, combined as 1 - (1 - tier) x (1 - specific). Conditions that ask "general" for the tier
-- themselves (Data.GENERAL_KEY) get the two separately. Wound infection and sepsis get no tier relief (v0.9). While
-- activated charcoal is active, antibiotic relief is halved (its interaction).

local Data = require "ExtensiveHealthRedone/Medication/Data"
local Doses = require "ExtensiveHealthRedone/Medication/Doses"

local Provider = {}
Provider.__index = Provider

function Provider.new(state)
    return setmetatable({ state = state }, Provider)
end

-- Medications with an active dose, and the flags and categories they bring.
function Provider.activeDoses(state)
    local list, flags, categories = {}, {}, {}
    local doses = state.meds and state.meds.doses or {}
    for id, d in pairs(doses) do
        local med = Data.byId[id]
        if med and d.since < med.active * 60 then
            list[#list + 1] = med
            for flag in pairs(med.flagSet) do
                flags[flag] = true
            end
            if med.category then
                categories[med.category] = true
            end
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list, flags, categories
end

function Provider:index()
    if not self.list then
        self.list, self.flags, self.categories = Provider.activeDoses(self.state)
        self.curingSet = self.state.meds and Doses.curing(self.state) or {}
    end
end

function Provider:curing(id)
    self:index()
    return self.curingSet[id] == true
end

function Provider:active(flag)
    self:index()
    return self.flags[flag] == true
end

function Provider:relief(id, symptom)
    self:index()
    local tier, specific = 0, 0
    local weaken = self.categories.charcoal
    for _, med in ipairs(self.list) do
        local own = med.reliefFor and med.reliefFor[id]
        if med.targetSet[id] or own then
            local scale = (weaken and med.category == "antibiotic") and 0.5 or 1
            if med.targetSet[id] and not Data.NO_TIER[id] then
                tier = math.max(tier, Data.TIER_RELIEF[med.tier] * scale)
            end
            local value = (own and own[symptom]) or (med.targetSet[id] and med.relief and med.relief[symptom]) or 0
            specific = math.max(specific, value * scale)
        end
    end
    if symptom == "general" then
        return tier
    end
    if Data.GENERAL_KEY[id] then
        return specific
    end
    return 1 - (1 - tier) * (1 - specific)
end

return Provider
