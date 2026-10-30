-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The disease engine features, on synthetic definitions: switches, stage schedules, reverse and driven
-- conditions, persistence and holds, the shared cleanup path, complications, speech pools, knowledge, immunity risk
-- and the client effects.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local Knowledge = require("ExtensiveHealthRedone/Conditions/Knowledge")
local Risk = require("ExtensiveHealthRedone/Conditions/Risk")
local ClientEffects = require("ExtensiveHealthRedone/Core/ClientEffects")
local Sim = require("support/sim")

local function run(p, defs, minutes, step)
    step = step or 60
    local done = 0
    while done < minutes do
        Engine.step(Sim.step(p), defs, step)
        done = done + step
    end
end

---@return table
local function contract(p, defs, id, opts)
    return Engine.contract(p, defs, id, opts) --[[@as table]]
end

describe("disease engine", function()
    it("honours the master DiseaseEnabled switch unless a condition opts out", function()
        local defs = { a = { incubation = { 1, 1 }, duration = { 1, 1 } },
            b = { incubation = { 1, 1 }, duration = { 1, 1 }, master = false } }
        local p = Sim.context({ sandbox = { DiseaseEnabled = false } })
        assert.equal("disabled", select(2, Engine.contract(p, defs, "a")))
        assert.truthy(Engine.contract(p, defs, "b"))
    end)

    it("uses explicit stage lengths and persists at the given stage", function()
        local defs = { x = { stages = { [1] = { 24, 24 }, [2] = { 24, 24 } }, persistsAt = 3, effectsInStage1 = true } }
        local p = Sim.context()
        local c = contract(p, defs, "x")
        run(p, defs, 24 * 60)
        assert.equal(2, c.stage)
        run(p, defs, 24 * 60)
        assert.equal(3, c.stage)
        run(p, defs, 500 * 60)
        assert.equal(3, c.stage)
        assert.truthy(p.state.conditions.active.x)
    end)

    it("counts a reverse condition down from its start stage and ends after stage 1", function()
        local defs = { r = { stages = { [3] = { 10, 10 }, [2] = { 10, 10 }, [1] = { 10, 10 } }, startStage = 3,
            reverse = true } }
        local p = Sim.context()
        local c = contract(p, defs, "r")
        assert.equal(3, c.stage)
        run(p, defs, 600)
        assert.equal(2, c.stage)
        run(p, defs, 600)
        assert.equal(1, c.stage)
        assert.near(600, Engine.minutesLeft(c, defs.r), 1e-9)
        run(p, defs, 600)
        assert.is_nil(p.state.conditions.active.r)
    end)

    it("holds a stage while hold() says so, and speeds time with rate()", function()
        local cooled = false
        local defs = { h = { stages = { [1] = { 1, 1 }, [2] = { 1, 1 }, [3] = { 1, 1 }, [4] = { 1, 1 } },
            hold = function(_, c) return c.stage == 3 and not cooled end,
            rate = function() return 2 end } }
        local p = Sim.context()
        local c = contract(p, defs, "h")
        run(p, defs, 60, 30)               -- 1 h of time at double rate = stages 1 and 2
        assert.equal(3, c.stage)
        run(p, defs, 600, 30)
        assert.equal(3, c.stage)
        cooled = true
        run(p, defs, 30, 30)
        assert.equal(4, c.stage)
    end)

    it("lets a driven condition set its own stage", function()
        local target = 2 ---@type integer|string
        local entered = {}
        local defs = { d = { driven = true, drive = function() return target end,
            onStage = function(_, _, stage) entered[#entered + 1] = stage end } }
        local p = Sim.context()
        local c = contract(p, defs, "d")
        run(p, defs, 1, 1)
        assert.equal(2, c.stage)
        target = "recovered"
        run(p, defs, 1, 1)
        assert.is_nil(p.state.conditions.active.d)
        assert.same({ 2 }, entered)
    end)

    it("runs the same cleanup for natural recovery, cure and complications", function()
        local ended = {}
        local defs = {
            a = { stages = { [1] = { 1, 1 }, [2] = { 1, 1 }, [3] = { 1, 1 }, [4] = { 1, 1 } },
                onEnd = function(_, _, reason) ended[#ended + 1] = reason end },
        }
        local p = Sim.context()
        contract(p, defs, "a")
        run(p, defs, 4 * 60)
        contract(p, defs, "a")
        Engine.cure(p, defs, "a")
        assert.same({ "recovered", "cured" }, ended)
        assert.is_false(Engine.cure(p, defs, "a"))
    end)

    it("rolls complications on stage entry, only untreated, and can replace the condition", function()
        local defs = {
            cold = { stages = { [1] = { 1, 1 }, [2] = { 1, 1 }, [3] = { 1, 1 }, [4] = { 10, 10 } },
                complications = { { stage = 4, id = "pneumonia", chance = 0.35, untreated = true, replace = true } } },
            pneumonia = { incubation = { 12, 12 }, duration = { 100, 100 } },
        }
        -- Contracting the cold uses 5 floats (4 stage lengths, severity); the 6th is the complication roll.
        local p = Sim.context({ floats = { 0, 0, 0, 0, 0, 0.34 } })
        contract(p, defs, "cold")
        run(p, defs, 3 * 60)
        assert.truthy(p.state.conditions.active.pneumonia)
        assert.is_nil(p.state.conditions.active.cold)
        assert.equal("cold", p.state.conditions.active.pneumonia.source)

        local missed = Sim.context({ floats = { 0, 0, 0, 0, 0, 0.36 } })
        contract(missed, defs, "cold")
        run(missed, defs, 3 * 60)
        assert.is_nil(missed.state.conditions.active.pneumonia)
        assert.equal(4, missed.state.conditions.active.cold.stage)
    end)

    it("speaks stage lines on entry and random lines at the DialogueFrequency rate", function()
        local defs = { s = { stages = { [1] = { 1, 1 }, [2] = { 100, 100 } }, persistsAt = 2,
            lines = { stage = { [2] = "UI_Stage2" }, random = { [2] = { "UI_Random" } }, every = 60 } } }
        local quiet = Sim.context({ sandbox = { DialogueFrequency = 1 } })
        contract(quiet, defs, "s")
        run(quiet, defs, 10 * 60)
        assert.same({}, quiet.said)

        local p = Sim.context({ sandbox = { DialogueFrequency = 3 }, float = 0 })
        contract(p, defs, "s")
        run(p, defs, 60)
        assert.equal("UI_Stage2", p.said[1])
        assert.equal("UI_Random", p.said[2])
    end)

    it("takes the random line rate by stage when every is a table", function()
        local function said(every)
            local defs = { s = { stages = { [1] = { 1, 1 }, [2] = { 100, 100 } }, persistsAt = 2,
                lines = { random = { [2] = { "UI_Random" } }, every = every } } }
            local p = Sim.context({ sandbox = { DialogueFrequency = 3 }, float = 0 })
            contract(p, defs, "s")
            run(p, defs, 60)
            return #p.said
        end
        assert.is_true(said({ [1] = 60, [2] = 60 }) > 0)
        assert.equal(0, said({ [1] = 60, [2] = 0 }))
    end)
end)

describe("knowledge gating", function()
    local function state(diseases, extra)
        local s = Sim.context().state
        s.knowledge.diseases = diseases or {}
        for k, v in pairs(extra or {}) do
            s.knowledge[k] = v
        end
        return s
    end

    it("names a disease from a flyer, a profession, First Aid 8 or when self-evident", function()
        local def = { knowledge = "pneumonia" }
        assert.is_false(Knowledge.of(state(), def, 7).name)
        assert.is_true(Knowledge.of(state(), def, 8).name)
        assert.is_true(Knowledge.of(state({ pneumonia = true }), def, 0).name)
        assert.is_true(Knowledge.of(state(nil, { professionGrant = "ehrdoctor" }), def, 0).name)
        assert.is_true(Knowledge.of(state(), { knowledge = "hypothermia", selfEvident = true }, 0).name)
    end)

    it("shows the stage from First Aid 4 and progress from 6", function()
        local known = state({ pneumonia = true })
        local def = { knowledge = "pneumonia" }
        assert.same({ name = true, stage = false, progress = false }, Knowledge.of(known, def, 3))
        assert.same({ name = true, stage = true, progress = false }, Knowledge.of(known, def, 4))
        assert.same({ name = true, stage = true, progress = true }, Knowledge.of(known, def, 6))
    end)

    it("names Knox only after the Kentucky Herald, never from skill or profession", function()
        local def = { knowledge = "knox_infection" }
        assert.is_false(Knowledge.of(state(nil, { professionGrant = "ehrsurgeon" }), def, 10).name)
        assert.is_false(Knowledge.of(state({ knox_infection = true }), def, 10).name)
        assert.is_true(Knowledge.of(state({ knox_infection = true }, { knoxHerald = true }), def, 0).name)
    end)
end)

describe("immunity risk", function()
    it("is neutral at score 50 and ranges from -35% to +50% at full sensitivity", function()
        assert.near(1, Risk.multiplier(50, 1, 1), 1e-9)
        assert.near(0.65, Risk.multiplier(100, 1, 1), 1e-9)
        assert.near(1.5, Risk.multiplier(0, 1, 1), 1e-9)
        assert.near(1 + 0.5 * 0.85, Risk.multiplier(0, 0.85, 1), 1e-9)
    end)

    it("applies only to supported diseases and only with immunity's gameplay effects on", function()
        local p = Sim.context()
        p.state.immunity.score = 0
        assert.near(0.15, Risk.chance(p, "cadaveric_aspergillosis", 0.1), 1e-9)
        assert.near(0.1, Risk.chance(p, "food_poisoning", 0.1), 1e-9)
        local off = Sim.context({ sandbox = { ImmunityGameplayEffects = false } })
        off.state.immunity.score = 0
        assert.near(0.1, Risk.chance(off, "cadaveric_aspergillosis", 0.1), 1e-9)
    end)
end)

describe("client effects", function()
    it("keeps the strongest wish and reports changes only", function()
        local fx = ClientEffects.new()
        fx:speed("blood", 0.8)
        fx:speed("hypothermia", 0.5)
        fx:blur("toxin", 0.4)
        fx:blur("concussion", 0.2)
        fx:noSprint("heat")
        local section = ClientEffects.defaults()
        assert.is_true(fx:writeTo(section))
        assert.same({ speed = 0.5, noSprint = true, blur = 0.4, tint = 0, noSleep = false, sleepBy = false,
            attackSpeed = 1, boost = 1, bladder = 0, night = 0, aim = 1 }, section)

        assert.is_false(fx:writeTo(section))
        assert.is_true(ClientEffects.new():writeTo(section))
        assert.equal(1, section.speed)
    end)
end)

describe("shared cough gap", function()
    local Cough = require("ExtensiveHealthRedone/Diseases/Shared/Cough")
    local Shared = require("ExtensiveHealthRedone/Diseases/Shared/Group")

    it("allows one cough per gap from any disease, never asleep", function()
        local p = Sim.context()
        assert.is_true(Cough.claim(p))
        assert.is_false(Cough.claim(p))
        Shared.systems[1].update(p, Cough.GAP)
        p.facts.asleep = true
        assert.is_false(Cough.claim(p))
        p.facts.asleep = false
        assert.is_true(Cough.claim(p))
    end)
end)
