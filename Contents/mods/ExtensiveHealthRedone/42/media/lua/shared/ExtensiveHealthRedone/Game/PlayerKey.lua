-- The key that names a player's health state in the server store and the client mirror.
-- MP: the account username (unique among online players). Single player: the local player index (split screen).

local PlayerKey = {}

function PlayerKey.of(player)
    if isClient() or isServer() then
        return "mp:" .. tostring(player:getUsername())
    end
    return "sp:" .. tostring(player:getPlayerNum())
end

-- How a client names another player in a command: the online ID in MP, the key in single player. The server's
-- strict lookup (Server/Players.find) accepts exactly these.
function PlayerKey.ref(player)
    if isClient() or isServer() then
        return player:getOnlineID()
    end
    return PlayerKey.of(player)
end

return PlayerKey
