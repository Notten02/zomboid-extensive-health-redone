-- Conditional healing: body parts only heal while the character is fed, hydrated, rested and calm (and optionally
-- not in pain), each condition switchable in the sandbox. While a condition fails, every part's HP is capped through
-- the body writer; wounds still close on vanilla's schedule.

local Data = require "ExtensiveHealthRedone/Data/Blood"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"

local Healing = {}

-- Returns true, or false and the first failing reason: "hungry", "thirsty", "stressed", "tired", "pain".
-- Fractions are of each stat's range (p.facts.norm).
function Healing.check(p)
    local facts = p.facts or {}
    local s = facts.norm or {}
    local t = Data.HEALING
    if p.sandbox("HealingRequiresFed", true) and (s.HUNGER or 0) > t.hunger then
        return false, "hungry"
    end
    if p.sandbox("HealingRequiresHydrated", true) and (s.THIRST or 0) > t.thirst then
        return false, "thirsty"
    end
    if p.sandbox("HealingRequiresCalm", true) and (s.STRESS or 0) > t.stress then
        return false, "stressed"
    end
    if p.sandbox("HealingRequiresRested", true) and (s.FATIGUE or 0) > t.fatigue
        and not facts.asleep and (facts.health or 100) > t.fatigueBypassHealth then
        return false, "tired"
    end
    if p.sandbox("HealingRequiresNoPain", false) and (s.PAIN or 0) > t.pain then
        return false, "pain"
    end
    return true
end

Healing.system = {
    name = "healing",
    order = 800,
    update = function(p)
        local ok, reason = Healing.check(p)
        if not ok then
            p.body:healFactorAll(BodyParts.names, "conditions", 0)
        end
        local status = p.state.body.healing
        if status.blocked ~= (not ok) or status.reason ~= reason then
            status.blocked = not ok
            status.reason = reason
            p.dirty("body")
        end
    end,
}

return Healing
