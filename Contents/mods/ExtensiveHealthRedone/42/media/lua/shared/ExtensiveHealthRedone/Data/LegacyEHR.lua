-- What the importer needs to know about the original mod's player modData (Extensive Health Rework Evolved v0.9,
-- internal version 2.8.1). The full key inventory and formats are in docs/porting/old-moddata-keys.md.

return {
    MOD_ID = "ExtensiveHealthReworkEvolved",

    -- Every player key of the original starts with this. Any such key means "has old data"; all are removed after
    -- the import. The original's own 14-key check missed knowledge-only characters.
    KEY_PREFIX = "EHR_",

    -- Knowledge ids the original could store (EHR_DiseaseFlyers.lua:45-71), less tuberculosis and flu: both diseases
    -- and their flyers are gone (W1, W2), so that knowledge is reported as unknown and dropped.
    KNOWLEDGE_IDS = {
        ahtr = true, blood_types = true, common_cold = true, concussion = true, delirium = true, insomnia = true,
        pneumonia = true, food_poisoning = true, gastroenteritis = true, dysentery = true,
        trichinosis = true, hyperkeratotic_scabies = true, toxin_poisoning = true, hypothermia = true,
        heat_exhaustion = true, heat_stroke = true, sepsis = true, corpse_sickness = true,
        cadaveric_aspergillosis = true, tetanus = true, wound_infection = true,
        cellulitis = true, knox_infection = true,
    },

    -- The original's id normaliser compacted ids (no spaces, _ - ( ), lower case) and looked them up here
    -- (EHR_DiseaseFlyers.lua:82-184). Applied to every imported knowledge id.
    COMPACT_ALIASES = {
        ahtr = "ahtr", acutehemolytictransfusionreaction = "ahtr",
        bloodtype = "blood_types", bloodtypes = "blood_types",
        commoncold = "common_cold", cold = "common_cold",
        concussion = "concussion", delirium = "delirium", madness = "delirium", insomnia = "insomnia",
        pneumonia = "pneumonia",
        foodpoisoning = "food_poisoning", gastroenteritis = "gastroenteritis", dysentery = "dysentery",
        trichinosis = "trichinosis", hyperkeratoticscabies = "hyperkeratotic_scabies", scabies = "hyperkeratotic_scabies",
        toxinpoisoning = "toxin_poisoning", hypothermia = "hypothermia",
        heatexhaustion = "heat_exhaustion", heatstroke = "heat_stroke", sepsis = "sepsis",
        corpsedisease = "corpse_sickness", corpsesickness = "corpse_sickness", corpseexposureillness = "corpse_sickness",
        cadavericaspergillosis = "cadaveric_aspergillosis",
        tetanus = "tetanus", woundinfection = "wound_infection", cellulitis = "cellulitis",
        knoxinfection = "knox_infection",
    },

    KNOX_KNOWLEDGE_ID = "knox_infection",
    KNOX_HERALD_SOURCE = "kentucky_herald_july16",
    PROFESSION_GRANTS = { ehrdoctor = true, ehrsurgeon = true },
}
