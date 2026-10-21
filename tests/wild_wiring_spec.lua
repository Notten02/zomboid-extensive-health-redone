-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, undefined-field, duplicate-set-field, need-check-nil
-- Server/WildSearch against the fake game: the plant search's access check, server-held board, thorn injuries and
-- gloves, find and XP, and cooldown; the hive search's grab timing, items and stings; the debug command. The client
-- panels need the game UI and are tested in game (docs/porting/phase8/herbal-and-hive-minigames.md).

insulate("single-player wiring: wild searches", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local Data = require("ExtensiveHealthRedone/Data/WildSearch")
    local Vegetation = require("ExtensiveHealthRedone/Wild/Vegetation")

    -- The game API the wild searches add on top of the fake game.
    local globalModData = {}
    _G.ModData = {
        getOrCreate = function(tag)
            globalModData[tag] = globalModData[tag] or {}
            return globalModData[tag]
        end,
    }
    _G.getScriptManager = function()
        return { FindItem = function() return {} end }
    end
    _G.IsoFlagType.canBeCut = "canBeCut"
    _G.getZones = function()
        return { size = function() return 1 end, get = function() return { getType = function() return "DeepForest" end } end }
    end
    _G.ItemBodyLocation = { HANDS = "Hands", HANDS_LEFT = "HandsLeft", HANDS_RIGHT = "HandsRight" }
    _G.Perks.PlantScavenging = { name = "PlantScavenging" }
    local xp = {}
    _G.addXp = function(_, perk, amount)
        xp[perk.name] = (xp[perk.name] or 0) + amount
    end
    local synced = 0
    _G.syncItemFields = function() synced = synced + 1 end

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({ firstAid = 4 })      -- getPerkLevel: 4 for every skill
    player.wornAt = {}
    function player:getWornItem(location) return self.wornAt[location] end
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local WildSearch = require("ExtensiveHealthRedone/Server/WildSearch")
    game.events.OnGameStart.trigger()

    local replies = {}
    for _, command in ipairs({ "herbSession", "herbDenied", "herbReveal", "herbResult", "herbClosed", "hiveSession",
        "hiveDenied", "hiveCollected", "hiveStung" }) do
        Client.on(command, function(args)
            replies[#replies + 1] = { command = command, args = args }
        end)
    end
    local function last(command)
        for i = #replies, 1, -1 do
            if replies[i].command == command then
                return replies[i].args
            end
        end
        return nil
    end

    local function addSquare(x, y, bush, tree)
        local sq = FakeGame.newSquare(x, y, 0)
        function sq:isOutside() return true end
        function sq:getTree() return tree end
        if bush then
            sq.objects[1] = { getSprite = function()
                return { getProperties = function()
                    return { has = function(_, flag) return flag == "canBeCut" end }
                end }
            end }
        end
        game.squares[x .. "," .. y .. ",0"] = sq
        return sq
    end

    -- A bush next to the player (at 100,100) that is a search patch.
    local bush
    for _, offset in ipairs({ { 1, 1 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { 1, -1 }, { -1, 0 }, { 0, -1 }, { -1, -1 } }) do
        local x, y = 100 + offset[1], 100 + offset[2]
        if Vegetation.passesDensity(x, y, 0, "deepForest") then
            bush = addSquare(x, y, true)
            break
        end
    end
    local tree = addSquare(98, 100, false, {})
    local thornCell

    it("refuses the plant search without the guide or the skills", function()
        player.firstAid = 3
        Client.send(player, "herb.begin", { x = bush.x, y = bush.y, z = 0 })
        assert.equal("invalid", last("herbDenied").reason)
        player.firstAid = 4
    end)

    it("refuses a bush that isn't there or out of reach", function()
        local far = addSquare(110, 110, true)
        Client.send(player, "herb.begin", { x = far.x, y = far.y, z = 0 })
        assert.equal("invalid", last("herbDenied").reason)
    end)

    it("opens a session and reveals only the picked cell", function()
        game.realMs = game.realMs + 20000      -- clear of the begin rate limit
        Client.send(player, "herb.begin", { x = bush.x, y = bush.y, z = 0 })
        local session = last("herbSession")
        assert.is_not_nil(session)
        assert.equal(9, session.maxPicks)
        assert.equal(Data.herb.SECONDS, session.seconds)
        local board = WildSearch.sessions.herb[session.owner].board
        for i, kind in ipairs(board) do
            if kind == "hazard" and not thornCell then
                thornCell = i
            end
        end
        -- A thorn without gloves: a scratch on a hand or forearm.
        Client.send(player, "herb.pick", { session = session.id, cell = thornCell })
        local reveal = last("herbReveal")
        assert.equal("hazard", reveal.kind)
        assert.is_false(reveal.gloved)
        local scratched = 0
        for _, part in ipairs(player.body.parts) do
            if part.flags.scratch then
                scratched = scratched + 1
                assert.truthy(part.name:find("^Hand_") or part.name:find("^ForeArm_"), part.name)
            end
        end
        assert.equal(1, scratched)
        -- The same cell again is refused; the other thorn hits the gloves.
        Client.send(player, "herb.pick", { session = session.id, cell = thornCell })
        assert.equal("picked", last("herbReveal").refused)
        local gloves = { clothing = true, condition = 10, fullType = "Base.Gloves_LeatherGloves" }
        function gloves:getCondition() return self.condition end
        function gloves:setCondition(v) self.condition = v end
        function gloves:getHolesNumber() return 0 end
        function gloves:getFullType() return self.fullType end
        player.wornAt.Hands = gloves
        local other
        for i, kind in ipairs(board) do
            if kind == "hazard" and i ~= thornCell then
                other = i
            end
        end
        game.realMs = game.realMs + 2000
        Client.send(player, "herb.pick", { session = session.id, cell = other })
        assert.is_true(last("herbReveal").gloved)
        assert.equal(9, gloves.condition)
        player.wornAt.Hands = nil
    end)

    it("finds herbs at three hits and gives First Aid and Foraging XP", function()
        local session = last("herbSession")
        local board = WildSearch.sessions.herb[session.owner].board
        game.float = 0                          -- the find roll succeeds
        local before = #player.inventory.items
        local hits = 0
        for i, kind in ipairs(board) do
            if kind == "target" and hits < 3 then
                game.realMs = game.realMs + 1000
                Client.send(player, "herb.pick", { session = session.id, cell = i })
                hits = hits + 1
            end
        end
        local result = last("herbResult")
        assert.is_true(result.found)
        -- Two thorns cost 0.24: quality 0.59, "rough", so one herb.
        assert.equal(1, result.count)
        assert.equal(before + 1, #player.inventory.items)
        assert.equal(result.item, player.inventory.items[#player.inventory.items].fullType)
        assert.equal(2, xp.Doctor)
        assert.equal(1, xp.PlantScavenging)
        assert.is_nil(WildSearch.sessions.herb[session.owner])
    end)

    it("refuses the same bush while it cools down", function()
        game.realMs = game.realMs + 20000
        Client.send(player, "herb.begin", { x = bush.x, y = bush.y, z = 0 })
        assert.equal("depleted", last("herbDenied").reason)
    end)

    it("gives nothing for a plant search finished from out of range", function()
        game.sandbox.DebugMode = true
        Client.send(player, "debug.wildSearch", { action = "herb", x = bush.x, y = bush.y, z = 0 })
        local session = last("herbSession")
        local board = WildSearch.sessions.herb[session.owner].board
        for i, kind in ipairs(board) do
            if kind == "target" then
                game.realMs = game.realMs + 1000
                Client.send(player, "herb.pick", { session = session.id, cell = i })
                break
            end
        end
        local before, results = #player.inventory.items, #replies
        player.x = 110
        game.float = 0
        game.realMs = game.realMs + Data.herb.SECONDS * 1000
        Client.send(player, "herb.stop", { session = session.id, reason = "time" })
        assert.equal(session.id, last("herbClosed").id)
        for i = results + 1, #replies do
            assert.are_not.equal("herbResult", replies[i].command)
        end
        assert.equal(before, #player.inventory.items)
        assert.is_nil(WildSearch.sessions.herb[session.owner])
        player.x = 100
        game.sandbox.DebugMode = false
    end)

    it("plays a hive search on a debug-filled tree: timing, items, XP, cooldown", function()
        game.sandbox.DebugMode = true
        player.x, player.y = 99, 100
        Client.send(player, "debug.wildSearch", { action = "hive", x = tree.x, y = tree.y, z = 0 })
        local session = last("hiveSession")
        assert.is_true(session.hive)
        assert.equal(3, session.webs)
        -- Too soon after the start.
        Client.send(player, "hive.collect", { session = session.id, target = "hive" })
        assert.equal("tooFast", last("hiveCollected").reason)
        game.realMs = game.realMs + 1500
        Client.send(player, "hive.collect", { session = session.id, target = "hive" })
        assert.is_true(last("hiveCollected").ok)
        assert.equal(1, player.inventory:count(Data.hive.HONEYCOMB))
        assert.equal(2, xp.PlantScavenging)
        game.realMs = game.realMs + 1000
        Client.send(player, "hive.collect", { session = session.id, target = "hive" })
        assert.equal("absent", last("hiveCollected").reason)
        -- A sting ends the session; the webs stay for a retry.
        Client.send(player, "hive.sting", { session = session.id, kind = "spider" })
        assert.is_false(last("hiveStung").gloved)
        game.realMs = game.realMs + 1000
        Client.send(player, "hive.collect", { session = session.id, target = "web" })
        assert.equal("noSession", last("hiveCollected").reason)
        game.realMs = game.realMs + 20000
        Client.send(player, "hive.begin", { x = tree.x, y = tree.y, z = 0 })
        local again = last("hiveSession")
        assert.equal(3, again.webs)
        assert.is_false(again.hive)
        for _ = 1, 3 do
            game.realMs = game.realMs + 1500
            Client.send(player, "hive.collect", { session = again.id, target = "web" })
        end
        assert.is_true(last("hiveCollected").done)
        assert.equal(3, player.inventory:count(Data.hive.SPIDERWEB))
        game.realMs = game.realMs + 20000
        Client.send(player, "hive.begin", { x = tree.x, y = tree.y, z = 0 })
        assert.equal("depleted", last("hiveDenied").reason)
    end)

    it("forgets cooldowns and trees on the debug reset", function()
        Client.send(player, "debug.wildSearch", { action = "reset" })
        local store = WildSearch.store()
        assert.same({}, store.herb)
        assert.same({}, store.tree)
    end)
end)
