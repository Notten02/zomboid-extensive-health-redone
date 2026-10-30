-- Character creation helpers for traits a sandbox option turns off (Client/PatientZero, Client/BloodTypeTraits).
--
-- The option is read from the sandbox options being set up, because SandboxVars still hold the defaults on the
-- new-game screens.
--
-- In the custom-sandbox flow vanilla shows the profession screen first and commits the sandbox screen's values after
-- (SandboxOptions.lua:968-972), so the trait lists were filled with the old value. They are rebuilt once the values
-- are set, so hidden traits disappear (or come back) at once.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"

local CreationTraits = {}

-- A boolean ExtensiveHealthRework sandbox option, as the screens being set up hold it.
function CreationTraits.option(name)
    local options = getSandboxOptions()
    local option = options and options:getOptionByName("ExtensiveHealthRework." .. name)
    if option then
        -- getOptionByName returns a SandboxOption interface the stubs don't give getValue; vanilla calls it the same way.
        ---@diagnostic disable-next-line: undefined-field
        return option:getValue() == true
    end
    return Env.sandbox(name, false) == true
end

-- After populateTraitList(list): take every trait matches(definition) accepts out of that list and out of the chosen
-- traits, refunding the chosen ones' points.
function CreationTraits.remove(screen, list, matches)
    local hidden = {}
    for _, entry in ipairs(list and list.items or {}) do
        if matches(entry.item) then
            hidden[#hidden + 1] = entry.text
        end
    end
    for _, text in ipairs(hidden) do
        list:removeMatchingItems(text)
    end
    local chosen = screen and screen.listboxTraitSelected
    local refunded = {}
    for _, entry in ipairs(chosen and chosen.items or {}) do
        if matches(entry.item) then
            refunded[#refunded + 1] = entry
        end
    end
    for _, entry in ipairs(refunded) do
        chosen:removeMatchingItems(entry.text)
        screen.pointToSpend = screen.pointToSpend + entry.item:getCost()
    end
end

-- After SandboxOptionsScreen:setSandboxVars: rebuild the trait lists, which runs the traitListPopulated listeners with
-- the new values.
Patches.on("sandboxVarsSet", {
    name = "creationTraitsRepopulate",
    after = function()
        local main = MainScreen and MainScreen.instance
        local screen = main and main.charCreationProfession
        if screen and screen.repopulateTraitLists then
            screen:repopulateTraitLists()
        end
    end,
})

return CreationTraits
