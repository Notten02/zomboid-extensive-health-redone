-- The client side: a read-only mirror of the health state the authority sends, and the way to send intents.
--
--   local Client = require "ExtensiveHealthRedone/Client/Client"
--   Client.section(player, "identity")                    -- mirrored data, or nil before the first snapshot
--   Client.onChange(function(ownerKey, sections) ... end) -- after each applied sync message
--   Client.on("debugDump", function(args) ... end)        -- other server messages
--   Client.send(player, "debug.skipTime", { minutes = 60 })
--   Client.localPlayer(args.owner)                         -- the local player a server message is for
--
-- The UI reads the mirror only. It never reads or writes health state in modData: in MP that copy is not
-- authoritative.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Sync = require "ExtensiveHealthRedone/Core/Sync"

local log = Env.logger("Client")

local Client = {}

Client.mirror = Sync.newMirror()

local changeListeners = {}
local messageHandlers = {}
local lastHello = {}

function Client.onChange(fn)
    changeListeners[#changeListeners + 1] = fn
end

function Client.on(command, fn)
    messageHandlers[command] = fn
end

function Client.send(player, command, args)
    Transport.toServer(player, command, args)
end

function Client.section(player, name)
    return Client.mirror:section(PlayerKey.of(player), name)
end

-- Asks for a full snapshot, at most once every few seconds per player.
function Client.hello(player)
    local key = PlayerKey.of(player)
    local now = Env.realSeconds()
    if lastHello[key] and now - lastHello[key] < 3 then
        return
    end
    lastHello[key] = now
    Client.send(player, "sync.hello", { v = Sync.PROTOCOL })
end

-- The local player a message is for (split screen has several), or nil.
function Client.localPlayer(ownerKey)
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and PlayerKey.of(player) == ownerKey then
            return player
        end
    end
    return nil
end

messageHandlers.sync = function(args)
    local changed, status = Client.mirror:apply(args)
    if status == "needHello" then
        local player = Client.localPlayer(args.owner)
        if player then
            Client.hello(player)
        end
        return
    elseif status ~= "ok" then
        log:warn("ignored a sync message:", status)
        return
    end
    if #changed > 0 then
        for _, fn in ipairs(changeListeners) do
            fn(args.owner, changed)
        end
    end
end

local rejectedListeners = {}

-- fn(args) when the server refused one of our commands: args.command, args.code (Core/CommandRegistry), args.detail.
-- Client/AdminChat shows refused admin commands to the admin.
function Client.onRejected(fn)
    rejectedListeners[#rejectedListeners + 1] = fn
end

messageHandlers.rejected = function(args)
    log:info("server rejected", args.command, args.code, args.detail)
    for _, fn in ipairs(rejectedListeners) do
        fn(args)
    end
end

Transport.onServerCommand(function(command, args)
    local handler = messageHandlers[command]
    if handler then
        handler(args)
    else
        log:warn("unknown server message", command)
    end
end)

Events.OnGameStart.Add(Env.applyLogLevel)

Events.OnCreatePlayer.Add(function(_, player)
    Client.mirror:forget(PlayerKey.of(player))
    lastHello[PlayerKey.of(player)] = nil
    Client.hello(player)
end)

return Client
