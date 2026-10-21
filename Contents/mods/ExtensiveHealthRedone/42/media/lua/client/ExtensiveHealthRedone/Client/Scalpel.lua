-- Scalpel Master on an MP client: the same main-hand tracking as the authority (Server/Scalpel, Game/Scalpel) for the
-- local players, so the client's copy of the scalpel has the values the server computes, whichever side computes a
-- melee hit in 42.21 MP (unverified). Equip events update at once; every tick checks the main hand (one getter per
-- local player); about once a real second a full pass re-evaluates the held scalpel (a trait synced later).
-- The swing guard also covers remote attackers' scalpels on this client.
-- Single player has no separate client: the authority there tracks the local players itself, so this file stops.

if not isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local GameScalpel = require "ExtensiveHealthRedone/Game/Scalpel"

local log = Env.logger("Scalpel")

local ClientScalpel = {}

ClientScalpel.FULL_PASS_MS = 1000

ClientScalpel.tracker = GameScalpel.Tracker.new(function(player, _, boosted)
    log:debug(player:getUsername(), boosted and "boosted" or "reset", "a scalpel")
end)

local tracker = ClientScalpel.tracker
local lastFull = 0

-- Local players by player number.
function ClientScalpel.pass(full)
    tracker:releaseWhere(function(index, player)
        return getSpecificPlayer(index) ~= player or player:isDead()
    end)
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() then
            tracker:reconcile(i, player, full)
        end
    end
end

local function onTick()
    local now = getTimestampMs()
    local full = now - lastFull >= ClientScalpel.FULL_PASS_MS
    if full then
        lastFull = now
    end
    ClientScalpel.pass(full)
end

local function onEquip(character)
    if character and character:isLocalPlayer() and not character:isDead() then
        tracker:reconcile(character:getPlayerNum(), character, true)
    end
end

Events.OnTick.Add(onTick)
Events.OnEquipPrimary.Add(onEquip)
Events.OnEquipSecondary.Add(onEquip)
Events.OnWeaponSwing.Add(function(attacker, weapon)
    tracker:guard(attacker, weapon)
end)
Events.OnPlayerDeath.Add(function(player)
    tracker:releasePlayer(player)
end)

return ClientScalpel
