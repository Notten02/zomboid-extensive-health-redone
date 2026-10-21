-- Spawn-time loot data: what happens to items as a container fills (package fill, Knox facility items) and what a
-- dead zombie may carry. Pure data for Loot/Fill; Server/Loot applies it on OnFillContainer and OnZombieDead
-- (docs/porting/phase8/loot-distribution.md sections 4-6).
--
-- Changes from v0.9 (EHR_MedicationSpawns.lua, EHR_KnoxDistribution.lua, EHR_ZombieLoot.lua):
--   * Location comes from exact room names and container types, not substrings: v0.9's "medic" matched every
--     bathroom "medicine" cabinet and "desk"/"shelf" made offices household (bug L7).
--   * Only our own multi-dose medicine is touched; vanilla pills are left alone (Q10). Knox items spawn full (L9).
--   * Kits, bags and the Medicine Storage Box filled inside a container get the fill too (Q8, L8).
--   * Knox: the 42.21 facility basements are z -13 to -17 (v0.9 expected -1 / -2, so its basement-1 list never ran
--     and Gene Therapy rolled in every basement container). Containers roll once, never again on loot respawn
--     (Q11, L10). Container types match exactly (v0.9's "bin" also matched "cabinet").
--   * Zombie loot is a weighted pick (Q9), not uniform over 83 items (L11): no box, Warming Pack, combat stimulants,
--     Knox, crafted or deleted items; the watch only rarely and Left only.

local M = "ExtensiveHealth."

local function set(list)
    local s = {}
    for _, v in ipairs(list) do
        s[v] = true
    end
    return s
end

local function prefixed(list)
    local out = {}
    for i, name in ipairs(list) do
        out[i] = M .. name
    end
    return out
end

-- Our spawnable multi-dose medicine (UseDelta below 1). The IV kit has one use; Phalanx is a Knox item and spawns
-- full; crafted items never spawn.
local fillItems = set(prefixed({
    "BronchodilatorInhaler", "AntiInflammatory", "ColdFluTablets", "AntipyreticTablets", "AntiNauseaTablets",
    "AntiDiarrheal", "MuscleRelaxants", "CoughSuppressant", "PrescriptionAntibiotics", "Buprenorphine",
    "NitricOxideBooster", "CombatStimulants", "AntiviralCapsules", "AntifungalTablets", "ActivatedCharcoal",
    "AntiparasiticPills", "OralRehydrationKit", "Antipsychotics", "DualOrexinReceptor", "CoughSyrup",
    "AntisepticCream", "TopicalPermethrin", "Furosemide", "AntibioticOintment", "BroadSpectrumAntibiotics", "Syringe",
    "SterilizedBandages", "ElectrolytePowder", "InstantIcePack", "RespiratorySupportKit",
}))

-- MedicationPackageFill 1-4: the chance a pharmacy package is full (with AllowFullPharmacyPackages), and per
-- location the fraction of doses left, { low, high } (v0.9 MS:21-70).
local profiles = {
    [1] = { pharmacyFull = 0.08, ranges = {
        pharmacy = { 0.25, 0.65 }, medical = { 0.15, 0.45 }, ambulance = { 0.10, 0.40 },
        household = { 0.02, 0.25 }, military = { 0.20, 0.50 }, default = { 0.02, 0.30 } } },
    [2] = { pharmacyFull = 0.15, ranges = {
        pharmacy = { 0.35, 0.80 }, medical = { 0.25, 0.60 }, ambulance = { 0.18, 0.55 },
        household = { 0.04, 0.35 }, military = { 0.30, 0.60 }, default = { 0.05, 0.40 } } },
    [3] = { pharmacyFull = 0.25, ranges = {
        pharmacy = { 0.45, 0.90 }, medical = { 0.35, 0.70 }, ambulance = { 0.25, 0.70 },
        household = { 0.05, 0.45 }, military = { 0.40, 0.70 }, default = { 0.10, 0.50 } } },
    [4] = { pharmacyFull = 0.35, ranges = {
        pharmacy = { 0.60, 0.95 }, medical = { 0.45, 0.70 }, ambulance = { 0.35, 0.70 },
        household = { 0.10, 0.60 }, military = { 0.50, 0.70 }, default = { 0.15, 0.60 } } },
}

-- Where a container is, from the room's distribution name (lower case). Vehicles pass their type as the room, so
-- the ambulance entries are vehicle script names (with the module stripped).
local rooms = {
    pharmacy = "pharmacy", pharmacystorage = "pharmacy",
    ambulance = "ambulance", vanambulance = "ambulance",
    armystorage = "military", armysurplus = "military", armytent = "military", oldarmy = "military",
    medical = "medical", medicaloffice = "medical", medicalstorage = "medical", oldmedical = "medical",
    hospitalroom = "medical", hospitalhallway = "medical", hospitalstorage = "medical", dentist = "medical",
    dentiststorage = "medical", waitingroom = "medical", laboratory = "medical", kennels = "medical",
    bathroom = "household", bedroom = "household", kidsbedroom = "household", hoarderbedroom = "household",
    ww_bedroom = "household", livingroom = "household", bandlivingroom = "household", ww_livingroom = "household",
    kitchen = "household", diningroom = "household", hall = "household", laundry = "household",
}

-- Container types that make a container household when its room is not one of the above (furniture in rooms the
-- table does not name, like a bedroom-style sidetable in a motel).
local householdContainers = set({ "sidetable", "dresser", "wardrobe" })

-- Kits and bags filled inside a container use their own class; anything else uses the outer container's.
local subContainers = {
    Bag_MedicalBag = "ambulance", Bag_Satchel_Medical = "ambulance",
    FirstAidKit = "household", FirstAidKit_New = "household", FirstAidKit_Camping = "household",
    FirstAidKit_Camping_New = "household", FirstAidKit_Military = "household", FirstAidKit_Pro = "household",
    FirstAidKit_NewPro = "household",
}

return {
    fillItems = fillItems,
    profiles = profiles,
    defaultProfile = 3,
    rooms = rooms,
    householdContainers = householdContainers,
    subContainers = subContainers,
    -- Zombie loot items get the household range (Q9).
    zombieLocation = "household",

    -- Knox facility (the Military Research Facility). Bounds from v0.9; depth bands from the 42.21 map (spec 6).
    knox = {
        minX = 5480, maxX = 5660, minY = 12390, maxY = 12560,
        -- z -13 to -15: barracks, storage, offices. z -16 and below: the laboratory levels.
        levels = {
            { top = -13, bottom = -15, items = {
                { item = M .. "PhalanxPills", chance = 3 },
                { item = M .. "AntibodyTestKit", chance = 4 },
                { item = M .. "ImmunoboosterShot", chance = 2 },
            } },
            { top = -16, bottom = -99, items = {
                { item = M .. "GeneTherapyKit", chance = 1 },
                { item = M .. "PhalanxPills", chance = 5 },
                { item = M .. "AntibodyTestKit", chance = 6 },
                { item = M .. "ImmunoboosterShot", chance = 4 },
            } },
        },
        containers = set({ "crate", "metal_shelves", "shelves", "counter", "desk", "filingcabinet", "locker",
            "militarycrate", "medicalcabinet", "militarylocker", "cardboardbox", "bin", "wardrobe", "dresser" }),
    },

    -- Zombie loot weights (ours, from the spec's Q9 default): OTC and dressings 4, prescription drugs and medical
    -- supplies 2, clinical 0.5, blood bags at loot rarity x 0.25, literature 1, the watch 0.25.
    zombie = {
        tiers = {
            { weight = 4, items = prefixed({
                "ColdFluTablets", "AntipyreticTablets", "CoughSyrup", "CoughSuppressant", "AntiNauseaTablets",
                "AntiDiarrheal", "AntiInflammatory", "ElectrolytePowder", "AntisepticCream", "MuscleRelaxants",
                "BronchodilatorInhaler", "NitricOxideBooster", "SterilizedBandages", "AlchoholicBandage",
                "InstantIcePack" }) },
            { weight = 2, items = prefixed({
                "PrescriptionAntibiotics", "BroadSpectrumAntibiotics", "AntiviralCapsules", "AntifungalTablets",
                "AntiparasiticPills", "AntibioticOintment", "ActivatedCharcoal", "OralRehydrationKit", "Furosemide",
                "Antipsychotics", "DualOrexinReceptor", "Buprenorphine", "TetanusAntitoxin", "TopicalPermethrin",
                "Syringe", "IVKit", "SalineBag", "EmptyBloodBag" }) },
            { weight = 0.5, items = prefixed({
                "IVAntibiotics", "IVMetronidazole", "IVAmphotericin", "IVCiprofloxacin", "IVVancomycin", "IVFluids",
                "EmergencySepsisKit", "CorticosteroidInjection", "RespiratorySupportKit", "ChelationKit",
                "AlbendazoleInjection", "TetanusImmunoglobulin", "LastChanceEpinephrine" }) },
            { weight = 1, items = prefixed({
                "DiseaseFlyer_CommonCold", "DiseaseFlyer_FoodPoisoning", "DiseaseFlyer_Hypothermia",
                "DiseaseFlyer_HeatExhaustion", "DiseaseFlyer_Pneumonia", "DiseaseFlyer_Sepsis",
                "DiseaseFlyer_CorpseSickness", "DiseaseFlyer_Gastroenteritis", "DiseaseFlyer_Dysentery",
                "DiseaseFlyer_Trichinosis", "DiseaseFlyer_HyperkeratoticScabies", "DiseaseFlyer_ToxinPoisoning",
                "DiseaseFlyer_HeatStroke", "DiseaseFlyer_CadavericAspergillosis", "DiseaseFlyer_Tetanus",
                "DiseaseFlyer_WoundInfection", "DiseaseFlyer_Cellulitis", "DiseaseFlyer_AHTR",
                "DiseaseFlyer_BloodType", "MedicalWildPlants", "EhrRecipePlantBasedAntibiotics",
                "EhrRecipeUltimateCraftGuide" }) },
            { weight = 0.25, items = prefixed({ "EHRMedicalWatch_Left" }) },
        },
        -- Blood bags: Data/Loot's rarity weights times this.
        bloodMult = 0.25,
    },
}
