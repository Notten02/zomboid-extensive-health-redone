-- The medication database: every medication defined once, by item full type. Reconciled from v0.9's Database,
-- DosingSchedules, per-disease treatment lists and item scripts (docs/porting/phase5/medication-database.md) with the
-- maintainer's Phase 5 decisions (docs/parity-checklist.md section 14). Hours are game hours.
--
-- An entry:
--   id          short name, used in state (state.meds) and logs
--   name        display name key (UI_EHR_Med_*)
--   route       how it is taken and how long that takes (ROUTES below)
--   vanilla     "pill", "eat" or "drink": a vanilla action (ISTakePillAction, ISEatFoodAction, ISDrinkFluidAction or
--               ISTakeWaterAction) consumes it and the server hook applies our effect; such a dose can't be refused,
--               only wasted
--   tier        0 basic, 1 OTC, 2 prescription, 3 clinical; the tier relief (TIER_RELIEF) it gives what it treats
--   active      hours a dose stays active (relief, flags, interactions)
--   interval    hours between course doses; doses = doses in a course (default 1)
--   cures       { [conditionId] = hours }: with doses > 1, a course cures once every dose is taken and that long has
--               passed since its first dose; a single-dose cure cures that long after the dose
--   treats      condition ids that get the tier relief and the specific relief (cures are added to them)
--   relief      { [symptom] = 0-1 } specific relief while active; reliefFor = { [conditionId] = { [symptom] = n } }
--   flags       effects active while a dose is: sleepAid, sleepTea, analgesic, antiseptic, antipsychotic,
--               buprenorphine, betaBlocker, antibiotic (systemic: suppresses immunity, Immunity/Immunity)
--   effects     timed effects started by a dose (Medication/Effects): { id, hours, ... }
--   side        side effects applied by every dose (Medication/SideEffects)
--   now         { [STAT] = fraction of its range } added once at the dose (antidepressant mood relief)
--   early       what a dose does while the previous one is active and not due: "refuse" or "waste". Course doses
--               taken before their interval are always wasted (maintainer, Phase 5)
--   earlyLine   what the character says then
--   overdose    an early dose overdoses (Medication/Overdose)
--   supply      "syringe" or "ivKit": one is used from the giver's inventory
--   needsWound  only with an open wound; needs = condition that must be active (ice pack: heat stroke)
--   option      a sandbox option that must not be false (refused otherwise, Medication/Doses)
--   addiction   counts toward painkiller addiction (W18: Base.Pills only)
--   category    for drug interactions (Medication/Interactions); by item, so homemade twins and IV drugs count
--   remote      false: can't be given to another player (of vanilla-route items only Data.giveVanilla can be)
--   silent      no line and no First Aid XP (everyday drinks: tea, water)
--   line        what the character says on a dose
--   woundStep   vanilla antibiotics: infected wounds drop one stage per dose (Wounds/Infection.antibiotics)

local Data = {}

Data.TIER_RELIEF = { [0] = 0.15, [1] = 0.40, [2] = 0.60, [3] = 0.80 }

-- Conditions whose code asks relief(id, "general") for the tier relief and combines it with the specific relief
-- itself (Diseases/Food/Common.lua, Dysentery.lua). For the others the provider folds the tier in.
Data.GENERAL_KEY = { food_poisoning = true, gastroenteritis = true, toxin_poisoning = true, trichinosis = true,
    dysentery = true }

-- Module conditions v0.9 gave no tier relief (they never read its multiplier).
Data.NO_TIER = { woundInfection = true, sepsis = true }

-- Action length in ticks by route, the animation, and the tooltip route name (UI_EHR_MedAction_AdminType_*).
Data.ROUTES = {
    pill = { ticks = 90, anim = "pills" },
    capsule = { ticks = 90, anim = "pills" },
    liquid = { ticks = 120, anim = "drink" },
    cream = { ticks = 150, anim = "loot" },
    inhaler = { ticks = 60, anim = "loot" },
    injection = { ticks = 180, anim = "loot", work = true },
    iv = { ticks = 300, anim = "loot", work = true },
    emergency = { ticks = 60, anim = "loot" },
}

-- A course dose counts from this share of its interval on (ours, Phase 5: v0.9's 3 game minutes were about 7 real
-- seconds at the default day length). Earlier, it is wasted, and on the overdose list it overdoses.
Data.DUE_SHARE = 0.9
-- A course whose next dose is this late (past due) is abandoned: max(24, min(72, 3 x interval)) hours (v0.9).
function Data.abandonHours(interval)
    return math.max(24, math.min(72, 3 * interval))
end

local T = "UI_EHR_Text_"

local M = {}
Data.byType = M

-- Vanilla items (module Base) ------------------------------------------------------------------------------------------

M["Base.Pills"] = {
    id = "Painkillers", name = "UI_EHR_Med_Painkillers", route = "pill", vanilla = "pill", tier = 0,
    active = 3, flags = { "analgesic" }, addiction = true, category = "painkiller",
    line = T .. "YouTakePainkillersThePainBeginsToFade",
}
M["Base.PillsVitamins"] = {
    id = "CaffeinePills", name = "UI_EHR_Med_CaffeinePills", route = "pill", vanilla = "pill", tier = 1,
    active = 12, early = "refuse", earlyLine = T .. "TheCaffeineIsStillActiveMoreWouldBeAVeryBadIdea",
    effects = { { id = "fatigueBlock", hours = 12 } }, category = "stimulant",
    line = T .. "YouTakeCaffeinePillsExhaustionVanishesButThis",
}
M["Base.PillsSleepingTablets"] = {
    id = "SleepingPills", name = "UI_EHR_Med_SleepingPills", route = "pill", vanilla = "pill", tier = 0,
    active = 8, treats = { "insomnia" }, flags = { "sleepAid" }, category = "sleepAid",
    line = T .. "YouTakeSleepingPillsDrowsinessSettlesIn",
}
M["Base.PillsAntiDep"] = {
    id = "Antidepressants", name = "UI_EHR_Med_Antidepressants", route = "pill", vanilla = "pill", tier = 2,
    active = 12, interval = 12, doses = 14, cures = { insomnia = 168 }, relief = { stress = 0.35, fatigue = 0.20 },
    flags = { "sleepAid" }, now = { STRESS = -0.05, PANIC = -0.035, UNHAPPINESS = -0.03 },
    early = "refuse", earlyLine = T .. "TheAntidepressantDoseIsStillActive", overdose = true,
    category = "antidepressant", line = T .. "YouTakeAntidepressantsTheEdgeSoftensALittle",
}
-- W8: no medicine helps hypothermia. The low-blood penalty is Phase 3's (Blood/Blood.lua).
M["Base.PillsBeta"] = {
    id = "BetaBlockers", name = "UI_EHR_Med_BetaBlockers", route = "pill", vanilla = "pill", tier = 0,
    active = 2, flags = { "betaBlocker" }, category = "betaBlocker",
    line = T .. "YouTakeBetaBlockersYourHeartRateStabilizes",
}
-- Vanilla's single-dose food item (maintainer, Phase 5): one wound-infection stage per dose and minor help for
-- sepsis and pneumonia.
M["Base.Antibiotics"] = {
    id = "Antibiotics", name = "UI_EHR_Med_Antibiotics", route = "pill", vanilla = "eat", tier = 0,
    active = 4, treats = { "pneumonia", "cellulitis" }, reliefFor = { sepsis = { fever = 0.15 } },
    woundStep = true, flags = { "antibiotic" }, category = "antibiotic",
    line = T .. "YouTakeTheAntibioticsTheyProvideMinorRelief",
}
-- Vanilla tea (food, and the Tea fluid: see Server/Medication) only counts as tea before sleeping.
M["Base.HotDrinkTea"] = {
    id = "Tea", route = "liquid", vanilla = "eat", tier = 0, active = 3, flags = { "sleepTea" }, silent = true,
}
M["Base.HotDrinkTeaCeramic"] = {
    id = "TeaCeramic", route = "liquid", vanilla = "eat", tier = 0, active = 3, flags = { "sleepTea" }, silent = true,
}
-- Drinking water (any container, or a world source: see Server/Medication) helps heat exhaustion a little
-- (maintainer, Phase 5). Not an item: keyed by the fluid.
M["Fluid.Water"] = {
    id = "Water", route = "liquid", vanilla = "drink", tier = 0, active = 1,
    reliefFor = { heat_exhaustion = { dehydration = 0.10 } }, silent = true,
}

-- Over-the-counter relief (tier 1) -------------------------------------------------------------------------------------

M["ExtensiveHealth.ColdFluTablets"] = {
    id = "ColdFluTablets", name = "UI_EHR_Med_ColdFluTablets", route = "pill", tier = 1,
    active = 4, interval = 4, doses = 8, cures = { common_cold = 28 }, relief = { fever = 0.35, fatigue = 0.30,
        pain = 0.25 },
    early = "refuse", earlyLine = T .. "TheCurrentColdMedicineDoseIsStillActive", category = "coldFlu",
    line = T .. "YouTakeTheColdFluTabletsTheColdShouldStart",
}
M["ExtensiveHealth.CommonColdTea"] = {
    id = "CommonColdTea", name = "UI_EHR_Med_HerbalTea", route = "liquid", vanilla = "eat", tier = 1,
    active = 4, interval = 4, doses = 8, cures = { common_cold = 28 }, relief = { fever = 0.25, fatigue = 0.20,
        pain = 0.15 },
    flags = { "sleepTea" }, effects = { { id = "hydration", hours = 0.35, now = 0.04, extra = 0.08, rate = 0.25 } },
    early = "waste", earlyLine = T .. "TheHerbalTeaDoseIsStillActive", remote = false,
    line = T .. "YouDrinkTheHerbalTeaWarmthSettlesInYourChest",
}

local FEVERS = { "common_cold", "pneumonia", "trichinosis", "cadaveric_aspergillosis", "woundInfection",
    "cellulitis", "tetanus", "sepsis", "ahtr", "hyperkeratotic_scabies" }

M["ExtensiveHealth.AntipyreticTablets"] = {
    id = "AntipyreticTablets", name = "UI_EHR_Med_AntipyreticTablets", route = "pill", tier = 1,
    active = 4, treats = FEVERS, relief = { fever = 0.60 }, category = "antipyretic",
    line = T .. "YouTakeAntipyreticTabletsTheFeverBeginsToEase",
}
M["ExtensiveHealth.AntipyreticTea"] = {
    id = "AntipyreticTea", name = "UI_EHR_Med_AntipyreticTea", route = "liquid", vanilla = "eat", tier = 1,
    active = 4, treats = FEVERS, relief = { fever = 0.60 }, flags = { "sleepTea" },
    effects = { { id = "hydration", hours = 0.35, now = 0.04, extra = 0.08, rate = 0.25 } },
    early = "waste", earlyLine = T .. "TheAntipyreticTeaDoseIsStillActiveMoreNowWillBe", remote = false,
    category = "antipyretic", line = T .. "YouDrinkTheAntipyreticTeaTheFeverBeginsToEase",
}

local COUGHS = { "common_cold", "pneumonia", "cadaveric_aspergillosis" }

M["ExtensiveHealth.CoughSyrup"] = {
    id = "CoughSyrup", name = "UI_EHR_Med_CoughSyrup", route = "liquid", tier = 1,
    active = 6, treats = COUGHS, relief = { coughing = 0.50 }, category = "coughSuppressant",
    line = T .. "YouDrinkTheCoughSyrupTheCoughingSubsides",
}
M["ExtensiveHealth.HomemadeCoughSyrup"] = {
    id = "HomemadeCoughSyrup", name = "UI_EHR_Med_HomemadeCoughSyrup", route = "liquid", tier = 1,
    active = 6, treats = COUGHS, relief = { coughing = 0.50 }, category = "coughSuppressant",
    line = T .. "YouDrinkTheHomemadeCoughSyrupTheCoughingSubsides",
}
M["ExtensiveHealth.CoughSuppressant"] = {
    id = "CoughSuppressant", name = "UI_EHR_Med_CoughSuppressant", route = "pill", tier = 1,
    active = 6, treats = COUGHS, relief = { coughing = 0.45 }, category = "coughSuppressant",
    line = T .. "YouTakeCoughSuppressantTheUrgeToCoughFades",
}
-- Heat exhaustion relief is ours (W9: the guide says electrolytes and rehydration help it).
M["ExtensiveHealth.ElectrolytePowder"] = {
    id = "ElectrolytePowder", name = "UI_EHR_Med_ElectrolytePowder", route = "liquid", tier = 1,
    active = 0.5, treats = { "dysentery", "food_poisoning", "gastroenteritis", "toxin_poisoning", "heat_stroke",
        "heat_exhaustion" },
    relief = { dehydration = 0.40, weakness = 0.30 },
    effects = { { id = "hydration", hours = 0.5, now = 0.10, extra = 0.20, rate = 0.50 } },
    category = "electrolyte", line = T .. "YouMixAndDrinkTheElectrolyteSolutionYouFeelMore",
}
M["ExtensiveHealth.BronchodilatorInhaler"] = {
    id = "BronchodilatorInhaler", name = "UI_EHR_Med_BronchodilatorInhaler", route = "inhaler", tier = 1,
    active = 0.5, treats = { "pneumonia", "corpse_sickness", "cadaveric_aspergillosis" },
    relief = { breathingDifficulty = 0.45, weakness = 0.25 },
    effects = { { id = "respiratory", hours = 0.5, now = 0.10, extra = 0.20, rate = 0.85 } },
    category = "bronchodilator", line = T .. "YouUseTheInhalerBreathingBecomesEasier",
}
M["ExtensiveHealth.AntiNauseaTablets"] = {
    id = "AntiNauseaTablets", name = "UI_EHR_Med_AntiNauseaTablets", route = "pill", tier = 1,
    active = 6, treats = { "food_poisoning", "gastroenteritis", "toxin_poisoning", "corpse_sickness", "dysentery",
        "ahtr" },
    relief = { nausea = 0.50, vomiting = 0.40, sickness = 0.30 }, reliefFor = { dysentery = { vomiting = 0.75 } },
    category = "antiNausea", line = T .. "YouTakeAntiNauseaTabletsYourStomachSettles",
}
M["ExtensiveHealth.AntiInflammatory"] = {
    id = "AntiInflammatory", name = "UI_EHR_Med_AntiInflammatoryPills", route = "pill", tier = 1,
    active = 6, treats = { "woundInfection", "cellulitis", "trichinosis", "tetanus", "ahtr" },
    relief = { inflammation = 0.50, pain = 0.55, fever = 0.30 }, category = "antiInflammatory",
    line = T .. "YouTakeAntiInflammatoryPillsSwellingBeginsTo",
}
-- W30: relief never lifts dysentery's caps. v0.9's x0.35 thirst drain is kept as dehydration relief.
M["ExtensiveHealth.AntiDiarrheal"] = {
    id = "AntiDiarrheal", name = "UI_EHR_Med_AntiDiarrhealTablets", route = "pill", tier = 1,
    active = 6, treats = { "dysentery" }, relief = { diarrhea = 0.85, dehydration = 0.65, bathroomNeed = 0.85 },
    category = "antiDiarrheal", line = T .. "YouTakeAntiDiarrhealTabletsTheCrampsAndUrgency",
}
M["ExtensiveHealth.MuscleRelaxants"] = {
    id = "MuscleRelaxants", name = "UI_EHR_Med_MuscleRelaxants", route = "pill", tier = 1,
    active = 8, treats = { "tetanus", "trichinosis" }, relief = { muscleSpasms = 0.40, pain = 0.30 },
    category = "muscleRelaxant", line = T .. "YouTakeMuscleRelaxantsTheCrampingEases",
}
M["ExtensiveHealth.HomemadeMuscleRelaxant"] = {
    id = "HomemadeMuscleRelaxant", name = "UI_EHR_Med_HomemadeMuscleRelaxant", route = "pill", tier = 1,
    active = 8, treats = { "tetanus", "trichinosis" }, relief = { muscleSpasms = 0.40, pain = 0.30 },
    category = "muscleRelaxant", line = T .. "YouTakeTheHomemadeMuscleRelaxantTheCrampingEases",
}
-- W18: herbal, so no addiction. Behaves like vanilla painkillers: pain to zero over 30 minutes, none for 3 h.
M["ExtensiveHealth.HomemadePainkillers"] = {
    id = "HomemadePainkillers", name = "UI_EHR_Med_HomemadePainkillers", route = "pill", tier = 0,
    active = 3, flags = { "analgesic" }, effects = { { id = "painkiller", hours = 3, fadeMinutes = 30 } },
    category = "painkiller", line = T .. "YouTakeHomemadePainkillersThePainBeginsToFade",
}
M["ExtensiveHealth.HomemadeSleepingPills"] = {
    id = "HomemadeSleepingPills", name = "UI_EHR_Med_HomemadeSleepingPills", route = "pill", tier = 0,
    active = 8, treats = { "insomnia" }, flags = { "sleepAid" }, category = "sleepAid",
    early = "refuse", earlyLine = "UI_EHR_MedReason_SleepAidActive",
    line = T .. "YouTakeHomemadeSleepingPillsDrowsinessSettlesIn",
}
M["ExtensiveHealth.RelaxantTea"] = {
    id = "RelaxantTea", name = "UI_EHR_Med_RelaxantTea", route = "liquid", vanilla = "eat", tier = 1,
    active = 3, flags = { "sleepTea" }, effects = { { id = "stress", hours = 3, rate = 0.35 } },
    early = "waste", earlyLine = T .. "TheRelaxantTeaDoseIsStillActiveMoreNowWillBe", remote = false,
    line = T .. "YouDrinkTheRelaxantTeaYourNervesBeginToLoosen",
}
M["ExtensiveHealth.AntisepticCream"] = {
    id = "AntisepticCream", name = "UI_EHR_Med_AntisepticCream", route = "cream", tier = 1,
    active = 8, flags = { "antiseptic" }, needsWound = true, category = "antiseptic",
    line = T .. "YouApplyAntisepticCreamToTheWound",
}
M["ExtensiveHealth.HomemadeAntisepticCream"] = {
    id = "HomemadeAntisepticCream", name = "UI_EHR_Med_HomemadeAntisepticCream", route = "cream", tier = 1,
    active = 8, flags = { "antiseptic" }, needsWound = true, category = "antiseptic",
    line = T .. "YouApplyHomemadeAntisepticCreamToTheWound",
}

-- Utility and emergency ------------------------------------------------------------------------------------------------

M["ExtensiveHealth.NitricOxideBooster"] = {
    id = "NitricOxideBooster", name = "UI_EHR_Med_NitricOxideBoosters", route = "pill", tier = 1,
    active = 3, early = "refuse", earlyLine = T .. "TheNitricOxideBoosterIsStillActive",
    effects = { { id = "staminaLock", hours = 3 } }, category = "stimulant",
    line = T .. "YouTakeANitricOxideBoosterYourMusclesFeelFlooded",
}
M["ExtensiveHealth.CombatStimulants"] = {
    id = "CombatStimulants", name = "UI_EHR_Med_CombatStimulants", route = "pill", tier = 3,
    active = 3, early = "refuse", earlyLine = T .. "TheCombatStimulantsAreStillActiveAnotherDose",
    effects = { { id = "combat", hours = 3 } }, category = "stimulant",
    line = T .. "YouTakeCombatStimulantsEverythingSharpensFast",
}
M["ExtensiveHealth.LastChanceEpinephrine"] = {
    id = "LastChanceEpinephrine", name = "UI_EHR_Med_EmergencyEpinephrineAutoInjector", route = "injection", tier = 3,
    active = 1, early = "refuse", earlyLine = T .. "TheEpinephrineSurgeIsStillActive",
    effects = { { id = "lastChance", hours = 1 } }, category = "epinephrine",
    line = T .. "YouTriggerTheAutoInjectorAdrenalineFloodsYour",
}
-- W6: a stimulant that wakes the character, also from a blackout (so it is mostly given by another player).
M["ExtensiveHealth.Epinephrine"] = {
    id = "Epinephrine", name = "UI_EHR_Med_EpinephrineAutoInjector", route = "emergency", tier = 3,
    active = 6, effects = { { id = "epinephrine", hours = 0 } }, side = { "headache", "insomnia" },
    category = "epinephrine", line = T .. "YouInjectTheEpinephrineYourHeartRacesAnd",
}
M["ExtensiveHealth.InstantIcePack"] = {
    id = "InstantIcePack", name = "UI_EHR_Med_InstantIcePack", route = "emergency", tier = 2,
    active = 1.1, interval = 1, doses = 4, cures = { heat_stroke = 4 }, needs = "heat_stroke",
    relief = { fever = 0.95, dehydration = 0.98, dizziness = 0.98, confusion = 0.98, collapse = 0.98,
        healthDrain = 0.98 },
    early = "refuse", earlyLine = "UI_EHR_Med_IcePackStillCooling",
    line = T .. "YouCrackAnInstantIcePackAndStartCoolingDown",
}

-- Warming Pack: toward 37 deg C at 3.2 deg C/h for 2 h, never above (Body/Temperature, v0.9 M:799-816). Refused
-- while BodyTemperatureEnabled is off, since it would do nothing.
M["ExtensiveHealth.WarmingPack"] = {
    id = "WarmingPack", name = "UI_EHR_Med_WarmingPack", route = "emergency", tier = 1,
    active = 2, effects = { { id = "warming", hours = 2 } }, option = "BodyTemperatureEnabled",
    early = "refuse", earlyLine = "UI_EHR_MedReason_WarmingPackActive",
    line = T .. "YouActivateTheWarmingPackAndHoldItCloseToYour",
}

-- Prescription (tier 2) ------------------------------------------------------------------------------------------------

M["ExtensiveHealth.AntiviralCapsules"] = {
    id = "AntiviralCapsules", name = "UI_EHR_Med_AntiviralCapsules", route = "capsule", tier = 2,
    active = 8, interval = 8, doses = 6, cures = { common_cold = 48, gastroenteritis = 48 }, overdose = true,
    category = "antiviral", line = T .. "YouTakeAntiviralCapsulesYourBodyFightsThe",
}
M["ExtensiveHealth.PrescriptionAntibiotics"] = {
    id = "PrescriptionAntibiotics", name = "UI_EHR_Med_PrescriptionAntibiotics", route = "pill", tier = 2,
    active = 8, interval = 8, doses = 9, cures = { woundInfection = 72, cellulitis = 72, pneumonia = 72 },
    overdose = true, flags = { "antibiotic" }, category = "antibiotic",
    line = T .. "YouTakePrescriptionAntibioticsTheInfectionShould",
}
local BROAD = { woundInfection = 72, sepsis = 72, pneumonia = 72, cellulitis = 72, dysentery = 72 }
M["ExtensiveHealth.BroadSpectrumAntibiotics"] = {
    id = "BroadSpectrumAntibiotics", name = "UI_EHR_Med_BroadSpectrumAntibiotics", route = "pill", tier = 2,
    active = 8, interval = 8, doses = 6, cures = BROAD, overdose = true, flags = { "antibiotic" },
    category = "antibiotic", line = T .. "YouTakeBroadSpectrumAntibioticsTheyFightMultiple",
}
M["ExtensiveHealth.PlantBasedAntibiotics"] = {
    id = "PlantBasedAntibiotics", name = "UI_EHR_Med_PlantBasedAntibiotics", route = "pill", tier = 2,
    active = 8, interval = 8, doses = 6, cures = BROAD, overdose = true, flags = { "antibiotic" },
    category = "antibiotic", line = T .. "YouTakePlantBasedAntibioticsTheyShouldHelpFight",
}
-- Topical: never suppresses immunity (IS "Antibiotic Suppression").
M["ExtensiveHealth.AntibioticOintment"] = {
    id = "AntibioticOintment", name = "UI_EHR_Med_AntibioticOintment", route = "cream", tier = 2,
    active = 8, interval = 8, doses = 6, cures = { woundInfection = 72, cellulitis = 72 },
    early = "waste", earlyLine = T .. "TheCurrentOintmentDoseIsStillActiveMoreNowWillBe", category = "antibiotic",
    line = T .. "YouApplyAntibioticOintmentToTheInfectedArea",
}
M["ExtensiveHealth.HomemadeAntibioticOintment"] = {
    id = "HomemadeAntibioticOintment", name = "UI_EHR_Med_HomemadeAntibioticOintment", route = "cream", tier = 2,
    active = 8, interval = 8, doses = 6, cures = { woundInfection = 72, cellulitis = 72 },
    early = "waste", earlyLine = T .. "TheCurrentOintmentDoseIsStillActiveMoreNowWillBe", category = "antibiotic",
    line = T .. "YouApplyHomemadeAntibioticOintmentToTheInfected",
}
M["ExtensiveHealth.AntifungalTablets"] = {
    id = "AntifungalTablets", name = "UI_EHR_Med_AntifungalTablets", route = "pill", tier = 2,
    active = 12, interval = 12, doses = 10, cures = { cadaveric_aspergillosis = 120 }, overdose = true,
    relief = { coughing = 0.40, breathingDifficulty = 0.35, weakness = 0.25, fever = 0.35, dehydration = 0.25 },
    category = "antifungal", line = T .. "YouTakeAntifungalTabletsTheFungalInfectionIs",
}
M["ExtensiveHealth.ActivatedCharcoal"] = {
    id = "ActivatedCharcoal", name = "UI_EHR_Med_ActivatedCharcoal", route = "pill", tier = 2,
    active = 4, cures = { food_poisoning = 6, toxin_poisoning = 12 }, category = "charcoal",
    line = T .. "YouSwallowActivatedCharcoalItAbsorbsTheToxins",
}
M["ExtensiveHealth.HomeMadeActivatedCharcoal"] = {
    id = "HomemadeActivatedCharcoal", name = "UI_EHR_Med_HomemadeActivatedCharcoal", route = "pill", tier = 2,
    active = 4, cures = { food_poisoning = 6, toxin_poisoning = 12 }, category = "charcoal",
    line = T .. "YouSwallowHomemadeActivatedCharcoalItAbsorbsThe",
}
M["ExtensiveHealth.AntiparasiticPills"] = {
    id = "AntiparasiticPills", name = "UI_EHR_Med_AntiparasiticPills", route = "pill", tier = 2,
    active = 12, interval = 12, doses = 14, cures = { trichinosis = 168, hyperkeratotic_scabies = 168 },
    overdose = true, relief = { pain = 0.30, fever = 0.25, healthDrain = 0.45 }, category = "antiparasitic",
    line = T .. "YouTakeAntiparasiticMedicationTheParasitesWill",
}
M["ExtensiveHealth.TopicalPermethrin"] = {
    id = "TopicalPermethrin", name = "UI_EHR_Med_TopicalPermethrin", route = "cream", tier = 2,
    active = 12, interval = 12, doses = 6, cures = { hyperkeratotic_scabies = 72 },
    relief = { pain = 0.45, fever = 0.30, healthDrain = 0.65 },
    early = "waste", earlyLine = T .. "TheCurrentPermethrinDoseIsStillActiveMoreNowWill", category = "antiparasitic",
    line = T .. "YouApplyTopicalPermethrinTheMitesShouldStart",
}
M["ExtensiveHealth.HomemadeTopicalPermethrin"] = {
    id = "HomemadeTopicalPermethrin", name = "UI_EHR_Med_HomemadeTopicalPermethrin", route = "cream", tier = 2,
    active = 12, interval = 12, doses = 6, cures = { hyperkeratotic_scabies = 72 },
    relief = { pain = 0.45, fever = 0.30, healthDrain = 0.65 },
    early = "waste", earlyLine = T .. "TheCurrentPermethrinDoseIsStillActiveMoreNowWill", category = "antiparasitic",
    line = T .. "YouApplyHomemadeTopicalPermethrinTheMitesShould",
}
M["ExtensiveHealth.OralRehydrationKit"] = {
    id = "OralRehydrationKit", name = "UI_EHR_Med_OralRehydrationKit", route = "liquid", tier = 2,
    active = 6, interval = 6, doses = 8, cures = { dysentery = 48 }, treats = { "heat_exhaustion" },
    relief = { dehydration = 0.75, weakness = 0.25 },
    effects = { { id = "hydration", hours = 1, now = 0.12, extra = 0.25, rate = 0.65 } },
    early = "waste", earlyLine = T .. "TheCurrentRehydrationDoseIsStillActiveMoreNow", category = "rehydration",
    line = T .. "YouPrepareAndDrinkTheRehydrationSolution",
}
M["ExtensiveHealth.Furosemide"] = {
    id = "Furosemide", name = "UI_EHR_Med_Furosemide", route = "pill", tier = 2,
    active = 8, interval = 8, doses = 6, cures = { ahtr = 48 }, overdose = true,
    relief = { healthDrain = 0.45, fever = 0.25, pain = 0.25, nausea = 0.25, weakness = 0.25 },
    side = { "dehydration", "lower_back_pain", "diuretic_urination" }, category = "diuretic",
    line = T .. "YouTakeFurosemideItShouldHelpYourBodyClearThe",
}
M["ExtensiveHealth.Antipsychotics"] = {
    id = "Antipsychotics", name = "UI_EHR_Med_Antipsychotics", route = "pill", tier = 2,
    active = 12, interval = 12, doses = 8, cures = { delirium = 96 }, overdose = true, flags = { "antipsychotic" },
    category = "antipsychotic", line = T .. "YouTakeAntipsychoticsTheNoiseShouldStartLosing",
}
M["ExtensiveHealth.DualOrexinReceptor"] = {
    id = "DualOrexinReceptor", name = "UI_EHR_Med_DualOrexinReceptor", route = "pill", tier = 2,
    active = 12, interval = 12, doses = 8, cures = { insomnia = 96 }, overdose = true, flags = { "sleepAid" },
    relief = { fatigue = 0.35, stress = 0.30 },
    early = "refuse", earlyLine = T .. "TheCurrentOrexinDoseIsStillActive", category = "sleepAid",
    line = T .. "YouTakeTheDualOrexinReceptorMedicationSleepFeels",
}
M["ExtensiveHealth.Buprenorphine"] = {
    id = "Buprenorphine", name = "UI_EHR_Med_Buprenorphine", route = "pill", tier = 2,
    active = 12, interval = 12, doses = 10, cures = { painkiller_addiction = 120 }, overdose = true,
    flags = { "buprenorphine" },
    early = "refuse", earlyLine = T .. "TheCurrentBuprenorphineDoseIsStillActive", category = "opioid",
    line = T .. "YouTakeBuprenorphineTheWithdrawalBeginsToSettle",
}
M["ExtensiveHealth.TetanusAntitoxin"] = {
    id = "TetanusAntitoxin", name = "UI_EHR_Med_TetanusAntitoxin", route = "injection", tier = 2,
    active = 4, cures = { tetanus = 120 }, supply = "syringe",
    relief = { muscleSpasms = 0.55, pain = 0.45, fever = 0.45, weakness = 0.35 }, category = "antitoxin",
    line = T .. "YouInjectTheTetanusAntitoxinItNeutralizesThe",
}

-- Clinical (tier 3) ----------------------------------------------------------------------------------------------------

M["ExtensiveHealth.CorticosteroidInjection"] = {
    id = "CorticosteroidInjection", name = "UI_EHR_Med_CorticosteroidInjection", route = "injection", tier = 3,
    active = 4, cures = { corpse_sickness = 12 }, supply = "syringe", side = { "immunosuppression", "insomnia" },
    category = "corticosteroid", line = T .. "YouInjectCorticosteroidsInflammationReduces",
}
M["ExtensiveHealth.RespiratorySupportKit"] = {
    id = "RespiratorySupportKit", name = "UI_EHR_Med_RespiratorySupportKit", route = "inhaler", tier = 3,
    active = 3, interval = 3, doses = 3, cures = { corpse_sickness = 6 },
    relief = { breathingDifficulty = 0.80, dizziness = 0.50, nausea = 0.35, weakness = 0.35 },
    early = "refuse", earlyLine = T .. "TheCurrentRespiratorySupportDoseIsStillActive",
    category = "respiratorySupport", line = T .. "YouUseTheRespiratorySupportKitFreshOxygenAnd",
}
M["ExtensiveHealth.IVFluids"] = {
    id = "IVFluids", name = "UI_EHR_Med_IVFluids", route = "iv", tier = 3,
    active = 4, cures = { ahtr = 24 }, supply = "ivKit",
    relief = { dehydration = 0.80, healthDrain = 0.70, weakness = 0.50, nausea = 0.35, fever = 0.25, pain = 0.20 },
    effects = { { id = "hydration", hours = 2, now = 0.12, extra = 0.30, rate = 0.50 } },
    category = "ivFluids", line = T .. "YouStartIVFluidsTheReactionShouldStabilizeOver",
}
M["ExtensiveHealth.IVAntibiotics"] = {
    id = "IVAntibiotics", name = "UI_EHR_Med_IVAntibiotics", route = "iv", tier = 3,
    active = 4, cures = { sepsis = 36, woundInfection = 36, cellulitis = 36, dysentery = 36 }, supply = "ivKit",
    side = { "nausea", "fatigue" }, flags = { "antibiotic" }, category = "antibiotic",
    line = T .. "YouAdministerIVAntibioticsTheInfectionIsBeing",
}
M["ExtensiveHealth.IVMetronidazole"] = {
    id = "IVMetronidazole", name = "UI_EHR_Med_IVMetronidazole", route = "iv", tier = 3,
    active = 4, cures = { dysentery = 24, sepsis = 24 }, supply = "ivKit", side = { "metallic_taste", "nausea" },
    flags = { "antibiotic" }, category = "antibiotic", line = T .. "YouAdministerIVMetronidazoleAnaerobicBacteriaAre",
}
M["ExtensiveHealth.IVAmphotericin"] = {
    id = "IVAmphotericin", name = "UI_EHR_Med_IVAmphotericinB", route = "iv", tier = 3,
    active = 4, cures = { cadaveric_aspergillosis = 24 }, supply = "ivKit",
    relief = { coughing = 0.65, breathingDifficulty = 0.55, weakness = 0.45, fever = 0.55, dehydration = 0.45 },
    side = { "fever", "kidney_stress", "fatigue" }, category = "ivAntifungal",
    line = T .. "YouAdministerIVAmphotericinThisAntifungalIs",
}
-- W7: a toxin-poisoning cure.
M["ExtensiveHealth.ChelationKit"] = {
    id = "ChelationKit", name = "UI_EHR_Med_ChelationTherapyKit", route = "iv", tier = 3,
    active = 4, cures = { toxin_poisoning = 24 }, supply = "ivKit", side = { "headache", "fatigue", "nausea" },
    category = "chelation", line = "UI_EHR_Med_ChelationLine",
}
M["ExtensiveHealth.AlbendazoleInjection"] = {
    id = "AlbendazoleInjection", name = "UI_EHR_Med_AlbendazoleInjection", route = "injection", tier = 3,
    active = 4, cures = { trichinosis = 72 }, supply = "syringe", side = { "abdominal_pain", "dizziness" },
    category = "antiparasitic", line = T .. "YouInjectAlbendazoleTheParasitesAreBeing",
}
M["ExtensiveHealth.IVCiprofloxacin"] = {
    id = "IVCiprofloxacin", name = "UI_EHR_Med_IVCiprofloxacin", route = "iv", tier = 3,
    active = 4, cures = { gastroenteritis = 12, dysentery = 12, pneumonia = 12 }, supply = "ivKit",
    side = { "tendon_weakness", "dizziness" }, flags = { "antibiotic" }, category = "antibiotic",
    line = T .. "YouAdministerIVCiprofloxacinBacterialInfectionIs",
}
M["ExtensiveHealth.TetanusImmunoglobulin"] = {
    id = "TetanusImmunoglobulin", name = "UI_EHR_Med_TetanusImmunoglobulin", route = "injection", tier = 3,
    active = 4, cures = { tetanus = 48 }, supply = "syringe",
    relief = { muscleSpasms = 0.75, pain = 0.60, fever = 0.60, weakness = 0.50 },
    side = { "injection_site_pain", "fever" }, category = "immunoglobulin",
    line = T .. "YouInjectTetanusImmunoglobulinImmediate",
}
M["ExtensiveHealth.IVVancomycin"] = {
    id = "IVVancomycin", name = "UI_EHR_Med_IVVancomycin", route = "iv", tier = 3,
    active = 4, cures = { sepsis = 48, cellulitis = 48 }, supply = "ivKit", side = { "red_man_syndrome",
        "kidney_stress" },
    flags = { "antibiotic" }, category = "antibiotic", line = T .. "YouAdministerIVVancomycinLastResortAntibiotic",
}
M["ExtensiveHealth.EmergencySepsisKit"] = {
    id = "EmergencySepsisKit", name = "UI_EHR_Med_EmergencySepsisKit", route = "iv", tier = 3,
    active = 4, cures = { sepsis = 24 }, supply = "ivKit", side = { "severe_fatigue", "nausea", "fever" },
    flags = { "antibiotic" }, category = "antibiotic", line = T .. "YouUseTheEmergencySepsisKitMultipleAntibiotics",
}

-- Indexes ----------------------------------------------------------------------------------------------------------------

Data.byId = {}
for fullType, med in pairs(M) do
    med.fullType = fullType
    med.doses = med.doses or 1
    med.interval = med.interval or 0
    -- Every condition the drug acts on: treats plus what it cures.
    local targets, seen = {}, {}
    for _, id in ipairs(med.treats or {}) do
        if not seen[id] then
            seen[id] = true
            targets[#targets + 1] = id
        end
    end
    for id in pairs(med.cures or {}) do
        if not seen[id] then
            seen[id] = true
            targets[#targets + 1] = id
        end
    end
    table.sort(targets)
    med.targets = targets
    med.targetSet = seen
    local flags = {}
    for _, f in ipairs(med.flags or {}) do
        flags[f] = true
    end
    med.flagSet = flags
    if Data.byId[med.id] then
        error("duplicate medication id " .. med.id)
    end
    Data.byId[med.id] = med
end

-- Items our own inventory option takes (not consumed by a vanilla action), as a set for the command registry.
Data.ownRoute = {}
-- Items a vanilla action consumes, by action: { pill = { [fullType] = true }, eat = { ... } }.
Data.vanillaRoute = { pill = {}, eat = {}, drink = {} }
for fullType, med in pairs(M) do
    if med.vanilla then
        Data.vanillaRoute[med.vanilla][fullType] = true
    else
        Data.ownRoute[fullType] = true
    end
end

-- Vanilla-route items a doctor may give another player (Phase 9 decision; v0.9 could): our action gives the dose
-- (medication.give) with vanilla's own effect. Teas and water stay excluded.
Data.giveVanilla = {
    ["Base.Pills"] = true,
    ["Base.PillsVitamins"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.PillsAntiDep"] = true,
    ["Base.PillsBeta"] = true,
    ["Base.Antibiotics"] = true,
}

-- A course drug: more than one dose.
function Data.isCourse(med)
    return med.doses > 1
end

function Data.curesAnything(med)
    for _ in pairs(med.cures or {}) do
        return true
    end
    return false
end

return Data
