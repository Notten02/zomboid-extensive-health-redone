-- The only code that writes vanilla character stats. tests/layout_spec.lua checks that no other file does.
--
-- After the simulation systems have run for a player, apply() resolves each stat they touched (Core/StatAggregator)
-- and writes the result once. On a dedicated server the new value is sent to the owning client.

local Env = require "ExtensiveHealthRedone/Game/Env"
local statNames = require "ExtensiveHealthRedone/Data/VanillaStats"

local log = Env.logger("Stats")

local StatWriter = {}

local ranges

-- Ranges of the stats we may change, read from the game: { [name] = { min, max } }.
function StatWriter.ranges()
    if not ranges then
        ranges = {}
        for _, name in ipairs(statNames) do
            local stat = CharacterStat[name]
            if stat then
                ranges[name] = { min = stat:getMinimumValue(), max = stat:getMaximumValue() }
            else
                log:warn("vanilla has no CharacterStat." .. name .. "; contributions to it will fail")
            end
        end
    end
    return ranges
end

-- Writes every stat the aggregator was told about. Returns the number of stats changed.
function StatWriter.apply(player, aggregator)
    local stats = player:getStats()
    local written = 0
    for _, name in ipairs(aggregator:touched()) do
        local stat = CharacterStat[name]
        local value, changed = aggregator:resolve(name, stats:get(stat))
        if changed then
            stats:set(stat, value)
            if isServer() then
                sendPlayerStat(player, stat)
            end
            written = written + 1
        end
    end
    return written
end

-- Keeps TEMPERATURE between floor and ceiling (deg C, either may be false): Server/Temperature calls this every
-- tick with Body/Temperature's bounds. Inside them vanilla's value is left alone. On a dedicated server the owning
-- client is sent the value at most every HOLD_SEND_MS.
StatWriter.HOLD_SEND_MS = 1000
local lastHoldSend = {}

function StatWriter.holdTemperature(key, player, floor, ceiling)
    local stat = CharacterStat.TEMPERATURE
    local stats = player:getStats()
    local current = stats:get(stat)
    local value
    if floor and current < floor then
        value = floor
    elseif ceiling and current > ceiling then
        value = ceiling
    else
        return
    end
    stats:set(stat, value)
    if isServer() then
        local now = getTimestampMs()
        if now - (lastHoldSend[key] or 0) >= StatWriter.HOLD_SEND_MS then
            lastHoldSend[key] = now
            sendPlayerStat(player, stat)
        end
    end
end

return StatWriter
