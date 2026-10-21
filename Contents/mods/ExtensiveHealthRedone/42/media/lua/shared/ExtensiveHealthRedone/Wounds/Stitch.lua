-- Stitch minigame rules: quality from misses, and what a stitch of that quality does. The client runs the minigame
-- and reports misses; the server applies the outcome (rolls happen here, on the authority).
-- From v0.9 EHR_StitchMinigame.lua (docs/porting/phase3/stitch-minigame-and-b42-api.md, part A). W34: a failed or
-- cancelled poor attempt rolls cellulitis, a very poor stitch can infect the wound, and immunity modifies the
-- cellulitis chance. A great stitch no longer clears infections.
-- Phase 9 (SA-1 to SA-3, Server/Health): stitching another player needs consent, the doctor must carry a stitching
-- item, a success faster than Stitch.MIN_SECONDS counts as poor, and with the minigame on a vanilla stitch that
-- arrives without a minigame result counts as poor.
-- Residual trust (accepted): the miss count is the client's. A modified client can wait out MIN_SECONDS and claim
-- 0 misses ("excellent"); the server logs every excellent claim with its duration so admins can spot it. The gain is
-- capped at one excellent stitch per wound (less pain, no cellulitis roll).

local Data = require("ExtensiveHealthRedone/Data/Wounds").stitch
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Risk = require "ExtensiveHealthRedone/Conditions/Risk"

local Stitch = {}

-- The shortest real time a finished minigame can take (Data/Wounds MIN_SECONDS_PER_POINT).
Stitch.MIN_SECONDS = Data.POINTS * Data.MIN_SECONDS_PER_POINT

-- Misses allowed before the attempt fails: 4 at First Aid 0-3, 5 at 4-7, 6 at 8-10.
function Stitch.maxMisses(firstAid)
    return math.min(6, 4 + math.floor((firstAid or 0) / 4))
end

function Stitch.quality(misses)
    return math.max(Data.MIN_QUALITY, 1 - misses * Data.MISS_QUALITY)
end

-- "excellent", "stable", "rough" or "poor".
function Stitch.band(quality)
    if quality >= Data.GREAT then
        return "excellent"
    elseif quality >= Data.STABLE then
        return "stable"
    elseif quality >= Data.ROUGH then
        return "rough"
    end
    return "poor"
end

-- Immunity modifies the chance (W34; Conditions/Risk).
function Stitch.cellulitisChance(p)
    return Risk.chance(p, "cellulitis", Data.CELLULITIS_CHANCE)
end

local function rollCellulitis(p, defs, part)
    if Chance.roll(p.rng, Stitch.cellulitisChance(p)) then
        return Engine.contract(p, defs, "cellulitis", { source = part }) ~= nil
    end
    return false
end

-- A finished stitch of a quality band on the patient p. wasInfected: the part's vanilla infection before vanilla's
-- own roll. Returns { band, cellulitis = bool, infected = bool }.
function Stitch.applyBand(p, defs, part, band, wasInfected)
    local result = { band = band, cellulitis = false, infected = false }
    if band == "excellent" then
        p.body:addPain(part, "stitch", Data.PAIN.great)
    elseif band == "rough" then
        p.body:addPain(part, "stitch", Data.PAIN.rough)
        result.cellulitis = rollCellulitis(p, defs, part)
    elseif band == "poor" then
        p.body:addPain(part, "stitch", Data.PAIN.poor)
        if not wasInfected and Chance.roll(p.rng, Data.VERY_POOR_INFECTION) then
            p.body:infect(part, "stitch")
            result.infected = true
        end
        result.cellulitis = rollCellulitis(p, defs, part)
    end
    return result
end

-- A finished stitch with that many misses.
function Stitch.applySuccess(p, defs, part, misses, wasInfected)
    return Stitch.applyBand(p, defs, part, Stitch.band(Stitch.quality(misses)), wasInfected)
end

-- A failed or cancelled attempt. started: at least one point was tried. Failure hurts; a dirty attempt (below
-- "stable") rolls cellulitis.
function Stitch.applyAbort(p, defs, part, misses, started, failed)
    local result = { cellulitis = false }
    if failed then
        p.body:addPain(part, "stitch", Data.PAIN.failed)
    end
    if started and Stitch.quality(misses) < Data.STABLE then
        result.cellulitis = rollCellulitis(p, defs, part)
    end
    return result
end

return Stitch
