-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla chat is deliberately partial.
---@diagnostic disable: missing-fields
-- Phase 9 admin commands: the pure full heal and reset (Admin/FullHeal), name matching (Admin/Names), chat parsing
-- (Admin/ChatCommands) and the inspect summary (Admin/Inspect), then the wiring in single-player mode against
-- tests/support/fake_game.lua: the chat hook, admin.fullHeal/reset/inspect on another player, the permission and the
-- debug menu's full heal.
local FullHeal = require("ExtensiveHealthRedone/Admin/FullHeal")
local Names = require("ExtensiveHealthRedone/Admin/Names")
local ChatCommands = require("ExtensiveHealthRedone/Admin/ChatCommands")
local Inspect = require("ExtensiveHealthRedone/Admin/Inspect")
local Schema = require("ExtensiveHealthRedone/Core/Schema")
local StatAggregator = require("ExtensiveHealthRedone/Core/StatAggregator")
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local Infection = require("ExtensiveHealthRedone/Wounds/Infection")
local ImmunityData = require("ExtensiveHealthRedone/Data/Immunity")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Sim = require("support/sim")

local RANGES = {}
for name, range in pairs(Sim.RANGES) do
    RANGES[name] = range
end
for _, name in ipairs({ "ZOMBIE_INFECTION", "ZOMBIE_FEVER", "BOREDOM", "POISON" }) do
    RANGES[name] = { min = 0, max = 100 }
end

local function context()
    local p = Sim.context()
    p.stats = StatAggregator.new(RANGES)
    return p
end

-- A state with something in every section: conditions, a wound infection, low blood, meds, exposure, mind,
-- temperature, Knox item history, permanent immunity and knowledge.
local function sickContext()
    local p = context()
    local s = p.state
    s.identity.bloodType = "AB-"
    s.knowledge.diseases.sepsis = true
    s.knowledge.knoxHerald = true
    s.knox.geneTherapyImmune = true
    s.knox.patientZeroTraitSource = true
    s.knox.survivor = true
    s.knox.lastTest = { bloodType = "AB-", chance = 10, rating = "x" }
    s.knox.boosterCooldown = 300
    s.knox.phalanxUses = 2
    s.knox.effects.phalanxNausea = 30
    s.immunity.score = 42
    s.immunity.tick = 7
    Engine.contract(p, defs, "sepsis", { source = "test" })
    Engine.contract(p, defs, "painkiller_addiction", { source = "test" })
    s.mind.painkiller.risk = 80
    Infection.start(p, "Hand_L", 2)
    s.blood.volume, s.blood.saline, s.blood.stage, s.blood.bleeding = 2000, 500, 1, true
    s.body.painApplied.Hand_L = 20
    s.exposure.cold, s.exposure.data.food = 60, { x = 1 }
    s.meds.courses.Amoxicillin = { count = 2, elapsed = 100, cured = {} }
    s.meds.side.tendon = { left = 50 }
    s.meds.xpCooldown.Amoxicillin = 30
    s.temperature.fever, s.temperature.floor = 39, 38.5
    s.effects.speed = 0.5
    s.conditions.timers.corpse_sicknessBlock = 60
    Sim.step(p)
    p.stats = StatAggregator.new(RANGES)
    return p
end

describe("admin full heal", function()
    it("resets every health row and keeps identity, immunity score and Knox item history", function()
        local p = sickContext()
        local summary = FullHeal.apply(p, defs, "heal")
        local s = p.state
        assert.same({ woundInfections = 1, conditions = 2 }, summary)
        assert.same({}, s.conditions.active)
        assert.same({}, s.wounds.parts)
        assert.same(Schema.sectionDefaults("wounds"), s.wounds)
        assert.equal(s.blood.max, s.blood.volume)
        assert.equal(0, s.blood.saline)
        assert.equal(4, s.blood.stage)
        assert.is_false(s.blood.bleeding)
        for _, name in ipairs(FullHeal.HEAL_SECTIONS) do
            assert.same(Schema.sectionDefaults(name), s[name], name)
        end
        assert.same({}, s.meds.courses)
        assert.same({}, s.meds.side)
        assert.same({ Amoxicillin = 30 }, s.meds.xpCooldown)
        -- identity and history kept
        assert.equal("AB-", s.identity.bloodType)
        assert.is_true(s.knowledge.diseases.sepsis)
        assert.is_true(s.knowledge.knoxHerald)
        assert.is_true(s.knox.geneTherapyImmune)
        assert.is_true(s.knox.patientZeroTraitSource)
        assert.is_true(s.knox.survivor)
        assert.equal(300, s.knox.boosterCooldown)
        assert.equal(2, s.knox.phalanxUses)
        assert.equal(10, s.knox.lastTest.chance)
        assert.same({}, s.knox.effects)
        assert.equal(42, s.immunity.score)
        assert.equal(0, s.immunity.tick)
        -- re-catch blocks: the existing one kept, the ended sepsis adds its own
        assert.equal(60, s.conditions.timers.corpse_sicknessBlock)
        assert.truthy(s.conditions.timers.sepsisBlock > 0)
    end)

    it("gives no XP, zeroes the needs and health stats and wishes the body restored", function()
        local p = sickContext()
        FullHeal.apply(p, defs, "heal")
        assert.same({}, p.xps)
        for _, stat in ipairs({ "HUNGER", "THIRST", "FATIGUE", "PAIN", "STRESS", "ZOMBIE_INFECTION", "POISON" }) do
            assert.equal(0, Sim.resolve(p, stat, 0.9), stat)
        end
        assert.same({ source = "admin" }, p.body.full)
        assert.equal("admin", p.body.knox.source)
        assert.is_false(p.body.infection.Hand_L)
    end)

    it("marks every section it changed dirty, and never the identity", function()
        local p = sickContext()
        p.dirtied = {}
        FullHeal.apply(p, defs, "heal")
        for _, name in ipairs({ "blood", "body", "wounds", "conditions", "exposure", "mind", "effects", "meds",
            "temperature", "knox", "immunity" }) do
            assert.truthy(p.dirtied[name], name)
        end
        assert.is_nil(p.dirtied.identity)
        assert.is_nil(p.dirtied.knowledge)
    end)

    it("reset keeps only meta, blood type, knowledge and permanent Knox immunity", function()
        local p = sickContext()
        local meta = p.state.meta
        FullHeal.apply(p, defs, "reset")
        local s = p.state
        local fresh = Schema.defaults()
        for _, name in ipairs(Schema.SECTIONS) do
            if not FullHeal.RESET_KEEPS[name] and name ~= "knox" then
                assert.same(fresh[name], s[name], name)
            end
        end
        assert.equal(ImmunityData.START, s.immunity.score)
        assert.same({}, s.meds.xpCooldown)
        assert.same({}, s.conditions.timers)
        assert.equal(meta, s.meta)
        assert.equal("AB-", s.identity.bloodType)
        assert.is_true(s.knowledge.diseases.sepsis)
        assert.is_true(s.knox.geneTherapyImmune)
        assert.is_true(s.knox.patientZeroTraitSource)
        assert.is_false(s.knox.immunityTraitGranted)
        assert.is_nil(s.knox.survivor)
        assert.is_nil(s.knox.lastTest)
        assert.equal(0, s.knox.boosterCooldown)
        assert.equal(0, s.knox.phalanxUses)
        assert.same({ source = "admin" }, p.body.full)
    end)

    it("leaves a healthy state healthy", function()
        local p = context()
        local before = p.state.identity.bloodType
        assert.same({ woundInfections = 0, conditions = 0 }, FullHeal.apply(p, defs))
        assert.equal(before, p.state.identity.bloodType)
    end)
end)

describe("admin name matching", function()
    local players = {
        { username = "BobTheBuilder", display = "BobTheBuilder", fullName = "Bob Smith" },
        { username = "bobcat", display = "bobcat", fullName = "Robert Cat" },
        { username = "alice", display = "Ally", fullName = "Alice Jones" },
        { username = "zed", display = "zed", fullName = "Bob Smith" },
    }

    it("prefers the exact username, ignoring case, quotes and spaces", function()
        assert.equal("bobcat", Names.match('  "BOBCAT" ', players).candidate.username)
    end)

    it("then an exact display or character name", function()
        assert.equal("alice", Names.match("ally", players).candidate.username)
        assert.equal("alice", Names.match("Alice Jones", players).candidate.username)
    end)

    it("reports two players with the same character name as ambiguous", function()
        local found = Names.match("bob smith", players)
        assert.equal("many", found.status)
        assert.same({ "BobTheBuilder", "zed" }, found.usernames)
    end)

    it("then a part of the username, if only one player has it", function()
        assert.equal("BobTheBuilder", Names.match("builder", players).candidate.username)
        local found = Names.match("bob", players)
        assert.equal("many", found.status)
        assert.equal(2, found.count)
    end)

    it("lists at most five usernames", function()
        local many = {}
        for i = 1, 7 do
            many[i] = { username = "user" .. i }
        end
        local found = Names.match("user", many)
        assert.equal(7, found.count)
        assert.equal(5, #found.usernames)
    end)

    it("finds nobody for an unknown or empty name", function()
        assert.equal("none", Names.match("carol", players).status)
        assert.equal("none", Names.match("  ", players).status)
    end)
end)

describe("admin chat commands", function()
    it("parses the three commands without case, with the name in its own case", function()
        assert.same({ command = "admin.fullHeal", usage = "UI_EHR_Admin_UsageFullHeal", word = "/ehrfullheal",
            name = "Bob Smith" }, ChatCommands.parse("/EhrFullHeal  Bob Smith "))
        assert.equal("admin.reset", ChatCommands.parse("/ehrreset x").command)
        assert.equal("admin.inspect", ChatCommands.parse("/ehrinspect x").command)
    end)

    it("has no name for the bare command", function()
        assert.is_nil(ChatCommands.parse("/ehrfullheal   ").name)
    end)

    it("leaves other lines to vanilla", function()
        assert.is_nil(ChatCommands.parse("/ehrfullhealx Bob"))
        assert.is_nil(ChatCommands.parse("hello /ehrfullheal Bob"))
        assert.is_nil(ChatCommands.parse("/all hi"))
    end)
end)

describe("admin inspect", function()
    it("summarises blood, conditions, wound infections, courses, immunity and Knox", function()
        local p = sickContext()
        local lines = Inspect.lines(p.state, defs, "bob")
        local keys = {}
        for _, t in ipairs(lines) do
            keys[#keys + 1] = t.key
        end
        assert.same({ "UI_EHR_Admin_InspectHeader", "UI_EHR_Admin_InspectBlood", "UI_EHR_Admin_InspectCondition",
            "UI_EHR_Admin_InspectCondition", "UI_EHR_Admin_InspectWound", "UI_EHR_Admin_InspectCourse",
            "UI_EHR_Admin_InspectImmunity", "UI_EHR_Admin_InspectKnox", "UI_EHR_Admin_InspectLogged" }, keys)
        assert.same({ "40", "AB-" }, lines[2].args)
        assert.equal("UI_EHR_Admin_KnoxImmune", lines[8].args[1].key)
    end)
end)

insulate("single-player wiring: admin commands", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- A fake MP chat window: the text box holds vanilla's function, as ISChat:createChildren copies it.
    local toVanilla = {}
    local chat = { textEntry = { text = "" }, chatText = { tabID = 0 }, tabs = { { tabID = 0 } }, history = {} }
    function chat.textEntry.getText(self) return self.text end
    function chat.unfocus(self) self.textEntry.text = "" end
    function chat.logChatCommand(self, line) self.history[#self.history + 1] = line end
    local lines = {}
    _G.ISChat = {
        instance = chat,
        onCommandEntered = function() toVanilla[#toVanilla + 1] = chat.textEntry.text end,
        addLineInChat = function(message, tab)
            assert.equal(0, tab)
            lines[#lines + 1] = message:getTextWithPrefix()
        end,
    }
    local vanillaEntered = ISChat.onCommandEntered
    chat.textEntry.onCommandEntered = vanillaEntered
    _G.doKeyPress = function() end
    _G.HaloTextHelper = { addText = function() end, addBadText = function() end }
    -- Translations show their arguments, so the lines can be checked.
    ---@diagnostic disable-next-line: duplicate-set-field
    _G.getText = function(key, ...)
        local args = { ... }
        return #args > 0 and key .. " " .. table.concat(args, "|") or key
    end

    local Client = require("ExtensiveHealthRedone/Client/Client")
    require("ExtensiveHealthRedone/Client/AdminChat")
    local admin = game.addPlayer({ username = "admin" })
    local bob = game.addPlayer({ username = "BobTheBuilder", forename = "Bob", surname = "Smith" })
    game.addPlayer({ username = "bobcat" })
    local alice = game.addPlayer({ username = "alice", displayName = "Ally" })
    _G.getPlayer = function() return admin end
    for i, player in ipairs(game.players) do
        game.events.OnCreatePlayer.trigger(i - 1, player)
    end
    require("ExtensiveHealthRedone/Server/Main")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    local Players = require("ExtensiveHealthRedone/Server/Players")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function type_(text)
        chat.textEntry.text = text
        chat.textEntry.onCommandEntered(chat.textEntry)
        game.realMs = game.realMs + 10000     -- past the rate limits
    end

    local function lastLine()
        return lines[#lines]
    end

    local function hasLine(prefix)
        for _, line in ipairs(lines) do
            if line:find("[EHR] " .. prefix, 1, true) == 1 then
                return true
            end
        end
        return false
    end

    local function state(player)
        return player.modData.ExtensiveHealthRedone
    end

    local function keyOf(player)
        return Players.record(player).key
    end

    local function makeSick(player)
        Runtime.applyNow(keyOf(player), function(p)
            Engine.contract(p, defs, "sepsis", { source = "test" })
            Infection.start(p, "Hand_L", 2)
            p.state.blood.volume = 2500
            p.state.meds.courses.Amoxicillin = { count = 1, elapsed = 10, cured = {} }
            p.state.exposure.cold = 70
            p.state.knowledge.diseases.sepsis = true
            p.state.knox.geneTherapyImmune = true
        end)
        player.body:part("ForeArm_R").health = 40
        player.body:part("ForeArm_R").flags.deep = true
        player.body:part("Head").stiffness = 50
        player.stats.HUNGER, player.stats.PAIN = 60, 30
    end

    it("rebinds the chat text box to the patched handler", function()
        assert.are_not.equal(vanillaEntered, ISChat.onCommandEntered)
        assert.equal(ISChat.onCommandEntered, chat.textEntry.onCommandEntered)
    end)

    it("prints the usage locally for a command without a name, and sends nothing to vanilla", function()
        type_("/EHRFULLHEAL   ")
        assert.equal("[EHR] UI_EHR_Admin_UsageFullHeal", lastLine())
        assert.same({}, toVanilla)
        assert.same({ "/EHRFULLHEAL   " }, chat.history)
        assert.equal("", chat.textEntry.text)
    end)

    it("leaves other slash commands to vanilla", function()
        type_("/ehrfullhealx bob")
        type_("/all hello")
        assert.same({ "/ehrfullhealx bob", "/all hello" }, toVanilla)
    end)

    it("fully heals another player by character name and keeps their identity", function()
        makeSick(bob)
        local bloodType = state(bob).identity.bloodType
        local xpBefore = game.xp.admin or 0
        type_("/ehrfullheal bob smith")
        local s = state(bob)
        assert.same({}, s.conditions.active)
        assert.same({}, s.wounds.parts)
        assert.equal(s.blood.max, s.blood.volume)
        assert.same({}, s.meds.courses)
        assert.equal(0, s.exposure.cold)
        assert.is_true(s.knowledge.diseases.sepsis)
        assert.is_true(s.knox.geneTherapyImmune)
        assert.equal(bloodType, s.identity.bloodType)
        assert.equal(100, bob.body:part("ForeArm_R").health)
        assert.is_nil(bob.body:part("ForeArm_R").flags.deep)
        assert.equal(0, bob.body:part("Head").stiffness)
        assert.is_true(bob.stiffnessRemoved.Head)
        assert.equal(0, bob.stats.HUNGER)
        assert.equal(0, bob.stats.PAIN)
        assert.equal(xpBefore, game.xp.admin or 0)
        assert.is_nil(game.xp.BobTheBuilder)
        assert.truthy(hasLine("UI_EHR_Admin_HealDone BobTheBuilder|1|1"))
        assert.truthy(hasLine("UI_EHR_Admin_YouWereHealed"))
        assert.truthy(game.logged("admin: heal of"))
        game.advance(5)
        assert.same({}, state(bob).conditions.active)
    end)

    it("refuses without the permission and leaves the target alone", function()
        makeSick(alice)
        local can = Players.can
        ---@diagnostic disable-next-line: duplicate-set-field
        Players.can = function() return false end
        type_("/ehrfullheal alice")
        Players.can = can
        assert.equal("[EHR] UI_EHR_Admin_Forbidden forbidden", lastLine())
        assert.truthy(state(alice).conditions.active.sepsis)
    end)

    it("reports an ambiguous or unknown name", function()
        type_("/ehrfullheal bob")
        assert.equal('[EHR] UI_EHR_Admin_Ambiguous bob|2|BobTheBuilder, bobcat', lastLine())
        type_("/ehrinspect carol")
        assert.equal("[EHR] UI_EHR_Admin_NotFound carol", lastLine())
    end)

    it("inspects a player by display name: summary lines to the admin, the full state to the log", function()
        local before = #lines
        type_("/ehrinspect Ally")
        assert.truthy(#lines - before >= 6)
        assert.equal("[EHR] UI_EHR_Admin_InspectHeader alice", lines[before + 1])
        assert.truthy(game.logged("inspect of"))
        assert.truthy(state(alice).conditions.active.sepsis)
    end)

    it("resets a player to a new character's state, keeping only identity", function()
        Runtime.applyNow(keyOf(alice), function(p)
            p.state.meds.xpCooldown.Amoxicillin = 30
            p.state.immunity.score = 20
        end)
        local bloodType = state(alice).identity.bloodType
        type_("/ehrreset alice")
        local s = state(alice)
        assert.same({}, s.conditions.active)
        assert.same({}, s.meds.xpCooldown)
        assert.equal(ImmunityData.START, s.immunity.score)
        assert.equal(bloodType, s.identity.bloodType)
        assert.is_true(s.knowledge.diseases.sepsis)
        assert.is_true(s.knox.geneTherapyImmune)
        assert.truthy(hasLine("UI_EHR_Admin_ResetDone alice"))
        assert.truthy(hasLine("UI_EHR_Admin_YouWereReset"))
    end)

    it("debug full heal cures Knox for good: knox_infection doesn't come back", function()
        game.sandbox.DebugMode = true
        admin.body.knox = { infected = true, time = game.minutes / 60 - 5, duration = 48 }
        admin.body:part("Hand_R").knox = true
        admin.stats.ZOMBIE_INFECTION = 30
        game.advance(2)
        assert.truthy(state(admin).conditions.active.knox_infection)
        Client.send(admin, "debug.healAll", {})
        assert.is_false(admin.body.knox.infected)
        assert.is_false(admin.body:part("Hand_R").knox)
        assert.equal(0, admin.stats.ZOMBIE_INFECTION)
        game.advance(5)
        assert.is_nil(state(admin).conditions.active.knox_infection)
        game.sandbox.DebugMode = false
    end)
end)
