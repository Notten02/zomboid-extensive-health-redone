-- What reading each EHR leaflet teaches (Phase 8; docs/porting/phase8/flyers-knowledge-radio.md section 1). Server/Flyers
-- looks the read item up here after vanilla's ISReadABook:complete; Knowledge/Learn applies it.
--
-- From v0.9 s/EHR_DiseaseFlyers.lua:19-44 (FLYER_ITEMS) and c/EHR_FlyerHook.lua:65-111 (the Wild Plants guide). The
-- knowledge ids are ours and equal v0.9's for every flyer we keep. The Tuberculosis, Flu and Knox flyers are deleted
-- from the mod (W1-W3, decided 2026-10-14); Knox knowledge comes only from the Kentucky Herald (Server/Knox).
--
-- Four flyers teach a self-evident condition (food poisoning, hypothermia, heat exhaustion, heat stroke): they only
-- record the id and give the XP, as in v0.9. The Blood Types flyer teaches "blood_types" (Blood/Transfusion reads it);
-- it has no handbook entry.
--
-- The recipe guides are not here: vanilla teaches their LearnedRecipes (scripts/EHR_Flyers.txt) through the read-book
-- list, and v0.9 gave no XP for them.

local Flyers = {}

Flyers.MODULE = "ExtensiveHealth"

-- item name (module ExtensiveHealth) -> knowledge id
Flyers.DISEASES = {
    DiseaseFlyer_CommonCold = "common_cold",
    DiseaseFlyer_Pneumonia = "pneumonia",
    DiseaseFlyer_FoodPoisoning = "food_poisoning",
    DiseaseFlyer_Hypothermia = "hypothermia",
    DiseaseFlyer_HeatExhaustion = "heat_exhaustion",
    DiseaseFlyer_HeatStroke = "heat_stroke",
    DiseaseFlyer_Sepsis = "sepsis",
    DiseaseFlyer_CorpseSickness = "corpse_sickness",
    DiseaseFlyer_Gastroenteritis = "gastroenteritis",
    DiseaseFlyer_Dysentery = "dysentery",
    DiseaseFlyer_Trichinosis = "trichinosis",
    DiseaseFlyer_HyperkeratoticScabies = "hyperkeratotic_scabies",
    DiseaseFlyer_ToxinPoisoning = "toxin_poisoning",
    DiseaseFlyer_CadavericAspergillosis = "cadaveric_aspergillosis",
    DiseaseFlyer_Tetanus = "tetanus",
    DiseaseFlyer_WoundInfection = "wound_infection",
    DiseaseFlyer_Cellulitis = "cellulitis",
    DiseaseFlyer_AHTR = "ahtr",
    DiseaseFlyer_BloodType = "blood_types",
}

-- The Medical Guide: Wild Medicinal Plants (knowledge.wildPlants).
Flyers.WILD_PLANTS = "MedicalWildPlants"

-- The name a learned id is spoken with ("Medical knowledge acquired: %1"). Default UI_EHR_Disease_<id>.
Flyers.NAME_KEYS = {
    blood_types = "UI_EHR_Disease_BloodTypes",
}

-- The recipe guides vanilla teaches by itself (listed for the tests that check their LearnedRecipes).
Flyers.RECIPE_GUIDES = { "EhrRecipePlantBasedAntibiotics", "EhrRecipeUltimateCraftGuide" }

function Flyers.nameKey(id)
    return Flyers.NAME_KEYS[id] or ("UI_EHR_Disease_" .. id)
end

-- What reading fullType teaches: { kind = "disease", id, name } or { kind = "wildPlants" }, or nil for any other item.
function Flyers.entry(fullType)
    if type(fullType) ~= "string" then
        return nil
    end
    local module, name = fullType:match("^([^.]+)%.(.+)$")
    if module ~= Flyers.MODULE then
        return nil
    end
    if name == Flyers.WILD_PLANTS then
        return { kind = "wildPlants" }
    end
    local id = Flyers.DISEASES[name]
    if id then
        return { kind = "disease", id = id, name = Flyers.nameKey(id) }
    end
    return nil
end

return Flyers
