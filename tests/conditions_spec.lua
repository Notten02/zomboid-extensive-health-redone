-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The staged-condition engine and the four Phase 3 conditions (cellulitis, sepsis, tetanus, AHTR).
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Sim = require("support/sim")

-- Tests that expect a refusal check the result for nil themselves.
---@return table
local function contract(p, id, opts)
    return Engine.contract(p, defs, id, opts) --[[@as table]]
end

local function run(p, minutes, step)
    step = step or 60
    local done = 0
    while done < minutes do
        Engine.step(Sim.step(p), defs, step)
        done = done + step
    end
end

describe("Conditions", function()
    describe("engine", function()
        it("rolls incubation and duration from the definition, divided by the speed option", function()
            local p = Sim.context({ floats = { 0, 1, 0.5 }, sandbox = { SepsisSpeed = 2 } })
            local c = contract(p, "sepsis")
            assert.equal(1, c.stage)
            assert.near(6 * 60 / 2, c.left, 1e-9)        -- incubation 6-24 h, the low end
            assert.near(96 * 60 / 2, c.duration, 1e-9)   -- duration 48-96 h, the high end
            assert.near(1.0, c.severity, 1e-9)           -- base 1.0 +- 0.15, the middle
            assert.equal(1, p.dirtied.conditions)
        end)

        it("refuses a disabled, already active or blocked condition", function()
            local p = Sim.context({ sandbox = { TetanusEnabled = false } })
            local c, why = contract(p, "tetanus")
            assert.is_nil(c)
            assert.equal("disabled", why)
            assert.truthy(contract(p, "sepsis"))
            assert.equal("active", select(2, contract(p, "sepsis")))
            Engine.cure(p, defs, "sepsis")
            assert.equal("blocked", select(2, contract(p, "sepsis")))
            run(p, 120)
            assert.truthy(contract(p, "sepsis"))
        end)

        it("splits the duration 40/30/30 over stages 2-4 and recovers at the end", function()
            local p = Sim.context({ floats = { 0, 0, 0.5 } })
            local c = contract(p, "tetanus")              -- 72 h incubation, 168 h duration
            run(p, 72 * 60)
            assert.equal(2, c.stage)
            assert.near(168 * 60 * 0.4, c.left, 1e-6)
            run(p, 168 * 60 * 0.4)
            assert.equal(3, c.stage)
            run(p, 168 * 60 * 0.6)
            assert.is_nil(p.state.conditions.active.tetanus)
        end)

        it("holds the stage while a curative course runs", function()
            local p = Sim.context({ treatment = { curing = { ahtr = true } } })
            local c = contract(p, "ahtr")
            local left = c.left
            run(p, 600)
            assert.equal(1, c.stage)
            assert.equal(left, c.left)
        end)

        it("keeps untreated sepsis at stage 4 for good", function()
            local p = Sim.context({ floats = { 0, 0, 0.5 } })
            local c = contract(p, "sepsis", { stage = 4 })
            run(p, 200 * 60)
            assert.equal(4, c.stage)
            assert.truthy(p.state.conditions.active.sepsis)
        end)
    end)

    describe("sepsis", function()
        it("drains health down to each stage's floor and blocks healing, unless treated", function()
            local p = Sim.context()
            local c = contract(p, "sepsis", { stage = 3 })
            c.left = 1e9
            Engine.step(Sim.step(p), defs, 60)
            assert.near(4.0, p.body.damages[1].hp, 1e-9)
            assert.equal(30, p.body.damages[1].floor)
            assert.equal(0, p.body.heal.Hand_L)
            assert.is_true(Sim.resolve(p, "TEMPERATURE", 37) > 37)

            local treated = Sim.context({ treatment = { curing = { sepsis = true } } })
            contract(treated, "sepsis", { stage = 3 })
            Engine.step(Sim.step(treated), defs, 60)
            assert.equal(0, #treated.body.damages)
            assert.is_nil(treated.body.heal.Hand_L)
        end)

        it("speaks a line when a stage begins", function()
            local p = Sim.context({ floats = { 0, 0, 0.5 } })
            contract(p, "sepsis")
            run(p, 6 * 60)
            assert.is_true(Sim.said(p, "UI_EHR_Text_ImShakingCantThinkStraight"))
        end)
    end)

    describe("cellulitis", function()
        it("turns into sepsis at stage 4 when untreated, and only ends when sepsis starts", function()
            local p = Sim.context()
            contract(p, "cellulitis", { source = "ForeArm_L", stage = 4 })
            contract(p, "sepsis")
            Engine.step(Sim.step(p), defs, 1)
            assert.truthy(p.state.conditions.active.cellulitis)   -- sepsis already running: it waits
            Engine.cure(p, defs, "sepsis")
            p.state.conditions.timers = {}
            Engine.step(Sim.step(p), defs, 1)
            assert.is_nil(p.state.conditions.active.cellulitis)
            assert.equal("ForeArm_L", p.state.conditions.active.sepsis.source)
            assert.is_true(Sim.said(p, "UI_EHR_Cellulitis_SpreadsToBlood"))
        end)

        it("stays at stage 4 while treated, and hurts the stitched part", function()
            local p = Sim.context({ treatment = { curing = { cellulitis = true } } })
            contract(p, "cellulitis", { source = "ForeArm_L", stage = 4 })
            Engine.step(Sim.step(p), defs, 1)
            assert.truthy(p.state.conditions.active.cellulitis)
            assert.is_nil(p.state.conditions.active.sepsis)
            assert.is_true(p.body.pains.ForeArm_L.cellulitis > 0)
        end)
    end)

    describe("tetanus", function()
        it("hides the incubation, then locks the jaw unless muscle relaxants work", function()
            local p = Sim.context()
            local c = contract(p, "tetanus")
            Engine.step(Sim.step(p), defs, 1)
            assert.same({}, p.said)
            assert.is_nil(next(p.body.pains))
            c.left = 0.5
            Engine.step(Sim.step(p), defs, 1)
            assert.equal(2, c.stage)
            assert.is_true(c.data.lockjaw)
            assert.equal(30, p.body.damages[1].floor)

            local relaxed = Sim.context({ treatment = { relief = { ["tetanus.muscleSpasms"] = 0.4 } } })
            local r = contract(relaxed, "tetanus", { stage = 2 })
            Engine.step(Sim.step(relaxed), defs, 1)
            assert.is_false(r.data.lockjaw)
        end)

        it("throws the character down in stage 3: first roll after 4-10 minutes, then every 30, 42 %", function()
            -- Dialogue off: an ambient line would use up the queued floats.
            local p = Sim.context({ floats = { 0.5, 0.5, 0.5, 0.43, 0.41 }, sandbox = { DialogueFrequency = 1 } })
            local c = contract(p, "tetanus", { stage = 3 })
            c.left = 1e9
            for _ = 1, 4 do                            -- the first roll (at 4 minutes) misses: 0.43
                Engine.step(Sim.step(p), defs, 1)
            end
            assert.equal(0, #p.sent)
            assert.equal(30, c.data.fallIn)
            for _ = 1, 30 do                           -- the next one hits: 0.41
                Engine.step(Sim.step(p), defs, 1)
            end
            assert.equal("fall", p.sent[1][1])
            assert.equal(0, p.body.damages[1].floor)   -- stage 3 has no floor
        end)
    end)

    describe("ambient lines (W35)", function()
        for id, stages in pairs({ ahtr = { 1, 2, 3, 4 }, cellulitis = { 2, 3, 4 }, sepsis = { 1, 2, 3, 4 },
            tetanus = { 2, 3, 4 } }) do
            it(id .. " speaks a line of its own pool in every stage that has one", function()
                for _, stage in ipairs(stages) do
                    local p = Sim.context({ float = 0, sandbox = { DialogueFrequency = 4 } })
                    local c = contract(p, id, { stage = stage })
                    c.left = 1e9
                    c.data.fallIn = 1e9
                    Engine.step(Sim.step(p), defs, 5)
                    local pool = {}
                    for _, key in ipairs(defs[id].lines.random[stage]) do pool[key] = true end
                    local spoken = false
                    for _, key in ipairs(p.said) do spoken = spoken or pool[key] == true end
                    assert.is_true(spoken, id .. " stage " .. stage)
                end
            end)
        end
    end)

    describe("AHTR", function()
        it("has effects from stage 1 and drains health to 50 in stage 2", function()
            local p = Sim.context()
            local c = contract(p, "ahtr")
            Engine.step(Sim.step(p), defs, 1)
            assert.is_true(p.body.pains.Torso_Lower.ahtr > 0)
            assert.equal(0, #p.body.damages)
            c.stage, c.left = 2, 1e9
            Engine.step(Sim.step(p), defs, 1)
            assert.equal(50, p.body.damages[1].floor)
        end)
    end)
end)
