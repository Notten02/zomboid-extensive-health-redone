-- What a character can tell about a condition: its name, its stage, and its progress and treatment. Pure, so the
-- monitor, the journal and the exam all use the same rules:
--   name      known from a flyer or radio unlock, a medical profession, First Aid 8, or self-evident (you know you are
--             freezing); Knox only from the Kentucky Herald, never from skill or profession
--   stage     First Aid 4+ (and the name is known)
--   progress  First Aid 6+ (and the name is known): time left, treatment
--
-- Add-on knowledge strands: a condition with def.strand is judged only by that strand's rule, never by the medical
-- rules above (a Doctor or First Aid 8 doesn't name another field's conditions). The level a character has reached
-- in a strand is state.knowledge.strands[id] (written by Knowledge/Learn.strand), so the exam sees the doctor's.
--
--   Knowledge.registerStrand("nutrition", function(state, def, firstAid, level)
--       return { name = level >= 1, stage = level >= 2, progress = level >= 2 }
--   end)

local Knowledge = {}

local strands = {}

-- rule(state, def, firstAid, level) -> { name, stage, progress } (booleans). level: the reader's level in the strand
-- (0 when none).
function Knowledge.registerStrand(id, rule)
    if type(id) ~= "string" or type(rule) ~= "function" then
        error("knowledge strands need an id and a rule", 2)
    end
    if strands[id] then
        error("knowledge strand " .. id .. " is already registered", 2)
    end
    strands[id] = rule
end

function Knowledge.hasStrand(id)
    return strands[id] ~= nil
end

-- The reader's level in a strand: 0 when none.
function Knowledge.strandLevel(state, id)
    local known = state.knowledge and state.knowledge.strands
    return known and tonumber(known[id]) or 0
end

Knowledge.NAME_LEVEL = 8
Knowledge.STAGE_LEVEL = 4
Knowledge.PROGRESS_LEVEL = 6
Knowledge.KNOX = "knox_infection"

-- state: the player's state (knowledge section); def: the condition definition; firstAid: the First Aid level.
-- Returns { name = bool, stage = bool, progress = bool }.
function Knowledge.of(state, def, firstAid)
    if def.strand then
        local rule = strands[def.strand]
        local r = rule and rule(state, def, firstAid, Knowledge.strandLevel(state, def.strand)) or {}
        local name = r.name == true or def.selfEvident == true
        return { name = name, stage = name and r.stage == true, progress = name and r.progress == true }
    end
    local id = def.knowledge

    local known = state.knowledge
    local name
    if id == Knowledge.KNOX then
        name = known.diseases[id] == true and known.knoxHerald == true
    else
        name = def.selfEvident == true or (id ~= nil and known.diseases[id] == true) or known.professionGrant ~= nil
            or (firstAid or 0) >= Knowledge.NAME_LEVEL
    end
    return {
        name = name,
        stage = name and (firstAid or 0) >= Knowledge.STAGE_LEVEL,
        progress = name and (firstAid or 0) >= Knowledge.PROGRESS_LEVEL,
    }
end

return Knowledge
