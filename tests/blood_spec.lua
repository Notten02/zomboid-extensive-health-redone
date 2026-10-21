-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Blood volume: bleeding, regeneration, stages, blackouts, death and saline (Blood/Blood).
local Blood = require("ExtensiveHealthRedone/Blood/Blood")
local Data = require("ExtensiveHealthRedone/Data/Blood")
local Timers = require("ExtensiveHealthRedone/Core/Timers")
local Sim = require("support/sim")

local function bleed(p, name, wound, health)
    local part = p.facts.parts[name]
    part.bleeding = true
    part[wound] = true
    part.health = health
end

describe("Blood", function()
    describe("bleeding", function()
        it("scales with wound type and body part, capped per part, x1.4 on the neck", function()
            -- neck, deep, 40 damage: 40 * 0.4 * 2.5 * 1.4 * 0.5 = 28, capped at 5 * 1.4
            assert.near(7, Blood.partLoss("Neck", { bleeding = true, deep = true, health = 60 }), 1e-9)
            -- upper leg, cut, 20 damage: 20 * 0.12 * 1.2 * 0.5
            assert.near(1.44, Blood.partLoss("UpperLeg_L", { bleeding = true, cut = true, health = 80 }), 1e-9)
            -- the worst wound wins: deep beats scratch
            assert.near(0.4, Blood.woundRate({ deep = true, scratch = true }), 1e-9)
            assert.near(0.15, Blood.woundRate({}), 1e-9)
            -- a part at full health loses nothing, a bandaged part loses nothing
            assert.equal(0, Blood.partLoss("Neck", { bleeding = true, deep = true, health = 100 }))
            assert.equal(0, Blood.partLoss("Neck", { bleeding = true, deep = true, bandaged = true, health = 10 }))
        end)

        it("drains game-minute volume x BloodLossMultiplier x 2.5 updates per minute", function()
            local p = Sim.context({ sandbox = { BloodLossMultiplier = 2 } })
            bleed(p, "Neck", "deep", 60)
            Blood.update(p, 1)
            assert.near(5000 - 7 * 2 * 2.5, p.state.blood.volume, 1e-9)
            assert.is_true(p.state.blood.bleeding)
            assert.is_true(Timers.running(p.state.blood.timers, "regenDelay"))
        end)

        it("stops when the part is bandaged, without giving lost blood back", function()
            local p = Sim.context()
            bleed(p, "Neck", "deep", 60)
            Blood.update(p, 1)
            local after = p.state.blood.volume
            p.facts.parts.Neck.bandaged = true
            Blood.update(Sim.step(p), 1)
            assert.equal(after, p.state.blood.volume)
            assert.is_false(p.state.blood.bleeding)
        end)
    end)

    describe("regeneration", function()
        it("waits for the delay after bleeding, then adds the hourly rate, faster while healing conditions hold", function()
            local p = Sim.context({ sandbox = { BloodRegenDelayHours = 2, BloodRegenRatePerHour = 60 } })
            p.state.blood.volume = 4000
            Timers.start(p.state.blood.timers, "regenDelay", 120)
            Blood.update(p, 60)
            assert.equal(4000, p.state.blood.volume)
            Blood.update(Sim.step(p), 60)  -- the delay ran out at the start of this step
            assert.near(4000 + 60 * 1.5, p.state.blood.volume, 1e-9)
            p.facts.norm.HUNGER = 0.9      -- hungry: no bonus
            Blood.update(Sim.step(p), 60)
            assert.near(4000 + 90 + 60, p.state.blood.volume, 1e-9)
        end)

        it("never regenerates below the minimum, when disabled, or past the maximum", function()
            local p = Sim.context({ sandbox = { BloodRegenMinimumPercent = 30 } })
            p.state.blood.volume = 1400
            Blood.update(p, 60)
            assert.equal(1400, p.state.blood.volume)
            local q = Sim.context({ sandbox = { BloodRegenEnabled = false } })
            q.state.blood.volume = 4000
            Blood.update(q, 60)
            assert.equal(4000, q.state.blood.volume)
            local r = Sim.context({ sandbox = { BloodRegenRatePerHour = 200 } })
            r.state.blood.volume = 4990
            Blood.update(r, 60)
            assert.equal(5000, r.state.blood.volume)
        end)
    end)

    describe("stages", function()
        it("follow the sandbox thresholds, speak on getting worse, and cap endurance", function()
            local p = Sim.context()
            p.state.blood.volume = 4100       -- 82 %: mild
            Blood.update(p, 1)
            assert.equal(Blood.MILD, p.state.blood.stage)
            assert.is_true(Sim.said(p, "UI_EHR_Dialogue_Blood_Stage3"))
            assert.equal(0.75, Sim.resolve(p, "ENDURANCE", 1))
            p.state.blood.volume = 3600       -- 72 %: moderate
            Blood.update(Sim.step(p), 1)
            assert.equal(Blood.MODERATE, p.state.blood.stage)
            assert.equal(0.5, Sim.resolve(p, "ENDURANCE", 1))
            p.state.blood.volume = 3000       -- 60 %: critical, no endurance at all
            Blood.update(Sim.step(p), 1)
            assert.equal(Blood.CRITICAL, p.state.blood.stage)
            assert.equal(0, Sim.resolve(p, "ENDURANCE", 1))
            p.state.blood.volume = 4500       -- recovered: no line, no penalty
            local said = #p.said
            Blood.update(Sim.step(p), 1)
            assert.equal(Blood.HEALTHY, p.state.blood.stage)
            assert.equal(said, #p.said)
            assert.equal(1, Sim.resolve(p, "ENDURANCE", 1))
        end)

        it("count blood as 5 points lower under a beta blocker, below 90 %", function()
            assert.near(0.82, Blood.functionalShare(0.87, true), 1e-9)
            assert.equal(0.95, Blood.functionalShare(0.95, true))
            assert.equal(0.87, Blood.functionalShare(0.87, false))
            local p = Sim.context({ treatment = { active = { betaBlocker = true } } })
            p.state.blood.volume = 4350       -- 87 %: healthy, but mild with the blocker
            Blood.update(p, 1)
            assert.equal(Blood.MILD, p.state.blood.stage)
        end)
    end)

    describe("death", function()
        it("kills at once at 5 % or less", function()
            local p = Sim.context()
            p.state.blood.volume = 200
            Blood.update(p, 1)
            assert.equal("exsanguination", p.body.killed.cause)
        end)

        it("rolls 1 in 50 per update below 20 %, also when blackouts are disabled", function()
            local lucky = Sim.context({ sandbox = { BlackoutEnabled = false } })
            lucky.state.blood.volume = 900
            Blood.update(lucky, 1)
            assert.is_nil(lucky.body.killed)
            local unlucky = Sim.context({ sandbox = { BlackoutEnabled = false }, floats = { 0.01 } })
            unlucky.state.blood.volume = 900
            Blood.update(unlucky, 1)
            assert.equal("hypovolemic shock", unlucky.body.killed.cause)
        end)
    end)

    describe("blackouts", function()
        local function critical(opts)
            local p = Sim.context(opts)
            p.state.blood.volume = 3000
            p.state.blood.stage = Blood.CRITICAL
            return p
        end

        it("knock the character out, then wait for the cooldown", function()
            local p = critical({ floats = { 0.0 }, sandbox = { BlackoutCooldownHours = 24 } })
            Blood.update(p, 1)
            assert.is_true(p.state.blood.blackout)
            assert.equal("blackout", p.sent[1][1])
            assert.equal(Data.BLACKOUT_HOURS, p.sent[1][2].hours)
            assert.near(24 * 60, Timers.remaining(p.state.blood.timers, "blackoutCooldown"), 1e-9)
            assert.equal(1, Sim.resolve(p, "FATIGUE", 0.2))
        end)

        it("halve fatigue on waking", function()
            local p = critical({ floats = { 0.0 } })
            Blood.update(p, 1)
            p.facts.asleep = true
            Blood.update(Sim.step(p), 30)
            assert.is_true(p.state.blood.blackout)
            p.facts.asleep = false
            p.facts.stats.FATIGUE = 0.8
            Blood.update(Sim.step(p), 1)
            assert.is_false(p.state.blood.blackout)
            assert.near(0.4, Sim.resolve(p, "FATIGUE", 0.8), 1e-9)
            assert.is_true(Sim.said(p, "UI_EHR_Dialogue_Blackout_Wake"))
        end)

        it("are prevented by panic or stress above half, unless a beta blocker is active", function()
            local p = critical({ floats = { 0.0 } })
            p.facts.norm.PANIC = 0.6
            Blood.update(p, 1)
            assert.is_false(p.state.blood.blackout)
            local q = critical({ floats = { 0.0 }, treatment = { active = { betaBlocker = true } } })
            q.facts.norm.PANIC = 0.6
            Blood.update(q, 1)
            assert.is_true(q.state.blood.blackout)
        end)

        it("never happen with BlackoutEnabled off", function()
            local p = critical({ floats = { 0.0, 0.0 }, sandbox = { BlackoutEnabled = false } })
            Blood.update(p, 1)
            assert.is_false(p.state.blood.blackout)
        end)
    end)

    describe("saline", function()
        it("decays, and dilutes blood dangerously above 40 % and lethally above 60 %", function()
            local p = Sim.context()
            p.state.blood.saline = 2100        -- 42 %
            Blood.update(p, 1)
            assert.near(2100 - Data.SALINE_DECAY * 2.5, p.state.blood.saline, 1e-9)
            assert.is_true(Sim.resolve(p, "FATIGUE", 0.1) > 0.1)
            assert.is_true(Sim.resolve(p, "ENDURANCE", 1) < 1)
            assert.equal(0, #p.body.damages)
            p.state.blood.saline = 3100        -- 62 %
            Blood.update(Sim.step(p), 1)
            assert.equal(1, #p.body.damages)
            assert.equal(0, Sim.resolve(p, "ENDURANCE", 1))
        end)
    end)
end)
