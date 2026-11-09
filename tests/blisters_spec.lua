-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Foot blisters (Diseases/Extremities/Blisters): friction per foot from walking in shoes, the stages, the burst
-- wound, natural healing, blister patches and the Medical Alert threshold.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Group = require("ExtensiveHealthRedone/Diseases/Extremities/Group")
local Blisters = require("ExtensiveHealthRedone/Diseases/Extremities/Blisters")
local Meters = require("ExtensiveHealthRedone/Diseases/Extremities/Meters")
local Parts = require("ExtensiveHealthRedone/Diseases/Extremities/Parts")
local Data = require("ExtensiveHealthRedone/Diseases/Extremities/Data")
local MoodleLevels = require("ExtensiveHealthRedone/UI/MoodleLevels")
local Sim = require("support/sim")

local D = Data.blisters

-- Game minutes of walking in good footwear that build h friction.
local function walking(h)
    return math.ceil(h / D.GAIT.walk * 60)
end

local function context(opts)
    local p = Sim.context(opts)
    p.facts.extremities = {
        windChillC = 20,
        socks = { wet = 0, holes = 0 },
        shoes = { wet = 0, holes = 0, wear = 1, waterRes = 0 },
        parts = { Hand_L = { skinC = 33, insulation = 0 }, Hand_R = { skinC = 33, insulation = 0 },
            Foot_L = { skinC = 33, insulation = 0 }, Foot_R = { skinC = 33, insulation = 0 } },
    }
    return p
end

local function walk(p, how)
    local env = p.facts.env
    env.moving, env.running, env.sprinting = how ~= "rest", how == "run", how == "sprint"
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

local function blisters(p)
    return p.state.conditions.active.foot_blisters
end

local function friction(p, foot)
    return Meters.value(p, foot or "Foot_L", "frictionH")
end

describe("foot blister friction", function()
    it("builds only while walking in shoes", function()
        local p = context()
        walk(p, "rest")
        run(p, 60)
        assert.equal(0, friction(p))
        walk(p, "walk")
        run(p, 60)
        assert.near(D.GAIT.walk, friction(p), 1e-6)
        p.facts.extremities.shoes = nil
        run(p, 60)
        assert.near(D.GAIT.walk, friction(p), 1e-6, "barefoot builds none")
    end)

    it("builds faster running, without socks, in wet socks and in worn or holed shoes", function()
        local function rate(setup)
            local p = context()
            setup(p)
            return Blisters.gain(p, "Foot_L")
        end
        assert.equal(D.GAIT.walk, rate(function(p) walk(p, "walk") end))
        assert.equal(D.GAIT.run, rate(function(p) walk(p, "run") end))
        assert.equal(D.GAIT.sprint, rate(function(p) walk(p, "sprint") end))
        local w = D.GAIT.walk
        assert.equal(w * D.NO_SOCKS, rate(function(p) walk(p, "walk"); p.facts.extremities.socks = nil end))
        assert.equal(w * D.WET_SOCKS, rate(function(p) walk(p, "walk"); p.facts.extremities.socks.wet = 0.5 end))
        assert.equal(w * D.WORN_MULT, rate(function(p) walk(p, "walk"); p.facts.extremities.shoes.wear = 0.4 end))
        assert.equal(w * D.WORN_OUT_MULT,
            rate(function(p) walk(p, "walk"); p.facts.extremities.shoes.wear = 0.1 end))
        assert.equal(w * D.SHOE_HOLES, rate(function(p) walk(p, "walk"); p.facts.extremities.shoes.holes = 1 end))
        assert.equal(w * D.SOCK_HOLES, rate(function(p) walk(p, "walk"); p.facts.extremities.socks.holes = 2 end))
    end)

    it("builds much slower with a blister patch or a clean bandage on the foot", function()
        local p = context({ treatment = { active = { blisterPatch = true } } })
        walk(p, "walk")
        assert.near(D.GAIT.walk * D.PATCH, Blisters.gain(p, "Foot_L"), 1e-9)
        p = context()
        walk(p, "walk")
        p.facts.parts.Foot_R.bandaged = true
        assert.near(D.GAIT.walk * D.BANDAGE, Blisters.gain(p, "Foot_R"), 1e-9)
        p.facts.parts.Foot_R.bandageDirty = true
        assert.equal(D.GAIT.walk, Blisters.gain(p, "Foot_R"))
    end)

    it("follows the sandbox multiplier, and stops when disabled", function()
        local p = context({ sandbox = { FootBlistersFrictionMultiplier = 2 } })
        walk(p, "walk")
        assert.equal(D.GAIT.walk * 2, Blisters.gain(p, "Foot_L"))
        p = context({ sandbox = { FootBlistersEnabled = false } })
        walk(p, "sprint")
        run(p, 600)
        assert.equal(0, friction(p))
        assert.is_nil(blisters(p))
    end)

    it("falls at rest, faster asleep", function()
        local p = context()
        Meters.set(p, "Foot_L", "frictionH", 2)
        walk(p, "rest")
        run(p, 60)
        assert.near(2 - D.DECAY_REST, friction(p), 1e-6)
        p.facts.asleep = true
        run(p, 30)
        assert.near(2 - D.DECAY_REST - D.DECAY_SLEEP / 2, friction(p), 1e-6)
    end)
end)

describe("foot blister stages", function()
    it("start as a hot spot on both feet, then blister and burst into a scratch", function()
        local p = context()
        walk(p, "walk")
        p.facts.extremities.socks = nil      -- shoes on bare feet: rubs at twice the rate
        local bare = D.NO_SOCKS
        run(p, math.ceil(walking(D.STAGE_H[1]) / bare) + 1)
        local c = blisters(p)
        assert.truthy(c)
        assert.equal(1, c.stage)
        assert.equal(1, Parts.stage(c, "Foot_L"))
        assert.equal(1, Parts.stage(c, "Foot_R"))
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_BlisterHotSpot"))
        run(p, math.ceil(walking(D.STAGE_H[2] - D.STAGE_H[1]) / bare) + 1)
        assert.equal(2, blisters(p).stage)
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_BlisterFormed"))
        -- Step until the foot bursts; the scratch is wished for in that step.
        for _ = 1, math.ceil(walking(D.STAGE_H[3] - D.STAGE_H[2]) / bare) + 1 do
            step(p, 1)
            if Parts.stage(blisters(p), "Foot_L") == 3 then
                break
            end
        end
        assert.equal(3, Parts.stage(blisters(p), "Foot_L"))
        assert.same({ Foot_L = "foot_blisters", Foot_R = "foot_blisters" }, p.body.scratches)
    end)

    it("hurt each blistered foot and slow by the worst one", function()
        local p = context()
        local c = Engine.contract(p, defs, "foot_blisters", { stage = 2, source = "Foot_L" })
        Parts.setStage(p, c, "Foot_L", 2)
        Parts.setStage(p, c, "Foot_R", 1)
        walk(p, "rest")
        step(p, 1)
        assert.equal(D.PAIN[2], p.body.pains.Foot_L.foot_blisters)
        assert.equal(D.PAIN[1], p.body.pains.Foot_R.foot_blisters)
        assert.equal(D.SPEED[2], p.fx.values.speed)
    end)

    it("ease the pain with pain relief", function()
        local p = context({ treatment = { relief = { ["foot_blisters.pain"] = 0.5 } } })
        local c = Engine.contract(p, defs, "foot_blisters", { stage = 2, source = "Foot_L" })
        Parts.setStage(p, c, "Foot_L", 2)
        walk(p, "rest")
        step(p, 1)
        assert.equal(D.PAIN[2] * 0.5, p.body.pains.Foot_L.foot_blisters)
    end)

    it("give no First Aid XP", function()
        local p = context()
        walk(p, "walk")
        run(p, walking(D.STAGE_H[1]) + 1)
        walk(p, "rest")
        run(p, (D.HEAL_H[1] + 1) * 60)
        assert.is_nil(blisters(p))
        assert.same({}, p.xps)
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_FeetFeelBetter"))
    end)
end)

describe("foot blister healing", function()
    local function blistered(opts)
        local p = context(opts)
        local c = Engine.contract(p, defs, "foot_blisters", { stage = 2, source = "Foot_L" })
        Parts.setStage(p, c, "Foot_L", 2)
        Meters.set(p, "Foot_L", "frictionH", D.STAGE_H[2])
        return p, c
    end

    it("heals on its own at rest, no medicine needed", function()
        local p = blistered()
        walk(p, "rest")
        run(p, D.HEAL_H[2] * 60 + 1)
        assert.equal(1, Parts.stage(blisters(p), "Foot_L"))
        run(p, D.HEAL_H[1] * 60 + 1)
        assert.is_nil(blisters(p))
    end)

    it("heals faster asleep", function()
        local p = blistered()
        walk(p, "rest")
        p.facts.asleep = true
        run(p, math.ceil(D.HEAL_H[2] / D.HEAL_SLEEP * 60) + 1)
        assert.equal(1, Parts.stage(blisters(p), "Foot_L"))
    end)

    it("keeps healing slowly while walking in dry socks and decent shoes, rubbing no further", function()
        local p = blistered()
        walk(p, "walk")
        assert.equal(D.HEAL_WALK, Blisters.healRate(p))
        run(p, math.ceil(D.HEAL_H[2] / D.HEAL_WALK * 60) + 1)
        assert.equal(1, Parts.stage(blisters(p), "Foot_L"))
        assert.is_true(friction(p) <= D.STAGE_H[1], "set back under the new stage")
    end)

    it("rubs a blistered foot further in bad footwear", function()
        local p = blistered()
        walk(p, "walk")
        p.facts.extremities.socks = nil
        run(p, math.ceil(walking(D.STAGE_H[3] - D.STAGE_H[2]) / D.NO_SOCKS) + 1)
        assert.equal(3, Parts.stage(blisters(p), "Foot_L"))
    end)

    it("pauses healing when running or in bad footwear", function()
        local p = blistered()
        walk(p, "run")
        assert.equal(0, Blisters.healRate(p))
        walk(p, "walk")
        p.facts.extremities.socks.wet = 0.6
        assert.equal(0, Blisters.healRate(p))
        p.facts.extremities.socks = nil
        assert.equal(0, Blisters.healRate(p))
        p.facts.extremities.socks = { wet = 0, holes = 0 }
        p.facts.extremities.shoes.wear = 0.3
        assert.equal(0, Blisters.healRate(p))
    end)

    it("heals twice as fast under a blister patch", function()
        local p = blistered({ treatment = { active = { blisterPatch = true } } })
        walk(p, "rest")
        assert.equal(D.HEAL_REST * D.HEAL_PATCH, Blisters.healRate(p))
    end)

    it("starts over after a cure (blister patch course) or a full heal", function()
        local p = blistered()
        Engine.cure(p, defs, "foot_blisters")
        assert.equal(0, friction(p))
        p = blistered()
        Engine.finish(p, defs, "foot_blisters", "admin")
        assert.equal(0, friction(p))
    end)
end)

describe("foot blister debug and alert", function()
    it("lands a debug start on its source foot, and debug stages move that foot", function()
        local p = context()
        walk(p, "rest")
        Engine.contract(p, defs, "foot_blisters", { source = Blisters.debugSource })
        step(p, 1)
        local c = blisters(p)
        assert.truthy(c)
        assert.equal(1, Parts.stage(c, "Foot_L"))
        Engine.setStage(p, defs, "foot_blisters", 3)
        assert.equal(3, Parts.stage(c, "Foot_L"))
        assert.same({ Foot_L = "foot_blisters" }, p.body.scratches)
    end)

    it("lights the Medical Alert from a blister, not a hot spot", function()
        local function level(stage)
            return MoodleLevels.compute({ conditions = { active = { foot_blisters = { stage = stage } } } }).medical.level
        end
        assert.equal(0, level(1))
        assert.equal(2, level(2))
        assert.equal(3, level(3))
    end)

    it("lists the affected feet on the Monitor row", function()
        local p = context()
        local c = Engine.contract(p, defs, "foot_blisters", { stage = 1, source = "Foot_L" })
        Parts.setStage(p, c, "Foot_L", 1)
        Parts.setStage(p, c, "Foot_R", 2)
        local row = {}
        Blisters.monitorRow(row, c, { name = true })
        assert.equal("UI_EHR_Extremities_Join", row.description.key)
        assert.equal("IGUI_health_Left_Foot", row.description.args[1].key)
        row = {}
        Blisters.monitorRow(row, c, { name = false })
        assert.is_nil(row.description)
    end)
end)
