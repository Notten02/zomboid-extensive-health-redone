-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Concussion: the server-side trauma check behind vanilla's fall and crash damage event, the reverse course, and
-- its effects.
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

-- Health lost on every part at once, the way vanilla's fall and crash damage lands.
local function landHard(p, hp)
    for _, part in pairs(p.facts.parts) do
        part.health = part.health - hp
    end
end

local function zombieHit(p)
    p.facts.parts.ForeArm_L.scratch = true
    p.facts.parts.ForeArm_L.health = 92
    p.facts.parts.Neck.bite = true
    p.facts.parts.Neck.health = 85
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
        assert.is_true(Concussion.report(p, defs))
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
        Concussion.report(p, defs)
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
        Concussion.report(p, defs)
        p.facts.parts.Head.health = 90
        track(p, 1)
        assert.is_nil(p.state.conditions.active[ID])        -- 0.5 >= 0.325
        assert.is_false(Concussion.report(p, defs))          -- cooling down
        track(p, 2)
        assert.is_true(Concussion.report(p, defs))
    end)

    it("counts deep wounds and fractures as severe trauma", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        Concussion.report(p, defs)
        p.facts.trauma = { headPain = 0, fractures = { LowerLeg_L = true } }
        track(p, 1)
        assert.truthy(p.state.conditions.active[ID])
    end)

    it("takes a client's report for the kind the server's facts give", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        local _, kind = Concussion.report(p, defs)
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

    it("takes the kind and the damage from vanilla's event where the authority heard it", function()
        local p = Sim.context({ float = 0 })
        p.facts.inVehicle = true                             -- in a car, yet vanilla says it was a fall
        track(p, 3)
        local opened, kind = Concussion.report(p, defs, { kind = "fall", damage = 7 })
        assert.is_true(opened)
        assert.equal("fall", kind)
        -- A stumble opens nothing; a crash has no least damage.
        local q = Sim.context({ float = 0 })
        track(q, 3)
        assert.is_false(Concussion.report(q, defs, { kind = "fall", damage = 2.6 }))
        assert.is_nil(q.state.exposure.data.concussion.pending)
        assert.is_true(Concussion.report(q, defs, { kind = "crash", damage = 1 }))
    end)

    it("knows a two-floor fall by health lost all over the body, though the head loses little", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        Concussion.report(p, defs, { kind = "fall", damage = 7 })
        -- What a 42.21 dedicated server saw after two floors.
        for name, loss in pairs({ Hand_L = 4.1, Hand_R = 4.1, ForeArm_L = 2, ForeArm_R = 2, UpperArm_L = 1.3,
            UpperArm_R = 1.3, Torso_Upper = 1.1, Torso_Lower = 1, Head = 0.6, Neck = 0.5, Groin = 1, UpperLeg_L = 1.3,
            UpperLeg_R = 1.3, LowerLeg_L = 2, LowerLeg_R = 2, Foot_L = 2, Foot_R = 2 }) do
            p.facts.parts[name].health = 100 - loss
        end
        track(p, 1)
        local c = p.state.conditions.active[ID]
        assert.truthy(c)
        assert.equal("fall", c.source)
        -- One floor: the hands at most.
        local q = Sim.context({ float = 0 })
        track(q, 3)
        Concussion.report(q, defs)
        for name, loss in pairs({ Hand_L = 1.5, Hand_R = 1.5, ForeArm_L = 0.7, ForeArm_R = 0.7, Head = 0.2,
            LowerLeg_L = 0.7, LowerLeg_R = 0.7, Foot_L = 0.7, Foot_R = 0.7 }) do
            q.facts.parts[name].health = 100 - loss
        end
        track(q, 3)
        assert.is_nil(q.state.conditions.active[ID])
    end)

    it("never opens a window by itself: no event, no concussion, whatever happens to the body", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        zombieHit(p)
        landHard(p, 20)
        p.facts.trauma = { headPain = 60, fractures = { LowerLeg_L = true } }
        track(p, 5)
        assert.is_nil(p.state.exposure.data.concussion.pending)
        assert.is_nil(p.state.conditions.active[ID])
    end)

    it("compares a fall with the body shortly before, not minutes ago", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        zombieHit(p)
        track(p, 2)                                          -- the fight was two minutes ago
        Concussion.report(p, defs)
        track(p, 3)
        assert.is_nil(p.state.conditions.active[ID])
    end)

    it("starts over after the player is attached: saved samples and windows are dropped", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        Concussion.report(p, defs)                           -- logged out with a window open
        assert.truthy(p.state.exposure.data.concussion.pending)
        p.fresh = true                                       -- the next session, and hurt
        landHard(p, 20)
        assert.is_false(Concussion.report(p, defs, { kind = "fall", damage = 20 }))   -- nothing to compare with yet
        track(p, 1)
        local d = p.state.exposure.data.concussion
        assert.is_nil(d.pending)
        assert.equal(1, #d.history)
        p.fresh = false
        track(p, 5)
        assert.is_nil(p.state.conditions.active[ID])
    end)

    it("drops samples an older version saved", function()
        local p = Sim.context({ float = 0 })
        local old = { headPain = 0, headHealth = 100, partHealth = 1700, wounds = 0, severe = 0, z = 2 }
        p.state.exposure.data.concussion = { history = { old, old, old },
            pending = { kind = "fall", before = old, left = 2 } }
        Concussion.rebase(p, { health = { Head = -5 }, pain = { Head = 10 } })    -- a one-off effect before the step
        p.fresh = true
        track(p, 1)
        p.fresh = false
        landHard(p, 20)
        track(p, 3)
        assert.is_nil(p.state.conditions.active[ID])
    end)

    it("never takes the mod's own body writes for trauma", function()
        local p = Sim.context({ float = 0 })
        track(p, 3)
        assert.is_true(Concussion.report(p, defs))
        -- A disease drain and a medication headache, written by the body writer after the step.
        Concussion.rebase(p, { health = { Head = -3, Neck = -3 }, pain = { Head = 35 } })
        p.facts.parts.Head.health, p.facts.parts.Neck.health = 97, 97
        p.facts.trauma = { headPain = 35, fractures = {} }
        track(p, 1)
        assert.is_nil(p.state.conditions.active[ID])
        -- Real damage on top of it still shows.
        p.facts.parts.Head.health = 94
        track(p, 1)
        assert.truthy(p.state.conditions.active[ID])
    end)

    it("follows ConcussionEnabled and DiseaseEnabled", function()
        for _, sandbox in ipairs({ { ConcussionEnabled = false }, { DiseaseEnabled = false } }) do
            local p = Sim.context({ float = 0, sandbox = sandbox })
            track(p, 3)
            Concussion.report(p, defs)
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
