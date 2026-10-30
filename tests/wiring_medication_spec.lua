-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions passed to complete() are deliberately partial.
---@diagnostic disable: missing-fields
-- Medication end to end in single-player mode against tests/support/fake_game.lua: the medication.take command with
-- real (fake) items and supplies (run the way our shared action's complete() runs it, Actions/Authority; a client
-- can't send it), giving a dose to another player with their consent for that item, vanilla pills and antibiotics
-- given to another player (medication.give), the vanilla pill, eat and tea hooks, First Aid XP, and a course curing
-- a disease through the full simulation.

insulate("single-player wiring: medication", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.Fluid = { TaintedWater = "TaintedWater", Tea = "Tea", Water = "Water" }
    _G.ISTakeWaterAction = { complete = function() return true end }
    _G.ISTakePillAction = { complete = function() return true end }
    _G.ISDrinkFluidAction = {
        new = function(_, character, item) return { character = character, item = item, fluidContainer = item.fluid } end,
        complete = function() return true end,
    }

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local Authority = require("ExtensiveHealthRedone/Actions/Authority")
    local doctor = game.addPlayer({ username = "doctor" })
    local patient = game.addPlayer({ x = 101, y = 100, username = "patient" })
    game.events.OnCreatePlayer.trigger(0, doctor)
    game.events.OnCreatePlayer.trigger(1, patient)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()
    game.advance(2)

    local received = {}
    for _, command in ipairs({ "notice", "rejected", "consentAsk", "consentResult", "say" }) do
        received[command] = {}
        Client.on(command, function(args)
            table.insert(received[command], args)
        end)
    end

    local function state(player)
        return player.modData.ExtensiveHealthRedone
    end

    local function lastNotice()
        return received.notice[#received.notice].key
    end

    local function wait()
        game.realMs = game.realMs + 10000    -- past the consent ask rate limit
    end

    -- The doctor asks the patient for consent to give item; the patient says yes (per dose: that item, one use).
    local function allow(item)
        wait()
        Client.send(doctor, "consent.ask", { target = "sp:1", purpose = "medicate", item = item.id })
        local ask = received.consentAsk[#received.consentAsk]
        assert.equal(item.id, ask.item)
        Client.send(patient, "consent.answer", { from = ask.from, purpose = "medicate", item = ask.item,
            accepted = true })
        assert.is_true(received.consentResult[#received.consentResult].accepted)
    end

    it("takes one dose from a bottle and syncs the dose to the client", function()
        local syrup = doctor.inventory:add("ExtensiveHealth.CoughSyrup", { uses = 6 })
        Client.send(doctor, "medication.take", { item = syrup.id })
        assert.equal("action_only", received.rejected[#received.rejected].code)
        assert.equal(6, syrup.uses)
        assert.is_true(Authority.run(doctor, "medication.take", { item = syrup.id }))
        assert.equal(5, syrup.uses)
        assert.truthy(state(doctor).meds.doses.CoughSyrup)
        game.advance(1)
        assert.truthy(Client.section(doctor, "meds").doses.CoughSyrup)
        assert.equal(5, game.xp.doctor)
    end)

    it("refuses an IV drug without a kit and keeps it; with a kit both are used up", function()
        wait()
        local iv = doctor.inventory:add("ExtensiveHealth.IVAntibiotics")
        Authority.run(doctor, "medication.take", { item = iv.id })
        assert.equal("UI_EHR_MedReason_RequiresIVKit", lastNotice())
        assert.equal(1, doctor.inventory:count("ExtensiveHealth.IVAntibiotics"))
        doctor.inventory:add("ExtensiveHealth.HomemadeIVKit", { uses = 1 })
        Authority.run(doctor, "medication.take", { item = iv.id })
        assert.equal(0, doctor.inventory:count("ExtensiveHealth.IVAntibiotics"))
        assert.equal(0, doctor.inventory:count("ExtensiveHealth.HomemadeIVKit"))
        assert.truthy(state(doctor).meds.courses.IVAntibiotics)
    end)

    it("won't take a vanilla-route item or another player's item through the command", function()
        wait()
        local pills = doctor.inventory:add("Base.Pills", { uses = 16 })
        Authority.run(doctor, "medication.take", { item = pills.id })
        assert.equal("wrong_item", received.rejected[#received.rejected].code)
        local theirs = patient.inventory:add("ExtensiveHealth.CoughSyrup", { uses = 6 })
        Authority.run(doctor, "medication.take", { item = theirs.id })
        assert.equal("no_item", received.rejected[#received.rejected].code)
    end)

    it("gives a dose to another player only with their consent, using the doctor's supplies", function()
        wait()
        local shot = doctor.inventory:add("ExtensiveHealth.TetanusAntitoxin")
        Authority.run(doctor, "medication.take", { item = shot.id, target = "sp:1" })
        assert.equal("no_consent", received.rejected[#received.rejected].code)

        allow(shot)
        -- One attempt per yes, a refused one included.
        Authority.run(doctor, "medication.take", { item = shot.id, target = "sp:1" })
        assert.equal("UI_EHR_MedReason_RequiresSyringe", lastNotice())
        local syringes = doctor.inventory:add("ExtensiveHealth.Syringe", { uses = 5 })
        Authority.run(doctor, "medication.take", { item = shot.id, target = "sp:1" })
        assert.equal("no_consent", received.rejected[#received.rejected].code)
        assert.equal(5, syringes.uses)
        allow(shot)
        Authority.run(doctor, "medication.take", { item = shot.id, target = "sp:1" })
        assert.equal(4, syringes.uses)
        assert.equal(0, doctor.inventory:count("ExtensiveHealth.TetanusAntitoxin"))
        assert.truthy(state(patient).meds.courses.TetanusAntitoxin)
        assert.is_nil(state(doctor).meds.courses.TetanusAntitoxin)
    end)

    it("gives vanilla pills to another player with consent: the doctor's pill, the patient's dose and effect", function()
        state(patient).meds.doses.BetaBlockers = nil
        local beta = doctor.inventory:add("Base.PillsBeta", { uses = 10 })
        local other = doctor.inventory:add("Base.PillsBeta", { uses = 10 })
        Client.send(doctor, "medication.give", { item = beta.id, target = "sp:1" })
        assert.equal("action_only", received.rejected[#received.rejected].code)
        Authority.run(doctor, "medication.give", { item = beta.id, target = "sp:1" })
        assert.equal("no_consent", received.rejected[#received.rejected].code)
        allow(beta)
        Authority.run(doctor, "medication.give", { item = other.id, target = "sp:1" })
        assert.equal("no_consent", received.rejected[#received.rejected].code)
        local xp = game.xp.doctor or 0
        assert.is_true(Authority.run(doctor, "medication.give", { item = beta.id, target = "sp:1" }))
        assert.equal(9, beta.uses)
        assert.equal(10, other.uses)
        assert.truthy(state(patient).meds.doses.BetaBlockers)
        assert.equal(beta, patient.body.pillsTaken[#patient.body.pillsTaken])
        assert.is_true((game.xp.doctor or 0) > xp)
        -- The yes is used up.
        Authority.run(doctor, "medication.give", { item = beta.id, target = "sp:1" })
        assert.equal("no_consent", received.rejected[#received.rejected].code)
        assert.equal(9, beta.uses)
        doctor.inventory:Remove(beta)
        doctor.inventory:Remove(other)
    end)

    it("refuses a vanilla dose the patient can't take without using the doctor's pill", function()
        local caffeine = doctor.inventory:add("Base.PillsVitamins", { uses = 10 })
        state(patient).meds.doses.CaffeinePills = { since = 0 }
        allow(caffeine)
        Authority.run(doctor, "medication.give", { item = caffeine.id, target = "sp:1" })
        assert.equal("UI_EHR_Text_TheCaffeineIsStillActiveMoreWouldBeAVeryBadIdea", lastNotice())
        assert.equal(10, caffeine.uses)
        state(patient).meds.doses.CaffeinePills = nil
        doctor.inventory:Remove(caffeine)
    end)

    it("gives vanilla antibiotics to another player: used up, a wound stage and vanilla's infection power", function()
        state(patient).wounds.parts.Hand_R = { phase = "infected", stage = 2, left = 1000 }
        local antibiotics = doctor.inventory:add("Base.Antibiotics", { food = true, infectionPower = 50 })
        allow(antibiotics)
        assert.is_true(Authority.run(doctor, "medication.give", { item = antibiotics.id, target = "sp:1" }))
        assert.equal(0, doctor.inventory:count("Base.Antibiotics"))
        assert.equal(1, state(patient).wounds.parts.Hand_R.stage)
        assert.equal(50, patient:getReduceInfectionPower())
        state(patient).wounds.parts.Hand_R = nil
    end)

    it("refuses to give a tea to someone else", function()
        wait()
        local tea = doctor.inventory:add("ExtensiveHealth.RelaxantTea", { food = true })
        -- The command only takes our own route, so a tea (vanilla Drink) is the wrong item.
        Authority.run(doctor, "medication.take", { item = tea.id, target = "sp:1" })
        assert.equal("wrong_item", received.rejected[#received.rejected].code)
        Authority.run(doctor, "medication.give", { item = tea.id, target = "sp:1" })
        assert.equal("wrong_item", received.rejected[#received.rejected].code)
    end)

    it("applies vanilla pills, food medicine and tea through the vanilla action hooks", function()
        local beta = doctor.inventory:add("Base.PillsBeta", { uses = 16 })
        ISTakePillAction.complete({ character = doctor, item = beta })
        assert.truthy(state(doctor).meds.doses.BetaBlockers)

        local tea = doctor.inventory:add("ExtensiveHealth.RelaxantTea", { food = true })
        ISEatFoodAction.complete({ character = doctor, item = tea })
        assert.truthy(state(doctor).meds.effects.stress)

        local mug = doctor.inventory:add("Base.Mugl", { fluid = { contains = function(_, f) return f == "Tea" end } })
        local drink = ISDrinkFluidAction:new(doctor, mug, 1)
        ISDrinkFluidAction.complete(drink)
        assert.truthy(state(doctor).meds.doses.Tea)
        assert.is_nil(state(doctor).meds.doses.Water)

        local bottle = doctor.inventory:add("Base.WaterBottle", { fluid = { contains = function(_, f)
            return f == "Water" end } })
        ISDrinkFluidAction.complete(ISDrinkFluidAction:new(doctor, bottle, 1))
        assert.truthy(state(doctor).meds.doses.Water)
        state(doctor).meds.doses.Water = nil
        ISTakeWaterAction.complete({ character = doctor })
        assert.truthy(state(doctor).meds.doses.Water)
    end)

    it("blocks sleep on the mirror while the beta blocker is active", function()
        game.advance(1)
        local effects = Client.section(doctor, "effects")
        assert.is_true(effects.noSleep)
        assert.equal("betaBlocker", effects.sleepBy)
    end)

    it("cures a cold with a full course through the simulation and awards the cure XP", function()
        state(patient).conditions.active.common_cold = { stage = 2, left = 1e6, len = {}, duration = 0, extra = 0,
            severity = 1, data = {} }
        local xpBefore = game.xp.patient or 0
        local tablets = patient.inventory:add("ExtensiveHealth.ColdFluTablets", { uses = 12 })
        for dose = 1, 8 do
            wait()
            Authority.run(patient, "medication.take", { item = tablets.id })
            if dose < 8 then
                game.advance(4 * 60)
            end
        end
        assert.equal(4, tablets.uses)
        game.advance(2)
        assert.is_nil(state(patient).conditions.active.common_cold)
        assert.is_nil(Client.section(patient, "conditions").active.common_cold)
        assert.equal(xpBefore + 5 * 8 + 3 * 8 + 20, game.xp.patient)
    end)

    it("upgrades a version 3 save, which has no medication section", function()
        local Schema = require("ExtensiveHealthRedone/Core/Schema")
        local old = Schema.new({ int = function(lo) return lo end })
        old.version = 3
        old.meds = nil
        assert.is_true(Schema.upgrade(old))
        Schema.fillDefaults(old)
        assert.same({}, old.meds.doses)
        assert.is_false(old.meds.overdose)
        assert.equal(1, old.effects.attackSpeed)
    end)
end)
