-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The environmental diseases (Diseases/Weather): cold and heat meters, common cold and its pneumonia complication,
-- pneumonia, hypothermia, heat exhaustion and heat stroke with its cures.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Exposure = require("ExtensiveHealthRedone/Diseases/Weather/Exposure")
local Meters = require("ExtensiveHealthRedone/Diseases/Weather/Meters")
local Hypothermia = require("ExtensiveHealthRedone/Diseases/Weather/Hypothermia")
local Sim = require("support/sim")

-- One full step: the weather systems, then the condition engine, with fresh aggregators.
local function step(p, dt)
    Sim.step(p)
    for _, system in ipairs(Exposure.systems) do
        system.update(p, dt, defs)
    end
    Engine.step(p, defs, dt)
end

local function run(p, minutes)
    for _ = 1, minutes do
        step(p, 1)
    end
end

local function contract(p, id, opts)
    return Engine.contract(p, defs, id, opts) --[[@as table]]
end

local function noises(p, kind)
    local n = 0
    for _, noise in ipairs(p.noises) do
        if noise[1] == kind then
            n = n + 1
        end
    end
    return n
end

describe("weather", function()
    describe("cold meter and common cold", function()
        it("builds outdoors when wet at 5 deg C or below, not at 6, and rolls once per hour", function()
            local p = Sim.context()
            p.facts.env.wetness, p.facts.env.airC = 0.5, 6
            run(p, 120)
            assert.equal(0, Meters.weather(p).coldH)

            p.facts.env.airC = 5
            run(p, 81)                                  -- 1.5 meter-hours per hour: ready after 80 minutes
            assert.near(2.0, Meters.weather(p).coldH, 0.03)
            assert.equal(100, p.state.exposure.cold)
            assert.is_nil(p.state.conditions.active.common_cold)     -- the default float 0.99 never rolls
            assert.truthy(Meters.weather(p).timers.coldRoll)
        end)

        it("catches the cold on a successful roll and resets the meters", function()
            local p = Sim.context({ float = 0 })
            p.facts.env.wetness, p.facts.env.airC = 0.5, 0
            run(p, 90)
            assert.truthy(p.state.conditions.active.common_cold)
            assert.is_true(Meters.weather(p).coldH < 0.5)      -- reset on catching it, building again since
            assert.truthy(Sim.said(p, "UI_EHR_Text_SniffIFeelABitRunDown"))
        end)

        it("counts being soaked anywhere, indoors too, and drains when warm and dry", function()
            local p = Sim.context()
            p.facts.env.wetness, p.facts.env.indoors, p.facts.env.airC = 0.95, true, 20
            run(p, 60)
            assert.near(1.0, Meters.weather(p).soakedH, 0.01)
            p.facts.env.wetness = 0
            run(p, 30)
            assert.near(0, Meters.weather(p).soakedH, 0.01)
        end)

        it("sets vanilla's cold by stage and sneezes, but not in its sleep", function()
            local p = Sim.context()
            local c = contract(p, "common_cold", { stage = 3 })
            c.left = 1e6
            step(p, 1)
            assert.equal(65, p.body.coldStrength)
            run(p, 31)
            assert.equal(1, noises(p, "sneeze"))
            p.facts.asleep = true
            run(p, 60)
            assert.equal(1, noises(p, "sneeze"))
            Engine.setStage(p, defs, "common_cold", 1)
            step(p, 1)
            assert.equal(0, p.body.coldStrength)
        end)

        it("rolls for pneumonia on entering stage 4 untreated, and the pneumonia replaces the cold", function()
            local p = Sim.context({ float = 0 })
            contract(p, "common_cold", { stage = 3 })
            Engine.setStage(p, defs, "common_cold", 4)
            assert.truthy(p.state.conditions.active.pneumonia)
            assert.is_nil(p.state.conditions.active.common_cold)
            assert.truthy(Sim.said(p, "UI_EHR_Text_CoughsViolentlyThisIsntJustAColdAnymore"))
        end)

        it("skips the pneumonia roll while a cold treatment is running", function()
            local p = Sim.context({ float = 0, treatment = { curing = { common_cold = true } } })
            contract(p, "common_cold", { stage = 3 })
            Engine.setStage(p, defs, "common_cold", 4)
            assert.is_nil(p.state.conditions.active.pneumonia)
            assert.truthy(p.state.conditions.active.common_cold)
        end)
    end)

    describe("pneumonia", function()
        it("drains to 30 HP in stage 3 and without a floor in stage 4, unless a cure course runs", function()
            local p = Sim.context()
            local c = contract(p, "pneumonia", { stage = 3 })
            c.left = 1e6
            step(p, 60)
            assert.near(2.5, p.body.damages[1].hp, 1e-6)
            assert.equal(30, p.body.damages[1].floor)
            Engine.setStage(p, defs, "pneumonia", 4)
            c.left = 1e6
            step(p, 60)
            assert.near(4.0, p.body.damages[1].hp, 1e-6)
            assert.equal(0, p.body.damages[1].floor)

            local treated = Sim.context({ treatment = { curing = { pneumonia = true } } })
            contract(treated, "pneumonia", { stage = 4 })
            step(treated, 60)
            assert.equal(0, #treated.body.damages)
        end)

        it("coughs severely from stage 2, at most once per throttle, never asleep", function()
            local p = Sim.context()
            local c = contract(p, "pneumonia", { stage = 2 })
            c.left = 1e6
            run(p, 61)
            assert.equal(1, noises(p, "coughSevere"))
            p.facts.asleep = true
            run(p, 120)
            assert.equal(1, noises(p, "coughSevere"))
        end)
    end)

    describe("hypothermia", function()
        local function cold(p, temp)
            p.facts.stats.TEMPERATURE = temp
        end

        it("follows body temperature: worse stages at once, back one band at a time with slack", function()
            local p = Sim.context()
            cold(p, 34.9)
            step(p, 1)
            local c = p.state.conditions.active.hypothermia
            assert.equal(1, c.stage)
            cold(p, 31.9)
            step(p, 1)
            assert.equal(3, c.stage)
            cold(p, 32.2)                           -- within 0.25 of stage 3's 32.0: still 3
            step(p, 1)
            assert.equal(3, c.stage)
            cold(p, 32.3)
            step(p, 1)
            assert.equal(2, c.stage)
            cold(p, 35.4)                           -- above stage 1 but below the clear temperature
            step(p, 1)
            assert.equal(1, c.stage)
            cold(p, 35.6)
            step(p, 1)
            assert.is_nil(p.state.conditions.active.hypothermia)
            assert.truthy(Sim.said(p, "UI_EHR_Text_StopsShivering"))
        end)

        it("speaks only when it gets worse, and the coldest stage no longer says it is warming up", function()
            local p = Sim.context()
            cold(p, 30.5)
            step(p, 1)
            assert.same({ "EHR_Dialogue_Hypothermia_S4_Novice_1" }, p.said)
            cold(p, 33.5)
            step(p, 1)
            assert.equal(1, #p.said)
        end)

        it("slows, blocks sprint from stage 2 and drains health from stage 2", function()
            local p = Sim.context()
            cold(p, 33.9)
            step(p, 1)
            step(p, 60)
            assert.equal(0.76, p.fx.values.speed)
            assert.is_true(p.fx.values.noSprint)
            assert.near(2, p.body.damages[1].hp, 1e-6)
        end)

        it("is off with BodyTemperatureEnabled=false or HypothermiaEnabled=false", function()
            for _, sandbox in ipairs({ { BodyTemperatureEnabled = false }, { HypothermiaEnabled = false },
                { DiseaseEnabled = false } }) do
                local p = Sim.context({ sandbox = sandbox })
                cold(p, 30)
                step(p, 1)
                assert.is_nil(p.state.conditions.active.hypothermia)
            end
        end)

        it("clamps the sandbox thresholds into order", function()
            local p = Sim.context({ sandbox = { HypothermiaStage1Temp = 33, HypothermiaStage2Temp = 34,
                HypothermiaClearTemp = 32 } })
            local t = Hypothermia.thresholds(p)
            assert.near(32.9, t[2], 1e-9)
            assert.equal(33, t.clear)
        end)
    end)

    describe("heat meter and heat exhaustion", function()
        local function hot(p, air)
            p.facts.env.airC, p.facts.env.hour = air, 12
        end

        it("fills in 4 h at 30 deg C, faster in more heat, much slower with a hat, and drains indoors", function()
            local p = Sim.context()
            hot(p, 30)
            assert.near(1, Exposure.heatRate(p), 1e-9)
            hot(p, 35)
            assert.near(1.3, Exposure.heatRate(p), 1e-9)
            p.facts.weather = { headwear = true }
            assert.near(0.39, Exposure.heatRate(p), 1e-9)
            p.facts.env.indoors = true
            assert.near(-2.25, Exposure.heatRate(p), 1e-9)
            p.facts.env.indoors, p.facts.env.hour = false, 22
            assert.near(-1.25, Exposure.heatRate(p), 1e-9)
        end)

        it("moves heat exhaustion through the meter's stages and recovers as the meter falls", function()
            local p = Sim.context()
            hot(p, 30)
            run(p, 85)                                  -- 35% of a 4 h meter
            local c = p.state.conditions.active.heat_exhaustion
            assert.equal(1, c.stage)
            run(p, 60)                                  -- 60%
            assert.equal(2, c.stage)
            assert.equal(0.9, p.fx.values.speed)
            run(p, 60)                                  -- 85%
            assert.equal(3, c.stage)
            assert.is_true(p.fx.values.noSprint)
            p.facts.env.indoors = true
            run(p, 6)
            assert.equal(4, c.stage)
            run(p, 120)
            assert.is_nil(p.state.conditions.active.heat_exhaustion)
        end)

        it("starts heat stroke at a full meter, and rolls every 5 minutes between 85% and 100%", function()
            local p = Sim.context()
            Meters.weather(p).heatH = 3.6                -- 90%
            hot(p, 30)
            step(p, 1)
            assert.is_nil(p.state.conditions.active.heat_stroke)
            assert.truthy(Meters.weather(p).timers.strokeRoll)
            Meters.weather(p).heatH = 4
            step(p, 1)
            assert.truthy(p.state.conditions.active.heat_stroke)
            assert.equal(0, Meters.weather(p).heatH)

            local lucky = Sim.context({ float = 0 })
            Meters.weather(lucky).heatH = 3.5
            hot(lucky, 30)
            step(lucky, 1)
            assert.truthy(lucky.state.conditions.active.heat_stroke)
        end)

        it("is all off with HeatExhaustionEnabled=false", function()
            local p = Sim.context({ sandbox = { HeatExhaustionEnabled = false } })
            hot(p, 40)
            run(p, 400)
            assert.equal(0, Meters.weather(p).heatH)
            assert.is_nil(p.state.conditions.active.heat_stroke)
        end)
    end)

    describe("heat stroke", function()
        local function stroke(p)
            local c = contract(p, "heat_stroke")
            p.facts.env.airC, p.facts.env.hour = 32, 12
            return c
        end

        it("drains only from stage 2", function()
            local p = Sim.context()
            local c = stroke(p)
            c.left = 1e6
            Engine.step(Sim.step(p), defs, 0.01)
            assert.equal(0, #p.body.damages)
            Engine.setStage(p, defs, "heat_stroke", 2)
            c.left = 1e6
            Engine.step(Sim.step(p), defs, 60)
            assert.near(15, p.body.damages[1].hp, 1e-6)
        end)

        it("holds at stage 3 while hot and recovers once cooled", function()
            local p = Sim.context()
            local c = stroke(p)
            run(p, 9 * 60)
            assert.equal(3, c.stage)
            assert.truthy(Sim.said(p, "UI_EHR_Text_PantsStillTooHotCantRecover"))
            p.facts.env.airC = 25
            run(p, 9 * 60)
            assert.is_nil(p.state.conditions.active.heat_stroke)
        end)

        it("is cured by 3 h in air at or below 10 deg C, a car's AC included", function()
            local p = Sim.context()
            local c = stroke(p)
            c.left = 1e6
            p.facts.env.vehicleC = 9
            run(p, 179)
            assert.truthy(p.state.conditions.active.heat_stroke)
            assert.equal(0, #p.body.damages)            -- cooling stops the drain
            run(p, 1)
            assert.is_nil(p.state.conditions.active.heat_stroke)
        end)

        it("is cured by a 3 h cold bath kept alive by heartbeats, and the bath lapses without them", function()
            local p = Sim.context()
            local c = stroke(p)
            c.left = 1e6
            Meters.weather(p).bath = { left = 15, elapsed = 0 }
            for _ = 1, 18 do
                run(p, 10)
                if Meters.weather(p).bath then
                    Meters.weather(p).bath.left = 15
                end
            end
            assert.is_nil(p.state.conditions.active.heat_stroke)
            assert.same({ "coldBathDone", { cured = true } }, p.sent[#p.sent])

            local q = Sim.context()
            stroke(q).left = 1e6
            Meters.weather(q).bath = { left = 15, elapsed = 0 }
            run(q, 16)
            assert.is_nil(Meters.weather(q).bath)
            assert.truthy(q.state.conditions.active.heat_stroke)
        end)

        it("collapses into a forced sleep, then not again for 45 awake minutes", function()
            local p = Sim.context({ float = 0 })
            local c = stroke(p)
            c.left = 1e6
            run(p, 5)
            local falls = 0
            for _, sent in ipairs(p.sent) do
                if sent[1] == "blackout" then
                    falls = falls + 1
                end
            end
            assert.equal(1, falls)
            run(p, 40)
            local again = 0
            for _, sent in ipairs(p.sent) do
                if sent[1] == "blackout" then
                    again = again + 1
                end
            end
            assert.equal(1, again)
        end)
    end)
end)
