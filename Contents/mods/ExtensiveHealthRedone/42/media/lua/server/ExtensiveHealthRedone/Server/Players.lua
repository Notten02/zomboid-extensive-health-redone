-- Server adapter for players: finding them, describing them as plain records, and the facts the command registry
-- needs (distance, inventory items, permissions). Nothing here trusts what a client says about itself.

local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Permissions = require "ExtensiveHealthRedone/Game/Permissions"

local Players = {}

-- Every player whose state the server owns right now: online players in MP, the local players in single player.
function Players.online()
    local list = {}
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do
            list[#list + 1] = online:get(i)
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player then
                list[#list + 1] = player
            end
        end
    end
    return list
end

function Players.isAlive(player)
    return player ~= nil and not player:isDead()
end

-- The record the command registry and handlers work with. `player` is the game object, for adapter code only.
function Players.record(player)
    return { key = PlayerKey.of(player), player = player }
end

-- Strict lookup of a player a client names in a command.
-- MP: the online ID only (a number), and the player must be online and alive. Single player: our player key.
function Players.find(ref)
    local player
    if isServer() then
        if type(ref) ~= "number" then
            return nil
        end
        player = getPlayerByOnlineID(ref)
    elseif type(ref) == "string" then
        local index = tonumber(ref:match("^sp:(%d+)$"))
        player = index and getSpecificPlayer(index)
    end
    if not Players.isAlive(player) then
        return nil
    end
    return Players.record(player)
end

-- Tiles between two players, 0 in the same vehicle, nil on different floors.
function Players.distance(a, b)
    local vehicle = a:getVehicle()
    if vehicle and vehicle == b:getVehicle() then
        return 0
    end
    if math.floor(a:getZ()) ~= math.floor(b:getZ()) then
        return nil
    end
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end

-- An item in the player's own inventory or in containers they carry, by item ID. Returns a record or nil.
function Players.findItem(player, id)
    local item = player:getInventory():getItemWithIDRecursiv(id)
    if not item then
        return nil
    end
    return { id = id, fullType = item:getFullType(), item = item }
end

function Players.can(player, permission)
    return Permissions.has(player, permission)
end

return Players
