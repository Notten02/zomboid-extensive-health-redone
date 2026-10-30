-- Loads or creates a player's health state in their modData, on the side that owns it.
--
-- Existing state: upgraded through the schema's migration chain, then each add-on section through its own. New
-- character: a fresh state, plus the one-time import when the character carries the original mod's data.
--
-- Either way, a blood type trait sets the blood type (unless BloodTypeTraitsDisabled is on). It is applied at every
-- load, not only to a new state, so it holds whenever the trait shows up (an admin adding it later included). With the
-- option on, the trait is ignored and the blood type stays what it was: the option never changes a type it already set.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Schema = require "ExtensiveHealthRedone/Core/Schema"
local Importer = require "ExtensiveHealthRedone/Core/Importer"
local BloodTypes = require "ExtensiveHealthRedone/Core/BloodTypes"

local log = Env.logger("PlayerState")

local PlayerState = {}

-- The blood type the player picked with a trait (media/registries.lua tokens), or nil.
local function chosenBloodType(player)
    if Env.sandbox("BloodTypeTraitsDisabled", false) == true or not EHRCharacterTraits then
        return nil
    end
    return BloodTypes.chosen(function(traitKey)
        local token = EHRCharacterTraits[traitKey]
        return token ~= nil and player:hasTrait(token)
    end)
end

local function applyBloodTypeTrait(player, key, state)
    local chosen = chosenBloodType(player)
    if chosen and chosen ~= state.identity.bloodType then
        log:info(key, "blood type", tostring(state.identity.bloodType), "->", chosen, "from the trait")
        state.identity.bloodType = chosen
    end
end

-- Returns the state table, or nil when it can't be used (saved by a newer version of the mod).
function PlayerState.load(player, key)
    local modData = player:getModData()
    local state = modData[Schema.ROOT_KEY]
    if state ~= nil then
        local ok, err = Schema.upgrade(state)
        if not ok then
            log:error(key, "state left untouched:", err)
            return nil
        end
        ok, err = Schema.upgradeSections(state)
        if not ok then
            log:error(key, "state left untouched:", err)
            return nil
        end
        Schema.fillDefaults(state)
        applyBloodTypeTrait(player, key, state)
        return state
    end
    state = Schema.new(Env.rng)
    if Importer.hasOldData(modData) then
        local report = Importer.run(modData, state)
        log:info(key, "imported from Extensive Health Rework:", report.summary)
    else
        Importer.removeOldKeys(modData)
    end
    applyBloodTypeTrait(player, key, state)
    modData[Schema.ROOT_KEY] = state
    log:info(key, "new health state, schema version", state.version)
    return state
end

return PlayerState
