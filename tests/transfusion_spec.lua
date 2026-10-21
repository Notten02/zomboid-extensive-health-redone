-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Blood types, transfusion outcomes, blood draw and blood bag spoilage (Blood/Transfusion, Blood/Spoilage).
local Transfusion = require("ExtensiveHealthRedone/Blood/Transfusion")
local Spoilage = require("ExtensiveHealthRedone/Blood/Spoilage")
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Sim = require("support/sim")

local function patient(bloodType, volume, opts)
    local p = Sim.context(opts)
    p.state.identity.bloodType = bloodType
    p.state.blood.volume = volume or 3000
    return p
end

describe("Transfusion", function()
    it("follows ABO/Rh donor rules", function()
        for _, recipient in ipairs({ "O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+" }) do
            assert.is_true(Transfusion.compatible("O-", recipient), "O- gives to " .. recipient)
            assert.is_true(Transfusion.compatible(recipient, "AB+"), "AB+ takes " .. recipient)
        end
        assert.is_false(Transfusion.compatible("B-", "A+"))
        assert.is_false(Transfusion.compatible("O+", "O-"))
        assert.is_true(Transfusion.compatible("A-", "AB-"))
    end)

    it("shows compatibility only with the Blood Types flyer or First Aid 8", function()
        assert.is_false(Transfusion.knowsTypes({ diseases = {} }, 7))
        assert.is_true(Transfusion.knowsTypes({ diseases = {} }, 8))
        assert.is_true(Transfusion.knowsTypes({ diseases = { blood_types = true } }, 0))
    end)

    it("adds 500 mL of compatible blood, and refuses a bag at full blood or a rotten one", function()
        local p = patient("A+")
        assert.is_nil(Transfusion.refusal(p.state, "ExtensiveHealth.BloodBagOPos", "fresh"))
        assert.equal("compatible", Transfusion.apply(p, defs, "ExtensiveHealth.BloodBagOPos", "fresh"))
        assert.equal(3500, p.state.blood.volume)
        assert.equal("UI_EHR_Transfusion_BloodSpoiledDesc",
            Transfusion.refusal(p.state, "ExtensiveHealth.BloodBagOPos", "rotten"))
        p.state.blood.volume = 5000
        assert.equal("UI_EHR_Transfusion_BloodFull",
            Transfusion.refusal(p.state, "ExtensiveHealth.BloodBagOPos", "fresh"))
        assert.equal("UI_EHR_Transfusion_Unusable", Transfusion.refusal(p.state, "Base.Apple", "fresh"))
    end)

    it("reacts to incompatible blood on each stat's own scale, and starts AHTR", function()
        local p = patient("O-")
        assert.equal("ahtr", Transfusion.apply(p, defs, "ExtensiveHealth.BloodBagABPos", "fresh"))
        assert.equal(2850, p.state.blood.volume)
        assert.near(12, Sim.resolve(p, "PAIN", 0), 1e-9)          -- 0-100 scale, not clamped to 1
        assert.near(35, Sim.resolve(p, "PANIC", 0), 1e-9)
        assert.near(0.18, Sim.resolve(p, "SICKNESS", 0), 1e-9)
        assert.is_true(p.state.conditions.active.ahtr.severity >= 0.95)
    end)

    it("worsens an active AHTR and keeps at least 72 hours of it left", function()
        local p = patient("O-")
        Transfusion.apply(p, defs, "ExtensiveHealth.BloodBagABPos", "fresh")
        local c = p.state.conditions.active.ahtr
        c.stage, c.left = 4, 60
        local severity = c.severity
        assert.equal("worsened", Transfusion.apply(Sim.step(p), defs, "ExtensiveHealth.BloodBagAPos", "fresh"))
        assert.near(math.min(1.25, severity + 0.25), c.severity, 1e-9)
        assert.near(72 * 60, Engine.minutesLeft(c), 1e-6)
    end)

    it("respects AHTREnabled for a new reaction", function()
        local p = patient("O-", 3000, { sandbox = { AHTREnabled = false } })
        assert.equal("reaction", Transfusion.apply(p, defs, "ExtensiveHealth.BloodBagABPos", "fresh"))
        assert.is_nil(p.state.conditions.active.ahtr)
    end)

    it("adds a spoiled-blood reaction for a stale bag", function()
        local p = patient("A+")
        Transfusion.apply(p, defs, "ExtensiveHealth.BloodBagAPos", "stale")
        assert.equal(3350, p.state.blood.volume)
        assert.near(39, p.state.temperature.fever, 1e-9)       -- a held fever spike of +2 (Body/Temperature)
        assert.equal("staleBlood", p.state.temperature.source)
        local damaged = 0
        for _, hp in pairs(p.body.partDamages) do
            damaged = damaged + hp
        end
        assert.is_true(damaged >= 40)
        assert.is_true(Sim.said(p, "UI_EHR_Text_ThatBloodTastedOff"))
    end)

    it("counts saline only for the volume it actually added", function()
        local p = patient("A+", 4900)
        assert.equal("saline", Transfusion.apply(p, defs, "ExtensiveHealth.SalineBag", "fresh"))
        assert.equal(5000, p.state.blood.volume)
        assert.equal(100, p.state.blood.saline)
    end)

    it("draws 500 mL into a bag of the donor's type, from 80 % blood", function()
        local p = patient("B-", 3900)
        assert.equal("UI_EHR_Transfusion_NotEnoughBloodSafe", Transfusion.drawRefusal(p.state))
        p.state.blood.volume = 4000
        assert.is_nil(Transfusion.drawRefusal(p.state))
        assert.equal("ExtensiveHealth.BloodBagBNeg", Transfusion.draw(p))
        assert.equal(3500, p.state.blood.volume)
    end)
end)

describe("Blood bag spoilage", function()
    it("turns stale after 1 warm hour and rotten after 2, and stays rotten", function()
        local data = Spoilage.new(100)
        assert.equal("fresh", (Spoilage.update(data, 100.5, false)))
        assert.equal("stale", (Spoilage.update(data, 101.5, false)))
        assert.is_true(data.stale)
        assert.equal("rotten", (Spoilage.update(data, 102.1, false)))
        assert.equal("rotten", (Spoilage.update(data, 102.2, true)))
    end)

    it("doesn't count time while frozen", function()
        local data = Spoilage.new(0)
        Spoilage.update(data, 0.5, false)
        assert.equal("fresh", (Spoilage.update(data, 50, true)))
        assert.equal("stale", (Spoilage.update(data, 51, false)))
    end)

    it("treats a bag without data (loot) as fresh from now, and peeks without changing anything", function()
        local state, data = Spoilage.update(nil, 10, false)
        assert.equal("fresh", state)
        assert.equal(10, data.createdHour)
        assert.equal("stale", (Spoilage.peek(data, 11.2, false)))
        assert.equal(10, data.lastCheckHour)
        assert.near(0.8, Spoilage.hoursLeft(data, 10.2, false) --[[@as number]], 1e-9)
        assert.is_nil((Spoilage.hoursLeft(data, 10.2, true)))
    end)

    it("reads v0.9 bag data unchanged", function()
        local old = { createdHour = 5, lastCheckHour = 5, warmElapsed = 1.5, stale = true, rotten = false,
            isFrozen = false }
        assert.equal("stale", (Spoilage.update(old, 5.2, false)))
        assert.near(1.7, old.warmElapsed, 1e-9)
    end)
end)
