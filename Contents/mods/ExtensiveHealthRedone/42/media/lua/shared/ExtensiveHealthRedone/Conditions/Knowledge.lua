-- What a character can tell about a condition: its name, its stage, and its progress and treatment. Pure, so the
-- monitor (Phase 7), the journal and the exam (Phase 9) all use the same rules. From the checklist (section 7,
-- "Knowledge gating"; v0.9 EHR_HealthPanelUI.lua:2203-2433, EHR_DiseaseFlyers.lua:357-390):
--   name      known from a flyer or radio unlock, a medical profession, First Aid 8, or self-evident (you know you are
--             freezing); Knox only from the Kentucky Herald, never from skill or profession
--   stage     First Aid 4+ (and the name is known)
--   progress  First Aid 6+ (and the name is known): time left, treatment

local Knowledge = {}

Knowledge.NAME_LEVEL = 8
Knowledge.STAGE_LEVEL = 4
Knowledge.PROGRESS_LEVEL = 6
Knowledge.KNOX = "knox_infection"

-- state: the player's state (knowledge section); def: the condition definition; firstAid: the First Aid level.
-- Returns { name = bool, stage = bool, progress = bool }.
function Knowledge.of(state, def, firstAid)
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
