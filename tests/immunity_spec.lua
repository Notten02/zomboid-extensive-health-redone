-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The immune system: factors, hygiene, target, the 15-minute movement, suppression, the Phalanx debuff, the sandbox
-- switches, and wound containment.
local Immunity = require("ExtensiveHealthRedone/Immunity/Immunity")
local Data = require("ExtensiveHealthRedone/Data/Immunity")
local Risk = require("ExtensiveHealthRedone/Conditions/Risk")
local Infection = require("ExtensiveHealthRedone/Wounds/Infection")
local Provider = require("ExtensiveHealthRedone/Medication/Provider")
local Schema = require("ExtensiveHealthRedone/Core/Schema")
local Sim = require("support/sim")

-- A context whose immune system already runs at score, with a typical survivor's needs.
local function survivor(opts)
    opts = opts or {}
    local p = Sim.context(opts)
    p.facts.norm = { HUNGER = 0.2, THIRST = 0.1, FATIGUE = 0.3, STRESS = 0.1 }
    p.facts.hygiene = { dirt = 0, blood = 0 }
    if opts.score then
        p.state.immunity.score, p.state.immunity.target = opts.score, opts.score
    end
    return p
end

local function minutes(p, n)
    for _ = 1, n do
        Immunity.update(Sim.step(p), 1)
    end
end

describe("immunity target", function()
    it("weighs the six factors (v0.9's typical survivor: 92.8)", function()
        local p = survivor()
        local f = Immunity.factors(p.facts.norm, 100, 100, 0)
        assert.same({ nutrition = 80, hydration = 90, rest = 100, stressControl = 90, bloodCondition = 100,
            healthReserve = 100 }, f)
        assert.equal(92.8, Immunity.baseTarget(f, Immunity.hygiene(0, 0)))
    end)

    it("loses rest past half fatigue, and blood below 40%", function()
        local f = Immunity.factors({ FATIGUE = 0.75 }, 100, 70, 0)
        assert.equal(50, f.rest)
        assert.equal(50, f.bloodCondition)
        assert.equal(0, Immunity.factors({ FATIGUE = 1 }, 100, 30, 0).rest)
        assert.equal(0, Immunity.factors({}, 100, 30, 0).bloodCondition)
    end)

    it("takes the hygiene penalty off: 30% dirt and 10% blood cost 23.4", function()
        local h = Immunity.hygiene(0.30, 0.10)
        assert.equal(16.3, h.dirtPenalty)
        assert.equal(7.1, h.bloodPenalty)
        assert.equal(23.4, h.penalty)
        local f = Immunity.factors({ HUNGER = 0.2, THIRST = 0.1, FATIGUE = 0.3, STRESS = 0.1 }, 100, 100, 0)
        assert.equal(69.4, Immunity.baseTarget(f, h))
        assert.equal(Data.HYGIENE_MAX, Immunity.hygiene(1, 1).penalty)
        assert.equal(0, Immunity.hygiene(0.05, 0.02).penalty)
    end)

    it("counts disease pressure against the health reserve", function()
        local p = survivor()
        local active = p.state.conditions.active
        active.common_cold = { stage = 2 }
        assert.equal(12, Immunity.pressure(p.state))
        active.insomnia = { stage = 2 }
        assert.equal(18, Immunity.pressure(p.state))      -- mental conditions count half
        active.insomnia = nil
        active.knox_infection = { stage = 3 }
        assert.equal(12, Immunity.pressure(p.state))
        active.sepsis = { stage = 1 }
        assert.equal(37, Immunity.pressure(p.state))
        p.state.wounds.parts.Hand_L = { phase = "infected", stage = 2 }
        p.state.wounds.parts.Hand_R = { phase = "incubating", left = 60 }
        assert.equal(47, Immunity.pressure(p.state))
        active.pneumonia, active.tetanus = { stage = 4 }, { stage = 4 }
        assert.equal(Data.PRESSURE.MAX, Immunity.pressure(p.state))
    end)
end)

describe("immunity score", function()
    it("starts a new character at 75, then drifts toward its target", function()
        local p = survivor({ state = Schema.new({ int = function(lo) return lo end }) })
        assert.equal(Data.START, p.state.immunity.score)
        assert.is_false(p.state.immunity.target)
        minutes(p, 1)
        assert.equal(75.4, p.state.immunity.score)
        assert.equal(92.8, p.state.immunity.target)
        assert.equal("recovering", p.state.immunity.trend)
        assert.equal(Data.TICK_MINUTES, p.state.immunity.tick)
    end)

    it("keeps an imported score, which then moves at the normal rate", function()
        local p = survivor()
        p.state.immunity.score = 40
        minutes(p, 1)
        assert.equal(40.4, p.state.immunity.score)
        assert.equal("recovering", p.state.immunity.trend)
    end)

    it("updates every 15 game minutes: +0.375 or -0.75 a step at the default rates", function()
        local p = survivor({ score = 60 })
        minutes(p, 1)
        assert.equal(60.4, p.state.immunity.score)
        minutes(p, 14)
        assert.equal(60.4, p.state.immunity.score)
        minutes(p, 1)
        assert.equal(60.8, p.state.immunity.score)
        local q = survivor({ score = 99 })
        minutes(q, 1)
        assert.equal(98.3, q.state.immunity.score)
        assert.equal("declining", q.state.immunity.trend)
    end)

    it("scales the movement with ImmunityRecoveryRate and ImmunityDeclineRate", function()
        local p = survivor({ score = 60, sandbox = { ImmunityRecoveryRate = 2 } })
        minutes(p, 1)
        assert.equal(60.8, p.state.immunity.score)
        local q = survivor({ score = 99, sandbox = { ImmunityDeclineRate = 0.25 } })
        minutes(q, 1)
        assert.equal(98.8, q.state.immunity.score)
    end)

    it("settles on the target", function()
        local p = survivor({ score = 92.6 })
        minutes(p, 1)
        assert.equal(92.8, p.state.immunity.score)
        minutes(p, 15)
        assert.equal("stable", p.state.immunity.trend)
    end)

    it("syncs on each update only", function()
        local p = survivor({ score = 60 })
        minutes(p, 15)
        assert.equal(1, p.dirtied.immunity)
    end)
end)

describe("immunity suppression", function()
    it("drops 4 points a step toward 35 while a systemic antibiotic is active (guide: 90 -> 86)", function()
        local p = survivor({ score = 90, treatment = { active = { antibiotic = true } } })
        minutes(p, 1)
        assert.equal(86, p.state.immunity.score)
        assert.equal(Data.SUPPRESSED_CAP, p.state.immunity.target)
        assert.is_true(p.state.immunity.pressures.antibiotic)
        minutes(p, 15 * 20)
        assert.equal(35, p.state.immunity.score)
    end)

    it("lets a low score rise to 35 during a course", function()
        local p = survivor({ score = 30, treatment = { active = { antibiotic = true } } })
        minutes(p, 1)
        assert.equal(30.4, p.state.immunity.score)
    end)

    it("counts the antibiotic flag only: ointments don't suppress", function()
        local state = Schema.new({ int = function(lo) return lo end })
        state.meds.doses.AntibioticOintment = { since = 0 }
        local _, flags = Provider.activeDoses(state)
        assert.is_nil(flags.antibiotic)
        state.meds.doses.PrescriptionAntibiotics = { since = 0 }
        _, flags = Provider.activeDoses(state)
        assert.is_true(flags.antibiotic)
    end)

    it("suppresses the same way under the immunosuppression side effect", function()
        local p = survivor({ score = 90 })
        p.state.meds.side.immunosuppression = { left = 60 }
        minutes(p, 1)
        assert.equal(86, p.state.immunity.score)
        assert.is_true(p.state.immunity.pressures.immunosuppression)
    end)

    it("takes 20 points off the target during the Phalanx debuff", function()
        local p = survivor({ score = 90 })
        p.state.knox.effects.phalanxDebuff = 60
        minutes(p, 1)
        assert.equal(72.8, p.state.immunity.target)
        assert.equal(89.3, p.state.immunity.score)
        assert.equal(20, p.state.immunity.pressures.phalanx)
    end)
end)

describe("immunity switches", function()
    it("freezes the score when the system is off, and every roll is neutral", function()
        local p = survivor({ score = 30, sandbox = { ImmunitySystemEnabled = false } })
        minutes(p, 60)
        assert.equal(30, p.state.immunity.score)
        assert.equal("disabled", p.state.immunity.trend)
        assert.equal(0.2, Risk.chance(p, "common_cold", 0.2))
        assert.equal(0, Risk.strength(p))
    end)

    it("moves the score but changes nothing in monitoring-only mode", function()
        for _, sandbox in ipairs({ { ImmunityGameplayEffects = false }, { ImmunityEffectStrength = 0 } }) do
            local p = survivor({ score = 10, sandbox = sandbox })
            minutes(p, 1)
            assert.equal(10.4, p.state.immunity.score)
            assert.equal(0.2, Risk.chance(p, "common_cold", 0.2))
            assert.equal(0, Infection.containChance(100, Risk.strength(p)))
        end
    end)
end)

describe("wound containment", function()
    it("scales with ImmunityEffectStrength, capped at 65%", function()
        assert.near(0.45, Infection.containChance(100, 1), 1e-9)
        assert.near(0.65, Infection.containChance(100, 2), 1e-9)
        assert.near(0.225, Infection.containChance(60, 1), 1e-9)
        assert.equal(0, Infection.containChance(100, 0))
    end)
end)

describe("immunity bands", function()
    it("labels the score like the guide", function()
        assert.equal("Suppressed", Immunity.band(0))
        assert.equal("Suppressed", Immunity.band(19.9))
        assert.equal("Compromised", Immunity.band(20))
        assert.equal("Strained", Immunity.band(40))
        assert.equal("Stable", Immunity.band(60))
        assert.equal("Strong", Immunity.band(80))
        assert.equal("Strong", Immunity.band(100))
    end)
end)

describe("immunity schema", function()
    it("migrates a version 4 state, keeping its score", function()
        local state = Schema.new({ int = function(lo) return lo end })
        state.version, state.immunity = 4, { score = 63.4 }
        assert.is_true(Schema.upgrade(state))
        Schema.fillDefaults(state)
        assert.equal(63.4, state.immunity.score)
        assert.is_false(state.immunity.target)
        assert.equal(0, state.immunity.tick)
    end)
end)

insulate("immunity hygiene reader", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local ServerImmunity = require("ExtensiveHealthRedone/Server/Immunity")

    it("averages the worst of skin and worn clothing over every body part (clothing counts)", function()
        local player = game.addPlayer({})
        player.visual.dirt.Hand_L = 0.9
        player.visual.blood.Torso_Upper = 0.2
        player.worn = { { clothing = true, soil = { Torso_Upper = { dirt = 0.5, blood = 0.9 } },
            getFullType = function() return "Base.Tshirt_DefaultTEXTURE" end } }
        local soil = ServerImmunity.soil(player)
        assert.near((0.9 + 0.5) / 18, soil.dirt, 1e-9)
        assert.near(0.9 / 18, soil.blood, 1e-9)
    end)
end)
