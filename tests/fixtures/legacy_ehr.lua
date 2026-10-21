-- Player modData of characters from the original mod, in its real formats (docs/porting/old-moddata-keys.md).
-- Each function returns a fresh copy.

local Fixtures = {}

-- A long-lived character: Patient Zero, several flyers and the Herald read, mid-illness and mid-course.
function Fixtures.veteran()
    return {
        EHR_Initialized = true,
        EHR_Blood = {
            currentVolume = 4870.5, maxVolume = 5000, bloodType = "A+", lossRate = 0,
            lastBleedTime = 1412.25, isCurrentlyBleeding = false, lossAccumulator = 0.12, lastRegenHour = 1450.0,
            transfusedSaline = 0, transfusedBlood = 0, lastStage = 4,
        },
        EHR_KnownDiseases = {
            common_cold = true,
            tetanus = true,
            hyperkeratotic_scabies = true,
            knox_infection = true,
            dysentery = false,
        },
        EHR_KnoxHeraldRead = true,
        EHR_KnoxKnowledgeSource = "kentucky_herald_july16",
        EHR_MedicalJournal = {
            entries = {
                [1] = { timestamp = 820.5, gameDay = 35, actualDisease = "pneumonia", stage = 2, diagnosedAs = "flu",
                        isCorrect = false, playerSkill = 3, effectiveSkill = 3.5, entryType = "diagnosis" },
            },
            treatments = {},
            statistics = { totalDiagnoses = 1, correctDiagnoses = 0, wrongDiagnoses = 1,
                           diseasesContracted = { pneumonia = 1 }, diseasesCured = { pneumonia = 1 } },
            settings = { showNotifications = true, trackHistory = true },
            createdTime = 0.0, lastUpdated = 840.1,
            discoveries = { pneumonia = 700.2, Scabies = 310.0, ["Heat Stroke"] = 320.0, Mystery = 1.0 },
        },
        EHR_Radio = { heardEffects = { ["3:9:XP:4"] = true, ["3:21:KNOW:tetanus"] = true } },
        EHR_MedicalWildPlantsKnown = true,
        EHR_MedicalWildPlantsReadHour = 200.5,
        EHR_ProfessionDiseaseKnowledge = "ehrdoctor",
        EHR_Immunity = {
            version = 4, score = 63.4, target = 71.2, trend = "recovering",
            factors = { nutrition = 82.0, hydration = 90.5, rest = 100 },
            lastUpdateHour = 1450.25, enabled = true, observationOnly = false, antibioticSuppressed = false,
        },
        EHR_KnoxCure = {
            phalanxUsageCount = 2, phalanxSideEffectsEnd = 905.5, phalanxResetTime = 880.0,
            immunoboosterActiveUntil = 0, immunoboosterHasBeenUsed = true,
            geneTherapySurvivor = false, geneTherapyImmune = true,
            immunityTraitGranted = true, patientZeroTraitSource = true,
        },
        -- Active state and borderline keys that must not survive the import.
        EHR_Disease = {
            active = { common_cold = { stage = 2, startTime = 1400.0 } },
            history = { lastBadFood = 1300.0, recoveries = { food_poisoning = 900.0 } },
            immunity = { general = 1.0, wound_infection = 0.25 },
        },
        EHR_Sepsis = { active = true, stage = 2 },
        EHR_WoundInfection_V2_Initialized = true,
        EHR_Medication = { active = { amoxicillin = { dosesTaken = 3 } } },
        EHR_PainkillerAddiction = { risk = 40, doseHours = { 1440.0, 1444.0 } },
        EHR_SkillXP_Data = { totalXPAwarded = 120, lastActions = {}, actionCounts = {} },
        EHR_HeatStrokeColdBathX = 10500,
        -- Not ours: Lifestyle's keys stay.
        bathroomNeed = 35,
        lastBath = 1200.0,
        -- Vanilla or other mods' keys stay.
        SomeOtherMod_Flag = true,
    }
end

-- A character that only ever read one flyer: none of the original's 14 marker keys except the journal.
function Fixtures.flyerOnly()
    return {
        EHR_KnownDiseases = { CommonCold = true },
        EHR_MedicalJournal = { entries = {}, discoveries = { common_cold = 152.4 } },
    }
end

-- An MP client that never heard back from the server, with the Knox flag but no Herald.
function Fixtures.pending()
    return {
        EHR_Initialized = true,
        EHR_Blood = { bloodType = "PENDING" },
        EHR_KnownDiseases = { knox_infection = true },
        EHR_KnoxCure = {},
        EHR_Immunity = { version = 4 },
    }
end

function Fixtures.dead()
    local data = Fixtures.veteran()
    data.EHR_DeadCharacter = true
    return data
end

return Fixtures
