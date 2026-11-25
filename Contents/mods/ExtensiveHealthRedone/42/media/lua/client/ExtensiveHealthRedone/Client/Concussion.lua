-- Reports fall and vehicle-crash damage to the server for the concussion check (Diseases/Concussion), for the
-- damage events vanilla raises on an MP client only. Where the authority hears the event itself it needs no report
-- (Server/Corpse): in single player, and on a dedicated server for a fall, which B42 raises there and never here.
-- A report only opens the window: the server takes the kind from its own facts and looks for real trauma on the
-- body before it rolls.

if not isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"

local KINDS = { FALLDOWN = "fall", CARCRASHDAMAGE = "crash" }
local MIN_GAP = 1           -- real seconds between two reports per player (damage fires every frame of a fall)

local last = {}

Events.OnPlayerGetDamage.Add(function(character, damageType)
    local kind = KINDS[tostring(damageType)]
    if not kind or not instanceof(character, "IsoPlayer") then
        return
    end
    local player = character --[[@as IsoPlayer]]
    if not player:isLocalPlayer() then
        return
    end
    local key = PlayerKey.of(player)
    local now = Env.realSeconds()
    if last[key] and now - last[key] < MIN_GAP then
        return
    end
    last[key] = now
    Client.send(player, "concussion.trauma", { kind = kind })
end)
