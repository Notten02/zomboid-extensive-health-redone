-- The EHR professions (EHR Doctor, EHR Surgeon) and the Scalpel Master trait: what Lua adds on top of the scripts
-- (scripts/EHR_Professions.txt, scripts/EHR_Traits.txt), plus the pure knowledge-grant rule.
--
-- The scripts already give the starting levels (Doctor: First Aid 6, Short Blade 1, cost 0; Surgeon: First Aid 10,
-- Short Blade 3, cost -8, the Scalpel Master trait) and the 24 recipes. Lua adds:
--   * disease knowledge: knowledge.professionGrant names every non-Knox condition (Conditions/Knowledge; Knox only
--     from the Kentucky Herald). The grant also writes the blood_types knowledge id, so an EHR Doctor at First Aid 6
--     can judge blood compatibility (Blood/Transfusion.knowsTypes). Decided by the authority when the player is
--     simulated, never from a client; never overwritten (an imported grant stays) and never revoked. Vanilla Doctor
--     and Nurse get nothing.
--   * an outfit at character creation: our own clothing selections, below.
--   * Scalpel Master's numbers: x9 damage, and x100 durability through ConditionLowerChance (not a rescaled
--     ConditionMax, which re-equipping could repair). Exact Base.Scalpel only.

local Professions = {}

-- Profession ids whose characters get the knowledge grant. Mirrors Data/LegacyEHR PROFESSION_GRANTS (the importer's
-- list of the original mod's values); tests keep the two equal.
Professions.GRANTS = { ehrdoctor = true, ehrsurgeon = true }

-- The order the profession reader checks them in (never pairs order).
Professions.IDS = { "ehrdoctor", "ehrsurgeon" }

-- Knowledge ids the grant writes into knowledge.diseases besides professionGrant. Conditions read professionGrant
-- directly; blood types are no condition, so their id is written.
Professions.GRANT_KNOWLEDGE = { "blood_types" }

-- Character creation outfits, in vanilla's ClothingSelectionDefinitions format (shared/Definitions): per body location
-- the items to pick from and an optional chance (%). Vanilla dresses a new character in them (on top of the default
-- selection) and adds them to the clothing choices. Our own outfits, because vanilla's
-- "doctor" entry is only a formal shirt and suit trousers (its lab coat is commented out). The lab coat is a JacketSuit
-- item (BodyLocation base:jacketsuit).
Professions.OUTFITS = {
    ehrdoctor = {
        Female = {
            Neck = { chance = 70, items = { "Base.Tie_Full" } },
            Shirt = { items = { "Base.Shirt_FormalTINT" } },
            Pants = { items = { "Base.Trousers_SuitTEXTURE" } },
            JacketSuit = { items = { "Base.JacketLong_Doctor" } },
            Hands = { chance = 5, items = { "Base.Gloves_Surgical" } },
            Shoes = { items = { "Base.Shoes_Black" } },
        },
    },
    ehrsurgeon = {
        Female = {
            Hat = { items = { "Base.Hat_SurgicalCap" } },
            Mask = { items = { "Base.Hat_SurgicalMask" } },
            Shirt = { items = { "Base.Shirt_Scrubs" } },
            Pants = { items = { "Base.Trousers_Scrubs" } },
            JacketSuit = { items = { "Base.JacketLong_Doctor" } },
            Hands = { chance = 50, items = { "Base.Gloves_Surgical" } },
            Shoes = { items = { "Base.Shoes_TrainerTINT" } },
        },
    },
}

-- Scalpel Master.
Professions.SCALPEL_TYPE = "Base.Scalpel"
Professions.SCALPEL_DAMAGE = 9          -- damage 0.1-0.4 becomes 0.9-3.6
Professions.SCALPEL_DURABILITY = 100    -- applied to ConditionLowerChance (1 -> 100)

-- The knowledge grant (pure). state: the player's state; professionId: the character's profession id or nil.
-- Returns true when it changed state.knowledge (the caller marks it dirty). Idempotent.
function Professions.grantKnowledge(state, professionId)
    if type(professionId) ~= "string" or not Professions.GRANTS[professionId] then
        return false
    end
    local knowledge = state.knowledge
    local changed = false
    if knowledge.professionGrant == nil then
        knowledge.professionGrant = professionId
        changed = true
    end
    for _, id in ipairs(Professions.GRANT_KNOWLEDGE) do
        if knowledge.diseases[id] ~= true then
            knowledge.diseases[id] = true
            changed = true
        end
    end
    return changed
end

return Professions
