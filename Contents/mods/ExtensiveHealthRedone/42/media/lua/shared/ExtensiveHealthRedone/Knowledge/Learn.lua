-- Learning medical knowledge from the world: disease flyers, the Wild Plants guide and the 47.0 MHz radio. Pure rules
-- on a player context (Core/Simulation); Server/Flyers and Server/Radio call them inside Runtime.applyNow.
--
-- Only these rules (and Knox.learnFromHerald and Knox.learnFromBloodTest) write state.knowledge.diseases, and nothing
-- a client sends reaches them: the server sees the real item in vanilla's ISReadABook:complete, or decides itself who
-- heard the radio. No client command can unlock knowledge.
--
-- XP (Data/Xp): 50 for a flyer id learned for the first time (from any
-- source: a flyer for an id the radio already taught gives none), 50 for the first Wild Plants read, 4 for each 09:00
-- tip heard. Nothing for the 21:00 file, the recipe guides or a re-read.
-- Lines: "Medical knowledge acquired: %1" goes to the client as knowledgeLearned (Client/RadioKnowledge), because
-- p.say has no argument slot; the other lines are plain keys.

local Knowledge = require "ExtensiveHealthRedone/Conditions/Knowledge"
local RadioData = require "ExtensiveHealthRedone/Data/Radio"

local Learn = {}

-- Records a knowledge id. Returns "learned" (new), "known" (already recorded) or "refused" (Knox: only the Herald,
-- Knox.learnFromHerald, may teach it).
function Learn.disease(p, id)
    if type(id) ~= "string" or id == Knowledge.KNOX then
        return "refused"
    end
    local diseases = p.state.knowledge.diseases
    if diseases[id] then
        return "known"
    end
    diseases[id] = true
    p.dirty("knowledge")
    return "learned"
end

-- Raises the character's level in an add-on knowledge strand (Conditions/Knowledge). Levels never go down. nameKey:
-- optional translation key for the "Medical knowledge acquired" line. Returns "learned" (raised) or "known".
function Learn.strand(p, id, level, nameKey)
    if type(id) ~= "string" or type(level) ~= "number" then
        error("Learn.strand needs a strand id and a level", 2)
    end
    local knowledge = p.state.knowledge
    knowledge.strands = knowledge.strands or {}
    if (tonumber(knowledge.strands[id]) or 0) >= level then
        return "known"
    end
    knowledge.strands[id] = level
    p.dirty("knowledge")
    if nameKey then
        p.client("knowledgeLearned", { name = nameKey })
    end
    return "learned"
end

local function sayLearned(p, nameKey)

    p.client("knowledgeLearned", { name = nameKey })
end

-- The Wild Medicinal Plants guide: opens the medicinal plant search regardless of skill.
function Learn.wildPlants(p)
    local knowledge = p.state.knowledge
    if knowledge.wildPlants then
        p.say("UI_EHR_HerbalSearch_KnowledgeAlreadyKnown")
        return "known"
    end
    knowledge.wildPlants = true
    p.dirty("knowledge")
    p.xp("wildPlants")
    p.say("UI_EHR_HerbalSearch_KnowledgeLearned")
    return "learned"
end

-- A flyer or guide read to the end. entry: Data/Flyers.entry(fullType). Returns the outcome.
function Learn.read(p, entry)
    if entry.kind == "wildPlants" then
        return Learn.wildPlants(p)
    end
    local outcome = Learn.disease(p, entry.id)
    if outcome == "learned" then
        p.xp("flyer", entry.id)
        sayLearned(p, entry.name)
    elseif outcome == "known" then
        p.say("UI_EHR_FlyerAlreadyKnown")
    end
    return outcome
end

-- The day a radioHeard key belongs to ("<day>:<hour>:..."), or nil.
function Learn.heardDay(key)
    local day = type(key) == "string" and key:match("^(%-?%d+):") or nil
    return day and tonumber(day) or nil
end

-- Drops radioHeard keys from before today - keepDays. Keys without a day are left alone.
function Learn.prune(heard, today, keepDays)
    local old = {}
    for key in pairs(heard) do
        local day = Learn.heardDay(key)
        if day and day < today - keepDays then
            old[#old + 1] = key
        end
    end
    for _, key in ipairs(old) do
        heard[key] = nil
    end
    return #old
end

-- A listener heard a broadcast to the end. heard: the slot key in the original mod's format ("<day>:9:XP:4",
-- "<day>:21:KNOW:<id>"), so imported keys still count. reward: { kind = "xp" } or { kind = "know", id, name }.
-- today: the broadcast's day. Returns true when this rewarded the listener (once per slot).
function Learn.radio(p, heard, reward, today)
    local knowledge = p.state.knowledge
    if knowledge.radioHeard[heard] then
        return false
    end
    knowledge.radioHeard[heard] = true
    Learn.prune(knowledge.radioHeard, today, RadioData.HEARD_KEEP_DAYS)
    p.dirty("knowledge")
    if reward.kind == "xp" then
        p.xp("radioTip")
    elseif reward.kind == "know" then
        -- The Knox file is recorded as heard but teaches nothing.
        if Learn.disease(p, reward.id) == "learned" then
            sayLearned(p, reward.name)
        end
    end
    return true
end

return Learn
