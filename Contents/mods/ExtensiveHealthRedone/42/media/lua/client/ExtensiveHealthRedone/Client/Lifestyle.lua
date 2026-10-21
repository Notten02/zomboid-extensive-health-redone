-- Lifestyle: Hobbies, the client's two jobs (Phase 10):
--  1. MP only: report the local players' Lifestyle reading (hygiene, bathing, sitting, yoga) to the server, which can't
--     see Lifestyle's client-side data (Server/Lifestyle). Sent when it changes or appears or goes away, and at least
--     every HEARTBEAT_S while it lasts; checked every CHECK_S real seconds. In SP the server reads it directly.
--  2. Carry out the server's bladder pressure: dysentery and furosemide raise Lifestyle's bathroom need
--     (state.effects.bladder, points per game hour, from Core/ClientEffects). Lifestyle owns the need and its moodle;
--     we only add to the number each game minute, and not while the character is on the toilet. Without Lifestyle's
--     toilet system nothing happens.

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Lifestyle = require "ExtensiveHealthRedone/Game/Lifestyle"
local Client = require "ExtensiveHealthRedone/Client/Client"

local ClientLifestyle = {}

ClientLifestyle.CHECK_S = 5
ClientLifestyle.HEARTBEAT_S = 30
ClientLifestyle.HYGIENE_STEP = 2        -- points of hygiene need that make a new report

local nextCheck = 0
local sent = {}     -- key -> { sample = reading or false, at = real seconds }

local function changed(last, sample)
    if sample == false or last.sample == false then
        return sample ~= last.sample
    end
    local before = last.sample
    if (sample.hygiene == nil) ~= (before.hygiene == nil)
        or (sample.hygiene and math.abs(sample.hygiene - before.hygiene) >= ClientLifestyle.HYGIENE_STEP) then
        return true
    end
    return sample.showering ~= before.showering or sample.sitting ~= before.sitting or sample.yoga ~= before.yoga
        or math.abs(sample.comfort - before.comfort) >= 0.05
end

local function report(player, now)
    local key = PlayerKey.of(player)
    local sample = Lifestyle.sample(player) or false
    local last = sent[key]
    local due = last ~= nil and sample ~= false and now - last.at >= ClientLifestyle.HEARTBEAT_S
    if last ~= nil and not due and not changed(last, sample) then
        return
    end
    if sample == false and last == nil then
        return
    end
    if sample then
        Client.send(player, "lifestyle.report", {
            hygiene = sample.hygiene, showering = sample.showering, sitting = sample.sitting,
            comfort = sample.comfort, yoga = sample.yoga,
        })
    else
        Client.send(player, "lifestyle.report", { clear = true })
    end
    sent[key] = { sample = sample, at = now }
end

function ClientLifestyle.tick()
    local now = Env.realSeconds()
    if now < nextCheck then
        return
    end
    nextCheck = now + ClientLifestyle.CHECK_S
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() then
            report(player, now)
        end
    end
end

-- The server's bladder pressure for a player, in points per game hour (negative: medicine easing it).
function ClientLifestyle.bladderRate(player)
    local effects = Client.section(player, "effects")
    return effects and tonumber(effects.bladder) or 0
end

-- One game minute of bladder pressure for every local player.
function ClientLifestyle.minute()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() then
            local rate = ClientLifestyle.bladderRate(player)
            if rate ~= 0 then
                Lifestyle.addBathroomNeed(player, rate / 60)
            end
        end
    end
end

if isClient() then
    Events.OnTick.Add(ClientLifestyle.tick)
end
Events.EveryOneMinute.Add(ClientLifestyle.minute)

return ClientLifestyle
