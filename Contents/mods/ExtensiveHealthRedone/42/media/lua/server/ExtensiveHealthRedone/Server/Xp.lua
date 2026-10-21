-- Awards First Aid (and, for the wild searches, Foraging) XP on the authority (amounts in Data/Xp). Vanilla awards medical XP the same way, with the global
-- addXp in a timed action's complete(), which syncs it to the client.

local Env = require "ExtensiveHealthRedone/Game/Env"
local XpData = require "ExtensiveHealthRedone/Data/Xp"

local log = Env.logger("Xp")

local Xp = {}

function Xp.award(player, kind, id)
    if not player or player:isDead() then
        return 0
    end
    local amount = XpData.amount(kind, id, Env.sandbox)
    if amount > 0 then
        local perk = XpData.perk(kind)
        addXp(player, Perks[perk], amount)
        log:debug(player:getUsername(), perk, "XP", amount, "for", kind, id or "")
    end
    return amount
end

return Xp
