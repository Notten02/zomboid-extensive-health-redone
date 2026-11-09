-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Gangrene (Diseases/Extremities/Gangrene): onset from a part held at trench foot or frostbite stage 4, more parts
-- joining, its effects, the sepsis hand-off, antibiotic cures, amputation and what it holds in place.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Group = require("ExtensiveHealthRedone/Diseases/Extremities/Group")
local Gangrene = require("ExtensiveHealthRedone/Diseases/Extremities/Gangrene")
local Parts = require("ExtensiveHealthRedone/Diseases/Extremities/Parts")
local Meters = require("ExtensiveHealthRedone/Diseases/Extremities/Meters")
local Data = require("ExtensiveHealthRedone/Diseases/Extremities/Data")
local MedData = require("ExtensiveHealthRedone/Medication/Data")
local Sim = require("support/sim")

local function context(opts)
    local p = Sim.context(opts)
    p.facts.env.airC = 8
    p.facts.extremities = {
        windChillC = 8,
        socks = { wet = 0.8, holes = 0 },
        shoes = { wet = 1, holes = 0, wear = 1, waterRes = 0 },
        parts = { Hand_L = { skinC = 30, insulation = 0 }, Hand_R = { skinC = 30, insulation = 0 },
            Foot_L = { skinC = 20, insulation = 0 }, Foot_R = { skinC = 20, insulation = 0 } },
    }
    return p
end

local function step(p, dt)
    Sim.step(p)
    for _, system in ipairs(Group.systems) do
        system.update(p, dt, defs)
    end
    Engine.step(p, defs, dt)
end

local function run(p, minutes)
    for _ = 1, minutes do
        step(p, 1)
    end
end

local function active(p, id)
    return p.state.conditions.active[id]
end

-- Trench foot at stage 4 on both feet, kept soaked.
local function necrotic(opts)
    local p = context(opts)
    local c = Engine.contract(p, defs, "trench_foot", { stage = 4, source = "Foot_L" })
    for _, foot in ipairs({ "Foot_L", "Foot_R" }) do
        Parts.setStage(p, c, foot, 4)
        Meters.set(p, foot, "wetColdH", 72)
    end
    return p, c
end

describe("gangrene onset", function()
    it("starts on a foot held at trench foot stage 4 for the onset hours, both feet joining", function()
        local p = necrotic()
        run(p, 24 * 60 - 5)
        assert.is_nil(active(p, "gangrene"))
        run(p, 10)
        local g = active(p, "gangrene")
        assert.truthy(g)
        assert.equal(1, Parts.stage(g, "Foot_L"))
        assert.equal(1, Parts.stage(g, "Foot_R"))
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_GangreneBlackening"))
    end)

    it("follows the sandbox onset hours, and stays off when disabled", function()
        local p = necrotic({ sandbox = { GangreneOnsetHours = 6 } })
        run(p, 6 * 60 + 2)
        assert.truthy(active(p, "gangrene"))
        p = necrotic({ sandbox = { GangreneEnabled = false } })
        run(p, 30 * 60)
        assert.is_nil(active(p, "gangrene"))
    end)

    it("starts the count over when the foot leaves stage 4", function()
        -- Necrosis keeps counting on a dry foot, so give recovery the time to win.
        local p, c = necrotic({ sandbox = { GangreneOnsetHours = 168 } })
        run(p, 12 * 60)
        assert.truthy(Parts.get(c, "Foot_L").necrosis)
        p.facts.extremities.socks.wet = 0
        p.facts.extremities.shoes.wet = 0
        run(p, Data.trenchFoot.DRY_H[4] * 60 + 1)
        assert.equal(3, Parts.stage(c, "Foot_L"))
        assert.is_nil(Parts.get(c, "Foot_L").necrosis)
    end)
end)

describe("gangrene course", function()
    local function gangrenous(stage, opts)
        local p = context(opts)
        Gangrene.start(p, defs, "Foot_L")
        local g = active(p, "gangrene")
        if stage > 1 then
            Engine.setStage(p, defs, "gangrene", stage)
        end
        return p, g
    end

    it("hurts and damages each gangrenous part and stops it healing, then brings fever", function()
        local p = gangrenous(1)
        step(p, 60)
        assert.truthy(p.body.pains.Foot_L.gangrene)
        assert.truthy(p.body.partDamages.Foot_L)
        assert.equal(0, p.body.heal.Foot_L)
        p = gangrenous(3)
        step(p, 1)
        assert.truthy(p.stats:resolve("SICKNESS", 0) > 0)
    end)

    it("turns into sepsis at stage 4 untreated, and waits while sepsis can't start", function()
        local p = gangrenous(1)
        Engine.contract(p, defs, "sepsis", { source = "test" })
        Engine.setStage(p, defs, "gangrene", 4)
        step(p, 1)
        assert.truthy(active(p, "gangrene"), "sepsis already running: gangrene waits")
        Engine.finish(p, defs, "sepsis", "debug")
        step(p, 1)
        assert.is_nil(active(p, "gangrene"))
        assert.truthy(active(p, "sepsis"))
        assert.equal("Foot_L", active(p, "sepsis").source)
    end)

    it("holds its stage while a curative course runs", function()
        local p = gangrenous(2, { treatment = { curing = { gangrene = true } } })
        local before = active(p, "gangrene").stage
        run(p, 72 * 60)
        assert.equal(before, active(p, "gangrene").stage)
    end)

    it("is cured by the antibiotic courses, and helped by antibiotics and anti-inflammatories", function()
        for _, t in ipairs({ "ExtensiveHealth.PrescriptionAntibiotics", "ExtensiveHealth.BroadSpectrumAntibiotics",
            "ExtensiveHealth.PlantBasedAntibiotics", "ExtensiveHealth.IVAntibiotics", "ExtensiveHealth.IVVancomycin" }) do
            assert.truthy(MedData.byType[t].cures.gangrene, t)
        end
        local function treats(t)
            for _, id in ipairs(MedData.byType[t].treats) do
                if id == "gangrene" then return true end
            end
            return false
        end
        assert.is_true(treats("Base.Antibiotics"))
        assert.is_true(treats("ExtensiveHealth.AntiInflammatory"))
    end)

    it("blocks a new case for a while after a cure, and lets the necrosis count start over", function()
        local p, tf = necrotic()
        run(p, 24 * 60 + 2)
        assert.truthy(active(p, "gangrene"))
        Engine.cure(p, defs, "gangrene")
        assert.is_nil(Parts.get(tf, "Foot_L").necrosis)
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_GangreneStopped"))
        run(p, 30 * 60)
        assert.is_nil(active(p, "gangrene"), "blocked for 48 h")
    end)

    it("lands a debug start on the left foot", function()
        local p = context()
        Engine.contract(p, defs, "gangrene", { source = Gangrene.debugSource })
        step(p, 1)
        assert.equal(1, Parts.stage(active(p, "gangrene"), "Foot_L"))
    end)
end)

describe("gangrene and amputation", function()
    it("drops a cut part, and the last part gone cures it with XP only for a cut EHR saw happen", function()
        local p = context()
        Gangrene.start(p, defs, "Hand_L")
        Gangrene.start(p, defs, "Foot_L")
        Gangrene.dropPart(p, defs, "Hand_L", true)
        local g = active(p, "gangrene")
        assert.truthy(g)
        assert.equal("Foot_L", g.source)
        Gangrene.dropPart(p, defs, "Foot_L", true)
        assert.is_nil(active(p, "gangrene"))
        assert.same({ { "cure", "gangrene" } }, p.xps)
        p = context()
        Gangrene.start(p, defs, "Hand_R")
        Gangrene.dropPart(p, defs, "Hand_R", false)
        assert.is_nil(active(p, "gangrene"))
        assert.same({}, p.xps)
    end)
end)
