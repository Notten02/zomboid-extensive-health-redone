-- Blood types and how often each is rolled for a new character (real-world distribution, weights sum to 100).
-- Taken verbatim from the original mod. The strings are also the save
-- format, so they never change.
--
-- traits: the character-creation trait that picks each type instead of rolling it, by its key in EHRCharacterTraits
-- (media/registries.lua). Costs are in media/scripts/EHR_Traits.txt. The sandbox option BloodTypeTraitsDisabled hides
-- them (Client/BloodTypeTraits) and makes the authority ignore them (Server/PlayerState).

return {
    types = { "O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+" },
    weights = { 7, 36, 6, 34, 2, 9, 1, 5 },
    traits = {
        ["O-"] = "bloodtypeoneg", ["O+"] = "bloodtypeopos", ["A-"] = "bloodtypeaneg", ["A+"] = "bloodtypeapos",
        ["B-"] = "bloodtypebneg", ["B+"] = "bloodtypebpos", ["AB-"] = "bloodtypeabneg", ["AB+"] = "bloodtypeabpos",
    },
}
