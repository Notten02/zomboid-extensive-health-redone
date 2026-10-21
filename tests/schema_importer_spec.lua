-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local Schema = require("ExtensiveHealthRedone/Core/Schema")
local Importer = require("ExtensiveHealthRedone/Core/Importer")
local BloodTypes = require("ExtensiveHealthRedone/Core/BloodTypes")
local Fixtures = require("fixtures/legacy_ehr")

-- A deterministic rng: int() returns the given values in turn.
local function rng(...)
    local values, i = { ... }, 0
    return {
        int = function(lo, hi)
            i = i + 1
            local v = values[(i - 1) % #values + 1]
            assert(v >= lo and v <= hi, "fake rng value out of range")
            return v
        end,
        float = function() return 0.5 end,
    }
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

describe("BloodTypes", function()
    it("rolls by the original's weights", function()
        -- Cumulative weights: O- 1-7, O+ 8-43, A- 44-49, A+ 50-83, B- 84-85, B+ 86-94, AB- 95, AB+ 96-100.
        local cases = { [1] = "O-", [7] = "O-", [8] = "O+", [43] = "O+", [44] = "A-", [50] = "A+", [84] = "B-",
                        [86] = "B+", [95] = "AB-", [96] = "AB+", [100] = "AB+" }
        for value, expected in pairs(cases) do
            assert.equal(expected, BloodTypes.roll(rng(value)), "roll " .. value)
        end
    end)

    it("accepts only the eight save-format strings", function()
        assert.is_true(BloodTypes.isValid("AB-"))
        assert.is_false(BloodTypes.isValid("PENDING"))
        assert.is_false(BloodTypes.isValid("A_POS"))
        assert.is_false(BloodTypes.isValid(nil))
    end)
end)

describe("Schema", function()
    it("creates a state with every section, the current version and a rolled blood type", function()
        local state = Schema.new(rng(1))
        assert.equal(Schema.VERSION, state.version)
        for _, name in ipairs(Schema.SECTIONS) do
            assert.equal("table", type(state[name]), name)
        end
        assert.equal("O-", state.identity.bloodType)
        assert.equal("new", state.meta.createdAs)
    end)

    it("lists exactly the state's sections", function()
        local state = Schema.new(rng(1))
        local listed = {}
        for _, name in ipairs(Schema.SECTIONS) do listed[name] = true end
        for key in pairs(state) do
            if key ~= "version" then
                assert.truthy(listed[key], key .. " is not in SECTIONS")
            end
        end
        assert.equal(count(state) - 1, #Schema.SECTIONS)
    end)

    it("stores only plain data, so modData and the network keep it intact", function()
        local function check(value, path)
            local kind = type(value)
            assert.truthy(kind == "table" or kind == "string" or kind == "number" or kind == "boolean", path)
            if kind == "table" then
                assert.is_nil(getmetatable(value), path)
                for k, v in pairs(value) do
                    assert.equal("string", type(k), path .. " has a non-string key")
                    check(v, path .. "." .. k)
                end
            end
        end
        check(Schema.new(rng(1)), "state")
    end)

    it("upgrades through a migration chain, one version at a time", function()
        local migrations = {
            [1] = function(state) state.blood = { volume = 5000 } end,
            [2] = function(state) state.blood.volumeMl = state.blood.volume; state.blood.volume = nil end,
        }
        local state = { version = 1, identity = {} }
        local ok = Schema.upgrade(state, migrations, 3)
        assert.is_true(ok)
        assert.equal(3, state.version)
        assert.same({ volumeMl = 5000 }, state.blood)
        -- Already current: nothing runs.
        assert.is_true((Schema.upgrade(state, migrations, 3)))
    end)

    it("refuses states it can't upgrade and leaves them untouched", function()
        local newer = { version = 99, identity = { bloodType = "A+" } }
        local ok, err = Schema.upgrade(newer, {}, 1)
        assert.is_false(ok)
        assert.truthy(assert(err):find("newer", 1, true))
        assert.equal(99, newer.version)
        assert.is_false((Schema.upgrade({}, {}, 1)))
        assert.is_false((Schema.upgrade({ version = 1 }, {}, 2)))
    end)

    it("has a migration for every version below the current one", function()
        for v = 1, Schema.VERSION - 1 do
            assert.equal("function", type(Schema.MIGRATIONS[v]), "missing migration from " .. v)
        end
    end)

    it("fills missing sections and fields without overwriting existing ones", function()
        local state = { version = Schema.VERSION, identity = { bloodType = "B-" }, knowledge = { diseases = { tetanus = true } } }
        Schema.fillDefaults(state)
        assert.equal("B-", state.identity.bloodType)
        assert.same({ tetanus = true }, state.knowledge.diseases)
        assert.is_false(state.knowledge.wildPlants)
        assert.equal(75, state.immunity.score)
        assert.equal("new", state.meta.createdAs)
    end)
end)

describe("Importer detection", function()
    it("detects any EHR_ key, including knowledge-only characters the original's check missed", function()
        assert.is_true(Importer.hasOldData(Fixtures.veteran()))
        assert.is_true(Importer.hasOldData(Fixtures.flyerOnly()))
        assert.is_true(Importer.hasOldData({ EHR_Radio = { heardEffects = {} } }))
        assert.is_false(Importer.hasOldData({}))
        assert.is_false(Importer.hasOldData({ bathroomNeed = 1, ExtensiveHealthRedone = {} }))
    end)

    it("detects each of the original's 14 marker keys", function()
        local markers = { "EHR_Initialized", "EHR_Blood", "EHR_Disease", "EHR_MedicalJournal", "EHR_Sepsis",
            "EHR_WoundInfections", "EHR_WoundInfection", "EHR_WoundInfection_V2_Initialized", "EHR_Medication",
            "EHR_Medications", "EHR_Immunity", "EHR_Temperature", "EHR_Corpse", "EHR_CorpseSickness" }
        for _, key in ipairs(markers) do
            assert.is_true(Importer.hasOldData({ [key] = {} }), key)
        end
    end)

    it("treats a dead character's data as no data", function()
        assert.is_false(Importer.hasOldData(Fixtures.dead()))
    end)
end)

describe("Importer.run", function()
    local function import(modData)
        local state = Schema.new(rng(1))
        local report = Importer.run(modData, state)
        return state, report
    end

    it("carries over permanent identity", function()
        local modData = Fixtures.veteran()
        local state, report = import(modData)
        assert.is_true(report.imported)
        assert.equal("A+", state.identity.bloodType)
        assert.equal("kept", report.bloodType)
        assert.same({
            common_cold = true, tetanus = true, hyperkeratotic_scabies = true, knox_infection = true,
            pneumonia = true, heat_stroke = true,
        }, state.knowledge.diseases)
        assert.is_true(state.knowledge.knoxHerald)
        assert.is_true(state.knowledge.wildPlants)
        assert.equal("ehrdoctor", state.knowledge.professionGrant)
        assert.same({ ["3:9:XP:4"] = true, ["3:21:KNOW:tetanus"] = true }, state.knowledge.radioHeard)
        assert.equal(63.4, state.immunity.score)
        assert.is_true(state.knox.geneTherapyImmune)
        assert.is_true(state.knox.immunityTraitGranted)
        assert.is_true(state.knox.patientZeroTraitSource)
        -- Active Knox item state is reset, never imported.
        assert.equal(0, state.knox.phalanxUses)
        assert.equal(0, state.knox.boosterCooldown)
        assert.equal("imported", state.meta.createdAs)
        assert.equal("ExtensiveHealthReworkEvolved", state.meta.importedFrom)
        assert.same({ "Mystery" }, report.unknownKnowledge)
    end)

    it("resets active state: the result has only schema fields", function()
        local state = import(Fixtures.veteran())
        -- Fields a fresh state has, plus the optional ones that start out nil.
        local allowed = Schema.defaults()
        allowed.meta.importedFrom = true
        allowed.identity.bloodType = true
        allowed.knowledge.professionGrant = true
        for key, section in pairs(state) do
            if key ~= "version" then
                assert.truthy(allowed[key], key .. " is not a schema section")
                for field in pairs(section --[[@as table]]) do
                    assert.truthy(allowed[key][field] ~= nil, key .. "." .. field .. " is not a schema field")
                end
            end
        end
    end)

    it("removes every EHR_ key and leaves other mods' keys alone", function()
        local modData = Fixtures.veteran()
        local _, report = import(modData)
        assert.same({}, Importer.oldKeys(modData))
        assert.equal(19, report.removedKeys)
        assert.equal(35, modData.bathroomNeed)
        assert.equal(1200.0, modData.lastBath)
        assert.is_true(modData.SomeOtherMod_Flag)
    end)

    it("never runs twice: afterwards there is nothing to detect", function()
        local modData = Fixtures.veteran()
        import(modData)
        assert.is_false(Importer.hasOldData(modData))
    end)

    it("normalises knowledge ids like the original did", function()
        local state = import(Fixtures.flyerOnly())
        assert.same({ common_cold = true }, state.knowledge.diseases)
        assert.equal("heat_stroke", Importer.normalizeKnowledgeId("Heat Stroke"))
        assert.equal("cadaveric_aspergillosis", Importer.normalizeKnowledgeId("Cadaveric_Aspergillosis"))
        assert.is_nil(Importer.normalizeKnowledgeId("painkiller_addiction"))
        assert.is_nil(Importer.normalizeKnowledgeId(42))
    end)

    it("rolls a blood type for PENDING, refuses Knox knowledge without the Herald, tolerates partial tables", function()
        local state, report = import(Fixtures.pending())
        assert.equal("rolled", report.bloodType)
        assert.equal("O-", state.identity.bloodType)
        assert.same({}, state.knowledge.diseases)
        assert.same({ "knox_infection (no Herald)" }, report.unknownKnowledge)
        assert.equal(75, state.immunity.score)
        assert.is_false(state.knox.geneTherapyImmune)
    end)

    it("imports nothing from a dead character but still cleans up", function()
        local modData = Fixtures.dead()
        local state, report = import(modData)
        assert.is_false(report.imported)
        assert.equal("O-", state.identity.bloodType)
        assert.same({}, state.knowledge.diseases)
        assert.equal("new", state.meta.createdAs)
        assert.same({}, Importer.oldKeys(modData))
    end)

    it("clamps an out-of-range immunity score and ignores a non-number", function()
        local state = import({ EHR_Immunity = { score = 140 } })
        assert.equal(100, state.immunity.score)
        state = import({ EHR_Immunity = { score = "high" } })
        assert.equal(75, state.immunity.score)
    end)

    it("accepts the string 'true' for flags, as a defensive reading", function()
        local state = import({ EHR_MedicalWildPlantsKnown = "true", EHR_KnownDiseases = { tetanus = "true" } })
        assert.is_true(state.knowledge.wildPlants)
        assert.same({ tetanus = true }, state.knowledge.diseases)
    end)
end)
