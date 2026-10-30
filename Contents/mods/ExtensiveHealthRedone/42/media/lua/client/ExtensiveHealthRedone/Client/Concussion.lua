-- Reports fall and vehicle-crash damage to the server for the concussion check (Diseases/Concussion). Vanilla only
-- raises OnPlayerGetDamage for local players, so the owning client sees it first. The report only speeds things up:
-- the server also notices falls and crashes itself, takes the kind from its own facts, and looks for real trauma on
-- the body before it rolls.

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
