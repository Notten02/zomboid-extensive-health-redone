-- How each disease is shown: its icon (common/media/textures, file names kept from the original mod, typos
-- included), the handbook category, whether it can kill, and the name and hint an unidentified case shows. Shared by
-- the EHR Monitor (UI/Monitor) and the handbook (UI/Handbook). Ids are condition ids; wound_infection is the per-part
-- infection (state.wounds), which has no condition definition.
--
--   icon      texture name without ".png"
--   category  UI_EHR_Codex_Category_<category>
--   lethal    "LETHAL RISK" in the handbook
--   unknown   suffix of UI_EHR_Unknown_<unknown> and UI_EHR_Unknown_<unknown>_Desc, shown before the disease is
--             identified
--   unknownName, unknownDesc   full keys instead of `unknown` (add-on conditions, Conditions/Registration)
--   lockedDesc  the key of a locked handbook entry's text, instead of the flyer text (add-on conditions)

local DiseaseInfo = {}

DiseaseInfo.UNKNOWN_ICON = "EHR_Disease_Unknown"

-- The handbook's order.
DiseaseInfo.ORDER = {
    "food_poisoning", "gastroenteritis", "trichinosis", "toxin_poisoning", "dysentery", "common_cold", "pneumonia",
    "hypothermia", "heat_exhaustion", "heat_stroke", "corpse_sickness", "cadaveric_aspergillosis", "wound_infection",
    "cellulitis", "sepsis", "tetanus", "hyperkeratotic_scabies", "concussion", "delirium", "insomnia",
    "painkiller_addiction", "ahtr", "knox_infection",
}

DiseaseInfo.BY_ID = {
    food_poisoning = { icon = "EHR_Disease_FoodPoisoning", category = "food" },
    gastroenteritis = { icon = "EHR_Disease_Gastroenteritis", category = "food", unknown = "Gastrointestinal" },
    trichinosis = { icon = "EHR_Disease_Trichinosis", category = "food", lethal = true, unknown = "Parasitic" },
    toxin_poisoning = { icon = "EHR_Disease_ToxinPoisoning", category = "food", lethal = true, unknown = "Toxic" },
    dysentery = { icon = "EHR_Disease_Dysentery", category = "environmental", lethal = true,
        unknown = "SevereGastrointestinal" },
    common_cold = { icon = "EHR_Disease_CommonCold", category = "environmental", unknown = "Respiratory" },
    pneumonia = { icon = "EHR_Disease_Pneumonia", category = "environmental", lethal = true,
        unknown = "SevereRespiratory" },
    hypothermia = { icon = "EHR_Disease_Hypotermia", category = "environmental", lethal = true },
    heat_exhaustion = { icon = "EHR_Disease_HeatExhaustion", category = "environmental" },
    heat_stroke = { icon = "EHR_Disease_HeatStroke", category = "environmental", lethal = true },
    corpse_sickness = { icon = "EHR_Disease_CorpseSickness", category = "corpse", unknown = "Illness" },
    cadaveric_aspergillosis = { icon = "EHR_Disease_CadavericAspergillosis", category = "corpse", lethal = true,
        unknown = "Fungal" },
    wound_infection = { icon = "EHR_Disease_Wound_Infection", category = "wound", unknown = "Wound" },
    cellulitis = { icon = "EHR_Disease_Cellulitis", category = "wound", unknown = "Skin" },
    sepsis = { icon = "EHR_Disease_Sepsis", category = "wound", lethal = true, unknown = "Systemic" },
    tetanus = { icon = "EHR_Disease_Tetanus", category = "wound", lethal = true, unknown = "Neuromuscular" },
    hyperkeratotic_scabies = { icon = "EHR_Disease_hyperkeratoticScabies", category = "infection", lethal = true,
        unknown = "Skin_Infestation" },
    concussion = { icon = "EHR_Disease_Concussion", category = "wound" },
    delirium = { icon = "EHR_Disease_Delirium", category = "mental" },
    insomnia = { icon = "EHR_Disease_Insomina", category = "mental" },
    painkiller_addiction = { icon = "EHR_Disease_PainkillerAddiction", category = "mental" },
    ahtr = { icon = "EHR_Disease_AHTR", category = "blood", lethal = true, unknown = "Transfusion" },
    knox_infection = { icon = "EHR_Disease_KnoxInfection", category = "infection", lethal = true,
        unknown = "Infection" },
}

-- Wound infection as a definition for Conditions/Knowledge (it has no entry in the condition registry).
DiseaseInfo.WOUND_INFECTION = { knowledge = "wound_infection", name = "UI_EHR_WoundInfection" }

-- The unknown name and hint keys for a condition id. The fallback is the generic "Unknown Illness".
function DiseaseInfo.unknownKeys(id)
    local info = DiseaseInfo.BY_ID[id]
    if info and info.unknownName then
        return info.unknownName, info.unknownDesc or (info.unknownName .. "_Desc")
    end
    if info and info.unknown then

        return "UI_EHR_Unknown_" .. info.unknown, "UI_EHR_Unknown_" .. info.unknown .. "_Desc"
    end
    return "UI_EHR_DiseaseUnknown", "UI_EHR_DiseaseUnknownDesc"
end

function DiseaseInfo.icon(id)
    local info = DiseaseInfo.BY_ID[id]
    return info and info.icon or DiseaseInfo.UNKNOWN_ICON
end

return DiseaseInfo
