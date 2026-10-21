-- Character creation: with PatientZeroTraitDisabled, the Patient Zero trait is not offered, and a build or preset that
-- carries it loses it (its cost is refunded). The option is read from the sandbox options being set up, because
-- SandboxVars still hold the defaults on the new-game screens (v0.9 EHR_PatientZeroTraitToggle.lua).
-- The option never takes immunity away from a character who already has it (decided 2026-10-07). A character who
-- has the trait anyway (a modified client, an admin) gets no immunity from it while the option is on: the authority
-- checks that itself (Diseases/Knox/Infection traitImmunity).
--
-- In the custom-sandbox flow vanilla shows the profession screen first and commits the sandbox screen's values after
-- (SandboxOptions.lua:968-972), so the trait lists were filled with the old value. They are rebuilt once the values
-- are set, so Patient Zero disappears (or comes back) at once (spec professions-and-traits.md 5.3.1).

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"

local PatientZero = {}

function PatientZero.disabled()
    local options = getSandboxOptions()
    local option = options and options:getOptionByName("ExtensiveHealthRework.PatientZeroTraitDisabled")
    if option then
        -- getOptionByName returns a SandboxOption interface the stubs don't give getValue; vanilla calls it the same way.
        ---@diagnostic disable-next-line: undefined-field
        return option:getValue() == true
    end
    return Env.sandbox("PatientZeroTraitDisabled", false) == true
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

-- populateTraitList(list) fills the positive-trait list (both lists share the same filter). After it ran, take Patient
-- Zero out of that list and out of the chosen traits, refunding its points.
Patches.on("traitListPopulated", {
    name = "patientZeroHidden",
    after = function(_, screen, list)
        if not PatientZero.disabled() then
            return
        end
        for _, entry in ipairs(list and list.items or {}) do
            if PatientZero.is(entry.item) then
                list:removeMatchingItems(entry.text)
                break
            end
        end
        local chosen = screen and screen.listboxTraitSelected
        for _, entry in ipairs(chosen and chosen.items or {}) do
            if PatientZero.is(entry.item) then
                chosen:removeMatchingItems(entry.text)
                screen.pointToSpend = screen.pointToSpend + entry.item:getCost()
                break
            end
        end
    end,
})

-- After SandboxOptionsScreen:setSandboxVars: rebuild the trait lists, which runs the listener above with the new value.
Patches.on("sandboxVarsSet", {
    name = "patientZeroRepopulate",
    after = function()
        local main = MainScreen and MainScreen.instance
        local screen = main and main.charCreationProfession
        if screen and screen.repopulateTraitLists then
            screen:repopulateTraitLists()
        end
    end,
})

return PatientZero
