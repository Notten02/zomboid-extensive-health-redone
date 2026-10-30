-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Concussion: the server-side trauma check behind a client report or the server's own fall and crash causes, the
-- reverse course, and its effects.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Concussion = require("ExtensiveHealthRedone/Diseases/Concussion/Concussion")
local Sim = require("support/sim")

local ID = "concussion"

local function track(p, minutes)
    for _ = 1, minutes do
        Concussion.update(Sim.step(p), 1, defs)
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

describe("concussion detection", function()
    it("rolls only once the body shows trauma after a reported fall", function()
        local p = Sim.context({ floats = { 0.64 } })
        track(p, 3)
        assert.is_true(Concussion.report(p, defs, "fall"))
        assert.is_nil(p.state.conditions.active[ID])        -- nothing visible yet
        p.facts.parts.Head.health = 95                       -- the fall damage arrives
        track(p, 1)
        local c = p.state.conditions.active[ID]
        assert.truthy(c)
        assert.equal(3, c.stage)
        assert.is_true(Sim.said(p, "UI_EHR_Text_MyHeadSomethingIsWrong"))
    end)

    it("forgets a report the body doesn't back up", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        Concussion.report(p, defs, "fall")
        track(p, 3)
        p.facts.parts.Head.health = 50                       -- too late: the window has closed
        track(p, 1)
        assert.is_nil(p.state.conditions.active[ID])
    end)

    it("needs more for a crash: 6 health lost over the body, or head trauma", function()
        local p = Sim.context({ float = 0 })
        p.facts.inVehicle = true
        track(p, 3)
        Concussion.report(p, defs)
        p.facts.parts.UpperLeg_L.health = 96
        track(p, 1)
        assert.is_nil(p.state.conditions.active[ID])
        p.facts.parts.UpperLeg_R.health = 97
        track(p, 1)
        assert.truthy(p.state.conditions.active[ID])
    end)

    it("uses the chance multipliers and cools down after a failed roll", function()
        local p = Sim.context({ floats = { 0.5 }, sandbox = { ConcussionFallChanceMultiplier = 0.5 } })
        track(p, 3)
        Concussion.report(p, defs, "fall")
        p.facts.parts.Head.health = 90
        track(p, 1)
        assert.is_nil(p.state.conditions.active[ID])        -- 0.5 >= 0.325
        assert.is_false(Concussion.report(p, defs, "fall"))  -- cooling down
        track(p, 2)
        assert.is_true(Concussion.report(p, defs, "fall"))
    end)

    it("counts deep wounds and fractures as severe trauma", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        Concussion.report(p, defs, "fall")
        p.facts.trauma = { headPain = 0, fractures = { LowerLeg_L = true } }
        track(p, 1)
        assert.truthy(p.state.conditions.active[ID])
    end)

    it("takes the kind from the server's facts, not the client's report", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        local _, kind = Concussion.report(p, defs, "crash")
        assert.equal("fall", kind)                           -- not in a vehicle: a fall's thresholds
        assert.equal("fall", p.state.exposure.data.concussion.pending.kind)
        local q = Sim.context({ float = 0 })
        q.facts.inVehicle = true
        track(q, 3)
        q.facts.inVehicle = false                            -- thrown out, or just got out: still a crash
        assert.equal("crash", Concussion.kind(q))
        track(q, 1)
        assert.equal("fall", Concussion.kind(q))
    end)

    it("notices a fall itself from the drop in height, without a report", function()
        local p = Sim.context({ float = 0 })
        p.facts.trauma = { headPain = 0, fractures = {}, z = 2 }
        track(p, 3)
        p.facts.trauma = { headPain = 0, fractures = {}, z = 0.4 }  -- mid-fall at the step
        track(p, 1)
        p.facts.trauma = { headPain = 0, fractures = {}, z = 0 }
        p.facts.parts.Head.health = 90
        track(p, 1)
        local c = p.state.conditions.active[ID]
        assert.truthy(c)
        assert.equal("fall", c.source)
    end)

    it("doesn't roll for stairs: a drop in height without trauma", function()
        local p = Sim.context({ float = 0 })
        p.facts.trauma = { headPain = 0, fractures = {}, z = 1 }
        track(p, 3)
        p.facts.trauma = { headPain = 0, fractures = {}, z = 0 }
        track(p, 5)
        assert.is_nil(p.state.conditions.active[ID])
    end)

    it("notices a crash itself from the vehicle's speed loss, without a report", function()
        local p = Sim.context({ float = 0 })
        p.facts.inVehicle = true
        p.facts.trauma = { headPain = 0, fractures = {}, z = 0, speed = 70 }
        track(p, 3)
        p.facts.trauma = { headPain = 3, fractures = {}, z = 0, speed = 0 }
        track(p, 1)
        local c = p.state.conditions.active[ID]
        assert.truthy(c)
        assert.equal("crash", c.source)
        -- Braking hard without trauma opens a window but never rolls.
        local q = Sim.context({ float = 0 })
        q.facts.inVehicle = true
        q.facts.trauma = { headPain = 0, fractures = {}, z = 0, speed = 70 }
        track(q, 3)
        q.facts.trauma = { headPain = 0, fractures = {}, z = 0, speed = 0 }
        track(q, 6)
        assert.is_nil(q.state.conditions.active[ID])
    end)

    it("follows ConcussionEnabled and DiseaseEnabled", function()
        for _, sandbox in ipairs({ { ConcussionEnabled = false }, { DiseaseEnabled = false } }) do
            local p = Sim.context({ float = 0, sandbox = sandbox })
            track(p, 3)
            Concussion.report(p, defs, "fall")
            p.facts.parts.Head.health = 50
            track(p, 1)
            assert.is_nil(p.state.conditions.active[ID])
        end
    end)
end)

describe("concussion", function()
    it("improves from stage 3 to 1 over 48 h (16 h each), scaled by DiseaseSpeed", function()
        local p = Sim.context({ sandbox = { DiseaseSpeed = 2 } })
        local c = Engine.contract(p, defs, ID) --[[@as table]]
        assert.equal(3, c.stage)
        run(p, 8 * 60)
        assert.equal(2, c.stage)
        run(p, 8 * 60)
        assert.equal(1, c.stage)
        run(p, 8 * 60)
        assert.is_nil(p.state.conditions.active[ID])
    end)

    it("pulls health down to 50 at stage 3, then lets it recover to 75 at stage 2", function()
        local p = Sim.context()
        local c = Engine.contract(p, defs, ID, { severity = 1 }) --[[@as table]]
        run(p, 1, 1)
        assert.equal(50, p.body.damages[1].floor)
        assert.equal(0, p.body.heal.Head)
        assert.is_true(p.body:painTargets().Head > 0)
        p.facts.health = 50
        run(p, 1, 1)
        Engine.setStage(p, defs, ID, 2)
        Engine.step(Sim.step(p), defs, 1)
        assert.equal(75, c.data.cap)
        assert.is_nil(p.body.heal.Head)                   -- 50 < 75: vanilla healing may raise it
    end)

    it("blurs vision during a dizzy spell", function()
        local p = Sim.context({ float = 0 })
        Engine.contract(p, defs, ID)
        run(p, 1, 1)
        assert.equal(0.55, p.fx.values.blur)
    end)
end)
