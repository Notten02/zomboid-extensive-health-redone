-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, inject-field
-- The Medical Monitor Watch battery: the pure rules (a missing state is a full battery, 168 h of wear to empty, the
-- swap rules), and the wiring in single player: worn watches drain on game time, a dead one switches its alarm off,
-- insert and remove go through the server with the charge carried over, the menu offers the swap and drops "Set
-- Alarm" without power, the HUD clock decision, and the MP sync message reaching the client's copy.

local WatchBattery = require("ExtensiveHealthRedone/Items/WatchBattery")

describe("watch battery rules", function()
    it("counts a watch without battery data as full and installed", function()
        local s = WatchBattery.read(nil)
        assert.is_true(s.installed)
        assert.equal(1, s.charge)
        assert.is_true(WatchBattery.powered(s))
        assert.equal(100, WatchBattery.percent(s))
    end)

    it("normalises stored data", function()
        assert.same({ installed = false, charge = 0 }, WatchBattery.read({ version = 1, installed = false, charge = 0.7 }))
        assert.same({ installed = true, charge = 1 }, WatchBattery.read({ version = 1, installed = true, charge = 3 }))
        assert.same({ installed = true, charge = 1 }, WatchBattery.read({ version = 1 }))
        assert.same({ version = 1, installed = true, charge = 0.25 },
            WatchBattery.toModData({ installed = true, charge = 0.25 }))
    end)

    it("lasts 168 hours of wear", function()
        local s = WatchBattery.read(nil)
        local changed, depleted = WatchBattery.drain(s, 167 * 60)
        assert.is_true(changed)
        assert.is_false(depleted)
        assert.near(1 / 168, s.charge, 1e-9)
        assert.equal(1, WatchBattery.percent(s))
        changed, depleted = WatchBattery.drain(s, 60)
        assert.is_true(depleted)
        assert.equal(0, s.charge)
        assert.is_false(WatchBattery.powered(s))
        assert.equal(0, WatchBattery.percent(s))
        assert.same({ false, false }, { WatchBattery.drain(s, 60) })
    end)

    it("only swaps a battery in and out when that makes sense", function()
        local s = WatchBattery.read(nil)
        assert.equal("installed", WatchBattery.insertRefusal(s, 0.5))
        assert.is_nil(WatchBattery.removeRefusal(s))
        assert.equal(1, WatchBattery.remove(s))
        assert.same({ installed = false, charge = 0 }, s)
        assert.equal("missing", WatchBattery.removeRefusal(s))
        assert.equal("empty", WatchBattery.insertRefusal(s, 0))
        assert.is_nil(WatchBattery.insertRefusal(s, 0.4))
        WatchBattery.insert(s, 0.4)
        assert.same({ installed = true, charge = 0.4 }, s)
    end)
end)

insulate("watch wiring", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- Stand-ins for the vanilla pieces Client/Watch uses.
    package.preload["TimedActions/ISBaseTimedAction"] = function() return true end
    local Action = {}
    Action.__index = Action
    function Action:derive(name)
        local d = setmetatable({ Type = name }, { __index = self })
        d.__index = d
        return d
    end
    function Action.new(self, character)
        return setmetatable({ character = character }, self)
    end
    function Action:perform() self.performed = true end
    function Action:setActionAnim() end
    _G.ISBaseTimedAction = Action
    _G.ISTimedActionQueue = { added = {}, add = function(a) table.insert(ISTimedActionQueue.added, a) end }
    for _, name in ipairs({ "OnFillInventoryObjectContextMenu", "OnPreUIDraw" }) do
        local handlers = {}
        _G.Events[name] = {
            Add = function(fn) table.insert(handlers, fn) end,
            trigger = function(...) for _, fn in ipairs(handlers) do fn(...) end end,
        }
    end
    local clock = { visible = true }
    function clock:isVisible() return self.visible end
    function clock:setVisible(v) self.visible = v end
    function clock:resize() end
    _G.UIManager = { getClock = function() return clock end }
    rawset(_G, "getCore", function() return { getOptionClock24Hour = function() return true end } end)
    -- getText with its arguments visible: "key|arg1|arg2".
    rawset(_G, "getText", function(key, ...)
        local parts = { key }
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        return table.concat(parts, "|")
    end)
    local function newContext()
        local menu = { options = {} }
        function menu:addOption(name, target, onSelect)
            local o = { name = name, target = target, onSelect = onSelect }
            self.options[#self.options + 1] = o
            return o
        end
        function menu:removeOptionByName(name)
            for i, o in ipairs(self.options) do
                if o.name == name then table.remove(self.options, i) return end
            end
        end
        return menu
    end

    local LEFT = "ExtensiveHealth.EHRMedicalWatch_Left"
    local function watchProps(extra)
        local props = { clock = true, alarm = false, rang = false }
        function props.isAlarmSet(self) return self.alarm end
        function props.setAlarmSet(self, v) self.alarm = v end
        function props.stopRinging(self) self.rang = false end
        function props.getHour() return 7 end
        function props.getMinute() return 5 end
        function props.setJobType() end
        function props.setJobDelta() end
        for k, v in pairs(extra or {}) do props[k] = v end
        return props
    end

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local ClientWatch = require("ExtensiveHealthRedone/Client/Watch")
    local Watch = require("ExtensiveHealthRedone/Game/Watch")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local ServerWatch = require("ExtensiveHealthRedone/Server/Watch")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local watch = player.inventory:add(LEFT, watchProps())
    player.worn[1] = watch
    local spare = player.inventory:add(LEFT, watchProps())

    it("drains a worn watch on game time and leaves a carried one alone", function()
        game.advance(61)
        local s = Watch.state(watch)
        -- 50 or 60 minutes of drain: the job steps every 10 game minutes from the baseline.
        assert.truthy(s.charge < 1 - 49 / 60 / 168 and s.charge > 1 - 61 / 60 / 168, tostring(s.charge))
        assert.equal(1, s.installed and 1 or 0)
        assert.is_nil(spare.modData.EHR_WatchBattery)
        assert.is_true(Watch.poweredWorn(player))
    end)

    it("switches the alarm off when the battery runs out", function()
        watch.alarm = true
        ServerWatch.drain("sp:0", player, 168 * 60)
        assert.is_false(Watch.powered(watch))
        assert.is_false(watch.alarm)
        assert.is_false(Watch.poweredWorn(player))
    end)

    it("hides the HUD clock only while a dead medical watch is the only clock", function()
        assert.is_true(ClientWatch.shouldHideClock())
        game.advance(1)
        game.events.OnPreUIDraw.trigger()
        assert.is_false(clock.visible)
        local alarmClock = player.inventory:add("Base.AlarmClock2", { clock = true })
        assert.is_false(ClientWatch.shouldHideClock())
        game.realMs = game.realMs + 2000
        game.advance(1)
        game.events.OnPreUIDraw.trigger()
        assert.is_true(clock.visible)
        player.inventory:Remove(alarmClock)
    end)

    it("offers Remove Battery and drops Set Alarm for a dead watch", function()
        local context = newContext()
        context:addOption("ContextMenu_SetAlarm")
        game.events.OnFillInventoryObjectContextMenu.trigger(0, context, { { items = { watch } } })
        assert.equal(1, #context.options)
        assert.equal("UI_EHR_WatchBattery_Remove|0", context.options[1].name)
    end)

    it("removes the battery through the server with its charge, then inserts the best battery", function()
        watch.modData.EHR_WatchBattery = { version = 1, installed = true, charge = 0.3 }
        watch.alarm = true
        local action = ClientWatch.Action:new(player, watch, nil, "remove")
        assert.equal("EHRWatchBatteryAction", action.Type)
        action:perform()                     -- the client's half sends nothing
        assert.is_true(Watch.state(watch).installed)
        action:complete()                    -- the authority's half (Actions/Authority)
        local s = Watch.state(watch)
        assert.is_false(s.installed)
        assert.is_false(watch.alarm)
        assert.equal(1, player.inventory:count("Base.Battery"))
        local out = player.inventory:getFirstEvalRecurse(function(i) return i.fullType == "Base.Battery" end)
        assert.near(0.3, out:getCurrentUsesFloat(), 1e-9)

        local better = player.inventory:add("Base.Battery", { usesFloat = 0.9 })
        local context = newContext()
        context:addOption("ContextMenu_SetAlarm")
        ClientWatch.menu(player, context, watch)
        assert.equal("UI_EHR_WatchBattery_Insert|90", context.options[1].name)
        context.options[1].onSelect()
        local queued = ISTimedActionQueue.added[#ISTimedActionQueue.added]
        assert.equal(better, queued.battery)
        queued:complete()
        s = Watch.state(watch)
        assert.is_true(s.installed)
        assert.near(0.9, s.charge, 1e-9)
        assert.is_nil(player.inventory:getItemWithIDRecursiv(better.id))
    end)

    it("refuses an empty battery and a second battery", function()
        local flat = player.inventory:add("Base.Battery", { usesFloat = 0 })
        ClientWatch.Action:new(player, watch, flat, "insert"):complete()
        assert.near(0.9, Watch.state(watch).charge, 1e-9)
        assert.truthy(player.inventory:getItemWithIDRecursiv(flat.id))
    end)

    it("shows time, alarm and battery in the tooltip lines", function()
        watch.alarm = true
        local lines = assert(ClientWatch.tooltipLines(watch))
        assert.equal("UI_EHR_WatchBattery_Time", lines[1].label.key)
        assert.equal("07:05", lines[2].value.raw)
        assert.equal("90%", lines[3].value.raw)
        assert.equal("green", lines[3].color)
        assert.near(0.9, lines[3].progress, 1e-9)
        assert.is_nil(ClientWatch.tooltipLines(player.inventory:add("Base.Apple")))
    end)

    it("sends the state in MP and the client writes it into its copy", function()
        local sent
        rawset(_G, "isServer", function() return true end)
        rawset(_G, "sendServerCommand", function(_, _, command, args) sent = { command = command, args = args } end)
        ServerWatch.sync("sp:0", player, { watch })
        rawset(_G, "isServer", function() return false end)
        assert.equal("watchBattery", sent.command)
        assert.equal(watch.id, sent.args.watches[1].id)
        sent.args.watches[1].charge = 0.5
        local Transport = require("ExtensiveHealthRedone/Game/Transport")
        Transport.toClient(player, "watchBattery", sent.args)
        assert.near(0.5, Watch.state(watch).charge, 1e-9)
    end)

    it("gives the debug test items only in DebugMode, with a nearly empty watch and fresh bags", function()
        local before = player.inventory:count("ExtensiveHealth.EHRMedicalWatch_Right")
        local batteries = player.inventory:count("Base.Battery")
        Client.send(player, "debug.testItems", {})
        assert.equal(before, player.inventory:count("ExtensiveHealth.EHRMedicalWatch_Right"))
        game.sandbox.DebugMode = true
        Client.send(player, "debug.testItems", {})
        game.sandbox.DebugMode = false
        assert.equal(before + 1, player.inventory:count("ExtensiveHealth.EHRMedicalWatch_Right"))
        assert.equal(batteries + 1, player.inventory:count("Base.Battery"))
        local weak = player.inventory:getFirstEvalRecurse(function(item)
            return item:getFullType() == "ExtensiveHealth.EHRMedicalWatch_Right"
        end)
        assert.is_true(Watch.powered(weak))
        assert.is_true(Watch.state(weak).charge < 0.01)
        local bag = player.inventory:getFirstEvalRecurse(function(item)
            return item:getFullType() == "ExtensiveHealth.BloodBagONeg"
        end)
        assert.truthy(bag:getModData().EHR_BloodSpoilage)
    end)
end)
