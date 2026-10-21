-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions and items are deliberately partial.
---@diagnostic disable: missing-fields
-- Knox (Phase 4 step 7): the item rules, immunity enforcement, the knox_infection display condition, the Kentucky
-- Herald and the Patient Zero trait. Pure rules on a test context, then the server wiring against the fake game.
local Knox = require("ExtensiveHealthRedone/Diseases/Knox/Knox")
local KnoxItems = require("ExtensiveHealthRedone/Diseases/Knox/Items")
local Infection = require("ExtensiveHealthRedone/Diseases/Knox/Infection")
local Data = require("ExtensiveHealthRedone/Diseases/Knox/Data")
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local StatAggregator = require("ExtensiveHealthRedone/Core/StatAggregator")
local Sim = require("support/sim")

local RANGES = {}
for name, range in pairs(Sim.RANGES) do
    RANGES[name] = range
end
RANGES.ZOMBIE_INFECTION = { min = 0, max = 100 }
RANGES.ZOMBIE_FEVER = { min = 0, max = 100 }

local function context(opts)
    local p = Sim.context(opts)
    p.stats = StatAggregator.new(RANGES)
    p.facts.knox = { infected = false, partInfected = false, bitten = false, level = 0, fever = 0 }
    return p
end

local function step(p)
    Sim.step(p)
    p.stats = StatAggregator.new(RANGES)
    return p
end

local function run(p, minutes)
    for _ = 1, minutes do
        step(p)
        Infection.update(p, 1, defs)
        Engine.step(p, defs, 1)
    end
end

local function infect(p, level)
    p.facts.knox.infected = true
    p.facts.knox.level = level or 0.3
end

describe("Knox rules", function()
    it("rates gene therapy odds by blood type", function()
        assert.equal(95, Knox.geneTherapyChance("O-"))
        assert.equal(40, Knox.geneTherapyChance("AB+"))
        assert.equal(50, Knox.geneTherapyChance(nil))
        assert.equal("UI_EHR_KnoxCure_Rating_High", Knox.rating(75))
        assert.equal("UI_EHR_KnoxCure_Rating_Moderate", Knox.rating(74))
        assert.equal("UI_EHR_KnoxCure_Rating_Low", Knox.rating(40))
        assert.equal("UI_EHR_KnoxCure_Rating_Critical", Knox.rating(24))
    end)

    it("resets Phalanx to less each dose and then not at all", function()
        assert.same({ 0, 0.25, 0.5, 0.75 }, { Knox.phalanxResetFor(0), Knox.phalanxResetFor(1),
            Knox.phalanxResetFor(2), Knox.phalanxResetFor(3) })
        assert.is_nil(Knox.phalanxResetFor(4))
    end)

    it("recognises the July 16 Kentucky Herald by print media id or title", function()
        assert.is_true(Knox.isHerald("KentuckyHerald_July16"))
        assert.is_true(Knox.isHerald("Print_Media_KentuckyHerald_July16_title"))
        assert.is_false(Knox.isHerald("KentuckyHerald_July15"))
        assert.is_false(Knox.isHerald(nil))
    end)

    it("maps progress to the display stage", function()
        assert.equal(1, Knox.stageFor(0.1))
        assert.equal(2, Knox.stageFor(0.2))
        assert.equal(3, Knox.stageFor(0.6))
        assert.equal(4, Knox.stageFor(0.95))
    end)
end)

describe("Knox items", function()
    it("gene therapy refuses without consuming when immune or not infected", function()
        local p = context()
        assert.same({ consume = 0, outcome = "notInfected" }, KnoxItems.geneTherapy(p))
        p.state.knox.geneTherapyImmune = true
        infect(p)
        assert.same({ consume = 0, outcome = "immune" }, KnoxItems.geneTherapy(p))
    end)

    it("gene therapy cures, costs 10% health and makes the survivor immune", function()
        local p = context({ ints = { 94 } })     -- O- succeeds below 95
        p.state.identity.bloodType = "O-"
        infect(p)
        local result = KnoxItems.geneTherapy(p)
        assert.equal("cured", result.outcome)
        assert.equal(1, result.consume)
        assert.is_true(result.grantTrait)
        assert.same({ source = "geneTherapy" }, p.body.knox)
        assert.equal(0, select(1, p.stats:resolve("ZOMBIE_INFECTION", 40)))
        assert.equal(Data.GENE_THERAPY_HEALTH_COST, p.body:resolveDamage(100))
        assert.is_true(p.state.knox.geneTherapyImmune)
        assert.is_true(Sim.said(p, "UI_EHR_Knox_GeneTherapyWorked"))
    end)

    it("gene therapy without Patient Zero cures but grants no immunity", function()
        local p = context({ sandbox = { PatientZeroTraitDisabled = true } })
        infect(p)
        local result = KnoxItems.geneTherapy(p)
        assert.equal("cured", result.outcome)
        assert.is_false(result.grantTrait)
        assert.is_false(p.state.knox.geneTherapyImmune)
    end)

    it("gene therapy kills when the blood rejects it", function()
        local p = context({ ints = { 40 } })     -- AB+ succeeds below 40
        p.state.identity.bloodType = "AB+"
        infect(p)
        local result = KnoxItems.geneTherapy(p)
        assert.equal("died", result.outcome)
        assert.equal(1, result.consume)
        assert.equal("geneTherapy", p.body.killed.source)
    end)

    it("the antibody test reports the odds and is always used up", function()
        local p = context()
        p.state.identity.bloodType = "B+"
        local result = KnoxItems.antibodyTest(p)
        assert.equal(1, result.consume)
        assert.equal(65, p.state.knox.lastTest.chance)
        assert.equal("knoxSay", p.sent[1][1])
        assert.same({ "B+", "UI_EHR_KnoxCure_Rating_Moderate", "65%" }, p.sent[1][2].args)
    end)

    it("the immunobooster refuses in v0.9's order and protects for 24 h with a 7-day cooldown", function()
        local p = context()
        p.facts.knox.bitten = true
        assert.equal("bitten", KnoxItems.immunobooster(p).outcome)
        infect(p)
        assert.equal("infected", KnoxItems.immunobooster(p).outcome)
        p.facts.knox = { infected = false, bitten = false, level = 0, fever = 0 }
        local used = KnoxItems.immunobooster(p)
        assert.same({ consume = 1, outcome = "protected" }, used)
        assert.equal(24 * 60, p.state.knox.boosterLeft)
        assert.equal(7 * 24 * 60, p.state.knox.boosterCooldown)
        assert.equal("active", KnoxItems.immunobooster(p).outcome)
        p.state.knox.boosterLeft = 0
        assert.equal("cooldown", KnoxItems.immunobooster(p).outcome)
    end)

    it("Phalanx resets progress with diminishing returns, then the body adapts", function()
        local p = context()
        infect(p, 0.9)
        for dose, resetTo in ipairs({ 0, 0.25, 0.5, 0.75 }) do
            step(p)
            local result = KnoxItems.phalanx(p)
            assert.equal("reset", result.outcome)
            assert.equal(resetTo, result.resetTo)
            assert.equal(dose, p.state.knox.phalanxUses)
            assert.same({ source = "phalanx", rewindTo = resetTo }, p.body.knox)
            assert.equal(resetTo * 100, select(1, p.stats:resolve("ZOMBIE_INFECTION", 90)))
        end
        assert.equal(Data.PHALANX_DEBUFF_MINUTES, p.state.knox.effects.phalanxDebuff)
        step(p)
        assert.same({ consume = 1, outcome = "adapted" }, KnoxItems.phalanx(p))
        assert.equal(4, p.state.knox.phalanxUses)
    end)

    it("a too-early Phalanx dose costs one dose and doesn't count", function()
        local p = context()
        p.state.knox.phalanxUses = 1          -- the next dose resets to 25%
        infect(p, 0.2)
        local result = KnoxItems.phalanx(p)
        assert.equal("tooEarly", result.outcome)
        assert.equal(1, result.consume)
        assert.equal(1, p.state.knox.phalanxUses)
        assert.is_nil(p.body.knox)
    end)
end)

describe("Knox simulation", function()
    it("clears vanilla's infection every step while immune", function()
        local p = context()
        p.state.knox.geneTherapyImmune = true
        infect(p, 0.05)
        run(p, 1)
        assert.same({ source = "knoxImmunity" }, p.body.knox)
        assert.is_nil(p.state.conditions.active.knox_infection)
    end)

    it("makes the Patient Zero trait permanent immunity", function()
        local p = context()
        p.facts.knox.hasTrait = true
        run(p, 1)
        assert.is_true(p.state.knox.geneTherapyImmune)
        assert.is_true(p.state.knox.patientZeroTraitSource)
    end)

    it("gives no immunity from the trait while PatientZeroTraitDisabled is on, and voids none", function()
        local p = context({ sandbox = { PatientZeroTraitDisabled = true } })
        p.facts.knox.hasTrait = true
        run(p, 1)
        assert.is_false(p.state.knox.geneTherapyImmune)
        assert.is_false(p.state.knox.patientZeroTraitSource)
        local q = context({ sandbox = { PatientZeroTraitDisabled = true } })
        q.state.knox.geneTherapyImmune, q.state.knox.patientZeroTraitSource = true, true
        q.facts.knox.hasTrait = false           -- the option turned on, and an admin removed the trait
        run(q, 1)
        assert.is_true(Knox.immune(q.state))
    end)

    it("mirrors vanilla's infection as knox_infection, its stage following progress", function()
        local p = context({ sandbox = { DialogueFrequency = 3 } })
        infect(p, 0.3)
        run(p, 1)
        local c = p.state.conditions.active.knox_infection
        assert.equal(2, c.stage)
        assert.equal(0.3, c.data.progress)
        assert.is_true(Sim.said(p, "UI_EHR_Knox_Stage2"))
        p.facts.knox.level = 0.85
        run(p, 1)
        assert.equal(4, c.stage)
        assert.is_true(Sim.said(p, "UI_EHR_Knox_Stage4"))
        p.facts.knox = { infected = false, level = 0, fever = 0 }
        run(p, 1)
        assert.is_nil(p.state.conditions.active.knox_infection)
    end)

    it("ignores DiseaseEnabled for Knox", function()
        local p = context({ sandbox = { DiseaseEnabled = false } })
        infect(p)
        run(p, 1)
        assert.truthy(p.state.conditions.active.knox_infection)
    end)

    it("runs the immunobooster's side effects and says once when it wears off", function()
        local p = context({ ints = { 60 } })
        KnoxItems.immunobooster(p)
        p.said = {}
        step(p)
        Infection.update(p, 1, defs)
        assert.equal(0.2, select(1, p.stats:resolve("FOOD_SICKNESS", 0)) / 100)
        run(p, 60)
        assert.equal("knoxTremor", p.sent[#p.sent][1])
        run(p, 24 * 60)
        local count = 0
        for _, key in ipairs(p.said) do
            if key == "UI_EHR_Knox_BoosterWearingOff" then
                count = count + 1
            end
        end
        assert.equal(1, count)
        assert.equal(0, p.state.knox.boosterLeft)
        assert.is_true(p.state.knox.boosterCooldown > 0)
    end)

    it("gives Phalanx nausea for 6 h and fever for 12 h", function()
        local p = context()
        p.state.knox.effects = { phalanxNausea = 60, phalanxFever = 120, phalanxDebuff = 200 }
        step(p)
        Infection.update(p, 1, defs)
        assert.is_true(select(1, p.stats:resolve("FOOD_SICKNESS", 0)) > 0)
        assert.is_true(select(1, p.stats:resolve("TEMPERATURE", 37)) > 37)
        run(p, 200)
        assert.equal(0, p.state.knox.effects.phalanxNausea)
        assert.equal(0, p.state.knox.effects.phalanxDebuff)
        step(p)
        Infection.update(p, 1, defs)
        assert.equal(0, select(1, p.stats:resolve("FOOD_SICKNESS", 0)))
    end)

    it("unlocks Knox knowledge from the Herald only once", function()
        local p = context()
        assert.is_true(Knox.learnFromHerald(p))
        assert.is_true(p.state.knowledge.knoxHerald)
        assert.is_true(p.state.knowledge.diseases.knox_infection)
        assert.is_false(Knox.learnFromHerald(p))
    end)
end)

insulate("single-player wiring: Knox", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.EHRCharacterTraits = { patientzero = "ExtensiveHealth:patientzero" }
    _G.ISReadABook = { complete = function() return true end }
    rawset(_G, "sendSyncPlayerFields", function() error("only on a dedicated server") end)

    local Client = require("ExtensiveHealthRedone/Client/Client")
    -- The Knox item commands are what EHRKnoxAction's complete() runs (Actions/Knox); a client can't send them.
    local Authority = require("ExtensiveHealthRedone/Actions/Authority")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Server/Knox")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local said = {}
    Client.on("knoxSay", function(args) said[#said + 1] = args end)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    local function bite()
        player.body.knox = { infected = true, time = game.minutes / 60, duration = 60 }
        player.body:part("Hand_L").knox = true
        player.body:part("Hand_L").flags.bite = true
        player.stats.ZOMBIE_INFECTION = 30
    end

    it("reads vanilla's infection into the knox_infection display condition", function()
        bite()
        game.advance(2)
        assert.equal(2, state().conditions.active.knox_infection.stage)
    end)

    it("cures with gene therapy, uses the kit, and grants the Patient Zero trait", function()
        state().identity.bloodType = "O-"
        local kit = player.inventory:add("ExtensiveHealth.GeneTherapyKit")
        local rejected
        Client.on("rejected", function(args) rejected = args end)
        Client.send(player, "knox.geneTherapy", { item = kit.id })
        assert.equal("action_only", rejected.code)
        assert.equal(1, player.inventory:count("ExtensiveHealth.GeneTherapyKit"))
        assert.is_true(Authority.run(player, "knox.geneTherapy", { item = kit.id }))
        assert.equal(0, player.inventory:count("ExtensiveHealth.GeneTherapyKit"))
        assert.is_false(player.body.knox.infected)
        assert.equal(-1, player.body.knox.time)
        assert.is_false(player.body:part("Hand_L").knox)
        assert.is_true(player.body:part("Hand_L").flags.bite)
        assert.equal(0, player.stats.ZOMBIE_INFECTION)
        assert.equal(90, player.body.health)
        assert.is_true(state().knox.geneTherapyImmune)
        assert.is_true(player.traits["ExtensiveHealth:patientzero"])
        game.advance(2)
        assert.is_nil(state().conditions.active.knox_infection)
    end)

    it("keeps an immune character free of new bites' infection", function()
        bite()
        game.advance(2)
        assert.is_false(player.body.knox.infected)
        assert.is_false(player.body:part("Hand_L").knox)
        assert.equal(0, player.stats.ZOMBIE_INFECTION)
    end)

    it("leaves the item when a Knox item is refused, and shows the test result", function()
        local pills = player.inventory:add("ExtensiveHealth.PhalanxPills", { uses = 3 })
        Authority.run(player, "knox.phalanx", { item = pills.id })
        assert.equal(3, pills.uses)
        local test = player.inventory:add("ExtensiveHealth.AntibodyTestKit")
        Authority.run(player, "knox.antibodyTest", { item = test.id })
        assert.equal(0, player.inventory:count("ExtensiveHealth.AntibodyTestKit"))
        assert.equal("UI_EHR_KnoxCure_TestResult", said[#said].key)
    end)

    it("unlocks Knox knowledge when the July 16 Herald is read, and only that issue", function()
        local function paper(id)
            return {
                hasModData = function() return true end,
                getModData = function() return { printMedia = { id = id, title = "Print_Media_" .. id .. "_title" } } end,
            }
        end
        ISReadABook.complete({ character = player, item = paper("KentuckyHerald_July15") })
        assert.is_false(state().knowledge.knoxHerald)
        ISReadABook.complete({ character = player, item = paper("KentuckyHerald_July16") })
        assert.is_true(state().knowledge.knoxHerald)
        assert.is_true(state().knowledge.diseases.knox_infection)
    end)

    it("unlocks it for a character who had read that issue before", function()
        local other = game.addPlayer({ x = 120 })
        game.events.OnCreatePlayer.trigger(1, other)
        other.printMediaRead.KentuckyHerald_July16 = true
        game.advance(12)
        assert.is_true(other.modData.ExtensiveHealthRedone.knowledge.knoxHerald)
    end)
end)
