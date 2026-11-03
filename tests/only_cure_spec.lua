-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake game objects are deliberately partial.
---@diagnostic disable: missing-fields
-- The Only Cure beside us: the pure amputation rules (Wounds/Amputation), the body aggregator's missing parts, the
-- washing plan's extra parts and the Monitor rows first, then the server wiring against the fake game with a stand-in
-- for the mod's DataController, with the mod off, on but not ready, and on.
local Amputation = require("ExtensiveHealthRedone/Wounds/Amputation")
local Infection = require("ExtensiveHealthRedone/Wounds/Infection")
local WoundData = require("ExtensiveHealthRedone/Data/Wounds")
local Washing = require("ExtensiveHealthRedone/Diseases/Food/Washing")
local BodyAggregator = require("ExtensiveHealthRedone/Core/BodyAggregator")
local Sim = require("support/sim")

local STUMP = WoundData.stump
local EVERY = STUMP.EVERY_HOURS * 60

-- A snapshot as Game/OnlyCure reads it. cut: { [limb] = { healed, cauterized, dirt } }.
local function snapshot(cut, prosthesis)
    local toc = { limbs = {}, prosthesis = prosthesis or {} }
    for _, limb in ipairs(Amputation.LIMBS) do
        local c = cut and cut[limb]
        toc.limbs[limb] = { cut = c ~= nil, healed = c and c.healed or false, cauterized = c and c.cauterized or false,
            dirt = c and c.dirt or 0 }
    end
    return toc
end

local function context(opts)
    local p = Sim.context(opts)
    p.state.onlyCure = Amputation.defaults()
    return p
end

describe("amputation snapshot rules", function()
    it("knows the cut parts, each arm's stump and the part it sits on", function()
        local toc = snapshot({ Hand_L = {}, ForeArm_L = { dirt = 0.4 }, UpperArm_R = { healed = true },
            ForeArm_R = {}, Hand_R = {} })
        assert.same({ Hand_L = true, ForeArm_L = true, Hand_R = true, ForeArm_R = true, UpperArm_R = true },
            Amputation.missing(toc))
        local stumps = Amputation.stumps(toc)
        assert.equal(2, #stumps)
        assert.same({ limb = "ForeArm_L", side = "L", part = "UpperArm_L", healed = false, cauterized = false,
            dirt = 0.4 }, stumps[1])
        assert.equal("UpperArm_R", stumps[2].limb)
        assert.equal("Torso_Upper", stumps[2].part)
        assert.is_true(stumps[2].healed)
    end)

    it("tells a hand from a prosthesis from nothing", function()
        local toc = snapshot({ Hand_L = {}, Hand_R = {} }, { R = true })
        assert.equal("none", Amputation.hand(toc, "L"))
        assert.equal("prosthesis", Amputation.hand(toc, "R"))
        assert.is_false(Amputation.noHands(toc))
        assert.is_true(Amputation.noHands(snapshot({ Hand_L = {}, Hand_R = {} })))
        assert.equal("hand", Amputation.hand(snapshot(), "L"))
    end)

    it("scales the stump chance by dirtiness and the multiplier, within 0-1", function()
        assert.near(STUMP.CHANCE, Amputation.stumpChance(1, 1), 1e-9)
        assert.near(STUMP.CHANCE / 2, Amputation.stumpChance(0.5, 1), 1e-9)
        assert.equal(0, Amputation.stumpChance(0.8, 0))
        assert.equal(0, Amputation.stumpChance(0, 5))
        assert.equal(1, Amputation.stumpChance(1, 100))
    end)
end)

describe("the amputation system", function()
    it("does nothing without the mod's facts", function()
        local p = context()
        p.state.wounds.parts.Hand_L = { phase = "infected", stage = 2, left = 100 }
        Amputation.update(p, 1)
        assert.same(Amputation.defaults(), p.state.onlyCure)
        assert.is_not_nil(p.state.wounds.parts.Hand_L)
        assert.same({}, p.dirtied)
    end)

    it("cleans up an amputation it finds on the first sight of the mod, without a line or XP", function()
        local p = context()
        p.state.wounds.parts.Hand_L = { phase = "infected", stage = 2, left = 100 }
        p.state.wounds.tetanus.dirty.Hand_L = 30
        p.state.wounds.tetanus.seen.Hand_L = { deep = true, glass = false }
        p.state.body.woundLock = { Hand_L = { cut = 2 } }
        p.facts.toc = snapshot({ Hand_L = {} })
        Amputation.update(p, 1)
        assert.is_nil(p.state.wounds.parts.Hand_L)
        assert.is_nil(p.state.wounds.tetanus.dirty.Hand_L)
        assert.is_nil(p.state.wounds.tetanus.seen.Hand_L)
        assert.is_nil(p.state.body.woundLock.Hand_L)
        assert.same({}, p.said)
        assert.same({}, p.xps)
        assert.is_true(p.state.onlyCure.known)
        assert.same({ Hand_L = true }, p.state.onlyCure.cut)
    end)

    it("cures a wound infection by amputating at or above it, once, and leaves sepsis alone", function()
        local p = context({ sandbox = { DialogueFrequency = 3 } })
        p.facts.toc = snapshot()
        Amputation.update(p, 1)
        p.state.wounds.parts.Hand_L = { phase = "infected", stage = 3, left = 10 }
        p.state.wounds.parts.UpperArm_L = { phase = "infected", stage = 1, left = 500 }
        p.state.conditions.active.sepsis = { stage = 1, left = 100, data = {} }
        -- Cutting the forearm takes the hand too.
        p.facts.toc = snapshot({ Hand_L = {}, ForeArm_L = {} })
        Amputation.update(p, 1)
        assert.is_nil(p.state.wounds.parts.Hand_L)
        assert.is_not_nil(p.state.wounds.parts.UpperArm_L)
        assert.is_not_nil(p.state.conditions.active.sepsis)
        assert.same({ STUMP.CURED_LINE }, p.said)
        assert.same({ { "cure", "woundInfection" } }, p.xps)
        Amputation.update(p, 1)
        assert.equal(1, #p.said)
        assert.equal(1, #p.xps)
    end)

    it("drops an incubation on a cut part without a word", function()
        local p = context({ sandbox = { DialogueFrequency = 3 } })
        p.facts.toc = snapshot()
        Amputation.update(p, 1)
        p.state.wounds.parts.Hand_R = { phase = "incubating", left = 100, immune = 50, rolled = false }
        p.facts.toc = snapshot({ Hand_R = {} })
        Amputation.update(p, 1)
        assert.is_nil(p.state.wounds.parts.Hand_R)
        assert.same({}, p.said)
        assert.same({}, p.xps)
    end)

    it("changes nothing while the mod's data is not ready, and never brings state back", function()
        local p = context()
        p.facts.toc = snapshot({ Hand_L = {} })
        Amputation.update(p, 1)
        p.facts.toc = nil
        p.state.wounds.parts.ForeArm_L = { phase = "infected", stage = 1, left = 100 }
        Amputation.update(p, 1)
        assert.same({ Hand_L = true }, p.state.onlyCure.cut)
        assert.is_not_nil(p.state.wounds.parts.ForeArm_L)
    end)

    it("forgets a limb the mod no longer has cut (mod removed or reset) and keeps an infection already there", function()
        local p = context()
        p.facts.toc = snapshot({ Hand_L = { dirt = 1 } })
        Amputation.update(p, 1)
        p.state.wounds.parts.ForeArm_L = { phase = "infected", stage = 1, left = 100 }
        p.facts.toc = snapshot()
        Amputation.update(p, 1)
        assert.same({}, p.state.onlyCure.cut)
        assert.same({}, p.state.onlyCure.stumps)
        assert.is_not_nil(p.state.wounds.parts.ForeArm_L)
    end)

    it("rolls an open stump every 12 h by its dirtiness, on the part above it", function()
        local p = context({ floats = { 0.99, STUMP.CHANCE * 0.8 - 0.01 } })
        p.facts.toc = snapshot({ Hand_L = { dirt = 0.8 } })
        Amputation.update(p, EVERY - 1)
        assert.is_nil(p.state.wounds.parts.ForeArm_L)
        Amputation.update(p, 1)                         -- the first roll misses
        assert.is_nil(p.state.wounds.parts.ForeArm_L)
        assert.equal(0, p.state.onlyCure.stumps.Hand_L.elapsed)
        Amputation.update(p, EVERY)                     -- the second hits
        local e = p.state.wounds.parts.ForeArm_L
        assert.equal("incubating", e.phase)
        assert.equal("Hand_L", e.stump)
    end)

    it("doesn't roll a healed or cauterized stump, under antiseptic, with wound infection off or at 0", function()
        local cases = {
            { cut = { Hand_L = { dirt = 1, healed = true } } },
            { cut = { Hand_L = { dirt = 1, cauterized = true } } },
            { cut = { Hand_L = { dirt = 1 } }, treatment = { active = { antiseptic = true } } },
            { cut = { Hand_L = { dirt = 1 } }, sandbox = { WoundInfectionEnabled = false } },
            { cut = { Hand_L = { dirt = 1 } }, sandbox = { StumpInfectionChanceMultiplier = 0 } },
        }
        for i, case in ipairs(cases) do
            local p = context({ float = 0, treatment = case.treatment, sandbox = case.sandbox })
            p.facts.toc = snapshot(case.cut)
            Amputation.update(p, EVERY)
            Amputation.update(p, EVERY)
            assert.is_nil(p.state.wounds.parts.ForeArm_L, "case " .. i)
        end
    end)

    it("counts the mod's wound cleaning as disinfecting an incubation under the stump", function()
        local p = context({ sandbox = { DialogueFrequency = 3 } })
        p.facts.toc = snapshot({ Hand_L = { dirt = 0.9 } })
        Amputation.update(p, 1)
        Infection.start(p, "ForeArm_L")
        p.facts.toc = snapshot({ Hand_L = { dirt = 0 } })
        Amputation.update(p, 1)
        assert.is_nil(p.state.wounds.parts.ForeArm_L)
        assert.same({ WoundData.infection.PREVENTED_LINE }, p.said)
    end)

    it("syncs the section only when what the Monitor shows changes", function()
        local p = context()
        p.facts.toc = snapshot({ Hand_L = { dirt = 0.31 } })
        Amputation.update(p, 1)
        p.dirtied = {}
        p.facts.toc = snapshot({ Hand_L = { dirt = 0.32 } })
        Amputation.update(p, 1)
        assert.is_nil(p.dirtied.onlyCure)
        p.facts.toc = snapshot({ Hand_L = { dirt = 0.36 } })
        Amputation.update(p, 1)
        assert.equal(1, p.dirtied.onlyCure)
        assert.equal(0.4, p.state.onlyCure.stumps.Hand_L.shown)
    end)

    it("leaves the part under an open stump to the stump's roll, not to vanilla's infection flag", function()
        local p = context()
        p.facts.parts.ForeArm_L = { health = 50, deep = true, wound = true, infected = true, stump = "Hand_L" }
        Infection.update(p, 1, {})
        assert.is_nil(p.state.wounds.parts.ForeArm_L)
        assert.is_false(p.body.infection.ForeArm_L)
        p.facts.parts.ForeArm_L.stump = nil
        Infection.update(p, 1, {})
        assert.equal("incubating", p.state.wounds.parts.ForeArm_L.phase)
    end)

    it("runs before the wound systems", function()
        local systems = require("ExtensiveHealthRedone/Systems")
        local order = {}
        for _, s in ipairs(systems) do
            order[s.name] = s.order
        end
        assert.is_true(order.amputation < order.wounds)
    end)
end)

describe("missing parts in the body aggregator", function()
    it("drops every per-part wish for a missing part", function()
        local body = BodyAggregator.new({ Hand_L = true })
        body:healFactor("Hand_L", "x", 0)
        body:pain("Hand_L", "x", 10)
        body:addPain("Hand_L", "x", 10)
        body:partDamage("Hand_L", "x", 10)
        body:infect("Hand_L", "x")
        body:scratch("Hand_L", "x")
        body:reopen("Hand_L", "x", "deep")
        body:woundSpeed("Hand_L", "x", 0.5)
        body:fractureSpeed("Hand_L", "x", 0.5)
        body:pain("Hand_R", "x", 10)
        assert.same({}, body.heal)
        assert.same({ Hand_R = { x = 10 } }, body.pains)
        assert.same({}, body.oneOff)
        assert.same({}, body.partDamages)
        assert.same({}, body.infection)
        assert.is_nil(body.scratches)
        assert.is_nil(body.reopened)
        assert.is_nil(body.woundSpeeds)
        assert.is_nil(body.fractureSpeeds)
    end)

    it("takes every wish without missing parts", function()
        local body = BodyAggregator.new()
        body:healFactor("Hand_L", "x", 0)
        body:scratch("Hand_L", "x")
        assert.equal(0, body.heal.Hand_L)
        assert.equal("x", body.scratches.Hand_L)
    end)
end)

describe("washing with The Only Cure's parts", function()
    it("plans the hands and arms as before when the soil has nothing else", function()
        local soil = { Hand_L = { blood = 0.2, dirt = 0 }, ForeArm_R = { blood = 0, dirt = 0.5 } }
        local plan = Washing.plan(soil, false) --[[@as table]]
        assert.same({ "Hand_L", "ForeArm_R" }, plan.parts)
    end)

    it("adds worn prostheses after the arms, and plans the face alone", function()
        local plan = Washing.plan({ ForeArm_L = { blood = 0, dirt = 0.3 }, Prosthesis_L = { blood = 0.4, dirt = 0 } },
            false) --[[@as table]]
        assert.same({ "ForeArm_L", "Prosthesis_L" }, plan.parts)
        assert.is_true(plan.bloody)
        local face = Washing.plan({ Head = { blood = 0, dirt = 0.6 } }, false) --[[@as table]]
        assert.same({ "Head" }, face.parts)
        assert.is_nil(Washing.plan({ Head = { blood = 0, dirt = 0 } }, false))
    end)

    it("averages two hands exactly as the two-hand formula did", function()
        local a, b = { blood = 0.3, dirt = 0.7 }, { blood = 0.1, dirt = 0.2 }
        assert.same({ blood = (a.blood + b.blood) / 2, dirt = (a.dirt + b.dirt) / 2 }, Washing.average({ a, b }))
        assert.same({ blood = 0.3, dirt = 0.7 }, Washing.average({ a }))
    end)
end)

describe("the amputation rows", function()
    local Rows = require("ExtensiveHealthRedone/UI/Amputation")

    it("shows nothing without amputations", function()
        assert.same({}, Rows.build({ state = {} }))
        assert.same({}, Rows.build({ state = { onlyCure = Amputation.defaults() } }))
    end)

    it("shows one row per stump: open with its dirt, healed, cauterized, and a prosthesis", function()
        local rows = Rows.build({ state = { onlyCure = {
            stumps = { ForeArm_L = { part = "UpperArm_L", shown = 0.6 }, Hand_R = { part = "ForeArm_R", healed = true } },
            prosthesis = { R = true },
        } } })
        assert.equal(2, #rows)
        assert.equal("UI_EHR_Amputation_ForeArm_L", rows[1].name.key)
        assert.equal("UI_EHR_Amputation_Open", rows[1].status.key)
        assert.equal("orange", rows[1].statusColor)
        assert.equal(0.6, rows[1].progress)
        assert.is_nil(rows[1].detail)
        assert.equal("UI_EHR_Amputation_Healed", rows[2].status.key)
        assert.equal("UI_EHR_Amputation_Prosthesis", rows[2].detail.key)
        local cauterized = Rows.build({ state = { onlyCure = { stumps = { Hand_L = { cauterized = true } } } } })
        assert.equal("UI_EHR_Amputation_Cauterized", cauterized[1].status.key)
    end)
end)

-- A stand-in for the mod's TOC/Controllers/DataController: one instance per username.
local function installFakeToc()
    local DataController = { instances = {} }
    function DataController.GetInstance(username)
        return DataController.instances[username]
    end
    function DataController.add(username)
        local dc = { ready = true, limbs = {}, prost = {} }
        for _, limb in ipairs(Amputation.LIMBS) do
            dc.limbs[limb] = { isCut = false, isCicatrized = false, isCauterized = false, woundDirtyness = 0 }
        end
        function dc:getIsDataReady() return self.ready end
        function dc:getIsCut(limb) return self.limbs[limb].isCut end
        function dc:getIsCicatrized(limb) return self.limbs[limb].isCicatrized end
        function dc:getIsCauterized(limb) return self.limbs[limb].isCauterized end
        function dc:getWoundDirtyness(limb) return self.limbs[limb].woundDirtyness end
        function dc:getIsProstEquipped(limb) return self.prost[limb:sub(-1)] == true end
        DataController.instances[username] = dc
        return dc
    end
    package.loaded["TOC/Controllers/DataController"] = DataController
    return DataController
end

-- A worn prosthesis: a fake Clothing item with soil on the parts it covers.
local function prosthesis(side, soil)
    local item = { fullType = "TOC.Prost_HookArm_" .. side, clothing = true, soil = soil }
    function item:getFullType() return self.fullType end
    function item:setBlood(part, v) self.soil[part.name].blood = v end
    function item:setDirt(part, v) self.soil[part.name].dirt = v end
    -- What Server/Corpse asks of worn clothing.
    function item:hasTag() return false end
    function item:getCorpseSicknessDefense() return 0 end
    return item
end

-- The server wiring with the fake game. mod: whether The Only Cure is enabled.
local function wiring(mod)
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    if mod then
        game.mods.TheOnlyCure = true
    end
    local Toc = installFakeToc()
    local player = game.addPlayer({ username = "alice" })
    game.events.OnCreatePlayer.trigger(0, player)
    _G.ItemTag = _G.ItemTag or {}
    _G.sendHumanVisual = function() end
    local synced = { items = 0, visuals = 0 }
    _G.syncItemFields = function() synced.items = synced.items + 1 end
    _G.syncVisuals = function() synced.visuals = synced.visuals + 1 end
    function player:resetModelNextFrame() end
    function player.inventory:getSoapList()
        return { size = function() return 0 end }
    end
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameStart.trigger()
    game.advance(2)
    return {
        game = game, player = player, Toc = Toc, synced = synced, FakeGame = FakeGame,
        state = function() return player.modData.ExtensiveHealthRedone end,
    }
end

insulate("single-player wiring: The Only Cure off", function()
    local w = wiring(false)
    local dc = w.Toc.add("alice")
    dc.limbs.Hand_L.isCut = true
    local Food = require("ExtensiveHealthRedone/Server/Food")
    local Facts = require("ExtensiveHealthRedone/Server/Facts")

    it("never reads the mod: no facts, no missing parts, nothing dropped", function()
        w.state().wounds.parts.Hand_L = { phase = "infected", stage = 1, left = 1000 }
        w.game.advance(2)
        local facts = Facts.read(w.player, { WETNESS = { min = 0, max = 100 } })
        assert.is_nil(facts.toc)
        assert.is_nil(facts.missing)
        assert.is_not_nil(w.state().wounds.parts.Hand_L)
        local section = w.state().onlyCure
        assert.is_false(section.known)
        assert.same({}, section.cut)
        assert.same({}, section.stumps)
    end)

    it("reads both hands for a bite and washes the hands and arms, as before", function()
        local v = w.player.visual
        v.blood.Hand_L, v.dirt.Hand_L, v.blood.Hand_R, v.dirt.Hand_R = 0.3, 0.7, 0.1, 0.2
        v.dirt.Head = 0.9
        assert.same({ blood = (0.3 + 0.1) / 2, dirt = (0.7 + 0.2) / 2 }, Food.hands(w.player))
        local soil, mode = Food.soil(w.player)
        assert.equal("hands", mode)
        for _, name in ipairs(Washing.PARTS) do
            assert.is_not_nil(soil[name], name)
        end
        assert.is_nil(soil.Head)
        assert.is_nil(soil.Prosthesis_L)
    end)
end)

insulate("single-player wiring: The Only Cure on, data not ready", function()
    local w = wiring(true)
    local dc = w.Toc.add("alice")
    dc.limbs.Hand_L.isCut = true
    dc.ready = false
    local Food = require("ExtensiveHealthRedone/Server/Food")

    it("treats the mod as absent until its data is ready", function()
        w.state().wounds.parts.Hand_L = { phase = "infected", stage = 1, left = 1000 }
        w.game.advance(2)
        assert.is_not_nil(w.state().wounds.parts.Hand_L)
        assert.is_false(w.state().onlyCure.known)
        local v = w.player.visual
        v.dirt.Hand_L, v.dirt.Hand_R = 0.4, 0
        assert.equal(0.2, Food.hands(w.player).dirt)
    end)

    it("cleans up once the data arrives", function()
        dc.ready = true
        w.game.advance(2)
        assert.is_nil(w.state().wounds.parts.Hand_L)
        assert.is_true(w.state().onlyCure.known)
    end)
end)

insulate("single-player wiring: The Only Cure on", function()
    local w = wiring(true)
    local dc = w.Toc.add("alice")
    local Food = require("ExtensiveHealthRedone/Server/Food")
    local Facts = require("ExtensiveHealthRedone/Server/Facts")
    local Client = require("ExtensiveHealthRedone/Client/Client")
    local said = {}
    Client.on("say", function(args) said[#said + 1] = args.key end)
    _G.SandboxVars.ExtensiveHealthRework.DialogueFrequency = 3

    local function readFacts()
        return Facts.read(w.player, { WETNESS = { min = 0, max = 100 } })
    end

    it("reads a cut part as missing and the part under an open stump as wounded", function()
        dc.limbs.Hand_L.isCut = true
        dc.limbs.Hand_L.woundDirtyness = 0.5
        local facts = readFacts()
        assert.same({ Hand_L = true }, facts.missing)
        assert.is_true(facts.parts.Hand_L.missing)
        assert.is_false(facts.parts.Hand_L.wound)
        assert.equal("Hand_L", facts.parts.ForeArm_L.stump)
        assert.is_true(facts.parts.ForeArm_L.wound)
        assert.equal(0.5, facts.toc.limbs.Hand_L.dirt)
    end)

    it("cures a wound infection on a limb cut off during play, with XP", function()
        dc.limbs.Hand_L.isCut = false
        w.game.advance(2)
        assert.is_true(w.state().onlyCure.known)
        w.state().wounds.parts.Hand_R = { phase = "infected", stage = 2, left = 1000 }
        local xp = w.game.xp.alice or 0
        dc.limbs.Hand_R.isCut = true
        w.game.advance(2)
        assert.is_nil(w.state().wounds.parts.Hand_R)
        assert.equal(STUMP.CURED_LINE, said[#said])
        assert.is_true((w.game.xp.alice or 0) > xp)
        assert.same({ Hand_R = true }, w.state().onlyCure.cut)
    end)

    it("eats with the one hand left, a worn prosthesis, or face first", function()
        local v = w.player.visual
        v.blood.Hand_L, v.dirt.Hand_L, v.blood.Hand_R, v.dirt.Hand_R = 0, 0.6, 0, 0.1
        v.blood.Head, v.dirt.Head = 0.2, 0.8
        -- Hand_R is cut: only the left hand touches the food.
        assert.same({ blood = 0, dirt = 0.6 }, Food.hands(w.player))
        -- A hook on the right.
        dc.prost.R = true
        w.player.worn[1] = prosthesis("R", { UpperArm_R = { blood = 0.5, dirt = 0.4 } })
        assert.same({ blood = 0.25, dirt = 0.5 }, Food.hands(w.player))
        -- No hand and no prosthesis: the face.
        dc.prost.R = false
        w.player.worn[1] = nil
        dc.limbs.Hand_L.isCut = true
        assert.same({ blood = 0.2, dirt = 0.8 }, Food.hands(w.player))
    end)

    it("washes the face when no hand is left, and the parts left and the prosthesis otherwise", function()
        local soil, mode = Food.soil(w.player)
        assert.equal("face", mode)
        assert.same({ Head = { blood = 0.2, dirt = 0.8 } }, soil)

        dc.limbs.Hand_L.isCut = false
        dc.prost.R = true
        w.player.worn[1] = prosthesis("R", { UpperArm_R = { blood = 0.5, dirt = 0.4 } })
        soil, mode = Food.soil(w.player)
        assert.equal("hands", mode)
        assert.is_nil(soil.Hand_R)
        assert.is_not_nil(soil.ForeArm_R)
        assert.same({ blood = 0.5, dirt = 0.4 }, soil.Prosthesis_R)
    end)

    it("cleans a worn prosthesis at a sink, and the face with Wash Face", function()
        local sq = w.FakeGame.newSquare(101, 100, 0)
        local cell = _G.getCell()
        _G.getCell = function()
            cell.getGridSquare = function(_, x, y, z)
                return x == 101 and y == 100 and z == 0 and sq or nil
            end
            return cell
        end
        sq.objects[1] = {
            getFluidAmount = function() return 5 end,
            useFluid = function(_, amount) return amount end,
            transmitModData = function() end,
        }
        local Authority = require("ExtensiveHealthRedone/Actions/Authority")
        assert.is_true(Authority.run(w.player, "food.washHands", { x = 101, y = 100, z = 0 }))
        assert.same({ blood = 0, dirt = 0 }, w.player.worn[1].soil.UpperArm_R)
        assert.equal(1, w.synced.items)
        assert.equal(1, w.synced.visuals)
        assert.equal("UI_EHR_Text_WashesHandsMuchBetter", said[#said])

        dc.limbs.Hand_L.isCut = true
        dc.prost.R = false
        w.player.worn[1] = nil
        w.player.visual.dirt.Head = 0.8
        assert.is_true(Authority.run(w.player, "food.washHands", { x = 101, y = 100, z = 0 }))
        assert.equal(0, w.player.visual.dirt.Head)
        assert.equal("UI_EHR_Text_WashesFaceMuchBetter", said[#said])
    end)

    it("switches itself off when the mod's data has changed shape", function()
        local OnlyCure = require("ExtensiveHealthRedone/Game/OnlyCure")
        dc.getIsCut = nil
        assert.is_nil(OnlyCure.read(w.player))
        assert.is_false(OnlyCure.active())
    end)
end)
