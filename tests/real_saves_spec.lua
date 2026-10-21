---@diagnostic disable: need-check-nil
-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The importer against REAL data: the EHR_* player modData of eight saves made with the original mod (August 2026),
-- decoded by tools/decode-ehr-moddata.py into tests/fixtures/real_saves/save_<n>.lua. The synthetic fixtures in
-- tests/fixtures/legacy_ehr.lua test the formats we inferred from the original's source; these test what the
-- original actually wrote. Offline validation only: the migration has not been run in the game.
--
-- EXPECTED holds the values read from each fixture by hand, so the spec fails if the importer drops or corrupts
-- them, and also if a fixture is regenerated with different data.

local Schema = require("ExtensiveHealthRedone/Core/Schema")
local Importer = require("ExtensiveHealthRedone/Core/Importer")
local BloodTypes = require("ExtensiveHealthRedone/Core/BloodTypes")
local Legacy = require("ExtensiveHealthRedone/Data/LegacyEHR")

-- Per save: blood type, known diseases (sorted), wild plants flag, immunity score, and which active state the
-- original had running when the save was made (the importer must clear all of it).
local EXPECTED = {
    [1] = { blood = "A+", known = {}, wildPlants = false, immunity = 66.2 },
    [2] = { blood = "O+", known = {}, wildPlants = false, immunity = 96.2 },
    [3] = { blood = "A-", known = { "food_poisoning" }, wildPlants = true, immunity = 78.1,
            diseases = { "gastroenteritis" }, doses = { "ExtensiveHealth.AntiNauseaTablets" } },
    [4] = { blood = "O+", known = {}, wildPlants = false, immunity = 89.4 },
    [5] = { blood = "A-", known = { "heat_exhaustion", "pneumonia" }, wildPlants = false, immunity = 65.4,
            diseases = { "gastroenteritis" }, doses = { "ExtensiveHealth.BroadSpectrumAntibiotics" },
            woundParts = { "Foot_L" }, antibiotic = true },
    [6] = { blood = "A+", known = { "corpse_sickness" }, wildPlants = false,
            immunity = 40.9, diseases = { "hyperkeratotic_scabies" },
            doses = { "ExtensiveHealth.AntibioticOintment", "ExtensiveHealth.BroadSpectrumAntibiotics" },
            woundParts = { "Groin" } },
    [7] = { blood = "B-", known = {}, wildPlants = false, immunity = 94, diseases = { "food_poisoning" } },
    [8] = { blood = "A+", known = { "ahtr", "pneumonia" }, wildPlants = true, immunity = 94 },
}
local SAVES = 8

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function fixture(n)
    return deepCopy(require("fixtures/real_saves/save_" .. n))
end

local function rng(value)
    return {
        int = function(lo, hi)
            assert(value >= lo and value <= hi, "fake rng value out of range")
            return value
        end,
        float = function() return 0.5 end,
    }
end

describe("Real saves: the data the original wrote", function()
    for n = 1, SAVES do
        local expected = EXPECTED[n]
        it("save " .. n .. " has the shapes the importer reads", function()
            local data = fixture(n)
            -- Every key is an old key, none is the tombstone, and none of them is nested under another name.
            for _, key in ipairs(sortedKeys(data)) do
                assert.equal(Legacy.KEY_PREFIX, key:sub(1, #Legacy.KEY_PREFIX))
            end
            assert.is_nil(data.EHR_DeadCharacter)
            assert.equal("2.8.1", data.EHR_Version)
            -- Blood type: save-format spelling, nothing else.
            assert.equal(expected.blood, data.EHR_Blood.bloodType)
            assert.is_true(BloodTypes.isValid(data.EHR_Blood.bloodType))
            -- Knowledge: a map id -> true, every id one the importer knows, and the journal agrees with it.
            assert.same(expected.known, sortedKeys(data.EHR_KnownDiseases))
            for id, value in pairs(data.EHR_KnownDiseases) do
                assert.is_true(value, id)
                assert.equal(id, Importer.normalizeKnowledgeId(id))
            end
            local discovered = data.EHR_MedicalJournal.discoveries
            assert.same(expected.known, sortedKeys(discovered))
            for id, hour in pairs(discovered) do
                assert.equal("number", type(hour), id)
            end
            assert.same({}, data.EHR_MedicalJournal.entries)
            -- Immunity: a one-decimal number in 0-100 under `score`.
            assert.equal(expected.immunity, data.EHR_Immunity.score)
            assert.equal(4, data.EHR_Immunity.version)
            -- Knox: only the gene-therapy fields exist; nobody here is Patient Zero.
            assert.is_false(data.EHR_KnoxCure.geneTherapyImmune)
            assert.is_nil(data.EHR_KnoxCure.immunityTraitGranted)
            assert.is_nil(data.EHR_KnoxCure.patientZeroTraitSource)
            assert.is_nil(data.EHR_KnoxHeraldRead)
            assert.is_nil(data.EHR_KnoxKnowledgeSource)
            assert.is_nil(data.EHR_ProfessionDiseaseKnowledge)
            assert.is_nil(data.EHR_Radio)
            assert.equal(expected.wildPlants or nil, data.EHR_MedicalWildPlantsKnown)
            -- The active state this save was made with, which the importer has to clear.
            assert.same(expected.diseases or {}, sortedKeys(data.EHR_Disease.active))
            assert.same(expected.doses or {}, sortedKeys(data.EHR_Medication.activeDoses))
            assert.same(expected.woundParts or {}, sortedKeys(data.EHR_WoundInfection.parts))
            assert.equal(expected.antibiotic or nil, data.EHR_Immunity.activeAntibiotic and true or nil)
        end)
    end

    it("includes saves made mid-illness, mid-course, with infected wounds and under an antibiotic", function()
        local sick, treated, infected, antibiotic = 0, 0, 0, 0
        for n = 1, SAVES do
            local data = fixture(n)
            sick = sick + #sortedKeys(data.EHR_Disease.active)
            treated = treated + #sortedKeys(data.EHR_Medication.activeDoses)
            infected = infected + #sortedKeys(data.EHR_WoundInfection.parts)
            antibiotic = antibiotic + (data.EHR_Immunity.activeAntibiotic and 1 or 0)
        end
        assert.equal(4, sick)
        assert.equal(4, treated)
        assert.equal(2, infected)
        assert.equal(1, antibiotic)
    end)
end)

describe("Real saves: Importer.run", function()
    for n = 1, SAVES do
        local expected = EXPECTED[n]
        it("save " .. n .. " carries identity over and reports it", function()
            local modData = fixture(n)
            local topLevel = #sortedKeys(modData)
            local state = Schema.new(rng(1))
            local report = Importer.run(modData, state)
            assert.is_true(report.imported)
            assert.equal("kept", report.bloodType)
            assert.equal(expected.blood, state.identity.bloodType)
            assert.same(expected.known, sortedKeys(state.knowledge.diseases))
            assert.same({}, report.unknownKnowledge)
            assert.equal(expected.wildPlants, state.knowledge.wildPlants)
            assert.equal(expected.immunity, state.immunity.score)
            assert.is_false(state.knox.geneTherapyImmune)
            assert.is_false(state.knox.immunityTraitGranted)
            assert.is_false(state.knox.patientZeroTraitSource)
            assert.equal(topLevel, report.removedKeys)
            assert.same({}, Importer.oldKeys(modData))
            assert.same({}, modData)
            assert.equal("blood type kept, " .. #expected.known .. " diseases known, immunity "
                .. tostring(expected.immunity) .. ", " .. topLevel .. " old keys removed", report.summary)
        end)
    end
end)

insulate("Real saves: first load through PlayerState", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local PlayerState = require("ExtensiveHealthRedone/Server/PlayerState")

    -- Everything the importer must reset is exactly a fresh state's section.
    local RESET = { "blood", "body", "wounds", "conditions", "exposure", "mind", "effects", "meds", "temperature" }

    for n = 1, SAVES do
        local expected = EXPECTED[n]
        it("save " .. n .. ": identity kept, active state reset, old keys gone, second load changes nothing", function()
            local modData = fixture(n)
            modData.bathroomNeed = 35          -- another mod's key, which must survive
            local player = game.addPlayer({ modData = modData })
            assert.is_true(Importer.hasOldData(modData))

            local state = PlayerState.load(player, "save" .. n)
            assert.is_not_nil(state)
            assert.equal(Schema.VERSION, state.version)
            assert.equal(state, modData[Schema.ROOT_KEY])

            -- Marked imported.
            assert.equal("imported", state.meta.createdAs)
            assert.equal(Legacy.MOD_ID, state.meta.importedFrom)

            -- Identity.
            assert.same({ bloodType = expected.blood }, state.identity)
            assert.same(expected.known, sortedKeys(state.knowledge.diseases))
            assert.is_false(state.knowledge.knoxHerald)
            assert.equal(expected.wildPlants, state.knowledge.wildPlants)
            assert.is_nil(state.knowledge.professionGrant)
            assert.same({}, state.knowledge.radioHeard)
            assert.is_false(state.knox.geneTherapyImmune)
            assert.is_false(state.knox.immunityTraitGranted)
            assert.is_false(state.knox.patientZeroTraitSource)

            -- Immunity: the score only. The target, factors and any antibiotic pressure start over.
            local immunity = Schema.sectionDefaults("immunity")
            immunity.score = expected.immunity
            assert.same(immunity, state.immunity)

            -- Active state: no conditions, medication, wound infections, meters or timers; blood is full.
            for _, name in ipairs(RESET) do
                assert.same(Schema.sectionDefaults(name), state[name], name)
            end
            assert.same({}, state.conditions.active)
            assert.same({}, state.meds.doses)
            assert.same({}, state.meds.courses)
            assert.same({}, state.wounds.parts)
            assert.equal(5000, state.blood.volume)
            assert.equal(state.blood.max, state.blood.volume)
            assert.same({}, state.knox.effects)
            assert.equal(0, state.knox.phalanxUses)

            -- No EHR_ key is left, so nothing can import again; other mods' keys stay.
            assert.same({}, Importer.oldKeys(modData))
            assert.is_false(Importer.hasOldData(modData))
            assert.equal(35, modData.bathroomNeed)
            assert.same({ "ExtensiveHealthRedone", "bathroomNeed" }, sortedKeys(modData))

            -- Loading again takes the existing-state path: the same table, unchanged.
            local before = deepCopy(state)
            local again = PlayerState.load(player, "save" .. n)
            assert.equal(state, again)
            assert.same(before, again)
            assert.same({ "ExtensiveHealthRedone", "bathroomNeed" }, sortedKeys(modData))
        end)
    end
end)
