-- Messages between the client side and the server side, with one code path for single player and multiplayer.
--
-- MP: sendClientCommand / OnClientCommand and sendServerCommand / OnServerCommand under our module name.
-- Single player has no network, so the two sides call each other directly. Arguments are deep-copied either way, so
-- neither side can hold a reference into the other's tables, just as over the network.
-- A message that arrives before the other side has registered its handler is queued until it does.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Transport = {}

Transport.MODULE = "ExtensiveHealthRedone"

local serverHandler, clientHandler
local toServerQueue, toClientQueue = {}, {}

local function local_()
    return not isClient() and not isServer()
end

-- Server side. handler(player, command, args).
function Transport.onClientCommand(handler)
    serverHandler = handler
    if local_() then
        local queued = toServerQueue
        toServerQueue = {}
        for _, m in ipairs(queued) do
            handler(m.player, m.command, m.args)
        end
        return
    end
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module == Transport.MODULE then
            handler(player, command, args or {})
        end
    end)
end

-- Client side. handler(command, args).
function Transport.onServerCommand(handler)
    clientHandler = handler
    if local_() then
        local queued = toClientQueue
        toClientQueue = {}
        for _, m in ipairs(queued) do
            handler(m.command, m.args)
        end
        return
    end
    Events.OnServerCommand.Add(function(module, command, args)
        if module == Transport.MODULE then
            handler(command, args or {})
        end
    end)
end

-- Client -> server, on behalf of a local player.
function Transport.toServer(player, command, args)
    args = Tables.deepCopy(args or {})
    if not local_() then
        sendClientCommand(player, Transport.MODULE, command, args)
    elseif serverHandler then
        serverHandler(player, command, args)
    else
        toServerQueue[#toServerQueue + 1] = { player = player, command = command, args = args }
    end
end

-- Server -> the client of one player.
function Transport.toClient(player, command, args)
    args = Tables.deepCopy(args or {})
    if not local_() then
        sendServerCommand(player, Transport.MODULE, command, args)
    elseif clientHandler then
        clientHandler(command, args)
    else
        toClientQueue[#toClientQueue + 1] = { command = command, args = args }
    end
end

return Transport
