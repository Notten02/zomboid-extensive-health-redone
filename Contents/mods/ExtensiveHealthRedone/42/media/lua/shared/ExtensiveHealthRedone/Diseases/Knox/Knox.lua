-- Knox rules shared by the items, the immunity system and the display condition. Pure.
--
-- Vanilla owns the Knox infection itself (bites, progress, death). What we add:
--   * permanent immunity (gene therapy survivors, the Patient Zero trait) and 24 h immunobooster protection, enforced
--     every simulation step by clearing vanilla's infection (bite wounds stay);
--   * the four Knox items (Diseases/Knox/Items) and their side effects;
--   * a display condition that mirrors vanilla's infection for the monitor (Diseases/Knox/Infection).
--
-- p.facts.knox (Server/Knox reads it): { infected, partInfected, bitten, level 0-1 (ZOMBIE_INFECTION share of its
-- range), fever 0-1 (ZOMBIE_FEVER share), timerProgress 0-1 or nil, hasTrait, followTimer }. Missing when not read (tests,
-- other players' facts), and then Knox does nothing.

local Data = require "ExtensiveHealthRedone/Diseases/Knox/Data"

local Knox = {}

Knox.ID = "knox_infection"

-- Permanently immune (gene therapy, Patient Zero). PatientZeroTraitDisabled never voids existing immunity.
function Knox.permanentlyImmune(state)
    return state.knox.geneTherapyImmune == true
end

-- Protected right now: permanently, or by an active immunobooster.
function Knox.immune(state)
    return Knox.permanentlyImmune(state) or (state.knox.boosterLeft or 0) > 0
end

-- Infection progress 0-1 from the facts: the stat, or the timers when the stat hasn't moved yet. followTimer (Server/Knox,
-- set while Zombie Virus Vaccine is on) trusts the timers alone: the vaccine and its albumin pills delay the infection by
-- moving the infection time, and vanilla may not pull the stat back with it.
function Knox.progress(k)
    if not k then
        return 0
    end
    if k.followTimer and k.timerProgress then
        return k.timerProgress
    end
    return math.max(k.level or 0, k.timerProgress or 0)
end

function Knox.infected(k)
    return k ~= nil and (k.infected == true or k.partInfected == true)
end

-- Display stage 1-4 from progress.
function Knox.stageFor(progress)
    local stage = 1
    for s, from in ipairs(Data.STAGE_FROM) do
        if progress >= from then
            stage = s
        end
    end
    return stage
end

function Knox.geneTherapyChance(bloodType)
    return Data.GENE_THERAPY_CHANCE[bloodType or ""] or Data.GENE_THERAPY_DEFAULT_CHANCE
end

function Knox.rating(chance)
    for _, band in ipairs(Data.RATINGS) do
        if chance >= band.min then
            return band.key
        end
    end
    return Data.RATINGS[#Data.RATINGS].key
end

-- Progress the next Phalanx dose resets to, or nil once the body has adapted (5th dose on).
function Knox.phalanxResetFor(uses)
    return Data.PHALANX_RESET[(uses or 0) + 1]
end

-- Whether a print media id or title is the July 16 1993 Kentucky Herald.
function Knox.isHerald(text)
    if type(text) ~= "string" then
        return false
    end
    return text:lower():gsub("[^%w]", ""):find(Data.HERALD_MATCH, 1, true) ~= nil
end

-- Unlocks Knox knowledge. knoxHerald is the "Knox knowledge unlocked" flag the monitor checks (Conditions/Knowledge).
-- Returns true when it was new.
local function unlock(p)
    local knowledge = p.state.knowledge
    if knowledge.knoxHerald and knowledge.diseases[Knox.ID] then
        return false
    end
    knowledge.knoxHerald = true
    knowledge.diseases[Knox.ID] = true
    p.dirty("knowledge")
    return true
end

-- Only the Herald (a read the server saw) and a finished Zombie Virus Vaccine blood test (Server/ZVirusVaccine, run by
-- the vaccine mod's server code) may call these two.
function Knox.learnFromHerald(p)
    return unlock(p)
end

function Knox.learnFromBloodTest(p)
    return unlock(p)
end

return Knox
