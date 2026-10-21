-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Hyperkeratotic scabies: the natural-ground trigger, the bite, scratch wounds, the health cap and the lethal stage 4.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Scabies = require("ExtensiveHealthRedone/Diseases/Scabies/Scabies")
local Sim = require("support/sim")

local ID = "hyperkeratotic_scabies"

local function sit(p)
    local env = p.facts.env
    env.sitOnGround, env.naturalFloor, env.month = true, true, 7
end

local function trigger(p, minutes)
    for _ = 1, minutes do
        Scabies.update(Sim.step(p), 1, defs)
    end
end

local function run(p, minutes, step)
    step = step or 60
    local done = 0
    while done < minutes do
        Engine.step(Sim.step(p), defs, step)
        done = done + step
    end
end

---@return table
local function contract(p, opts)
    return Engine.contract(p, defs, ID, opts) --[[@as table]]
end

local function scratched(p)
    local parts = {}
    for part in pairs(p.body.scratches or {}) do
        parts[#parts + 1] = part
    end
    return parts
end

describe("scabies trigger", function()
    it("rolls 3% (x the multiplier) after each 15 minutes sitting on natural ground", function()
        local p = Sim.context({ floats = { 0.031, 0.059 }, sandbox = { ScabiesChanceMultiplier = 2 } })
        sit(p)
        trigger(p, 14)
        assert.is_nil(p.state.conditions.active[ID])
        trigger(p, 1)
        assert.truthy(p.state.conditions.active[ID])      -- 0.031 < 0.06
        assert.is_true(Sim.said(p, "UI_EHR_Text_SomethingBitMeItItchesAlready"))
    end)

    it("restarts the clock when the player moves, stands, or isn't on natural ground", function()
        local p = Sim.context({ float = 0 })
        sit(p)
        trigger(p, 10)
        p.facts.env.moving = true
        trigger(p, 1)
        p.facts.env.moving = false
        trigger(p, 10)
        assert.is_nil(p.state.conditions.active[ID])
        p.facts.env.naturalFloor = false
        p.facts.ground = { natural = false }
        trigger(p, 30)
        assert.is_nil(p.state.conditions.active[ID])
        p.facts.ground = { natural = true }        -- v0.9 also counted floors named grass, dirt or soil
        trigger(p, 15)
        assert.truthy(p.state.conditions.active[ID])
    end)

    it("is blocked in winter and on snow, unless those blocks are turned off", function()
        local p = Sim.context({ float = 0 })
        sit(p)
        p.facts.env.month = 1
        trigger(p, 60)
        assert.is_nil(p.state.conditions.active[ID])
        p.facts.env.month = 7
        p.facts.env.groundSnow = true
        trigger(p, 60)
        assert.is_nil(p.state.conditions.active[ID])

        local open = Sim.context({ float = 0, sandbox = { ScabiesWinterBlock = false, ScabiesSnowBlock = false } })
        sit(open)
        open.facts.env.month, open.facts.env.groundSnow = 12, true
        trigger(open, 15)
        assert.truthy(open.state.conditions.active[ID])
    end)
end)

describe("scabies", function()
    it("bites a part (never the head or neck) and makes it hurt from stage 1", function()
        local p = Sim.context({ ints = { 9 } })      -- muscles[9] = Groin
        contract(p)
        run(p, 1, 1)
        assert.same({ "Groin" }, scratched(p))
        assert.equal("Groin", p.state.conditions.active[ID].data.bite)
        assert.equal(8, p.body:painTargets().Groin)
    end)

    it("opens a scratch every 3 h at stage 2 and holds health down toward 60", function()
        local p = Sim.context()
        local c = contract(p, { stage = 2, severity = 1 })
        c.data.bite = "Hand_L"
        run(p, 179, 1)
        assert.same({}, scratched(p))
        run(p, 1, 1)
        assert.equal(1, #scratched(p))
        assert.equal(60, p.body.damages[1].floor)
        assert.equal(0, p.body.heal.Hand_L)
    end)

    it("drains health with no floor at stage 4 untreated", function()
        local p = Sim.context()
        local c = contract(p, { stage = 4, severity = 1 })
        c.data.bite = "Hand_L"
        run(p, 1, 1)
        assert.equal(0, p.body.damages[1].floor)
        assert.near(1.35 + 2.65, p.body.damages[1].hp * 0.28 * 60, 1e-9)
    end)

    it("stops scratches, the cap and the drain while a curative course runs", function()
        local p = Sim.context({ treatment = { curing = { [ID] = true } } })
        local c = contract(p, { stage = 3 })
        c.data.bite = "Hand_L"
        run(p, 600, 60)
        assert.same({}, scratched(p))
        assert.same({}, p.body.damages)
    end)
end)
