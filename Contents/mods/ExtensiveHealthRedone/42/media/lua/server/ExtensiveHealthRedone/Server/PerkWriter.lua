-- The only code that takes skill XP away: the passive-skill drains of a simulation step (Core/PerkAggregator), applied
-- the way vanilla's own Strength and Fitness decay does (server/XpSystem/XpUpdate.lua, everyTenMinutes): negative XP
-- through addXp, then a level lost once the XP falls below what the level needs. Drains build up in
-- state.body.perkDrain and are applied in whole XP, so a slow drain doesn't sync XP every minute.

local Tables = require "ExtensiveHealthRedone/Core/Tables"
local PerkAggregator = require "ExtensiveHealthRedone/Core/PerkAggregator"
local Env = require "ExtensiveHealthRedone/Game/Env"

local log = Env.logger("Perks")

local PerkWriter = {}

-- Vanilla's checkForLosingLevel.
local function loseLevel(player, perk)
    local info = player:getPerkInfo(perk)
    if not info then
        return
    end
    local level = info:getLevel()
    if level >= 1 and level <= 10 and player:getXp():getXP(perk) < PerkFactory.getPerk(perk):getTotalXpForLevel(level) then
        player:LoseLevel(perk)
        log:info(player:getUsername(), "lost a level of", tostring(perk))
    end
end

-- perks: the step's PerkAggregator; bodyState: state.body; dt: game minutes. Returns the XP taken, by perk name.
function PerkWriter.apply(player, perks, bodyState, dt)
    bodyState.perkDrain = bodyState.perkDrain or {}
    local pending = bodyState.perkDrain
    local taken = {}
    for _, name in ipairs(Tables.sortedKeys(PerkAggregator.PERKS)) do
        local rate = perks:get(name)
        if rate > 0 then
            local owed = (pending[name] or 0) + rate * dt / 60
            if owed >= 1 then
                local whole = math.floor(owed)
                owed = owed - whole
                local perk = Perks[name]
                if player:getXp():getXP(perk) > 0 then
                    addXp(player, perk, -whole)
                    taken[name] = whole
                end
                loseLevel(player, perk)
            end
            pending[name] = owed
        else
            pending[name] = nil
        end
    end
    return taken
end

return PerkWriter
