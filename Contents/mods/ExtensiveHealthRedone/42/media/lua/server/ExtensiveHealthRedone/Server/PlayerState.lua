-- Loads or creates a player's health state in their modData, on the side that owns it.
--
-- Existing state: upgraded through the schema's migration chain. New character: a fresh state, plus the one-time
-- import when the character carries the original mod's data.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Schema = require "ExtensiveHealthRedone/Core/Schema"
local Importer = require "ExtensiveHealthRedone/Core/Importer"

local log = Env.logger("PlayerState")

local PlayerState = {}

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
        Schema.fillDefaults(state)
        return state
    end
    state = Schema.new(Env.rng)
    if Importer.hasOldData(modData) then
        local report = Importer.run(modData, state)
        log:info(key, "imported from Extensive Health Rework:", report.summary)
    else
        Importer.removeOldKeys(modData)
    end
    modData[Schema.ROOT_KEY] = state
    log:info(key, "new health state, schema version", state.version)
    return state
end

return PlayerState
