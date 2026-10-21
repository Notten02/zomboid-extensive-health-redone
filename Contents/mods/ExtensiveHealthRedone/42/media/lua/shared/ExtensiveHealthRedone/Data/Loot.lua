-- World loot: which EHR items go into which vanilla 42.21 distribution list, and at what weight. Pure data; the
-- builder (Loot/Build) turns it into one entry per item per list, the writer (Loot/Apply) puts it into the game's
-- tables, and Server/Loot runs both at OnPreDistributionMerge (docs/porting/phase8/loot-distribution.md).
--
-- Numbers are v0.9's (EHR_Distributions.lua, EHR_MedicineStorageBoxDistribution.lua) unless marked "ours". Changes
-- from v0.9 (maintainer decisions 2026-10-14, spec section 13 defaults):
--   * Tuberculosis items are gone (W1): no TBAntibiotics, no tuberculosis flyer. Flu and Knox flyers (W2, W3) are
--     deleted too. Crafted-only items never spawn.
--   * One entry per item per list: v0.9's accidental doubles (bandages on pharmacy shelves, the clinic's
--     Furosemide/psych drugs/Permethrin/saline, the army saline alias) are summed into one weight (bug L3).
--     Overlapping pools (a list's own pool plus the clinical pool, say) are summed by the builder.
--   * No aliases and no dead lists: MedicalStorageBlood's block is folded into MedicalStorageOutfit (pool
--     hospitalBlood, replacing its hand-written blood subset); AmbulanceMedical's block is dropped (the ambulance
--     trunk carries all of it); ArmySurplusMedical's entries are written into ArmyStorageMedical directly (L1, L2).
--   * Plain Epinephrine (W6) in hospital and ambulance loot, at the spec's suggested weights (ours).
--   * Police storage rooms, evidence lockers and SWAT truck beds get the military high-value pool x 0.3 (maintainer).
--   * Clinical drugs stay in clinics, offices, hospital rooms, medical storage, the army bunker and story safehouses;
--     household clinical leftovers and FridgeMedical (which also fills school-lab fridges) are dropped.
--   * StoreShelfMedical (also gas-station and convenience-store shelves) loses Antipsychotics, DORA and
--     Buprenorphine; pharmacies still get them from MedicalClinicDrugs (pharmacy counter and storage).
--   * MedicationLootMultiplier scales every medication and medical supply, blood bags, saline, empty bags and the
--     Medicine Storage Box (spawn and contents) included. Flyers and recipe guides are unscaled; watches follow
--     MedicalWatchLootMultiplier (L4).
--
-- Shapes:
--   pools[name]   = { scale = "med" | "lit", items = { [item] = weight } }   ("lit": unscaled literature)
--   targets[i]    = { kind = "proc" | "bag" | "vehicle" | "postbox", list = name, minRolls = n?,
--                     add = { { pool = name, mult = n?, gate = option?, front = bool? }, ... } }
--     proc     ProceduralDistributions.list[list]
--     bag      SuburbsDistributions[list] (or SuburbsDistributions.all[list]): first-aid kits and bags
--     vehicle  VehicleDistributions[list]
--     postbox  SuburbsDistributions.all.postbox
--     gate     a boolean sandbox option that must be on for this contribution (HouseholdPrescriptionLoot)
--     front    the contribution's items go first in the list (medical bags: trauma gear wins limited capacity)
--     minRolls the list's rolls are raised to this, only when it got entries (never at multiplier 0)
--   roomProcs     vanilla procedural lists added to raw room containers (spec 1.3; adds vanilla loot there too)
--   box           the Medicine Storage Box's own contents, SuburbsDistributions.MedicineStorageBox (spec 7)
--   watch         the vanilla item whose entries the medical watch mirrors (spec 8; Left only, vanilla has no Right)
-- Item names without a module are ExtensiveHealth items.

-- Blood bag loot rarity (v0.9 DI:405-414): O+ most common, AB- rarest. Not the character blood-type weights (Q13).
local bloodRarity = {
    BloodBagOPos = 8, BloodBagAPos = 7, BloodBagBPos = 3, BloodBagONeg = 2,
    BloodBagANeg = 2, BloodBagBNeg = 1, BloodBagABPos = 1, BloodBagABNeg = 0.5,
}

local function withBlood(items, mult)
    for item, weight in pairs(bloodRarity) do
        items[item] = (items[item] or 0) + weight * mult
    end
    return items
end

local function med(items)
    return { scale = "med", items = items }
end

local pools = {
    -- Pharmacy and general-store medical shelves (StoreShelfMedical). Bandages and ice packs: v0.9's two adds summed.
    pharmacyShelf = med({
        ColdFluTablets = 3.5, AntipyreticTablets = 3.5, CoughSyrup = 2.5, CoughSuppressant = 2, AntiNauseaTablets = 2.5,
        AntiDiarrheal = 2.5, AntiInflammatory = 3.5, ElectrolytePowder = 2.5, AntisepticCream = 3.5,
        MuscleRelaxants = 1.2, BronchodilatorInhaler = 1, SterilizedBandages = 6, AlchoholicBandage = 3,
        InstantIcePack = 3, TopicalPermethrin = 1, SalineBag = 0.3,
    }),
    -- Supermarket toiletries (GigamartToiletries): the guide's lighter OTC list.
    supermarket = med({
        ColdFluTablets = 1.5, AntipyreticTablets = 1.5, CoughSyrup = 1, CoughSuppressant = 0.8, AntiNauseaTablets = 1,
        AntiDiarrheal = 1, AntiInflammatory = 1.5, ElectrolytePowder = 1, AntisepticCream = 1.5,
        SterilizedBandages = 1, InstantIcePack = 0.5, TopicalPermethrin = 0.5,
    }),
    -- Medical cabinets in police SWAT rooms, security and waiting rooms (MedicalCabinet): OTC.
    cabinetOtc = med({
        ColdFluTablets = 3, AntipyreticTablets = 3, CoughSyrup = 2, AntiNauseaTablets = 2, AntiDiarrheal = 2,
        AntiInflammatory = 3, ElectrolytePowder = 2, AntisepticCream = 3, SterilizedBandages = 2, AlchoholicBandage = 1,
        InstantIcePack = 1, TopicalPermethrin = 1,
    }),
    -- Clinics and pharmacy counters (MedicalClinicDrugs). v0.9's doubled adds summed: Furosemide 1 + 3,
    -- Antipsychotics 2 + 4, DORA 1.5 + 4, Buprenorphine 1.5 + 4, Permethrin 2 + 4, Saline 3 + 4. Rare blood bags.
    clinic = med(withBlood({
        PrescriptionAntibiotics = 10, BroadSpectrumAntibiotics = 8, AntiviralCapsules = 5, AntifungalTablets = 3,
        OralRehydrationKit = 5, AntibioticOintment = 6, InstantIcePack = 5, Syringe = 8, Furosemide = 4,
        Antipsychotics = 6, DualOrexinReceptor = 5.5, Buprenorphine = 5.5, NitricOxideBooster = 2,
        TopicalPermethrin = 6, SterilizedBandages = 6, AlchoholicBandage = 4, SalineBag = 7, IVFluids = 2,
        EmptyBloodBag = 4, WarmingPack = 0.2,
    }, 0.3)),
    -- Medical and hospital storage (MedicalStorageDrugs). TB drugs dropped (W1). Epinephrine 1.0 (W6, ours).
    storage = med({
        ColdFluTablets = 7, AntipyreticTablets = 6, CoughSyrup = 6, ElectrolytePowder = 6, BronchodilatorInhaler = 4,
        AntiNauseaTablets = 6, AntiInflammatory = 7, MuscleRelaxants = 5, NitricOxideBooster = 3, Syringe = 10,
        SterilizedBandages = 8, AlchoholicBandage = 5, InstantIcePack = 5, PrescriptionAntibiotics = 10,
        AntiviralCapsules = 5, ActivatedCharcoal = 5, AntiparasiticPills = 2, Furosemide = 4, Antipsychotics = 3,
        DualOrexinReceptor = 3, Buprenorphine = 3, TetanusAntitoxin = 3, AntibioticOintment = 5,
        BroadSpectrumAntibiotics = 8, IVKit = 5, IVFluids = 2, SalineBag = 6, TopicalPermethrin = 3,
        BloodBagONeg = 1, BloodBagOPos = 2, BloodBagAPos = 2, BloodBagBPos = 1, WarmingPack = 0.35, Epinephrine = 1.0,
    }),
    -- Large hospital storage (MedicalStorageOutfit): the best civilian clinical source. Epinephrine 2.4 (W6, ours).
    hospital = med({
        IVAntibiotics = 3.6, IVMetronidazole = 2.4, IVAmphotericin = 2.4, IVCiprofloxacin = 2.4, IVVancomycin = 2.4,
        IVFluids = 4.8, EmergencySepsisKit = 2.4, CorticosteroidInjection = 2.4, RespiratorySupportKit = 2.4,
        ChelationKit = 2.4, AlbendazoleInjection = 2.4, LastChanceEpinephrine = 1.2, TetanusImmunoglobulin = 2.4,
        Furosemide = 3, Antipsychotics = 2, DualOrexinReceptor = 2, Buprenorphine = 2, IVKit = 7, Syringe = 10,
        SalineBag = 7, SterilizedBandages = 8, AlchoholicBandage = 5, InstantIcePack = 4, Epinephrine = 2.4,
    }),
    -- v0.9's dead MedicalStorageBlood block, folded into large hospital storage (Q5).
    hospitalBlood = med(withBlood({ SalineBag = 6, IVFluids = 5, EmptyBloodBag = 8 }, 1)),
    -- Prescription leftovers in offices, hospital rooms and medical cabinets (v0.9 secondary pool, no TB).
    secondary = med({
        PrescriptionAntibiotics = 4, AntiviralCapsules = 1.5, AntifungalTablets = 1, AntiparasiticPills = 0.7,
        AntibioticOintment = 2, BroadSpectrumAntibiotics = 3, OralRehydrationKit = 1.5, Furosemide = 1,
        Antipsychotics = 0.8, DualOrexinReceptor = 0.8, Buprenorphine = 0.8, TetanusAntitoxin = 0.7,
        TopicalPermethrin = 1,
    }),
    -- Clinical drugs and IV gear (v0.9 clinical pool).
    clinical = med({
        IVAntibiotics = 2.4, IVMetronidazole = 1.5, IVAmphotericin = 0.8, IVCiprofloxacin = 1.5, IVVancomycin = 1.2,
        IVFluids = 3, EmergencySepsisKit = 1.2, CorticosteroidInjection = 1.5, RespiratorySupportKit = 1.5,
        ChelationKit = 0.8, AlbendazoleInjection = 0.8, TetanusImmunoglobulin = 1.2, LastChanceEpinephrine = 0.7,
        IVKit = 3, Syringe = 4, SalineBag = 3,
    }),
    -- The guide's military / police high-value list (v0.9 ArmyStorageMedical plus the ArmySurplusMedical alias,
    -- saline 5 + 7 summed). Combat stimulants are separate (combat).
    military = med(withBlood({
        SalineBag = 12, EmptyBloodBag = 6, IVAntibiotics = 5, IVCiprofloxacin = 3, IVFluids = 3,
        EmergencySepsisKit = 2, CorticosteroidInjection = 2, RespiratorySupportKit = 2, TetanusImmunoglobulin = 2,
        IVKit = 6, Syringe = 8, BroadSpectrumAntibiotics = 6, Furosemide = 2, SterilizedBandages = 6,
        AlchoholicBandage = 4, InstantIcePack = 3,
    }, 0.7)),
    combat = med({ CombatStimulants = 1 }),
    -- Plain Epinephrine (W6) for hospital rooms; the other lists carry it in their own pools.
    epinephrine = med({ Epinephrine = 1 }),
    warming = med({ WarmingPack = 1 }),
    box = med({ MedicineStorageBox = 1 }),
    -- First-aid kits: basic field medicine, and an advanced pool for the newer and military kits.
    kitBasic = med({
        AntisepticCream = 7, AntiInflammatory = 5, AntipyreticTablets = 4, ElectrolytePowder = 2,
        NitricOxideBooster = 1, Syringe = 1, SterilizedBandages = 7, AlchoholicBandage = 3, InstantIcePack = 3,
        TopicalPermethrin = 1,
    }),
    kitAdvanced = med({
        AntibioticOintment = 2, OralRehydrationKit = 1.5, BronchodilatorInhaler = 1.5, PrescriptionAntibiotics = 0.8,
        IVKit = 0.5, CorticosteroidInjection = 0.3, RespiratorySupportKit = 0.3,
    }),
    -- Ambulance glove box, seats and trunk. Epinephrine 0.5 / 1 / 4 (W6, ours); the box (v0.9 BX) included.
    ambulanceGlove = med({
        SterilizedBandages = 4, AlchoholicBandage = 2, AntisepticCream = 3, AntiInflammatory = 3,
        AntipyreticTablets = 3, AntiNauseaTablets = 2.5, ElectrolytePowder = 2, BronchodilatorInhaler = 1.5,
        InstantIcePack = 1.5, AntibioticOintment = 1.5, ActivatedCharcoal = 1, LastChanceEpinephrine = 0.35,
        Epinephrine = 0.5, MedicineStorageBox = 1,
    }),
    ambulanceSeat = med({
        SterilizedBandages = 5, AlchoholicBandage = 2.5, AntisepticCream = 4, AntiInflammatory = 3,
        AntipyreticTablets = 3, AntiNauseaTablets = 2.5, ElectrolytePowder = 2.5, BronchodilatorInhaler = 2,
        InstantIcePack = 2, AntibioticOintment = 2, ActivatedCharcoal = 1.2, PrescriptionAntibiotics = 3,
        BroadSpectrumAntibiotics = 2, LastChanceEpinephrine = 0.5, Epinephrine = 1, MedicineStorageBox = 1.5,
    }),
    ambulanceTrunk = med(withBlood({
        SterilizedBandages = 14, AlchoholicBandage = 9, AntisepticCream = 10, AntiInflammatory = 8,
        AntipyreticTablets = 8, AntiNauseaTablets = 7, AntiDiarrheal = 5, ElectrolytePowder = 8,
        BronchodilatorInhaler = 5, CoughSyrup = 4, CoughSuppressant = 4, InstantIcePack = 8, AntibioticOintment = 6,
        ActivatedCharcoal = 4, OralRehydrationKit = 4, PrescriptionAntibiotics = 8, BroadSpectrumAntibiotics = 8,
        IVKit = 18, Syringe = 22, SalineBag = 10, IVFluids = 12, Furosemide = 4, RespiratorySupportKit = 5,
        CorticosteroidInjection = 5, EmergencySepsisKit = 4, LastChanceEpinephrine = 3, IVCiprofloxacin = 4,
        IVAntibiotics = 4, IVMetronidazole = 3, IVVancomycin = 3, TetanusImmunoglobulin = 3, ChelationKit = 2,
        AlbendazoleInjection = 1.5, IVAmphotericin = 1.5, EmptyBloodBag = 22, Epinephrine = 4,
        MedicineStorageBox = 7,
    }, 0.75)),
    -- Medical bags: a basic and prescription mix, plus the front-inserted trauma gear. Epinephrine 1.5 (W6, ours).
    medicalBag = med({
        SterilizedBandages = 18, AlchoholicBandage = 9, AntisepticCream = 14, AntiInflammatory = 10,
        AntipyreticTablets = 10, AntiNauseaTablets = 8, AntiDiarrheal = 7, ElectrolytePowder = 8,
        BronchodilatorInhaler = 5, InstantIcePack = 7, AntibioticOintment = 6, ActivatedCharcoal = 4,
        OralRehydrationKit = 3, AntiviralCapsules = 1.5, AntifungalTablets = 1, AntiparasiticPills = 0.8,
    }),
    trauma = med(withBlood({
        IVKit = 18, Syringe = 24, SalineBag = 10, IVFluids = 8, EmptyBloodBag = 18, RespiratorySupportKit = 3,
        CorticosteroidInjection = 3, LastChanceEpinephrine = 1.2, EmergencySepsisKit = 2.5,
        PrescriptionAntibiotics = 8, BroadSpectrumAntibiotics = 6, IVCiprofloxacin = 2, IVAntibiotics = 2,
        IVMetronidazole = 1.5, IVVancomycin = 1.5, TetanusImmunoglobulin = 1.5, ChelationKit = 0.7,
        AlbendazoleInjection = 0.7, IVAmphotericin = 0.5, Epinephrine = 1.5,
    }, 0.35)),
    -- Houses (weights are multiplied per container below). Household clinical leftovers are dropped (Q3).
    homeCommon = med({
        ColdFluTablets = 0.3, AntipyreticTablets = 0.3, CoughSyrup = 0.2, CoughSuppressant = 0.15,
        AntiNauseaTablets = 0.2, AntiDiarrheal = 0.2, AntiInflammatory = 0.3, AntisepticCream = 0.2,
        MuscleRelaxants = 0.1, ElectrolytePowder = 0.15, BronchodilatorInhaler = 0.08, NitricOxideBooster = 0.1,
        SterilizedBandages = 0.15, InstantIcePack = 0.12,
    }),
    homeMedicine = med({
        ColdFluTablets = 4, AntipyreticTablets = 4, CoughSyrup = 3, AntiNauseaTablets = 3, AntiDiarrheal = 3,
        AntisepticCream = 4, AntiInflammatory = 3, NitricOxideBooster = 1, SterilizedBandages = 2,
        AlchoholicBandage = 1, InstantIcePack = 1, TopicalPermethrin = 1,
    }),
    homeRx = med({
        PrescriptionAntibiotics = 0.6, AntibioticOintment = 0.15, BroadSpectrumAntibiotics = 0.25,
        AntiviralCapsules = 0.05, AntifungalTablets = 0.04, AntiparasiticPills = 0.09, ActivatedCharcoal = 0.1,
        OralRehydrationKit = 0.08, Furosemide = 0.04, Antipsychotics = 0.04, DualOrexinReceptor = 0.04,
        Buprenorphine = 0.04, TopicalPermethrin = 0.06,
    }),
    homeMedicineRx = med({
        PrescriptionAntibiotics = 0.6, BroadSpectrumAntibiotics = 0.3, Antipsychotics = 1, DualOrexinReceptor = 0.8,
        Buprenorphine = 0.8,
    }),
    -- Disease flyers (the 19 remaining) and the Wild Plants guide. Unscaled.
    flyers = {
        scale = "lit",
        items = {
            DiseaseFlyer_CommonCold = 4, DiseaseFlyer_FoodPoisoning = 3, DiseaseFlyer_Hypothermia = 2,
            DiseaseFlyer_HeatExhaustion = 2, DiseaseFlyer_Pneumonia = 1.5, DiseaseFlyer_Sepsis = 0.8,
            DiseaseFlyer_CorpseSickness = 1.5, DiseaseFlyer_Gastroenteritis = 2, DiseaseFlyer_Dysentery = 1.2,
            DiseaseFlyer_Trichinosis = 1.2, DiseaseFlyer_HyperkeratoticScabies = 0.8, DiseaseFlyer_ToxinPoisoning = 1,
            DiseaseFlyer_HeatStroke = 1, DiseaseFlyer_CadavericAspergillosis = 0.8, DiseaseFlyer_Tetanus = 0.8,
            DiseaseFlyer_WoundInfection = 2, DiseaseFlyer_Cellulitis = 1.2, DiseaseFlyer_AHTR = 0.5,
            DiseaseFlyer_BloodType = 1.5, MedicalWildPlants = 1.2,
        },
    },
    -- Recipe guides: v0.9 gave each list its own pair of weights, so each list has its own small pool.
    recipesStorage = { scale = "lit", items = {
        EhrRecipePlantBasedAntibiotics = 1.2, EhrRecipeUltimateCraftGuide = 0.525 } },
    recipesClinic = { scale = "lit", items = {
        EhrRecipePlantBasedAntibiotics = 0.9, EhrRecipeUltimateCraftGuide = 0.375 } },
    recipesCabinet = { scale = "lit", items = {
        EhrRecipePlantBasedAntibiotics = 0.375, EhrRecipeUltimateCraftGuide = 0.12 } },
    recipesShelf = { scale = "lit", items = {
        EhrRecipePlantBasedAntibiotics = 0.225, EhrRecipeUltimateCraftGuide = 0.075 } },
    recipesMagazine = { scale = "lit", items = {
        EhrRecipePlantBasedAntibiotics = 0.6, EhrRecipeUltimateCraftGuide = 0.27 } },
}

local RX = "HouseholdPrescriptionLoot"

local targets = {
    -- Pharmacies, stores, supermarkets.
    { kind = "proc", list = "StoreShelfMedical", add = {
        { pool = "pharmacyShelf" }, { pool = "flyers", mult = 0.15 }, { pool = "recipesShelf" } } },
    { kind = "proc", list = "GigamartToiletries", add = { { pool = "supermarket" } } },
    -- Clinics, offices, hospital rooms, medical cabinets.
    { kind = "proc", list = "MedicalClinicDrugs", add = {
        { pool = "clinic" }, { pool = "clinical", mult = 0.8 }, { pool = "box", mult = 16 },
        { pool = "flyers", mult = 0.7 }, { pool = "recipesClinic" } } },
    { kind = "proc", list = "MedicalClinicTools", add = {
        { pool = "clinical", mult = 0.35 }, { pool = "box", mult = 12 } } },
    { kind = "proc", list = "MedicalCabinet", add = {
        { pool = "cabinetOtc" }, { pool = "secondary", mult = 0.7 }, { pool = "box", mult = 12 },
        { pool = "flyers", mult = 0.4 }, { pool = "recipesCabinet" } } },
    { kind = "proc", list = "MedicalOfficeCounter", add = {
        { pool = "secondary", mult = 0.9 }, { pool = "clinical", mult = 0.5 }, { pool = "box", mult = 12 } } },
    { kind = "proc", list = "MedicalOfficeDesk", add = {
        { pool = "secondary", mult = 0.45 }, { pool = "clinical", mult = 0.15 }, { pool = "box", mult = 7 } } },
    { kind = "proc", list = "HospitalRoomCounter", add = {
        { pool = "secondary", mult = 1.0 }, { pool = "clinical", mult = 0.8 }, { pool = "box", mult = 12 } } },
    { kind = "proc", list = "HospitalRoomShelves", add = {
        { pool = "secondary", mult = 1.2 }, { pool = "clinical", mult = 1.5 }, { pool = "box", mult = 16 },
        { pool = "epinephrine", mult = 1.0 } } },
    -- Medical and hospital storage.
    { kind = "proc", list = "MedicalStorageDrugs", add = {
        { pool = "storage" }, { pool = "clinical", mult = 1.5 }, { pool = "box", mult = 20 },
        { pool = "flyers", mult = 1 }, { pool = "recipesStorage" } } },
    { kind = "proc", list = "MedicalStorageOutfit", add = {
        { pool = "hospital" }, { pool = "hospitalBlood" }, { pool = "box", mult = 14 } } },
    { kind = "proc", list = "MedicalStorageTools", add = { { pool = "warming", mult = 0.4 } } },
    -- Military.
    { kind = "proc", list = "ArmyStorageMedical", add = { { pool = "military" }, { pool = "combat", mult = 3 } } },
    { kind = "proc", list = "ArmyStorageOutfit", add = { { pool = "combat", mult = 2 } } },
    { kind = "proc", list = "ArmyStorageGuns", add = { { pool = "combat", mult = 1.5 } } },
    { kind = "proc", list = "ArmyStorageAmmunition", add = { { pool = "combat", mult = 1.5 } } },
    { kind = "proc", list = "ArmyBunkerMedical", add = {
        { pool = "clinical", mult = 0.8 }, { pool = "box", mult = 12 } } },
    -- Story safehouses (survivor stashes) keep v0.9's small clinical weights.
    { kind = "proc", list = "SafehouseMedical", add = { { pool = "clinical", mult = 0.6 } } },
    { kind = "proc", list = "SafehouseMedical_Mid", add = { { pool = "clinical", mult = 0.3 } } },
    { kind = "proc", list = "SafehouseMedical_Late", add = { { pool = "clinical", mult = 0.12 } } },
    -- Gun stores and police: combat stimulants; police storage and evidence also the military pool x 0.3.
    { kind = "proc", list = "GunStoreAccessories", add = { { pool = "combat", mult = 1.2 } } },
    { kind = "proc", list = "GunStoreCases", add = { { pool = "combat", mult = 1.0 } } },
    { kind = "proc", list = "GunStoreBodyArmor", add = { { pool = "combat", mult = 0.9 } } },
    { kind = "proc", list = "GunStoreAmmunition", add = { { pool = "combat", mult = 0.7 } } },
    { kind = "proc", list = "GunStoreKnives", add = { { pool = "combat", mult = 0.5 } } },
    { kind = "proc", list = "PoliceStorageGuns", add = {
        { pool = "military", mult = 0.3 }, { pool = "combat", mult = 0.8 } } },
    { kind = "proc", list = "PoliceEvidence", add = {
        { pool = "military", mult = 0.3 }, { pool = "combat", mult = 0.6 } } },
    { kind = "proc", list = "PoliceCaptainCabinet", add = { { pool = "combat", mult = 0.4 } } },
    { kind = "proc", list = "PoliceDesk", add = { { pool = "combat", mult = 0.3 } } },
    { kind = "bag", list = "Bag_Police", add = { { pool = "combat", mult = 0.6 } } },
    { kind = "vehicle", list = "PoliceGloveBox", add = { { pool = "combat", mult = 0.25 } } },
    { kind = "vehicle", list = "PoliceSeatFront", add = { { pool = "combat", mult = 0.25 } } },
    { kind = "vehicle", list = "PoliceTruckBed", add = { { pool = "combat", mult = 0.4 } } },
    { kind = "vehicle", list = "PoliceSWATGloveBox", add = { { pool = "combat", mult = 0.8 } } },
    { kind = "vehicle", list = "PoliceSWATSeatFront", add = { { pool = "combat", mult = 0.8 } } },
    { kind = "vehicle", list = "PoliceSWATTruckBed", add = {
        { pool = "military", mult = 0.3 }, { pool = "combat", mult = 1.2 } } },
    -- Warming packs: garages and crates, rarely closets, laundries and medical buildings.
    { kind = "proc", list = "GarageTools", add = { { pool = "warming", mult = 2.2 } } },
    { kind = "proc", list = "GarageCarpentry", add = { { pool = "warming", mult = 1.4 } } },
    { kind = "proc", list = "GarageMechanics", add = { { pool = "warming", mult = 1.2 } } },
    { kind = "proc", list = "GarageMetalwork", add = { { pool = "warming", mult = 1.0 } } },
    { kind = "proc", list = "CrateCamping", add = { { pool = "warming", mult = 2.4 } } },
    { kind = "proc", list = "CrateHumanitarian", add = { { pool = "warming", mult = 1.5 } } },
    { kind = "proc", list = "CrateTools", add = { { pool = "warming", mult = 1.2 } } },
    { kind = "proc", list = "CrateRandomJunk", add = { { pool = "warming", mult = 0.6 } } },
    { kind = "proc", list = "ClosetShelfGeneric", add = { { pool = "warming", mult = 0.45 } } },
    { kind = "proc", list = "LaundryCleaning", add = { { pool = "warming", mult = 0.35 } } },
    -- Literature: magazine racks and medical book lists, rarely mailboxes (about one leaflet per 35-40).
    { kind = "proc", list = "MagazineRackMixed", add = {
        { pool = "flyers", mult = 0.12 }, { pool = "recipesMagazine" } } },
    { kind = "proc", list = "MedicalOfficeBooks", add = { { pool = "flyers", mult = 0.25 } } },
    { kind = "proc", list = "HospitalMagazineRack", add = { { pool = "flyers", mult = 0.20 } } },
    { kind = "proc", list = "BookstoreMedical", add = { { pool = "flyers", mult = 0.12 } } },
    { kind = "proc", list = "LibraryMedical", add = { { pool = "flyers", mult = 0.10 } } },
    { kind = "proc", list = "UniversityLibraryMedical", add = { { pool = "flyers", mult = 0.15 } } },
    { kind = "proc", list = "UniversityDesk_Medical", add = { { pool = "flyers", mult = 0.08 } } },
    { kind = "postbox", list = "postbox", add = { { pool = "flyers", mult = 0.04 } } },
    -- First-aid kits (kit roll counts stay vanilla).
    { kind = "bag", list = "FirstAidKit", add = { { pool = "kitBasic", mult = 0.65 } } },
    { kind = "bag", list = "FirstAidKit_New", add = {
        { pool = "kitBasic", mult = 1.0 }, { pool = "kitAdvanced", mult = 0.25 } } },
    { kind = "bag", list = "FirstAidKit_Camping", add = { { pool = "kitBasic", mult = 0.65 } } },
    { kind = "bag", list = "FirstAidKit_Camping_New", add = { { pool = "kitBasic", mult = 0.85 } } },
    { kind = "bag", list = "FirstAidKit_Military", add = {
        { pool = "kitBasic", mult = 1.0 }, { pool = "kitAdvanced", mult = 1.0 } } },
    { kind = "bag", list = "FirstAidKit_Pro", add = {
        { pool = "kitBasic", mult = 0.9 }, { pool = "kitAdvanced", mult = 0.8 } } },
    { kind = "bag", list = "FirstAidKit_NewPro", add = {
        { pool = "kitBasic", mult = 1.1 }, { pool = "kitAdvanced", mult = 1.0 } } },
    -- Medical bags: trauma gear first; rolls raised to 4 / 3 (vanilla 2 / 2).
    { kind = "bag", list = "Bag_MedicalBag", minRolls = 4, add = {
        { pool = "trauma", front = true }, { pool = "medicalBag" } } },
    { kind = "bag", list = "Bag_Satchel_Medical", minRolls = 3, add = {
        { pool = "trauma", mult = 0.75, front = true }, { pool = "medicalBag", mult = 0.75 } } },
    -- Ambulances: rolls raised to 2 / 2 / 6 (vanilla 1 / 1 / 4).
    { kind = "vehicle", list = "AmbulanceGloveBox", minRolls = 2, add = { { pool = "ambulanceGlove" } } },
    { kind = "vehicle", list = "AmbulanceSeatFront", minRolls = 2, add = { { pool = "ambulanceSeat" } } },
    { kind = "vehicle", list = "AmbulanceTruckBed", minRolls = 6, add = { { pool = "ambulanceTrunk" } } },
}

-- Houses: common OTC everywhere, bathroom medicine in bathrooms (a little in bedrooms), prescription leftovers only
-- with HouseholdPrescriptionLoot. The box spawns in bathrooms with that option too.
local function house(list, common, medicine, box)
    local add = {}
    if common then
        add[#add + 1] = { pool = "homeCommon", mult = common }
        add[#add + 1] = { pool = "homeRx", mult = common, gate = RX }
    end
    if medicine then
        add[#add + 1] = { pool = "homeMedicine", mult = medicine }
        add[#add + 1] = { pool = "homeMedicineRx", mult = medicine, gate = RX }
    end
    if box then
        add[#add + 1] = { pool = "box", mult = box, gate = RX }
    end
    targets[#targets + 1] = { kind = "proc", list = list, add = add }
end

for _, suffix in ipairs({ "", "Classy", "Redneck" }) do
    house("BedroomSidetable" .. suffix, 1.5, 0.2)
    house("BedroomDresser" .. suffix, 3.0, 0.2)
    house("LivingRoomShelf" .. suffix, 1.5)
end
house("DeskGeneric", 1.5)
house("BathroomCabinet", nil, 0.65, 0.08)
house("BathroomCounter", nil, 0.30, 0.03)
house("BathroomShelf", nil, 0.30, 0.03)

return {
    MODULE = "ExtensiveHealth",
    bloodRarity = bloodRarity,
    pools = pools,
    targets = targets,
    -- Raw medical room containers get vanilla's medical procedural lists (v0.9 DI:390-398, kept per Q15). A
    -- container that already has its own non-empty item list is left alone.
    roomProcs = {
        { room = "medical", container = "medicine", proc = "MedicalClinicDrugs", min = 0, max = 99, weight = 100 },
        { room = "medical", container = "medicine", proc = "MedicalClinicTools", min = 0, max = 1, weight = 25 },
        { room = "medical", container = "sidetable", proc = "MedicalClinicDrugs", min = 0, max = 2, weight = 35 },
        { room = "medicalstorage", container = "medicine", proc = "MedicalStorageDrugs",
          min = 0, max = 99, weight = 100 },
        { room = "medicalstorage", container = "medicine", proc = "MedicalClinicTools", min = 0, max = 2, weight = 40 },
        { room = "medicalstorage", container = "sidetable", proc = "MedicalStorageDrugs",
          min = 0, max = 2, weight = 80 },
        { room = "medicalstorage", container = "sidetable", proc = "MedicalClinicDrugs",
          min = 0, max = 2, weight = 45 },
        { room = "oldmedical", container = "medicine", proc = "MedicalStorageDrugs", min = 0, max = 2, weight = 45 },
        { room = "oldmedical", container = "medicine", proc = "MedicalClinicTools", min = 0, max = 1, weight = 35 },
    },
    -- The Medicine Storage Box's contents, keyed by its item type: three prescription rolls and one clinical roll
    -- (vanilla's junk pool, which ItemPicker always processes; v0.9 BX:130-142). Scaled by the multiplier (Q6).
    box = {
        type = "MedicineStorageBox",
        rolls = 3,
        junkRolls = 1,
        items = {
            PrescriptionAntibiotics = 16, BroadSpectrumAntibiotics = 12, AntibioticOintment = 10,
            AntiviralCapsules = 8, ActivatedCharcoal = 7, AntifungalTablets = 6, OralRehydrationKit = 6,
            TopicalPermethrin = 5, AntiparasiticPills = 4, Furosemide = 4, Antipsychotics = 4, DualOrexinReceptor = 4,
            Buprenorphine = 4, TetanusAntitoxin = 3,
        },
        junk = {
            IVFluids = 8, IVAntibiotics = 6, CorticosteroidInjection = 5, RespiratorySupportKit = 4,
            IVCiprofloxacin = 3, IVMetronidazole = 3, IVVancomycin = 2.5, EmergencySepsisKit = 2,
            TetanusImmunoglobulin = 2, IVAmphotericin = 1.5, ChelationKit = 1.5, AlbendazoleInjection = 1.5,
            LastChanceEpinephrine = 1,
        },
    },
    -- The medical watch spawns wherever this vanilla watch does, at its weight x MedicalWatchLootMultiplier (spec 8).
    watch = { source = "Base.WristWatch_Left_DigitalRed", target = "EHRMedicalWatch_Left" },
}
