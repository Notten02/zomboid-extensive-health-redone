-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Frostnip and frostbite (Diseases/Extremities/Frostbite): the effective temperature of a hand or foot, the frost
-- meter, the stages and their effects, rewarming, the Warming Pack, gangrene, and a hand cut off with The Only Cure.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Group = require("ExtensiveHealthRedone/Diseases/Extremities/Group")
local Frostbite = require("ExtensiveHealthRedone/Diseases/Extremities/Frostbite")
local Gangrene = require("ExtensiveHealthRedone/Diseases/Extremities/Gangrene")
local Meters = require("ExtensiveHealthRedone/Diseases/Extremities/Meters")
local Parts = require("ExtensiveHealthRedone/Diseases/Extremities/Parts")
local Data = require("ExtensiveHealthRedone/Diseases/Extremities/Data")
local Amputation = require("ExtensiveHealthRedone/Wounds/Amputation")
local Sim = require("support/sim")

local D = Data.frostbite

-- Outdoors at -25 deg C wind chill, bare hands, dry socks and boots that insulate the feet well.
local function context(opts)
    local p = Sim.context(opts)
    p.facts.env.airC = -15
    p.facts.stats.TEMPERATURE = 37
    p.facts.extremities = {
        windChillC = -25,
        socks = { wet = 0, holes = 0 },
        shoes = { wet = 0, holes = 0, wear = 1, waterRes = 0.5 },
        parts = { Hand_L = { skinC = 15, insulation = 0 }, Hand_R = { skinC = 15, insulation = 0 },
            Foot_L = { skinC = 25, insulation = 2 }, Foot_R = { skinC = 25, insulation = 2 } },
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

local function frostbite(p)
    return p.state.conditions.active.frostbite
end

local function frost(p, part)
    return Meters.value(p, part, "frost")
end

local function bitten(stage, part, opts)
    local p = context(opts)
    local c = Engine.contract(p, defs, "frostbite", { stage = stage, source = part })
    Parts.setStage(p, c, part, stage)
    Meters.set(p, part, "frost", D.STAGE[stage])
    return p, c
end

local function warmUp(p)
    p.facts.env.indoors = true
    p.facts.env.airC = 20
end

describe("frostbite exposure", function()
    it("reads wind chill outdoors, the room indoors and the cabin in a vehicle", function()
        local p = context()
        assert.equal(-25, Frostbite.air(p))
        p.facts.env.indoors = true
        assert.equal(-15, Frostbite.air(p))
        p.facts.env.vehicleC = 12
        assert.equal(12, Frostbite.air(p))
    end)

    it("adds clothing insulation, takes off wetness and a cold body", function()
        local p = context()
        assert.equal(-25, Frostbite.effective(p, "Hand_L"))
        assert.equal(-25 + 2 * D.INSULATION_C, Frostbite.effective(p, "Foot_L"))
        p.facts.env.wetness = 0.5
        assert.equal(-25 - D.WET_C, Frostbite.effective(p, "Hand_L"))
        p.facts.env.wetness = 0
        p.facts.stats.TEMPERATURE = 35.8
        assert.equal(-25 - D.CORE_COLD_C, Frostbite.effective(p, "Hand_L"))
        p.state.conditions.active.hypothermia = { stage = 2 }
        assert.equal(-25 - D.HYPOTHERMIA_C, Frostbite.effective(p, "Hand_L"))
    end)

    it("freezes bare hands but not well-booted feet, faster the colder", function()
        local p = context()
        assert.near((15 / 10) ^ D.POWER, Frostbite.gain(p, "Hand_L"), 1e-9)
        assert.equal(0, Frostbite.gain(p, "Foot_L"))
        p.facts.extremities.windChillC = -35
        assert.near((25 / 10) ^ D.POWER, Frostbite.gain(p, "Hand_L"), 1e-9)
    end)

    it("freezes wet boots and gloveless hands in a blizzard, and gloves help", function()
        local p = context()
        p.facts.extremities.socks.wet = 0.8
        p.facts.extremities.parts.Foot_L.insulation = 0.5
        assert.is_true(Frostbite.gain(p, "Foot_L") > 0)
        p.facts.extremities.gloves = { wet = 0, holes = 0 }
        p.facts.extremities.parts.Hand_L.insulation = 1.5
        assert.equal(0, Frostbite.gain(p, "Hand_L"))
    end)

    it("halves the gain on the hands under a Warming Pack, and follows the sandbox", function()
        local p = context()
        local bare = Frostbite.gain(p, "Hand_L")
        p.state.meds.effects.warming = { left = 60 }
        assert.near(bare * D.PACK_HANDS, Frostbite.gain(p, "Hand_L"), 1e-9)
        p = context({ sandbox = { FrostbiteSpeed = 2, FrostbiteTemperature = -30 } })
        assert.equal(0, Frostbite.gain(p, "Hand_L"))
        p.facts.extremities.windChillC = -40
        assert.near(2 * (10 / 10) ^ D.POWER, Frostbite.gain(p, "Hand_L"), 1e-9)
    end)
end)

describe("frostbite stages", function()
    it("starts as frostnip on the bare hands", function()
        local p = context()
        run(p, 60)
        local c = frostbite(p)
        assert.truthy(c)
        assert.equal(1, Parts.stage(c, "Hand_L"))
        assert.equal(1, Parts.stage(c, "Hand_R"))
        assert.equal(0, Parts.stage(c, "Foot_L"))
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_FrostnipStings"))
    end)

    it("costs aim on the hands, speed and sprint on the feet", function()
        local p, c = bitten(3, "Hand_L")
        Parts.setStage(p, c, "Foot_R", 3)
        warmUp(p)
        step(p, 1)
        assert.equal(D.AIM[3], p.fx.values.aim)
        assert.equal(D.SPEED[3], p.fx.values.speed)
        assert.is_true(p.fx.values.noSprint)
        assert.equal(D.PAIN[3], p.body.pains.Hand_L.frostbite)
        assert.equal(D.HEAL_FACTOR[3], p.body.heal.Hand_L)
    end)

    it("raises a blister at stage 3 and damages the part at stage 4", function()
        local p = context()
        Meters.set(p, "Hand_L", "frost", D.STAGE[3])
        step(p, 1)
        assert.equal("frostbite", p.body.scratches.Hand_L)
        p = bitten(4, "Hand_R")
        warmUp(p)
        step(p, 60)
        assert.truthy(p.body.partDamages.Hand_R)
        assert.equal(0, p.body.heal.Hand_R)
    end)

    it("turns a part held at stage 4 gangrenous", function()
        local p = bitten(4, "Foot_L")
        run(p, 24 * 60 + 2)
        assert.is_true(Gangrene.has(p, "Foot_L"))
    end)
end)

describe("frostbite rewarming", function()
    it("thaws frostnip within an hour of warmth, faster by a fire", function()
        local p = bitten(1, "Hand_L")
        warmUp(p)
        run(p, 61)
        assert.is_nil(frostbite(p))
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_FeelingComesBack"))
        assert.same({}, p.xps, "frostnip is no First Aid practice")
        p = bitten(1, "Hand_L")
        warmUp(p)
        p.facts.weather = { nearHeat = true }
        run(p, math.ceil(60 / D.THAW_HEAT_NIP) + 1)
        assert.is_nil(frostbite(p))
    end)

    it("heals deeper frostbite a stage per days of warmth, with XP", function()
        local p = bitten(2, "Hand_L")
        warmUp(p)
        run(p, D.THAW_H[2] * 60 + 1)
        assert.equal(1, Parts.stage(frostbite(p), "Hand_L"))
        run(p, D.THAW_H[1] * 60 + 1)
        assert.is_nil(frostbite(p))
        assert.same({ { "cure", "frostbite" } }, p.xps)
    end)

    it("counts a Warming Pack as heat", function()
        local p = context()
        p.state.meds.effects.warming = { left = 60 }
        assert.equal(D.THAW_HEAT, Frostbite.thawRate(p, 2))
        assert.equal(D.THAW_HEAT_NIP, Frostbite.thawRate(p, 1))
        assert.is_true(Frostbite.rewarming(p, "Hand_L"))
    end)

    it("doesn't heal in the cold that isn't freezing it further", function()
        local p = bitten(2, "Hand_L")
        p.facts.extremities.windChillC = -5
        run(p, D.THAW_H[2] * 60 + 1)
        assert.equal(2, Parts.stage(frostbite(p), "Hand_L"))
    end)

    it("holds a gangrenous part at stage 4", function()
        local p = bitten(4, "Hand_L")
        Gangrene.start(p, defs, "Hand_L")
        warmUp(p)
        run(p, D.THAW_H[4] * 60 + 1)
        assert.equal(4, Parts.stage(frostbite(p), "Hand_L"))
    end)

    it("lands a debug start on the left hand", function()
        local p = context()
        warmUp(p)
        Engine.contract(p, defs, "frostbite", { source = Frostbite.debugSource })
        step(p, 1)
        assert.equal(1, Parts.stage(frostbite(p), "Hand_L"))
    end)
end)

describe("frostbite and The Only Cure", function()
    local function snapshot(cut)
        local toc = { limbs = {}, prosthesis = {} }
        for _, limb in ipairs(Amputation.LIMBS) do
            toc.limbs[limb] = { cut = cut[limb] == true, healed = false, cauterized = false, dirt = 0 }
        end
        return toc
    end

    it("drops a cut hand from frostbite and gangrene, curing gangrene with its last part", function()
        local p = bitten(4, "Hand_L")
        p.state.onlyCure = Amputation.defaults()
        p.state.onlyCure.known = true
        Gangrene.start(p, defs, "Hand_L")
        p.facts.toc = snapshot({ Hand_L = true })
        Amputation.update(p, 1, defs)
        assert.is_nil(p.state.conditions.active.gangrene)
        assert.equal(0, Parts.stage(frostbite(p), "Hand_L"))
        assert.same({ { "cure", "gangrene" } }, p.xps)
        assert.is_true(Sim.said(p, "UI_EHR_Extremities_GangreneCutAway"))
    end)

    it("leaves foot gangrene to antibiotics", function()
        local p = context()
        p.state.onlyCure = Amputation.defaults()
        p.state.onlyCure.known = true
        Gangrene.start(p, defs, "Foot_L")
        p.facts.toc = snapshot({ Hand_L = true, ForeArm_L = true })
        Amputation.update(p, 1, defs)
        assert.truthy(p.state.conditions.active.gangrene)
    end)
end)
