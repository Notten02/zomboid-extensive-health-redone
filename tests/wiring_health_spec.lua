-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions passed to complete() are deliberately partial.
---@diagnostic disable: missing-fields
-- Blood and wounds end to end in single-player mode against tests/support/fake_game.lua: body facts in, the stat
-- and body writers out, the transfusion and blood draw commands with real (fake) items (run the way our shared
-- actions' complete() runs them, Actions/Authority; a client can't send them), per-bag consent between two
-- split-screen players, the vanilla treatment hooks, and the stitch minigame round trip with its server checks.

insulate("single-player wiring: blood and wounds", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local Authority = require("ExtensiveHealthRedone/Actions/Authority")
    local doctor = game.addPlayer({})
    local patient = game.addPlayer({ x = 101, y = 100 })
    game.events.OnCreatePlayer.trigger(0, doctor)
    game.events.OnCreatePlayer.trigger(1, patient)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local received = {}
    for _, command in ipairs({ "notice", "say", "rejected", "consentAsk", "consentResult", "stitchSession",
        "stitchDenied" }) do
        received[command] = {}
        Client.on(command, function(args)
            table.insert(received[command], args)
        end)
    end

    local function state(player)
        return player.modData.ExtensiveHealthRedone
    end

    it("bleeds from the body facts, syncs the blood section, and stops under a bandage", function()
        local neck = doctor.body:part("Neck")
        neck.flags.bleeding, neck.flags.deep, neck.health = true, true, 60
        game.advance(5)
        local volume = state(doctor).blood.volume
        assert.is_true(volume < 5000)
        assert.equal(volume, Client.section(doctor, "blood").volume)
        neck.flags.bandaged = true
        game.advance(3)
        assert.equal(volume, state(doctor).blood.volume)
        neck.flags = {}
        neck.health = 100
    end)

    it("transfuses a compatible bag with an IV kit, both used up", function()
        state(doctor).blood.volume = 3000
        local bag = doctor.inventory:add("ExtensiveHealth.BloodBagOPos", { food = true })
        doctor.inventory:add("ExtensiveHealth.IVKit", { uses = 1 })
        Client.send(doctor, "blood.transfuse", { bag = bag.id })
        assert.equal("action_only", received.rejected[#received.rejected].code)
        assert.equal(3000, state(doctor).blood.volume)
        assert.is_true(Authority.run(doctor, "blood.transfuse", { bag = bag.id }))
        assert.near(3500, state(doctor).blood.volume, 1)
        assert.equal(0, doctor.inventory:count("ExtensiveHealth.BloodBagOPos"))
        assert.equal(0, doctor.inventory:count("ExtensiveHealth.IVKit"))
    end)

    it("refuses without an IV kit and keeps the bag", function()
        local bag = doctor.inventory:add("ExtensiveHealth.SalineBag")
        Authority.run(doctor, "blood.transfuse", { bag = bag.id })
        assert.equal("UI_EHR_MedAction_RequiresIVKit", received.notice[#received.notice].key)
        assert.equal(1, doctor.inventory:count("ExtensiveHealth.SalineBag"))
    end)

    it("draws blood into a fresh bag of the donor's own type", function()
        state(doctor).blood.volume = 5000
        local empty = doctor.inventory:add("ExtensiveHealth.EmptyBloodBag")
        Client.send(doctor, "blood.draw", { bag = empty.id })
        assert.equal("action_only", received.rejected[#received.rejected].code)
        assert.equal(1, doctor.inventory:count("ExtensiveHealth.EmptyBloodBag"))
        Authority.run(doctor, "blood.draw", { bag = empty.id })
        assert.near(4500, state(doctor).blood.volume, 1)
        assert.equal(0, doctor.inventory:count("ExtensiveHealth.EmptyBloodBag"))
        local filled = doctor.inventory:getFirstEvalRecurse(function(item)
            return item:getFullType() == "ExtensiveHealth.BloodBagAPos"
        end)
        assert.truthy(filled)
        assert.equal("A+", filled.modData.EHR_DonorBloodType)
        assert.is_false(filled.modData.EHR_BloodSpoilage.stale)
    end)

    it("needs the patient's consent for that one bag to transfuse another player", function()
        state(patient).blood.volume = 3000
        local bag = doctor.inventory:add("ExtensiveHealth.BloodBagONeg", { food = true })
        local other = doctor.inventory:add("ExtensiveHealth.BloodBagONeg", { food = true })
        doctor.inventory:add("ExtensiveHealth.HomemadeIVKit", { uses = 1 })
        Authority.run(doctor, "blood.transfuse", { bag = bag.id, target = "sp:1" })
        assert.equal("no_consent", received.rejected[#received.rejected].code)

        -- A transfusion ask names the bag; without one it goes nowhere.
        local asks = #received.consentAsk
        Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "transfuse" })
        assert.equal(asks, #received.consentAsk)
        Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "transfuse", item = bag.id })
        local ask = received.consentAsk[#received.consentAsk]
        assert.equal("sp:1", ask.owner)
        assert.equal("sp:0", ask.from)
        assert.equal(bag.id, ask.item)
        assert.equal("ExtensiveHealth.BloodBagONeg", ask.itemType)
        Client.send(patient, "consent.answer", { from = ask.from, purpose = "transfuse", item = ask.item,
            accepted = true })
        assert.is_true(received.consentResult[#received.consentResult].accepted)

        -- The yes covers that bag, not another of the same type.
        Authority.run(doctor, "blood.transfuse", { bag = other.id, target = "sp:1" })
        assert.equal("no_consent", received.rejected[#received.rejected].code)
        assert.is_true(Authority.run(doctor, "blood.transfuse", { bag = bag.id, target = "sp:1" }))
        assert.near(3500, state(patient).blood.volume, 1)
        assert.equal(0, doctor.inventory:count("ExtensiveHealth.HomemadeIVKit"))
        -- A yes is good for one attempt, a failed one included (here: no IV kit left).
        game.realMs = game.realMs + 10000    -- past the ask rate limit (3 per 10 s)
        Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "transfuse", item = other.id })
        ask = received.consentAsk[#received.consentAsk]
        Client.send(patient, "consent.answer", { from = ask.from, purpose = "transfuse", item = ask.item,
            accepted = true })
        assert.is_true(Authority.run(doctor, "blood.transfuse", { bag = other.id, target = "sp:1" }))
        assert.equal("UI_EHR_MedAction_RequiresIVKit", received.notice[#received.notice].key)
        doctor.inventory:add("ExtensiveHealth.HomemadeIVKit", { uses = 1 })
        assert.is_false(Authority.run(doctor, "blood.transfuse", { bag = other.id, target = "sp:1" }))
        assert.equal("no_consent", received.rejected[#received.rejected].code)
        doctor.inventory:Remove(other)
    end)

    it("starts an incubation from a vanilla infected wound, and the vanilla disinfect action stops it", function()
        local hand = doctor.body:part("Hand_L")
        hand.flags.cut, hand.infected = true, true
        game.advance(2)
        assert.equal("incubating", state(doctor).wounds.parts.Hand_L.phase)
        assert.equal(true, ISDisinfect.complete({ otherPlayer = doctor, bodyPart = hand }))
        assert.is_nil(state(doctor).wounds.parts.Hand_L)
        assert.is_false(hand.infected)
        hand.flags = {}
    end)

    it("treats another mod's alcoholic bandage on the vanilla Health tab like our own, and a plain one not at all", function()
        local hand = doctor.body:part("Hand_L")
        hand.flags.cut, hand.infected = true, true
        game.advance(2)
        assert.equal("incubating", state(doctor).wounds.parts.Hand_L.phase)
        local plain = doctor.inventory:add("OtherMod.PlainBandage", { alcoholic = false })
        assert.equal(true, ISApplyBandage.complete({ otherPlayer = doctor, bodyPart = hand, item = plain, doIt = true }))
        assert.equal("incubating", state(doctor).wounds.parts.Hand_L.phase)
        local strong = doctor.inventory:add("OtherMod.StrongBandage", { alcoholic = true })
        assert.equal(true, ISApplyBandage.complete({ otherPlayer = doctor, bodyPart = hand, item = strong, doIt = true }))
        assert.is_nil(state(doctor).wounds.parts.Hand_L)
        hand.flags, hand.infected = {}, false
    end)

    it("lowers infected wounds a stage when vanilla antibiotics are eaten", function()
        state(doctor).wounds.parts.Hand_R = { phase = "infected", stage = 2, left = 1000 }
        local pill = doctor.inventory:add("Base.Antibiotics")
        ISEatFoodAction.complete({ character = doctor, item = pill })
        assert.equal(1, state(doctor).wounds.parts.Hand_R.stage)
        state(doctor).wounds.parts.Hand_R = nil
    end)

    it("refuses food on the server while tetanus locks the jaw, but not drinks", function()
        state(doctor).conditions.active.tetanus = {
            stage = 2, left = 1e6, duration = 1e6, extra = 0, severity = 1, data = { lockjaw = true },
        }
        local food = { character = doctor, item = doctor.inventory:add("Base.Apple", { hunger = -0.1 }) }
        local drink = { character = doctor, item = doctor.inventory:add("Base.WaterBottle", { hunger = 0 }) }
        assert.is_false(ISEatFoodAction.complete(food))
        assert.is_nil(food.eaten)
        assert.is_true(ISEatFoodAction.complete(drink))
        state(doctor).conditions.active.tetanus = nil
    end)

    describe("stitching", function()
        local Exam = require("ExtensiveHealthRedone/Server/Exam")
        local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
        local needle

        -- A fresh start: past every stitch and consent rate limit, a deep wound on the part, a suture needle.
        local function setup(player, partName)
            game.realMs = game.realMs + 11000
            local part = player.body:part(partName)
            part.flags, part.additionalPain, part.infected = { deep = true }, 0, false
            if not needle or needle.container == nil then
                needle = doctor.inventory:add("Base.SutureNeedle")
            end
            return part
        end

        local function last(command)
            return received[command][#received[command]]
        end

        local function cleanUp(player, part)
            state(player).conditions.active.cellulitis = nil
            state(player).wounds.parts[part.name] = nil
            part.flags, part.additionalPain, part.infected = {}, 0, false
        end

        it("applies a rough stitch's outcome when the vanilla stitch completes", function()
            local arm = setup(doctor, "ForeArm_L")
            Client.send(doctor, "stitch.begin", { part = 2 })
            local session = last("stitchSession")
            assert.equal(2, session.part)
            game.realMs = game.realMs + 6000             -- a plausible minigame
            Client.send(doctor, "stitch.result", { session = session.id, misses = 3, outcome = "success", started = true })
            game.float = 0.1
            ISStitch.complete({ character = doctor, otherPlayer = doctor, bodyPart = arm, doIt = true })
            game.float = nil
            assert.equal("ForeArm_L", state(doctor).conditions.active.cellulitis.source)
            assert.equal(5, arm.additionalPain)
            -- The session is used up: a second result is ignored.
            Client.send(doctor, "stitch.result", { session = session.id, misses = 9, outcome = "failed", started = true })
            assert.equal(5, arm.additionalPain)
            cleanUp(doctor, arm)
        end)

        it("won't let another player open a session or hurt the patient without consent", function()
            local arm = setup(patient, "ForeArm_R")
            local sessions = #received.stitchSession
            Client.send(doctor, "stitch.begin", { target = "sp:1", part = 3 })
            assert.equal(sessions, #received.stitchSession)
            assert.equal("no_consent", last("stitchDenied").reason)
            Client.send(doctor, "stitch.result", { session = 1, misses = 20, outcome = "failed", started = true })
            Client.send(doctor, "stitch.result", { session = 999, misses = 20, outcome = "failed", started = true })
            assert.equal(0, arm.additionalPain)
            assert.is_nil(state(patient).conditions.active.cellulitis)
            cleanUp(patient, arm)
        end)

        it("stitches another player with a stitch permit, and with an exam session", function()
            local arm = setup(patient, "ForeArm_R")
            Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "stitch" })
            Client.send(patient, "consent.answer", { from = "sp:0", purpose = "stitch", accepted = true })
            Client.send(doctor, "stitch.begin", { target = "sp:1", part = 3 })
            local session = last("stitchSession")
            assert.equal(3, session.part)
            game.realMs = game.realMs + 6000
            Client.send(doctor, "stitch.result", { session = session.id, misses = 0, outcome = "success", started = true })
            assert.is_true(game.logged("claims an excellent stitch on sp:1 ForeArm_R"))
            arm.additionalPain = 10
            ISStitch.complete({ character = doctor, otherPlayer = patient, bodyPart = arm, doIt = true })
            assert.equal(5, arm.additionalPain)          -- excellent: -5
            cleanUp(patient, arm)

            local leg = setup(patient, "LowerLeg_L")
            Runtime.permits:forget("sp:1")
            Client.send(doctor, "stitch.begin", { target = "sp:1", part = 13 })
            assert.equal("no_consent", last("stitchDenied").reason)
            local sessions = #received.stitchSession
            -- An exam session (Server/Exam) is consent too; stubbed so this test doesn't build the exam's model.
            local isExamining = Exam.isExamining
            ---@diagnostic disable-next-line: duplicate-set-field
            Exam.isExamining = function(doctorKey, patientKey) return doctorKey == "sp:0" and patientKey == "sp:1" end
            Client.send(doctor, "stitch.begin", { target = "sp:1", part = 13 })
            Exam.isExamining = isExamining
            assert.equal(sessions + 1, #received.stitchSession)
            cleanUp(patient, leg)
        end)

        it("ignores a failed attempt once the doctor has walked out of range", function()
            local arm = setup(patient, "ForeArm_R")
            Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "stitch" })
            Client.send(patient, "consent.answer", { from = "sp:0", purpose = "stitch", accepted = true })
            Client.send(doctor, "stitch.begin", { target = "sp:1", part = 3 })
            local session = last("stitchSession")
            doctor.x = 110
            Client.send(doctor, "stitch.result", { session = session.id, misses = 9, outcome = "failed", started = true })
            doctor.x = 100
            assert.equal(0, arm.additionalPain)
            assert.is_true(game.logged("stitch result ignored: out of range of sp:1"))
            Runtime.permits:forget("sp:1")
            cleanUp(patient, arm)
        end)

        it("refuses a doctor without a suture needle or a needle and thread", function()
            local arm = setup(doctor, "Hand_L")
            doctor.inventory:Remove(needle)
            Client.send(doctor, "stitch.begin", { part = 0 })
            assert.equal("no_needle", last("stitchDenied").reason)
            local sewing = doctor.inventory:add("Base.Needle")
            Client.send(doctor, "stitch.begin", { part = 0 })
            assert.equal("no_needle", last("stitchDenied").reason)
            local thread = doctor.inventory:add("Base.Thread")
            local sessions = #received.stitchSession
            Client.send(doctor, "stitch.begin", { part = 0 })
            assert.equal(sessions + 1, #received.stitchSession)
            doctor.inventory:Remove(sewing)
            doctor.inventory:Remove(thread)
            cleanUp(doctor, arm)
        end)

        it("counts a success reported faster than a plausible minigame as poor", function()
            local arm = setup(doctor, "ForeArm_L")
            Client.send(doctor, "stitch.begin", { part = 2 })
            game.realMs = game.realMs + 2000             -- under Stitch.MIN_SECONDS (4.2 s)
            Client.send(doctor, "stitch.result",
                { session = last("stitchSession").id, misses = 0, outcome = "success", started = true })
            assert.is_true(game.logged("faster than"))
            ISStitch.complete({ character = doctor, otherPlayer = doctor, bodyPart = arm, doIt = true })
            assert.equal(12, arm.additionalPain)         -- poor, not excellent (-5)
            cleanUp(doctor, arm)
        end)

        it("counts a vanilla stitch without a minigame result as poor, unless the minigame is off", function()
            local arm = setup(doctor, "ForeArm_L")
            ISStitch.complete({ character = doctor, otherPlayer = doctor, bodyPart = arm, doIt = true })
            assert.equal(12, arm.additionalPain)
            assert.is_true(game.logged("stitch without minigame result"))
            cleanUp(doctor, arm)

            arm = setup(doctor, "ForeArm_L")
            game.sandbox.StitchMinigameEnabled = false
            ISStitch.complete({ character = doctor, otherPlayer = doctor, bodyPart = arm, doIt = true })
            game.sandbox.StitchMinigameEnabled = nil
            assert.equal(0, arm.additionalPain)
            cleanUp(doctor, arm)
        end)

        it("shows one consent prompt per doctor at a time, and none for a while after a no", function()
            game.realMs = game.realMs + 11000
            local asks = #received.consentAsk
            Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "stitch" })
            Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "exam" })
            assert.equal(asks + 1, #received.consentAsk)
            Client.send(patient, "consent.answer", { from = "sp:0", purpose = "stitch", accepted = false })
            game.realMs = game.realMs + 11000
            Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "stitch" })
            assert.equal(asks + 1, #received.consentAsk)
            game.realMs = game.realMs + 20000            -- past the 30 s cooldown
            Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "stitch" })
            assert.equal(asks + 2, #received.consentAsk)
            Client.send(patient, "consent.answer", { from = "sp:0", purpose = "stitch", accepted = false })
            game.realMs = game.realMs + 31000
        end)

        it("adds nothing when a vanilla stitch on another player had no consent and no minigame", function()
            local arm = setup(patient, "ForeArm_R")
            Runtime.permits:forget("sp:1")
            ISStitch.complete({ character = doctor, otherPlayer = patient, bodyPart = arm, doIt = true })
            assert.equal(0, arm.additionalPain)
            assert.is_nil(state(patient).conditions.active.cellulitis)
            assert.is_true(game.logged("without consent or minigame result: no roll"))
            cleanUp(patient, arm)
        end)

        it("harms another player's part once per consent window, however often a stitch fails", function()
            local arm = setup(patient, "ForeArm_R")
            Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "stitch" })
            Client.send(patient, "consent.answer", { from = "sp:0", purpose = "stitch", accepted = true })
            for _ = 1, 3 do
                game.realMs = game.realMs + 3000         -- inside the stitch rate limit
                Client.send(doctor, "stitch.begin", { target = "sp:1", part = 3 })
                Client.send(doctor, "stitch.result",
                    { session = last("stitchSession").id, misses = 20, outcome = "failed", started = true })
            end
            assert.equal(10, arm.additionalPain)         -- one failed attempt's pain, not three
            assert.is_true(game.logged("repeated stitch failed on sp:1 ForeArm_R ignored"))
            Runtime.permits:forget("sp:1")
            cleanUp(patient, arm)
        end)
    end)

    it("caps body part healing while the character is hungry", function()
        local leg = doctor.body:part("UpperLeg_R")
        leg.health = 50
        doctor.stats.HUNGER = 80
        game.advance(2)
        leg.health = 60                      -- vanilla heals
        game.advance(1)
        assert.equal(50, leg.health)
        assert.is_true(Client.section(doctor, "body").healing.blocked)
        doctor.stats.HUNGER = 0
        game.advance(1)
        leg.health = 60
        game.advance(1)
        assert.equal(60, leg.health)
        assert.is_false(Client.section(doctor, "body").healing.blocked)
    end)

    it("dies when the blood runs out", function()
        state(doctor).blood.volume = 100
        game.advance(2)
        assert.is_true(doctor.dead)
    end)
end)
