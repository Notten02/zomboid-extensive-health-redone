-- Character creation: with PatientZeroTraitDisabled, the Patient Zero trait is not offered, and a build or preset that
-- carries it loses it (its cost is refunded). Client/CreationTraits reads the option and rebuilds the lists when a
-- custom sandbox changes it.
-- The option never takes immunity away from a character who already has it. A character who
-- has the trait anyway (a modified client, an admin) gets no immunity from it while the option is on: the authority
-- checks that itself (Diseases/Knox/Infection traitImmunity).

local Patches = require "ExtensiveHealthRedone/Game/Patches"
local CreationTraits = require "ExtensiveHealthRedone/Client/CreationTraits"

local PatientZero = {}

function PatientZero.disabled()
    return CreationTraits.option("PatientZeroTraitDisabled")
end

-- A CharacterTraitDefinition is Patient Zero (by registry token, or by its type's name as a fallback).
function PatientZero.is(definition)
    local trait = definition and definition:getType()
    if not trait then
        return false
    end
    local token = EHRCharacterTraits and EHRCharacterTraits.patientzero
    return (token ~= nil and trait == token) or tostring(trait):lower():find("patientzero", 1, true) ~= nil
end

-- populateTraitList(list) fills the positive-trait list (both lists share the same filter).
Patches.on("traitListPopulated", {
    name = "patientZeroHidden",
    after = function(_, screen, list)
        if PatientZero.disabled() then
            CreationTraits.remove(screen, list, PatientZero.is)
        end
    end,
})

return PatientZero
