-- Lifestyle: Hobbies as the simulation sees it: facts.lifestyle, a cleaned reading of the player's hygiene,
-- bathing, sitting and yoga (Lifestyle/Pace), which Conditions/Engine turns into faster or slower recovery and
-- Diseases/Weather/Meters into "a shower counts as bathing for heat". An MP client loads this file too and stops at the
-- first line.
--
-- Lifestyle's data lives in the owning client's modData and a dedicated server never has it. So in MP the client
-- reports it (Client/Lifestyle) and the report is used only while Lifestyle is on here too and it is at most FRESH_S
-- real seconds old; in single player the reading comes straight from the player (Game/Lifestyle). Without Lifestyle,
-- facts.lifestyle stays nil and nothing changes.
--
-- Trust (a client can't be believed): every field is clamped to its range, a shower only counts
-- while the character stands still outside a vehicle, and the whole effect is bounded: the pace is at most +50 % and
-- the heat meters only get the usual bathing relief. Residual, accepted: a modified client can claim a clean, seated,
-- yogi character and recover faster. It affects nobody else, and the option to ignore Lifestyle is simply not
-- installing it.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Lifestyle = require "ExtensiveHealthRedone/Game/Lifestyle"
local Pace = require "ExtensiveHealthRedone/Lifestyle/Pace"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"

local log = Env.logger("Lifestyle")

local ServerLifestyle = {}

ServerLifestyle.FRESH_S = 90

local reported = {}     -- key -> { sample = raw reading, at = real seconds }
local glow = {}         -- key -> game minutes at which the "recently bathed" glow ends

-- A client's report for player key: the raw reading, or nil when it has no Lifestyle data any more.
function ServerLifestyle.report(key, sample)
    reported[key] = sample and { sample = sample, at = Env.realSeconds() } or nil
end

Runtime.registry:register("lifestyle.report", {
    args = {
        hygiene = { type = "number", min = 0, max = 100, optional = true },
        showering = { type = "boolean", optional = true },
        sitting = { type = "boolean", optional = true },
        comfort = { type = "number", min = 0, max = 1, optional = true },
        yoga = { type = "number", min = 0, max = 10, integer = true, optional = true },
        clear = { type = "boolean", optional = true },
    },
    rate = { count = 6, seconds = 10 },
    handler = function(ctx, args)
        if args.clear then
            ServerLifestyle.report(ctx.actor.key, nil)
            return
        end
        ServerLifestyle.report(ctx.actor.key, {
            hygiene = args.hygiene, showering = args.showering, sitting = args.sitting, comfort = args.comfort,
            yoga = args.yoga,
        })
    end,
})

Runtime.onDetach(function(key)
    reported[key] = nil
    glow[key] = nil
end)

-- The raw reading for a player now, or nil.
local function raw(player, key)
    if not Lifestyle.active() then
        return nil
    end
    if not isServer() then
        return Lifestyle.sample(player)
    end
    local r = reported[key]
    if r and Env.realSeconds() - r.at <= ServerLifestyle.FRESH_S then
        return r.sample
    end
    return nil
end

-- The reading as the simulation uses it: cleaned, a shower only believed to a character standing still outside a
-- vehicle, plus the glow after a shower. Returns nil when there is nothing to read.
function ServerLifestyle.read(player, facts)
    local key = PlayerKey.of(player)
    local sample = raw(player, key)
    if not sample then
        glow[key] = nil
        return nil
    end
    local now = Env.gameMinutes()
    local showering = sample.showering == true and not facts.inVehicle and not facts.env.moving
    if showering then
        glow[key] = now + Pace.BATH_GLOW_MINUTES
    end
    local left = glow[key] and glow[key] - now or 0
    if left <= 0 then
        glow[key] = nil
        left = 0
    end
    return Pace.read({
        hygiene = sample.hygiene, showering = showering, bathLeft = left, sitting = sample.sitting,
        comfort = sample.comfort, yoga = sample.yoga,
    })
end

Facts.extend("lifestyle", function(player, facts)
    facts.lifestyle = ServerLifestyle.read(player, facts)
end)

log:info("lifestyle loaded")

return ServerLifestyle
