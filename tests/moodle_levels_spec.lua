-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Moodle levels (UI/MoodleLevels) from the mirrored state: the Medical Alert and the four exposure moodles.
local MoodleLevels = require("ExtensiveHealthRedone/UI/MoodleLevels")

local function conditions(active)
    return { active = active }
end

describe("moodle levels", function()
    it("hide everything for a healthy character, also before the first sync", function()
        for _, id in ipairs(MoodleLevels.ORDER) do
            assert.equal(0, MoodleLevels.compute(nil)[id].level, id)
            assert.equal(MoodleLevels.TITLES[id], MoodleLevels.compute({})[id].title)
        end
    end)

    it("raise the Medical Alert to the worst condition stage, sepsis one higher", function()
        local m = MoodleLevels.compute({ conditions = conditions({ common_cold = { stage = 2 } }) }).medical
        assert.equal(2, m.level)
        assert.equal("UI_EHR_Moodle_MedicalAlert_Desc", m.desc.key)
        m = MoodleLevels.compute({ conditions = conditions({ common_cold = { stage = 2 }, sepsis = { stage = 3 } }) })
            .medical
        assert.equal(4, m.level)
        assert.equal("UI_EHR_Moodle_MedicalAlert_Multiple", m.desc.key)
    end)

    it("count infected wounds by stage, not incubating ones", function()
        local wounds = { parts = { Hand_L = { phase = "incubating", left = 60 } } }
        assert.equal(0, MoodleLevels.compute({ wounds = wounds }).medical.level)
        wounds.parts.Hand_R = { phase = "infected", stage = 3 }
        assert.equal(3, MoodleLevels.compute({ wounds = wounds }).medical.level)
    end)

    it("show side effects at 1 for one and 2 for several", function()
        local meds = { side = { nausea = { left = 10 } } }
        local m = MoodleLevels.compute({ meds = meds }).medical
        assert.equal(1, m.level)
        assert.equal("UI_EHR_Moodle_MedicalAlert_SideEffects", m.desc.key)
        meds.side.headache = { left = 10 }
        assert.equal(2, MoodleLevels.compute({ meds = meds }).medical.level)
    end)

    it("never reveal a fresh Knox infection; a symptomatic one counts at its stage", function()
        assert.equal(0, MoodleLevels.compute({ conditions = conditions({ knox_infection = { stage = 1 } }) })
            .medical.level)
        assert.equal(2, MoodleLevels.compute({ conditions = conditions({ knox_infection = { stage = 2 } }) })
            .medical.level)
    end)

    it("grade the corpse meter by its bands, the hourly risk and certainty", function()
        local function corpse(v) return MoodleLevels.compute({ exposure = { corpse = v } }).corpse.level end
        assert.equal(0, corpse(29))
        assert.equal(1, corpse(30))
        assert.equal(2, corpse(60))
        assert.equal(3, corpse(85))
        assert.equal(4, corpse(100))
    end)

    it("grade spores, and hide them once aspergillosis runs", function()
        local function spores(v, active)
            return MoodleLevels.compute({ exposure = { spores = v }, conditions = conditions(active or {}) })
                .cadaveric.level
        end
        assert.equal(0, spores(0))
        assert.equal(1, spores(1))
        assert.equal(2, spores(72))
        assert.equal(3, spores(102))
        assert.equal(4, spores(120))
        assert.equal(0, spores(120, { cadaveric_aspergillosis = { stage = 1 } }))
    end)

    it("grade heat by the meter share, at 4 during heat stroke", function()
        local function heat(v, active)
            return MoodleLevels.compute({ exposure = { heat = v }, conditions = conditions(active or {}) }).heat
        end
        assert.equal(0, heat(4).level)
        assert.equal(1, heat(5).level)
        assert.equal(2, heat(50).level)
        assert.equal(3, heat(85).level)
        assert.equal(4, heat(0, { heat_stroke = { stage = 2 } }).level)
        local desc = heat(50).desc
        assert.equal("UI_EHR_Moodle_ExposureLevel_Desc", desc.key)
        assert.equal("UI_EHR_ExposureLevel_Medium", desc.args[1].key)
    end)

    it("grade the cold meter, hidden while a cold or pneumonia runs", function()
        local function cold(v, active)
            return MoodleLevels.compute({ exposure = { cold = v }, conditions = conditions(active or {}) }).cold.level
        end
        assert.equal(1, cold(5))
        assert.equal(3, cold(90))
        assert.equal(0, cold(90, { common_cold = { stage = 1 } }))
        assert.equal(0, cold(90, { pneumonia = { stage = 2 } }))
    end)
end)
