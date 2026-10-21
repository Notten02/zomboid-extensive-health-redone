-- The body diagram's per-part facts read from vanilla's BodyParts, in the shape UI/BodyStatus takes. Shared, because
-- two sides read them: the own EHR Monitor on the client (Client/MonitorView, the local player's body) and an exam on
-- the authority (Server/Exam, the patient's body there; another player's body on a client is a stale copy).
-- Server/Facts reads its own, smaller set for the simulation; the two are kept apart on purpose (different names and
-- fields, and the simulation must not depend on what the diagram shows).
--
--   BodyFacts.read(player)   -- { [BodyPartType name] = { bleeding, infected, fracture, ... } }, plain data

local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"

local BodyFacts = {}

-- Vanilla counts a wound infection level below this as none (the same threshold as v0.9's diagram).
BodyFacts.INFECTED_LEVEL = 0.05

function BodyFacts.part(part)
    return {
        bleeding = part:bleeding(),
        infected = part:isInfectedWound() or part:getWoundInfectionLevel() > BodyFacts.INFECTED_LEVEL,
        fracture = part:getFractureTime() > 0,
        bullet = part:haveBullet(),
        glass = part:haveGlass(),
        burn = part:getBurnTime() > 0,
        burnWash = part:isNeedBurnWash(),
        bandaged = part:bandaged(),
        bandageDirty = part:bandaged() and part:getBandageLife() <= 0,
        deep = part:deepWounded(),
        bitten = part:bitten(),
        cut = part:isCut(),
        scratched = part:scratched(),
        injury = part:HasInjury(),
        pain = part:getAdditionalPain(),
        stiffness = part:getStiffness(),
        stitched = part:stitched(),
        splinted = part:getSplintFactor() > 0,
        plantain = part:getPlantainFactor() > 0,
        comfrey = part:getComfreyFactor() > 0,
        garlic = part:getGarlicFactor() > 0,
        health = part:getHealth(),
    }
end

function BodyFacts.read(player)
    local parts = {}
    local list = player:getBodyDamage():getBodyParts()
    for i = 0, list:size() - 1 do
        local name = BodyParts.names[i + 1]
        if name then
            parts[name] = BodyFacts.part(list:get(i))
        end
    end
    return parts
end

return BodyFacts
