-- Character creation: with BloodTypeTraitsDisabled, the blood type traits are not offered, and a build or preset that
-- carries one loses it (its cost is refunded). Client/CreationTraits reads the option and rebuilds the lists when a
-- custom sandbox changes it.
-- The authority ignores the traits itself while the option is on (Server/PlayerState), and never changes a blood
-- type the option finds already set.

local Patches = require "ExtensiveHealthRedone/Game/Patches"
local CreationTraits = require "ExtensiveHealthRedone/Client/CreationTraits"
local data = require "ExtensiveHealthRedone/Data/BloodTypes"

local BloodTypeTraits = {}

function BloodTypeTraits.disabled()
    return CreationTraits.option("BloodTypeTraitsDisabled")
end

-- A CharacterTraitDefinition is a blood type trait (by registry token, or by its type's name as a fallback).
function BloodTypeTraits.is(definition)
    local trait = definition and definition:getType()
    if not trait then
        return false
    end
    local name = tostring(trait):lower()
    for _, traitKey in pairs(data.traits) do
        local token = EHRCharacterTraits and EHRCharacterTraits[traitKey]
        if (token ~= nil and trait == token) or name:sub(-#traitKey) == traitKey then
            return true
        end
    end
    return false
end

Patches.on("traitListPopulated", {
    name = "bloodTypeTraitsHidden",
    after = function(_, screen, list)
        if BloodTypeTraits.disabled() then
            CreationTraits.remove(screen, list, BloodTypeTraits.is)
        end
    end,
})

return BloodTypeTraits
