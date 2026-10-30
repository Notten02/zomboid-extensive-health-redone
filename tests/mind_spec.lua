-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions passed to complete() are deliberately partial.
---@diagnostic disable: missing-fields
-- The Mind group: delirium, insomnia, painkiller addiction and pain sounds (Diseases/Mind), on the simulation context
-- of tests/support/sim.lua, plus the server and client wiring against the fake game.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Data = require("ExtensiveHealthRedone/Diseases/Mind/Data")
local Delirium = require("ExtensiveHealthRedone/Diseases/Mind/Delirium")
local Insomnia = require("ExtensiveHealthRedone/Diseases/Mind/Insomnia")
local Addiction = require("ExtensiveHealthRedone/Diseases/Mind/Addiction")
local PainSounds = require("ExtensiveHealthRedone/Diseases/Mind/PainSounds")
local Group = require("ExtensiveHealthRedone/Diseases/Mind/Group")
local Sim = require("support/sim")

local triggers = Group.systems[1].update

-- Runs the Mind triggers and the condition engine for `minutes`, one minute at a time.
local function run(p, minutes, before)
    for _ = 1, minutes do
        Sim.step(p)
        if before then before(p) end
        triggers(p, 1, defs)
        Engine.step(p, defs, 1)
    end
end

local function sent(p, command)
    local found = {}
    for _, message in ipairs(p.sent) do
        if message[1] == command then
            found[#found + 1] = message[2]
        end
    end
    return found
end

describe("Mind", function()
    it("registers the three conditions with their switches and knowledge", function()
        for id, option in pairs({ delirium = "DeliriumEnabled", insomnia = "InsomniaEnabled",
            painkiller_addiction = "PainkillerAddictionEnabled" }) do
            assert.equal(option, defs[id].enabledOption)
            assert.equal(id, defs[id].knowledge)
            assert.is_true(defs[id].selfEvident)
        end
    end)

    describe("delirium", function()
        it("starts after 12 continuous hours at maximum stress, asleep or awake", function()
            local p = Sim.context({ sandbox = { DialogueFrequency = 3 } })
            p.facts.norm.STRESS = 0.99
            p.facts.asleep = true
            run(p, 12 * 60 - 1)
            assert.is_nil(p.state.conditions.active.delirium)
            run(p, 1)
            assert.truthy(p.state.conditions.active.delirium)
            assert.is_true(Sim.said(p, Delirium.ENTRY_LINE))
            assert.equal(0, p.state.mind.stressFor)
        end)

        it("resets the stress clock on any lower sample, and waits while disabled", function()
            local p = Sim.context({ sandbox = { DeliriumEnabled = false } })
            p.facts.norm.STRESS = 1
            run(p, 6 * 60)
            p.facts.norm.STRESS = 0.5
            run(p, 1)
            assert.equal(0, p.state.mind.stressFor)
            p.facts.norm.STRESS = 1
            run(p, 13 * 60)
            assert.is_nil(p.state.conditions.active.delirium)
            assert.is_true(p.state.mind.stressFor >= 12 * 60)
        end)

        it("has its first episode 4-8 minutes in, then every 30-60, with a tint and an impulse", function()
            local p = Sim.context()
            Engine.contract(p, defs, "delirium")
            run(p, 4)                               -- rng.int returns the low end: 4 minutes
            local episodes = sent(p, "delirium")
            assert.equal(1, #episodes)
            assert.truthy(episodes[1].sound)
            assert.truthy(episodes[1].line:find("^UI_EHR_Text_"))
            assert.equal("shout", episodes[1].impulse)      -- nothing else is possible without p.facts.mind
            assert.equal("deliriumShout", p.noises[1][1])
            run(p, 1)
            assert.is_true(p.fx.values.tint >= Data.delirium.TINT_ALPHA[1])
            run(p, 28)                              -- the next one is 30 minutes after the first
            assert.equal(1, #sent(p, "delirium"))
            run(p, 1)
            assert.equal(2, #sent(p, "delirium"))
            assert.is_nil(sent(p, "delirium")[2].impulse)   -- the shout is cooling down for 45 minutes
        end)

        it("never repeats the same sound or line twice in a row", function()
            local p = Sim.context({ ints = { 1, 1, 1, 1, 1, 1, 1, 1 } })
            local c = Engine.contract(p, defs, "delirium") --[[@as table]]
            local a = Delirium.episode(p, c, false)
            local b = Delirium.episode(p, c, false)
            assert.are_not.equal(a.sound, b.sound)
            assert.are_not.equal(a.line, b.line)
        end)

        it("picks only impulses the character can act on, by weight", function()
            local p = Sim.context()
            p.facts.mind = { firearm = true, dropBackpack = false, window = true }
            local c = Engine.contract(p, defs, "delirium") --[[@as table]]
            -- Ready: firearm 25, window 30, shout 35. rng.int returns lo (1): the first, firearm.
            assert.equal("firearm", Delirium.episode(p, c, false).impulse)
            -- firearm cools down; then window 30, shout 35: the first again.
            assert.equal("window", Delirium.episode(p, c, false).impulse)
        end)

        it("waits while asleep or driving and stretches the schedule on antipsychotics", function()
            local p = Sim.context({ treatment = { active = { antipsychotic = true } } })
            Engine.contract(p, defs, "delirium")
            p.facts.asleep = true
            run(p, 60)
            assert.equal(0, #sent(p, "delirium"))
            p.facts.asleep = false
            run(p, 1)
            assert.equal(1, #sent(p, "delirium"))
            assert.equal(75, p.state.conditions.active.delirium.data.next)     -- 30 x 2.5
        end)

        it("keeps going until cured, and the cure clears it through the shared path", function()
            local p = Sim.context()
            Engine.contract(p, defs, "delirium")
            run(p, 3 * 24 * 60)
            assert.truthy(p.state.conditions.active.delirium)
            assert.is_true(Engine.cure(p, defs, "delirium"))
            assert.is_nil(p.state.conditions.active.delirium)
        end)
    end)

    describe("insomnia", function()
        it("starts after 12 hours awake at 80% fatigue; sleep resets the clock", function()
            local p = Sim.context({ sandbox = { DialogueFrequency = 3 } })
            p.facts.norm.FATIGUE = 0.85
            run(p, 11 * 60)
            p.facts.asleep = true
            run(p, 1)
            p.facts.asleep = false
            run(p, 12 * 60 - 1)
            assert.is_nil(p.state.conditions.active.insomnia)
            run(p, 1)
            assert.truthy(p.state.conditions.active.insomnia)
            assert.is_true(Sim.said(p, Insomnia.STAGE_LINES[1]))
        end)

        it("moves to stage 2 after a day and to a persistent stage 3 after another", function()
            local p = Sim.context()
            local c = Engine.contract(p, defs, "insomnia") --[[@as table]]
            run(p, 24 * 60)
            assert.equal(2, c.stage)
            run(p, 24 * 60)
            assert.equal(3, c.stage)
            run(p, 10 * 24 * 60)
            assert.equal(3, c.stage)
        end)

        it("blocks natural sleep from stage 2 unless a sleep aid is active", function()
            local p = Sim.context()
            Engine.contract(p, defs, "insomnia", { stage = 2 })
            run(p, 1)
            assert.is_true(p.fx.values.noSleep)
            local aided = Sim.context({ treatment = { active = { sleepAid = true } } })
            Engine.contract(aided, defs, "insomnia", { stage = 2 })
            run(aided, 1)
            assert.is_false(aided.fx.values.noSleep)
        end)

        it("pushes fatigue, stress and a headache, less with a sleep aid", function()
            local p = Sim.context()
            Engine.contract(p, defs, "insomnia", { stage = 3 })
            run(p, 1)
            assert.is_true(Sim.resolve(p, "FATIGUE", 0.5) > 0.5)
            assert.is_true(Sim.resolve(p, "STRESS", 0) > 0)
            assert.equal(28, p.body:painTargets().Head)
        end)

        -- One day: `awake` minutes up, then `asleep` minutes of sleep.
        local function day(p, asleep, opts)
            opts = opts or {}
            p.facts.asleep = false
            run(p, 24 * 60 - asleep)
            p.facts.asleep = true
            run(p, asleep, function(q)
                q.treatment = Sim.treatment({ active = { sleepAid = opts.aid, sleepTea = opts.tea } })
            end)
            p.facts.asleep = false
        end

        it("recovers from stage 1 after three good nights in a row, each one holding the stage", function()
            local p = Sim.context({ sandbox = { DialogueFrequency = 3 } })
            Engine.contract(p, defs, "insomnia")
            day(p, 7 * 60)
            day(p, 7 * 60)
            assert.equal(1, p.state.conditions.active.insomnia.stage)
            day(p, 7 * 60)
            assert.is_nil(p.state.conditions.active.insomnia)
            assert.is_true(Sim.said(p, "UI_EHR_Insomnia_Recovered"))
        end)

        it("counts a night with tea double", function()
            local p = Sim.context()
            Engine.contract(p, defs, "insomnia")
            day(p, 7 * 60, { tea = true })
            day(p, 7 * 60)
            assert.is_nil(p.state.conditions.active.insomnia)
        end)

        it("doesn't count short sleep, and a missed night breaks the streak", function()
            local p = Sim.context()
            local c = Engine.contract(p, defs, "insomnia") --[[@as table]]
            c.len[1] = 30 * 24 * 60
            c.left = c.len[1]
            day(p, 7 * 60)
            day(p, 7 * 60)
            day(p, 3 * 60)            -- too short, and more than 30 h since the last good night by tomorrow
            day(p, 3 * 60)
            assert.equal(0, c.data.streak)
            day(p, 7 * 60)
            assert.equal(1, c.data.streak)
        end)

        it("at stage 2 counts only nights with a sleep aid, and drops to stage 1", function()
            local p = Sim.context()
            local c = Engine.contract(p, defs, "insomnia", { stage = 2 }) --[[@as table]]
            day(p, 8 * 60)
            assert.equal(3, c.stage)                 -- unaided sleep didn't count, so the clock ran out
            local q = Sim.context()
            local d = Engine.contract(q, defs, "insomnia", { stage = 2 }) --[[@as table]]
            for _ = 1, 3 do
                day(q, 8 * 60, { aid = true })
            end
            assert.equal(1, d.stage)
        end)

        it("can come from a stimulant crash: 10%, at most once per 12 hours", function()
            local p = Sim.context({ floats = { 0.5, 0.05 } })
            assert.is_nil(Insomnia.stimulantCrash(p, defs, "caffeine_crash"))
            assert.is_nil(Insomnia.stimulantCrash(p, defs, "caffeine_crash"))     -- cooling down, no roll used
            run(p, 12 * 60)
            assert.truthy(Insomnia.stimulantCrash(p, defs, "caffeine_crash"))
            assert.equal("caffeine_crash", p.state.conditions.active.insomnia.source)
        end)
    end)

    describe("painkiller addiction", function()
        it("adds 1/1/1/1/8/12/20 risk by doses in a day, +4 for a redose within 3 h", function()
            assert.equal(1, Addiction.doseRisk(1, false))
            assert.equal(8, Addiction.doseRisk(5, false))
            assert.equal(12, Addiction.doseRisk(6, false))
            assert.equal(20, Addiction.doseRisk(9, false))
            assert.equal(24, Addiction.doseRisk(7, true))
        end)

        it("addicts at the 10th dose when taken every 3 hours (about 27 h)", function()
            local p = Sim.context()
            local doses = 0
            while not p.state.conditions.active.painkiller_addiction and doses < 20 do
                assert.is_true(Addiction.recordDose(p, defs, "Base.Pills"))
                doses = doses + 1
                run(p, 3 * 60)
            end
            assert.equal(10, doses)
            assert.equal(100, p.state.mind.painkiller.risk)
        end)

        it("ignores other items, herbal homemade painkillers and a duplicate report of the same dose", function()
            local p = Sim.context()
            assert.is_false(Addiction.recordDose(p, defs, "Base.PillsVitamins"))
            assert.is_false(Addiction.recordDose(p, defs, "ExtensiveHealth.HomemadePainkillers"))
            assert.is_true(Addiction.recordDose(p, defs, "Base.Pills"))
            assert.is_false(Addiction.recordDose(p, defs, "Base.Pills"))
            assert.equal(1, p.state.mind.painkiller.risk)
        end)

        it("decays 50 a day, only after a full day without a dose", function()
            local p = Sim.context()
            p.state.mind.painkiller.risk = 60
            Addiction.recordDose(p, defs, "Base.Pills")
            run(p, 24 * 60)
            assert.equal(61, p.state.mind.painkiller.risk)
            run(p, 24 * 60)
            assert.near(11, p.state.mind.painkiller.risk, 1e-6)
            assert.equal(0, #p.state.mind.painkiller.doses)
        end)

        it("stays off with PainkillerAddictionEnabled off", function()
            local p = Sim.context({ sandbox = { PainkillerAddictionEnabled = false } })
            p.state.mind.painkiller.risk = 99
            Addiction.recordDose(p, defs, "Base.Pills")
            assert.is_nil(p.state.conditions.active.painkiller_addiction)
        end)

        it("brings withdrawal that a painkiller dose suppresses for 3 hours, and persists at stage 3", function()
            local p = Sim.context()
            local c = Engine.contract(p, defs, "painkiller_addiction") --[[@as table]]
            run(p, 1)
            assert.is_true(Sim.resolve(p, "STRESS", 0) > 0)
            assert.is_true(Sim.resolve(p, "THIRST", 0) > 0)
            Addiction.recordDose(p, defs, "Base.Pills")
            run(p, 1)
            assert.is_true(Sim.resolve(p, "STRESS", 0.5) < 0.5)
            assert.equal(0, Sim.resolve(p, "THIRST", 0))
            run(p, 3 * 60)
            assert.is_true(Sim.resolve(p, "STRESS", 0) > 0)
            run(p, 2 * 24 * 60)
            assert.equal(3, c.stage)
            run(p, 5 * 24 * 60)
            assert.equal(3, c.stage)
        end)

        it("starts from nothing again after a cure", function()
            local p = Sim.context()
            p.state.mind.painkiller.risk = 99
            Addiction.recordDose(p, defs, "Base.Pills")
            assert.truthy(p.state.conditions.active.painkiller_addiction)
            Engine.cure(p, defs, "painkiller_addiction")
            assert.equal(0, p.state.mind.painkiller.risk)
            assert.equal(0, #p.state.mind.painkiller.doses)
        end)
    end)

    describe("pain sounds", function()
        local function painStep(p, pain)
            Sim.step(p)
            p.facts.norm.PAIN = pain
            PainSounds.update(p, 1)
        end

        it("cries out in real pain, scaled to ZombieAttractionRadius, then waits the cooldown", function()
            local p = Sim.context({ float = 0, sandbox = { ZombieAttractionRadius = 60, PainSoundCooldown = 300 } })
            painStep(p, 0.75)
            assert.equal(1, #p.noises)
            assert.equal("painSevere", p.noises[1][1])
            assert.equal(60, p.noises[1][2].radius)
            assert.equal(36, p.noises[1][2].volume)
            -- 300 real seconds = 120 game minutes at the default 1-hour day.
            for _ = 1, 119 do
                painStep(p, 0.75)
            end
            assert.equal(1, #p.noises)
            painStep(p, 0.75)
            assert.equal(2, #p.noises)
        end)

        it("uses the milder voice and a smaller radius at lower pain levels", function()
            local p = Sim.context({ float = 0 })
            painStep(p, 0.2)
            assert.equal("pain", p.noises[1][1])
            assert.equal(20, p.noises[1][2].radius)       -- 40 x 0.5
            assert.equal(0, PainSounds.level(0.1))
        end)

        it("stays quiet when disabled, asleep, under painkillers, or below the threshold", function()
            local off = Sim.context({ float = 0, sandbox = { PainSoundsEnabled = false } })
            painStep(off, 0.9)
            local asleep = Sim.context({ float = 0 })
            asleep.facts.asleep = true
            painStep(asleep, 0.9)
            local dosed = Sim.context({ float = 0 })
            Addiction.recordDose(dosed, defs, "Base.Pills")
            painStep(dosed, 0.9)
            local calm = Sim.context({ float = 0 })
            painStep(calm, 0.1)
            for _, p in ipairs({ off, asleep, dosed, calm }) do
                assert.equal(0, #p.noises)
            end
        end)

        it("cries out at a sudden jump in pain far more readily than at steady pain", function()
            local p = Sim.context({ floats = { 0.5, 0.5 } })
            painStep(p, 0.2)                  -- first sample: the baseline; 1/120 chance fails at 0.5
            assert.equal(0, #p.noises)
            painStep(p, 0.5)                  -- +0.3: a new injury, 2 in 3
            assert.equal(1, #p.noises)
        end)
    end)
end)

insulate("Mind wiring", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    local halo = {}
    _G.HaloTextHelper = { addBadText = function(_, text) halo[#halo + 1] = text end }
    _G.ISTakePillAction = { complete = function() return true end }
    local slept = 0
    _G.ISWorldObjectContextMenu = { onSleepWalkToComplete = function() slept = slept + 1 end }

    local Client = require("ExtensiveHealthRedone/Client/Client")
    require("ExtensiveHealthRedone/Client/Sleep")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Server/Mind")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    it("counts vanilla painkiller pills toward addiction on the server", function()
        local pills = player.inventory:add("Base.Pills")
        ISTakePillAction.complete({ character = player, item = pills })
        assert.equal(1, state().mind.painkiller.risk)
        local vitamins = player.inventory:add("Base.PillsVitamins")
        ISTakePillAction.complete({ character = player, item = vitamins })
        assert.equal(1, state().mind.painkiller.risk)
    end)

    it("blocks falling asleep while the mirrored effects say so", function()
        ISWorldObjectContextMenu.onSleepWalkToComplete(0, nil)
        assert.equal(1, slept)
        state().conditions.active.insomnia = { stage = 2, left = 1e6, len = {}, duration = 0, extra = 0,
            severity = 0.65, data = {} }
        -- The caffeine pill above blocks sleep too, and would be the reason named; only insomnia is wanted here.
        state().meds = require("ExtensiveHealthRedone/Core/Schema").defaults().meds
        local store = require("ExtensiveHealthRedone/Server/Runtime").store
        store:markDirty("sp:0", "conditions")
        store:markDirty("sp:0", "meds")
        game.advance(1)
        assert.is_true(Client.section(player, "effects").noSleep)
        ISWorldObjectContextMenu.onSleepWalkToComplete(0, nil)
        assert.equal(1, slept)
        assert.equal("UI_EHR_Insomnia_NoSleep", halo[#halo])
    end)
end)
