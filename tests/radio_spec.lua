-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake radio API is deliberately partial.
---@diagnostic disable: missing-fields
-- The Last Prescription on 47.0 MHz: the text keys, the schedule and story rules, the listener rule, the judging
-- window and the rewards, then the server wiring against the fake game with a fake radio.
local Data = require("ExtensiveHealthRedone/Data/Radio")
local Station = require("ExtensiveHealthRedone/Radio/Station")
local Learn = require("ExtensiveHealthRedone/Knowledge/Learn")
local LuaSource = require("LuaSource")
local Sim = require("support/sim")

-- Station.build for a slot that exists.
local function build(slot, day, world, suffix)
    return assert(Station.build(slot, day, world, suffix))
end

local TRANSLATE = "Contents/mods/ExtensiveHealthRedone/42/media/lua/shared/Translate/"
local LANGS = { "CH", "CN", "EN", "ES", "FR", "IT", "JP", "PTBR", "RU", "UA" }

local function uiTexts(lang)
    local texts = {}
    for line in LuaSource.read(TRANSLATE .. lang .. "/UI.json"):gmatch("[^\n]+") do
        local key, text = line:match('^%s*"([%w_]+)"%s*:%s*"(.*)",?%s*$')
        if key then
            texts[key] = text
        end
    end
    return texts
end

-- Every key a broadcast can use, built the way Station.build builds them.
local function allKeys()
    local keys = { "UI_EHR_Radio_Intro_Morning", "UI_EHR_Radio_Intro_Afternoon", "UI_EHR_Radio_Intro_Evening" }
    local function add(b)
        for _, line in ipairs(b.lines) do
            keys[#keys + 1] = line.key
            for _, arg in ipairs(line.args or {}) do
                keys[#keys + 1] = arg
            end
        end
    end
    for day = 1, #Data.TIP_LINES do
        add(build("morning", day, { story = 0 }))
    end
    for n = 1, #Data.STORY_LINES do
        add(build("afternoon", 1, { story = n - 1 }))
    end
    for day = 1, #Data.FILES do
        add(build("evening", day, { story = 0 }))
    end
    return keys
end

local function radio(props)
    local d = { kind = "carried", on = true, channel = Data.FREQUENCY, battery = false, power = 1, volume = 0.5,
        headphones = -1 }
    for k, v in pairs(props or {}) do
        d[k] = v
    end
    return d
end

local LISTENER = { alive = true, awake = true, x = 100.5, y = 100.5, z = 0, outside = false }

describe("radio text", function()
    local keys = allKeys()

    it("has every broadcast key in all 10 languages", function()
        for _, lang in ipairs(LANGS) do
            local texts = uiTexts(lang)
            for _, key in ipairs(keys) do
                assert.truthy(texts[key], lang .. " is missing " .. key)
            end
        end
    end)

    it("has exactly the lines Data/Radio counts", function()
        local texts = uiTexts("EN")
        for n, count in ipairs(Data.TIP_LINES) do
            assert.truthy(texts["UI_EHR_Radio_Tip_" .. n .. "_" .. count], "tip " .. n)
            assert.is_nil(texts["UI_EHR_Radio_Tip_" .. n .. "_" .. (count + 1)], "tip " .. n)
        end
        assert.is_nil(texts["UI_EHR_Radio_Tip_" .. (#Data.TIP_LINES + 1) .. "_1"])
        for n, count in ipairs(Data.STORY_LINES) do
            assert.truthy(texts["UI_EHR_Radio_Story_" .. n .. "_" .. count], "story " .. n)
            assert.is_nil(texts["UI_EHR_Radio_Story_" .. n .. "_" .. (count + 1)], "story " .. n)
        end
        assert.is_nil(texts["UI_EHR_Radio_Story_" .. (#Data.STORY_LINES + 1) .. "_1"])
    end)

    it("calls corpse illness by its name, keeps tip 5's swear word and loses v0.9's typos", function()
        local texts = uiTexts("EN")
        local evening = build("evening", 6, { story = 0 })
        assert.equal("corpse_sickness", evening.reward.id)
        assert.equal("UI_EHR_Disease_corpse_sickness", evening.lines[2].args[1])
        assert.equal("Corpse Exposure Illness", texts.UI_EHR_Disease_corpse_sickness)
        assert.truthy(texts.UI_EHR_Radio_Tip_5_2:find("A fucking heat!", 1, true))
        for key, text in pairs(texts) do
            if key:find("^UI_EHR_Radio_") then
                for _, typo in ipairs({ "Putrefaction", "Desifect", "shinny", "on touch", "dangerous that",
                    "would gave", "than it's probably", "snakes neighbors", "burn to crisps", "advices" }) do
                    assert.is_nil(text:find(typo, 1, true), key .. " still has " .. typo)
                end
            end
        end
    end)
end)

describe("radio schedule", function()
    it("rotates tips and files by day as v0.9 did", function()
        assert.equal(2, Station.tipFor(1))
        assert.equal(1, Station.tipFor(21))
        assert.equal(1, Station.fileFor(1))
        assert.equal(20, Station.fileFor(20))
        assert.equal(1, Station.fileFor(21))
        assert.equal(1, Station.day(0))
    end)

    it("airs each slot once, only when enabled and only in its hour", function()
        local world = Station.clean({})
        assert.equal("morning", Station.due(world, 3, 9, true))
        assert.is_nil(Station.due(world, 3, 9, false))
        assert.is_nil(Station.due(world, 3, 10, true))
        Station.aired(world, build("morning", 3, world))
        assert.is_nil(Station.due(world, 3, 9, true))
        assert.equal("afternoon", Station.due(world, 3, 15, true))
        assert.equal("morning", Station.due(world, 4, 9, true))
    end)

    it("advances the story only when an episode airs, then replays the loop recording", function()
        local world = Station.clean({})
        local b = build("afternoon", 9, world)
        assert.equal(1, b.story)
        assert.equal("UI_EHR_Radio_Story_1_1", b.lines[2].key)
        Station.aired(world, b)
        -- A week without a 15:00 skips nothing.
        b = build("afternoon", 16, world)
        assert.equal(2, b.story)
        Station.aired(world, b)
        for day = 17, 60 do
            Station.aired(world, build("afternoon", day, world))
        end
        assert.equal(#Data.STORY_LINES, world.story)
        assert.equal(22, build("afternoon", 61, world).story)
        assert.is_nil(build("afternoon", 61, world).heard)
    end)

    it("builds the rewards with v0.9's slot keys", function()
        local morning = build("morning", 3, { story = 0 }, 7)
        assert.equal("3:9:XP:4", morning.heard)
        assert.same({ kind = "xp" }, morning.reward)
        assert.equal(1 + Data.TIP_LINES[4], #morning.lines)
        assert.equal("EHR-LP-3-9-7", morning.id)
        assert.same(Data.COLORS.static, morning.lines[1].color)
        local evening = build("evening", 15, { story = 0 })
        assert.equal("15:21:KNOW:tetanus", evening.heard)
        assert.same({ kind = "know", id = "tetanus", name = "UI_EHR_Disease_tetanus" }, evening.reward)
        assert.equal(6, #evening.lines)
        assert.same({ "UI_EHR_Radio_File_tetanus_Treatment" }, evening.lines[5].args)
        assert.is_nil(Station.build("night", 1, { story = 0 }))
    end)

    it("repairs a stored world state", function()
        assert.same({ story = 0 }, Station.clean(nil))
        assert.same({ lastSlot = "4:15", story = 3 }, Station.clean({ lastSlot = "4:15", story = 3.7 }))
        assert.same({ story = 22 }, Station.clean({ lastSlot = "anything", story = 999 }))
        assert.same({ story = 0 }, Station.clean({ lastSlot = 5, story = "x" }))
    end)
end)

describe("radio listeners", function()
    it("counts a carried or vehicle radio that is on, tuned to 47.0, powered and audible", function()
        assert.is_true(Station.listening(LISTENER, { radio() }))
        assert.is_true(Station.listening(LISTENER, { radio({ kind = "vehicle", battery = true, power = 0.2 }) }))
        assert.is_false(Station.listening(LISTENER, { radio({ on = false }) }))
        assert.is_false(Station.listening(LISTENER, { radio({ channel = 98000 }) }))
        assert.is_false(Station.listening(LISTENER, { radio({ battery = true, power = 0 }) }))
        assert.is_false(Station.listening(LISTENER, { radio({ volume = 0 }) }))
        assert.is_false(Station.listening(LISTENER, {}))
        assert.is_true(Station.listening(LISTENER, { radio({ on = false }), radio() }))
    end)

    it("needs a listener who is alive and awake", function()
        assert.is_false(Station.listening({ alive = true, awake = false }, { radio() }))
        assert.is_false(Station.listening({ alive = false, awake = true }, { radio() }))
    end)

    it("counts a world radio within 5 tiles, on the floor and the side of the listener, without headphones", function()
        local function world(props)
            local d = radio({ kind = "world", x = 103, y = 96, z = 0, outside = false })
            for k, v in pairs(props) do
                d[k] = v
            end
            return d
        end
        assert.is_true(Station.listening(LISTENER, { world({}) }))
        assert.is_false(Station.listening(LISTENER, { world({ x = 106 }) }))
        assert.is_false(Station.listening(LISTENER, { world({ z = 1 }) }))
        assert.is_false(Station.listening(LISTENER, { world({ outside = true }) }))
        assert.is_false(Station.listening(LISTENER, { world({ headphones = 0 }) }))
    end)
end)

describe("radio judging", function()
    local function watch()
        return Station.watch(build("morning", 2, { story = 0 }), 1000)
    end

    it("judges when the final line airs or the broadcast ends", function()
        local w = watch()
        assert.is_false(Station.check(w, 1001, { ours = true, line = 1 }))
        assert.is_false(Station.check(w, 1008, { ours = true, line = 3 }))
        assert.is_true(Station.check(w, 1010, { ours = true, line = w.lines - 1 }))
        assert.is_true(w.done)
        assert.is_false(Station.check(w, 1011, { ours = true, line = w.lines }))

        w = watch()
        assert.is_true(Station.check(w, 1002, { ours = false }))
        assert.is_true(w.done)
    end)

    it("falls back to anyone listening 5 to 15 minutes in when the server shows no progress", function()
        local w = watch()
        assert.is_false(Station.check(w, 1004, { ours = true, line = 0 }))
        assert.is_true(Station.check(w, 1005, { ours = true, line = 0 }))
        assert.is_false(w.done)
        assert.is_true(Station.check(w, 1010, { ours = true }))
        assert.is_true(Station.check(w, 1015, { ours = true }))
        assert.is_true(w.done)
    end)

    it("does not fall back once progress was seen, but gives up after the watch limit", function()
        local w = watch()
        Station.check(w, 1001, { ours = true, line = 1 })
        assert.is_false(Station.check(w, 1010, { ours = true, line = 1 }))
        assert.is_true(Station.check(w, 1000 + Data.WATCH_LIMIT, { ours = true, line = 1 }))
    end)
end)

describe("radio rewards", function()
    it("gives the 09:00 XP once per broadcast", function()
        local p = Sim.context({})
        assert.is_true(Learn.radio(p, "3:9:XP:4", { kind = "xp" }, 3))
        assert.is_false(Learn.radio(p, "3:9:XP:4", { kind = "xp" }, 3))
        assert.same({ { "radioTip" } }, p.xps)
        assert.is_true(p.state.knowledge.radioHeard["3:9:XP:4"])
    end)

    it("teaches the 21:00 file once, without XP, and never Knox", function()
        local p = Sim.context({})
        assert.is_true(Learn.radio(p, "2:21:KNOW:sepsis", { kind = "know", id = "sepsis", name = "UI_EHR_Disease_sepsis" }, 2))
        assert.is_true(p.state.knowledge.diseases.sepsis)
        assert.same({}, p.xps)
        assert.same({ "knowledgeLearned", { name = "UI_EHR_Disease_sepsis" } }, p.sent[1])
        assert.is_true(Learn.radio(p, "20:21:KNOW:knox_infection",
            { kind = "know", id = "knox_infection", name = "UI_EHR_Disease_knox_infection" }, 20))
        assert.is_nil(p.state.knowledge.diseases.knox_infection)
        assert.is_true(p.state.knowledge.radioHeard["20:21:KNOW:knox_infection"])
        assert.equal(1, #p.sent)
    end)

    it("honours imported v0.9 keys and prunes keys older than 2 days", function()
        local p = Sim.context({})
        local heard = p.state.knowledge.radioHeard
        heard["10:9:XP:4"] = true
        heard["7:21:KNOW:tetanus"] = true
        heard["8:9:XP:4"] = true
        heard["oddKey"] = true
        assert.is_false(Learn.radio(p, "10:9:XP:4", { kind = "xp" }, 10))
        assert.is_true(Learn.radio(p, "10:21:KNOW:sepsis", { kind = "know", id = "sepsis", name = "n" }, 10))
        assert.is_nil(heard["7:21:KNOW:tetanus"])
        assert.is_true(heard["8:9:XP:4"])
        assert.is_true(heard["oddKey"])
    end)
end)

insulate("single-player wiring: radio", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.sandbox.DebugMode = true

    -- A fake radio: the script manager, our channel, broadcasts that tests advance by hand, and global ModData.
    local function event()
        local e = { handlers = {} }
        function e.Add(fn) e.handlers[#e.handlers + 1] = fn end
        function e.trigger(...)
            for _, h in ipairs(e.handlers) do h(...) end
        end
        return e
    end
    Events.OnLoadRadioScripts = event()
    Events.OnReceiveGlobalModData = event()
    _G.ChannelCategory = { Emergency = "Emergency" }
    _G.DynamicRadioChannel = {
        new = function(name, freq, category, uuid)
            local ch = { name = name, freq = freq, category = category, uuid = uuid }
            function ch:setAirCounterMultiplier(m) self.multiplier = m end
            function ch:setAiringBroadcast(bc) self.airing = bc end
            function ch:getAiringBroadcast() return self.airing end
            return ch
        end,
    }
    _G.RadioBroadCast = {
        new = function(id)
            local bc = { id = id, lines = {}, current = 0 }
            function bc:AddRadioLine(line) self.lines[#self.lines + 1] = line end
            function bc:getID() return self.id end
            function bc:getCurrentLineNumber() return self.current end
            return bc
        end,
    }
    _G.RadioLine = { new = function(text, r, g, b) return { text = text, r = r, g = g, b = b } end }
    local globalModData = {}
    _G.ModData = {
        getOrCreate = function(key)
            globalModData[key] = globalModData[key] or {}
            return globalModData[key]
        end,
    }
    local baseGameTime = _G.getGameTime
    ---@diagnostic disable-next-line: duplicate-set-field
    _G.getGameTime = function()
        local gt = baseGameTime()
        gt.getHour = function() return math.floor(game.minutes / 60) % 24 end
        gt.getNightsSurvived = function() return math.floor(game.minutes / 1440) end
        return gt
    end
    local baseInstanceof = _G.instanceof
    ---@diagnostic disable-next-line: duplicate-set-field
    _G.instanceof = function(obj, class)
        if class == "Radio" or class == "IsoWaveSignal" then
            return obj.deviceData ~= nil and obj.radioClass == class
        end
        return baseInstanceof(obj, class)
    end

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({ capabilities = { CanMedicalCheat = true } })
    player.square.isOutside = function() return false end
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local manager = { channels = {} }
    function manager:AddChannel(ch) self.channels[#self.channels + 1] = ch end
    Events.OnLoadRadioScripts.trigger(manager, true)
    local channel = manager.channels[1]

    local dumps = {}
    Client.on("debugDump", function(args) dumps[#dumps + 1] = args.text end)

    -- A HAM radio in the player's inventory.
    local device = { on = true, channel = Data.FREQUENCY, battery = false, power = 1, volume = 0.6, headphones = -1 }
    local item = player.inventory:add("Base.HamRadio1", { radioClass = "Radio", deviceData = {} })
    local data = item.deviceData
    function data.getIsTurnedOn() return device.on end
    function data.getChannel() return device.channel end
    function data.getIsBatteryPowered() return device.battery end
    function data.getPower() return device.power end
    function data.getDeviceVolume() return device.volume end
    function data.getHeadphoneType() return device.headphones end
    function item.getDeviceData() return item.deviceData end

    local function knowledge()
        return player.modData.ExtensiveHealthRedone.knowledge
    end

    -- Sets the clock to day `day`, hour:00 and runs two game minutes there (the first update after a reset only sets
    -- the scheduler's baseline).
    local function at(day, hour)
        game.minutes = (day - 1) * 1440 + hour * 60
        Runtime.scheduler:reset()
        game.advance(2)
    end

    local function finish()
        channel.airing.current = #channel.airing.lines - 1
        game.advance(2)
    end

    it("registers 47.0 MHz once, as an emergency channel", function()
        assert.equal(1, #manager.channels)
        assert.same({ "The Last Prescription", 47000, "Emergency", "EHR-LAST-PRESCRIPTION-470" },
            { channel.name, channel.freq, channel.category, channel.uuid })
        assert.equal(1.35, channel.multiplier)
    end)

    it("airs the 09:00 tip once and gives a listener 4 XP when its final line airs", function()
        at(6, 9)
        local bc = channel.airing
        assert.truthy(bc)
        assert.equal("UI_EHR_Radio_Intro_Morning", bc.lines[1].text)
        assert.equal("UI_EHR_Radio_Tip_" .. Station.tipFor(6) .. "_1", bc.lines[2].text)
        game.advance(3)
        assert.is_nil(game.xp[player:getUsername()])
        finish()
        assert.equal(4, game.xp[player:getUsername()])
        assert.is_true(knowledge().radioHeard["6:9:XP:4"])
        game.advance(5)
        assert.equal(bc, channel.airing)
        assert.equal("6:9", globalModData[Data.WORLD_KEY].lastSlot)
    end)

    it("advances the story only when 15:00 airs, and survives a reload of the world state", function()
        at(6, 15)
        assert.equal("UI_EHR_Radio_Story_1_1", channel.airing.lines[2].text)
        at(9, 15)
        assert.equal("UI_EHR_Radio_Story_2_1", channel.airing.lines[2].text)
        assert.equal(2, globalModData[Data.WORLD_KEY].story)
        -- A tampered table is put back from the authority's copy.
        globalModData[Data.WORLD_KEY] = { story = 20, lastSlot = "x" }
        Events.OnReceiveGlobalModData.trigger(Data.WORLD_KEY, {})
        assert.equal(2, globalModData[Data.WORLD_KEY].story)
    end)

    it("teaches the 21:00 file only to a listener with the radio on", function()
        device.on = false
        at(13, 21)      -- file 13: wound infection
        finish()
        assert.is_nil(knowledge().diseases.wound_infection)
        device.on = true
        at(14, 21)      -- file 14: sepsis
        assert.equal("UI_EHR_Radio_File_Title", channel.airing.lines[2].text)
        finish()
        assert.is_true(knowledge().diseases.sepsis)
        assert.is_true(knowledge().radioHeard["14:21:KNOW:sepsis"])
        -- Keys from more than 2 days before are pruned.
        assert.is_nil(knowledge().radioHeard["6:9:XP:4"])
    end)

    it("falls back to the 5-15 minute window when the broadcast shows no progress", function()
        at(15, 9)
        local before = game.xp[player:getUsername()]
        game.advance(3)
        assert.equal(before, game.xp[player:getUsername()])
        game.advance(3)
        assert.equal(before + 4, game.xp[player:getUsername()])
    end)

    it("airs a slot on demand with the debug command, without using up the real slot", function()
        Client.send(player, "debug.radio", { action = "afternoon" })
        assert.equal("UI_EHR_Radio_Story_3_1", channel.airing.lines[2].text)
        assert.equal("15:9", globalModData[Data.WORLD_KEY].lastSlot)
        assert.truthy(dumps[#dumps]:find("next 4", 1, true))
        assert.truthy(dumps[#dumps]:find("you are listening: true", 1, true))
        Client.send(player, "debug.radio", { action = "resetStory" })
        assert.equal(0, globalModData[Data.WORLD_KEY].story)
    end)

    it("stays silent when the station is off", function()
        game.sandbox.TheLastPrescriptionEnabled = false
        local aired = channel.airing
        at(16, 9)
        assert.equal(aired, channel.airing)
        local fresh = { channels = {} }
        function fresh:AddChannel(ch) self.channels[#self.channels + 1] = ch end
        Events.OnLoadRadioScripts.trigger(fresh, false)
        assert.equal(0, #fresh.channels)
        game.sandbox.TheLastPrescriptionEnabled = nil
    end)
end)
