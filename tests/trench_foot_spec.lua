-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Trench foot (Diseases/Extremities/TrenchFoot): hours of cold, wet feet, the stages and their effects, recovery on
-- dry feet, foot powder, warmth, the wet feet Monitor row and First Aid XP.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Group = require("ExtensiveHealthRedone/Diseases/Extremities/Group")
local TrenchFoot = require("ExtensiveHealthRedone/Diseases/Extremities/TrenchFoot")
local Meters = require("ExtensiveHealthRedone/Diseases/Extremities/Meters")
local Parts = require("ExtensiveHealthRedone/Diseases/Extremities/Parts")
local Data = require("ExtensiveHealthRedone/Diseases/Extremities/Data")
local Monitor = require("ExtensiveHealthRedone/UI/Monitor")
local Sim = require("support/sim")

local D = Data.trenchFoot
local HOURS = 12

local function context(opts)
    local p = Sim.context(opts)
    p.facts.env.airC = 8
    p.facts.extremities = {
        windChillC = 8,
        socks = { wet = 0, holes = 0 },
        shoes = { wet = 0, holes = 0, wear = 1, waterRes = 0 },
        parts = { Hand_L = { skinC = 30, insulation = 0 }, Hand_R = { skinC = 30, insulation = 0 },
            Foot_L = { skinC = 28, insulation = 0 }, Foot_R = { skinC = 28, insulation = 0 } },
    }
    return p
end

local function wet(p, share)
    p.facts.extremities.socks.wet = share
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

local function trench(p)
    return p.state.conditions.active.trench_foot
end

local function meter(p, foot)
    return Meters.value(p, foot or "Foot_L", "wetColdH")
end

-- A trench foot case at a stage on both feet, with the meter at that stage's threshold.
local function stricken(stage, opts)
    local p = context(opts)
    local c = Engine.contract(p, defs, "trench_foot", { stage = stage, source = "Foot_L" })
    for _, foot in ipairs({ "Foot_L", "Foot_R" }) do
        Parts.setStage(p, c, foot, stage)
        Meters.set(p, foot, "wetColdH", D.STAGE_X[stage] * HOURS)
    end
    return p, c
end

describe("trench foot exposure", function()
    it("builds on damp feet in cool air, not on dry feet or in warm air", function()
        local p = context()
        run(p, 60)
        assert.equal(0, meter(p))
        wet(p, 0.4)
        run(p, 60)
        assert.near(1, meter(p), 1e-6)
        p.facts.env.airC = 20
        run(p, 60)
        assert.near(1, meter(p), 1e-6, "too warm for trench foot")
    end)

    it("builds faster soaked, slower under foot powder, and powder helps little when soaked", function()
        local p = context()
        wet(p, 0.4)
        assert.equal(1, TrenchFoot.gain(p))
        wet(p, 0.8)
        assert.equal(D.SOAKED_MULT, TrenchFoot.gain(p))
        p = context({ treatment = { active = { footPowder = true } } })
        wet(p, 0.4)
        assert.equal(D.POWDER, TrenchFoot.gain(p))
        wet(p, 0.8)
        assert.near(D.SOAKED_MULT * D.POWDER_SOAKED, TrenchFoot.gain(p), 1e-9)
    end)

    it("reads the shoes without socks, and follows the sandbox", function()
        local p = context({ sandbox = { TrenchFootExposureMultiplier = 2, TrenchFootMaxTemperature = 5 } })
        p.facts.extremities.socks = nil
        p.facts.extremities.shoes.wet = 0.9
        p.facts.env.airC = 4
        assert.equal(2 * D.SOAKED_MULT, TrenchFoot.gain(p))
        p.facts.env.airC = 6
        assert.equal(0, TrenchFoot.gain(p))
    end)

    it("falls on dry feet, faster warm and resting", function()
        local p = context()
        Meters.set(p, "Foot_L", "wetColdH", 5)
        p.facts.env.moving = true
        run(p, 60)
        assert.near(5 - D.DECAY, meter(p), 1e-6)
        p.facts.env.moving = false
        p.facts.env.indoors = true
        p.facts.env.airC = 20
        run(p, 60)
        assert.near(5 - D.DECAY - D.DECAY_WARM_REST, meter(p), 1e-6)
    end)

    it("shows the worst foot's share of stage 1 as the wet feet meter, hidden once trench foot runs", function()
        local p = context()
        wet(p, 0.5)
        run(p, HOURS * 60 / 2)
        assert.equal(50, p.state.exposure.feet)
        local feet
        for _, meter in ipairs(Monitor.EXPOSURE) do
            if meter.id == "feet" then
                feet = meter
            end
        end
        assert.same({ "trench_foot" }, feet.hiddenBy)
    end)
end)

describe("trench foot stages", function()
    it("starts after TrenchFootHours of cold, wet feet, on both feet", function()
        local p = context()
        wet(p, 0.5)
        run(p, HOURS * 60 + 1)
        local c = trench(p)
        assert.truthy(c)
        assert.equal(1, c.stage)
        assert.equal(1, Parts.stage(c, "Foot_R"))
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_FeetColdAndNumb"))
    end)

    it("worsens at 2x, 4x and 6x the onset hours", function()
        local p = context()
        for stage, x in ipairs(D.STAGE_X) do
            assert.equal(stage, TrenchFoot.stageFor(p, x * HOURS))
            assert.equal(stage - 1, TrenchFoot.stageFor(p, x * HOURS - 0.01))
        end
    end)

    it("hurts and slows, stops sprinting and breaks the skin from stage 3, damages the foot at stage 4", function()
        local p = stricken(3)
        step(p, 1)
        assert.equal(D.PAIN[3], p.body.pains.Foot_L.trench_foot)
        assert.equal(D.SPEED[3], p.fx.values.speed)
        assert.is_true(p.fx.values.noSprint)
        assert.equal(D.HEAL_FACTOR, p.body.heal.Foot_L)
        local scratched = false
        for _ = 1, D.MACERATION_H * 60 do
            step(p, 1)
            scratched = scratched or (p.body.scratches ~= nil and p.body.scratches.Foot_L == "trench_foot")
        end
        assert.is_true(scratched)
        p = stricken(4)
        step(p, 60)
        assert.truthy(p.body.partDamages.Foot_L)
    end)
end)

describe("trench foot recovery", function()
    it("recovers a stage per stretch of dry feet, faster resting and warm", function()
        local p = stricken(2)
        p.facts.env.moving = true
        run(p, D.DRY_H[2] * 60 + 1)
        assert.equal(1, Parts.stage(trench(p), "Foot_L"))
        assert.equal(TrenchFoot.recoveryRate(p), 1)
        p.facts.env.moving = false
        p.facts.env.indoors = true
        p.facts.env.airC = 20
        assert.near(D.REST * D.WARM, TrenchFoot.recoveryRate(p), 1e-9)
        p.facts.env.airC = 5
        assert.near(D.REST, TrenchFoot.recoveryRate(p), 1e-9, "a cold room isn't warm")
    end)

    it("counts a Warming Pack and foot powder", function()
        local p = context({ treatment = { active = { footPowder = true } } })
        p.facts.env.moving = true
        assert.near(D.POWDER_HEAL, TrenchFoot.recoveryRate(p), 1e-9)
        p = context()
        p.facts.env.moving = true
        p.state.meds.effects.warming = { left = 60 }
        assert.near(D.WARM, TrenchFoot.recoveryRate(p), 1e-9)
        p = context({ sandbox = { BodyTemperatureEnabled = false } })
        p.facts.env.moving = true
        p.state.meds.effects.warming = { left = 60 }
        assert.equal(1, TrenchFoot.recoveryRate(p), "the pack does nothing with body temperature off")
    end)

    it("stops recovering on wet feet and starts the count over", function()
        local p = stricken(2)
        p.facts.env.moving = true
        run(p, D.DRY_H[2] * 60 / 2)
        assert.near(D.DRY_H[2] / 2, trench(p).data.parts.Foot_L.dry, 1e-6)
        wet(p, 0.5)
        step(p, 1)
        assert.equal(0, trench(p).data.parts.Foot_L.dry)
    end)

    it("ends after the feet stay dry, with XP only after a real case", function()
        local p = stricken(2)
        p.facts.env.moving = true
        run(p, (D.DRY_H[2] + D.DRY_H[1]) * 60 + 2)
        assert.is_nil(trench(p))
        assert.same({ { "cure", "trench_foot" } }, p.xps)
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_FeetWarmAgain"))
        p = stricken(1)
        p.facts.env.moving = true
        run(p, D.DRY_H[1] * 60 + 2)
        assert.is_nil(trench(p))
        assert.same({}, p.xps)
    end)

    it("holds a gangrenous foot at stage 4", function()
        local p = stricken(4)
        require("ExtensiveHealthRedone/Diseases/Extremities/Gangrene").start(p, defs, "Foot_L")
        p.facts.env.moving = false
        p.facts.env.indoors = true
        p.facts.env.airC = 20
        run(p, D.DRY_H[4] * 60)
        assert.equal(4, Parts.stage(trench(p), "Foot_L"))
        assert.is_true(Parts.stage(trench(p), "Foot_R") < 4, "the other foot recovers")
    end)

    it("starts over after a full heal", function()
        local p = stricken(2)
        Engine.finish(p, defs, "trench_foot", "admin")
        assert.equal(0, meter(p))
    end)

    it("lands a debug start on the left foot", function()
        local p = context()
        Engine.contract(p, defs, "trench_foot", { source = TrenchFoot.debugSource })
        step(p, 1)
        assert.equal(1, Parts.stage(trench(p), "Foot_L"))
    end)
end)
