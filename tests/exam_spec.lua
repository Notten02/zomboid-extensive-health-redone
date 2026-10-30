-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, inject-field, need-check-nil, duplicate-set-field
-- Examining another player in single-player mode with two split-screen players, against
-- tests/support/fake_game.lua: "Examine Health" after vanilla's Medical Check, consent, the server-built model with
-- the doctor's knowledge (nothing else is sent), the refresh and its throttle, the close rules, exam.keep, the
-- exam window drawing the server's model through MonitorView, and the Administer list through Client/Give.
-- Drawing needs the game; this checks the wiring and what travels.

insulate("examining another player", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- Stand-in UI classes: derive and new like ISUIElement's; addChild instantiates the child like the real one.
    local function class()
        local c = {}
        c.__index = c
        for _, name in ipairs({ "setTitle", "setResizable", "initialise", "addToUIManager", "removeFromUIManager",
            "bringToTop", "prerender", "render", "createChildren", "clearMaxDrawHeight", "setColorScheme", "setAlphas",
            "enableNodes", "setStencilRect", "clearStencilRect", "onGainJoypadFocus", "onLoseJoypadFocus" }) do
            c[name] = function() end
        end
        function c:titleBarHeight() return 16 end
        function c:setVisible(v) self.visible = v end
        function c:getIsVisible() return self.visible == true end
        function c:setX(v) self.x = v end
        function c:setY(v) self.y = v end
        function c:getX() return self.x end
        function c:getY() return self.y end
        function c:getWidth() return self.width end
        function c:getHeight() return self.height end
        function c:getAbsoluteX() return self.x end
        function c:getAbsoluteY() return self.y end
        function c:setValue(part, value) self.values = self.values or {}; self.values[part.name] = value end
        function c:derive(name)
            local d = setmetatable({ Type = name }, { __index = self })
            d.__index = d
            return d
        end
        function c.new(self, x, y, w, h)
            return setmetatable({ x = x, y = y, width = w, height = h, children = {} }, self)
        end
        function c:instantiate()
            if not self.instantiated then
                self.instantiated = true
                self:createChildren()
            end
        end
        function c:addChild(child)
            child:instantiate()
            child.parent = self
            self.children[#self.children + 1] = child
        end
        return c
    end
    for _, name in ipairs({ "ISUI/ISPanelJoypad", "ISUI/ISButton", "ISUI/BodyParts/ISBodyPartPanel",
        "ISUI/ISCollapsableWindowJoypad", "ISUI/ISScrollingListBox", "ISUI/ISPanel", "ISUI/ISLayoutManager",
        "ISUI/ISModalDialog" }) do
        package.preload[name] = function() return true end
    end
    for _, name in ipairs({ "ISPanelJoypad", "ISButton", "ISBodyPartPanel", "ISCollapsableWindowJoypad", "ISPanel",
        "ISScrollingListBox", "ISModalDialog" }) do
        _G[name] = class()
    end
    function ISModalDialog:isReallyVisible() return true end
    function ISModalDialog:destroy() end
    _G.ISLayoutManager = { RegisterWindow = function() end }
    local fonts = {}
    for _, name in ipairs({ "Small", "Medium", "Large" }) do
        fonts[name] = name
    end
    rawset(_G, "UIFont", fonts)
    _G.getTextManager = function()
        return { getFontHeight = function() return 16 end, MeasureStringX = function(_, _, s) return #s * 7 end }
    end
    _G.getCore = function()
        return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end }
    end
    _G.Keyboard = { KEY_J = 36, KEY_G = 34, KEY_H = 35 }
    _G.Color = { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
    _G.Joypad = { AButton = "A", BButton = "B", XButton = "X", YButton = "Y", LBumper = "LB", RBumper = "RB" }
    _G.JoypadState = { players = {} }
    _G.setJoypadFocus = function() end
    for _, name in ipairs({ "getPlayerScreenLeft", "getPlayerScreenTop" }) do
        _G[name] = function() return 0 end
    end
    _G.getPlayerScreenWidth = function() return 1920 end
    _G.getPlayerScreenHeight = function() return 1080 end
    _G.getPlayerInfoPanel = function() error("the exam must not open the doctor's own character window") end
    _G.HaloTextHelper = { shown = {}, addBadText = function(_, t) table.insert(HaloTextHelper.shown, t) end,
        addText = function(_, t) table.insert(HaloTextHelper.shown, t) end }
    rawset(_G.BodyPartType, "FromString", function(name) return { name = name } end)
    _G.UIManager = { getSpeedControls = function() return { getCurrentGameSpeed = function() return 1 end } end }
    _G.getDebug = function() return false end
    -- Vanilla's Health panel: the exam treats through one made for the patient, recording what it is asked.
    package.preload["XpSystem/ISUI/ISHealthPanel"] = function() return true end
    local healthPanels = {}
    _G.ISHealthPanel = {}
    function ISHealthPanel:new(character)
        local o = { character = character, menus = {}, drops = {} }
        function o:initialise() end
        function o:instantiate() end
        function o:getAbsoluteX() return 0 end
        function o:getAbsoluteY() return 0 end
        function o:setOtherPlayer(p) self.otherPlayer = p end
        function o:doBodyPartContextMenu(bp, x, y) self.menus[#self.menus + 1] = { bp, x, y } end
        function o:dropItemsOnBodyPart(bp, items) self.drops[#self.drops + 1] = { bp, items } end
        healthPanels[#healthPanels + 1] = o
        return o
    end

    -- A context menu like ISContextMenu: addOption, insertOptionAfter (addOption when the anchor is missing).
    local function newContext()
        local menu = { options = {} }
        function menu:addOption(name, target, onSelect, param1)
            local option = { name = name, target = target, onSelect = onSelect, param1 = param1 }
            self.options[#self.options + 1] = option
            return option
        end
        function menu:insertOptionAfter(prev, name, target, onSelect, param1)
            for i, o in ipairs(self.options) do
                if o.name == prev then
                    local option = { name = name, target = target, onSelect = onSelect, param1 = param1 }
                    table.insert(self.options, i + 1, option)
                    return option
                end
            end
            return self:addOption(name, target, onSelect, param1)
        end
        return menu
    end
    local lastMenu
    _G.ISContextMenu = { get = function() lastMenu = newContext() return lastMenu end }
    local testMode = false
    _G.ISWorldObjectContextMenu = {
        addToolTip = function()
            local t = { description = "" }
            function t:setName(name) self.name = name end
            return t
        end,
        setTest = function() testMode = true return true end,
    }

    -- The fake game's players: IsoPlayers here, with the body part readings the diagram needs, a name and squares
    -- that list who stands on them.
    local realInstanceof = _G.instanceof
    rawset(_G, "instanceof", function(obj, cls)
        if cls == "IsoPlayer" then return type(obj) == "table" and obj.body ~= nil end
        if cls == "IsoAnimal" then return false end
        return realInstanceof(obj, cls)
    end)
    local function prepare(player, forename)
        for _, part in ipairs(player.body.parts) do
            part.burnTime, part.stiffness, part.splint = 0, 0, 0
            function part:getBurnTime() return self.burnTime end
            function part:isNeedBurnWash() return false end
            function part:getBandageLife() return 1 end
            function part:getStiffness() return self.stiffness end
            function part:getSplintFactor() return self.splint end
            function part:getPlantainFactor() return 0 end
            function part:getComfreyFactor() return 0 end
            function part:getGarlicFactor() return 0 end
        end
        function player:getSquare() return self.square end
        function player:getDescriptor()
            return { getForename = function() return forename end, getSurname = function() return "Doe" end }
        end
        function player:getIndex() return self:getPlayerNum() end
        function player.body:getBodyPart(t) return self:part(t.name) end
        player.square.moving = { player }
        function player.square:getMovingObjects()
            local list = self.moving
            return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
        end
        return player
    end

    -- Client/Give's contract: options(doctor, patient) and start(doctor, patient, item).
    local given = {}
    package.preload["ExtensiveHealthRedone/Client/Give"] = function()
        return {
            options = function(_, _)
                return {
                    { item = "pills", label = "Painkillers", kind = "medicate", available = true },
                    { item = "bag", label = "UI_EHR_Consent_Waiting", kind = "transfuse", available = false,
                        reason = "UI_EHR_MedAction_RequiresIVKit" },
                }
            end,
            start = function(doctor, patient, item) given[#given + 1] = { doctor, patient, item } end,
        }
    end

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local Transport = require("ExtensiveHealthRedone/Game/Transport")
    local ClientExam = require("ExtensiveHealthRedone/Client/Exam")
    local doctor = prepare(game.addPlayer({}), "Doc")
    local patient = prepare(game.addPlayer({ x = 101, y = 100 }), "Pat")
    game.events.OnCreatePlayer.trigger(0, doctor)
    game.events.OnCreatePlayer.trigger(1, patient)
    require("ExtensiveHealthRedone/Server/Main")
    local Exam = require("ExtensiveHealthRedone/Server/Exam")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    game.events.OnGameStart.trigger()
    game.advance(2)

    -- Every server message, recorded on its way.
    local sent = {}
    local toClient = Transport.toClient
    rawset(Transport, "toClient", function(player, command, args)
        sent[#sent + 1] = { command = command, args = args }
        return toClient(player, command, args)
    end)
    local function messages(command)
        local list = {}
        for _, m in ipairs(sent) do
            if m.command == command then list[#list + 1] = m.args end
        end
        return list
    end
    local function last(command)
        local list = messages(command)
        return list[#list]
    end

    local function state(player)
        return player.modData.ExtensiveHealthRedone
    end

    -- Plain data only: no functions or userdata anywhere (it crosses the network as is).
    local function assertPlain(value, path)
        local kind = type(value)
        assert.truthy(kind == "table" or kind == "string" or kind == "number" or kind == "boolean",
            path .. " is a " .. kind)
        if kind == "table" then
            for k, v in pairs(value) do
                assertPlain(v, path .. "." .. tostring(k))
            end
        end
    end
    local function mentions(value, word)
        if type(value) == "string" then
            return value:lower():find(word, 1, true) ~= nil
        elseif type(value) == "table" then
            for k, v in pairs(value) do
                if mentions(k, word) or mentions(v, word) then return true end
            end
        end
        return false
    end

    local function contextFor(objects, vanilla, isTest)
        local menu = newContext()
        for _, name in ipairs(vanilla or {}) do
            menu:addOption(name)
        end
        for _, handler in ipairs(game.events.OnFillWorldObjectContextMenu.handlers) do
            handler(0, menu, objects, isTest)
        end
        return menu
    end

    local function examine()
        ClientExam.onExamine(doctor, patient)
        Client.send(patient, "consent.answer", { from = "sp:0", purpose = "exam", accepted = true })
        return Exam.sessions["sp:1"] and Exam.sessions["sp:1"]["sp:0"]
    end

    it("reads the diagram's body part facts in BodyStatus's shape", function()
        local BodyFacts = require("ExtensiveHealthRedone/Game/BodyFacts")
        local arm = patient.body:part("ForeArm_L")
        arm.flags.bleeding, arm.flags.cut, arm.health = true, true, 70
        local parts = BodyFacts.read(patient)
        assert.is_true(parts.ForeArm_L.bleeding)
        assert.is_true(parts.ForeArm_L.cut)
        assert.equal(70, parts.ForeArm_L.health)
        assert.is_false(parts.Head.bleeding)
        arm.flags, arm.health = {}, 100
    end)

    it("puts Examine Health right after vanilla's Medical Check, greyed beyond range", function()
        local menu = contextFor({ patient }, { "ContextMenu_Trade", "ContextMenu_Medical_Check", "ContextMenu_Walk" })
        assert.equal("UI_EHR_Context_ExamineHealthOf", menu.options[3].name)
        assert.equal(patient, menu.options[3].param1)
        assert.is_nil(menu.options[3].notAvailable)
        assert.equal("ContextMenu_Walk", menu.options[4].name)
        -- A player standing on a clicked square counts too; the doctor and other objects don't.
        local floor = { getSquare = function() return patient.square end }
        assert.equal(1, #contextFor({ floor, doctor }).options)
        patient.x = 105
        local far = contextFor({ patient })
        assert.is_true(far.options[1].notAvailable)
        assert.equal("UI_EHR_Context_TooFar", far.options[1].toolTip.name)
        patient.x = 101
        -- The controller's A menu runs in test mode.
        assert.equal(0, #contextFor({ patient }, nil, true).options)
        assert.is_true(testMode)
        assert.equal(0, #contextFor({ doctor }).options)
    end)

    it("starts a session on the patient's yes and sends the doctor the patient's Monitor", function()
        local before = #sent
        assert.truthy(examine())
        assert.is_true(Exam.isExamining("sp:0", "sp:1"))
        assert.equal("UI_EHR_Exam_BeingExamined", HaloTextHelper.shown[#HaloTextHelper.shown])
        local msg = last("examModel")
        assert.truthy(#sent > before)
        local keys = {}
        for k in pairs(msg) do keys[#keys + 1] = k end
        table.sort(keys)
        assert.same({ "model", "name", "overall", "owner", "patient", "target" }, keys)
        assert.equal("sp:1", msg.patient)
        assert.equal("sp:0", msg.owner)
        assertPlain(msg, "examModel")
        local window = ClientExam.window("sp:0", "sp:1")
        assert.truthy(window)
        assert.equal("Pat Doe", ClientExam.displayName(patient))
        -- The window's view draws the server's model, painted on the patient's body diagram.
        window.view:rebuild()
        assert.same(msg.model.bloodType, window.view.model.bloodType)
        assert.equal(100, window.view.overall)
        assert.equal(msg.model.parts.Head.value, window.view.diagram.values.Head)
        window.view:openHealth()          -- not the doctor's own Health tab (getPlayerInfoPanel would throw)
    end)

    it("treats the patient from the exam diagram through vanilla's panel for the patient, within vanilla's reach",
        function()
            local window = ClientExam.window("sp:0", "sp:1")      -- the session the test above opened
            local head = BodyPartType.FromString("Head")
            window.view:treat(head, 50, 60)
            local panel = healthPanels[#healthPanels]
            assert.equal(patient, panel.character)
            assert.equal(doctor, panel.otherPlayer)
            assert.equal(doctor:getPerkLevel(Perks.Doctor), panel.doctorLevel)
            assert.same({ { patient.body:part("Head"), 50, 60 } }, panel.menus)
            window.view:treatWith(head, { "bandage" })
            assert.same({ { patient.body:part("Head"), { "bandage" } } }, panel.drops)
            assert.equal(1, #healthPanels)                -- one panel per window
            -- Beyond vanilla's 2 tiles (still inside the exam's 3): no menu, a notice.
            patient.x = 103
            window.view:treat(head, 50, 60)
            assert.equal(1, #panel.menus)
            assert.equal("UI_EHR_Context_TooFar", HaloTextHelper.shown[#HaloTextHelper.shown])
            patient.x = 101
            -- MP: a remote patient's body damage. Treating reads it without asking again (asking resets it); the window
            -- asks again when vanilla's Medical Check window for the patient closes, and stops asking on closing.
            local isClientBefore, asks, remoteBody = _G.isClient, {}, { getBodyPart = function() return "remote" end }
            local vanillaWindow = { visible = true, getIsVisible = function(w) return w.visible end }
            finally(function()
                _G.isClient = isClientBefore
                _G.ISMedicalCheckAction = nil
                patient.isLocalPlayer, patient.getBodyDamageRemote = nil, nil
            end)
            _G.isClient = function() return true end
            function patient:isLocalPlayer() return false end
            function patient:getBodyDamageRemote() return remoteBody end
            function doctor:startReceivingBodyDamageUpdates(p) asks[#asks + 1] = { "start", p } end
            function doctor:stopReceivingBodyDamageUpdates(p) asks[#asks + 1] = { "stop", p } end
            _G.ISMedicalCheckAction = { getHealthWindowForPlayer = function(p) return p == patient and vanillaWindow end }
            window.view:treat(head, 50, 60)
            assert.equal("remote", panel.menus[#panel.menus][1])
            assert.same({}, asks)
            window:watchVanillaWindow()                     -- vanilla's window open: it receives the updates
            window:receiveBodyDamage(false)                 -- and stopping now would cut it off
            assert.same({}, asks)
            vanillaWindow.visible = false
            window:watchVanillaWindow()
            assert.same({ { "start", patient } }, asks)
            window:receiveBodyDamage(false)
            assert.same({ { "start", patient }, { "stop", patient } }, asks)
        end)

    it("names a condition only as far as the DOCTOR knows it, and sends nothing else of the patient", function()
        state(patient).conditions.active.tetanus = {
            stage = 2, left = 1e6, duration = 1e6, extra = 0, severity = 1, data = {},
        }
        state(patient).knowledge.diseases.tetanus = true
        Runtime.store:markDirty("sp:1", "conditions")
        game.advance(1)
        local model = last("examModel").model
        local row
        for _, r in ipairs(model.conditions) do
            if not r.exposure then row = r end
        end
        assert.truthy(row)
        assert.is_false(row.known)
        assert.is_false(mentions(last("examModel"), "tetanus"))
        assert.is_nil(model.knowledge)
        assert.is_nil(model.immunity)
        -- The doctor reads a flyer: the next model names it.
        state(doctor).knowledge.diseases.tetanus = true
        Runtime.store:markDirty("sp:0", "knowledge")
        game.advance(1)
        for _, r in ipairs(last("examModel").model.conditions) do
            if not r.exposure then row = r end
        end
        assert.is_true(row.known)
        state(patient).conditions.active.tetanus = nil
        state(doctor).knowledge.diseases.tetanus = nil
        state(patient).knowledge.diseases.tetanus = nil
        Runtime.store:markDirty("sp:1", "conditions")
        Runtime.store:markDirty("sp:0", "knowledge")
        game.advance(1)
    end)

    it("refreshes when the patient changes, at most once a real second", function()
        game.sandbox.MedicalWatchRequired = false    -- blood readings visible without a watch
        game.advance(1)
        game.realMs = game.realMs + 1000
        local count = #messages("examModel")
        state(patient).blood.volume = 4000
        Runtime.store:markDirty("sp:1", "blood")
        Runtime.flushAll()
        assert.equal(count + 1, #messages("examModel"))
        assert.near(80, last("examModel").model.blood.percent, 0.5)
        state(patient).blood.volume = 3000
        Runtime.store:markDirty("sp:1", "blood")
        Runtime.flushAll()
        assert.equal(count + 1, #messages("examModel"))       -- held back by the throttle
        game.realMs = game.realMs + 1000
        game.events.OnTick.trigger()
        assert.equal(count + 2, #messages("examModel"))
        assert.near(60, last("examModel").model.blood.percent, 0.5)
        state(patient).blood.volume = 5000
        game.sandbox.MedicalWatchRequired = nil
    end)

    it("sends no blood readings the patient's Monitor would hide (no watch)", function()
        game.realMs = game.realMs + 1000
        state(patient).blood.volume = 4500
        Runtime.store:markDirty("sp:1", "blood")
        Runtime.flushAll()
        local blood = last("examModel").model.blood
        assert.is_false(blood.visible)
        assert.is_nil(blood.percent)
        assert.is_nil(blood.ml)
        assert.is_nil(blood.saline)
        state(patient).blood.volume = 5000
    end)

    it("refreshes when vanilla treatment changes the patient's body, without waiting for the game minute", function()
        game.realMs = game.realMs + 1000
        game.events.OnTick.trigger()                          -- the restored blood volume goes out
        local count = #messages("examModel")
        local arm = patient.body:part("ForeArm_L")
        -- Health moving inside a band the diagram shows the same way sends nothing.
        arm.health = 95
        game.realMs = game.realMs + 1000
        game.events.OnTick.trigger()
        assert.equal(count, #messages("examModel"))
        arm.flags.bandaged = true
        game.realMs = game.realMs + 250
        game.events.OnTick.trigger()
        assert.equal(count + 1, #messages("examModel"))
        assert.equal("bandage", last("examModel").model.parts.ForeArm_L.statuses[1].id)
        -- Still at most once a real second.
        arm.flags.bleeding = true
        game.realMs = game.realMs + 250
        game.events.OnTick.trigger()
        assert.equal(count + 1, #messages("examModel"))
        game.realMs = game.realMs + 750
        game.events.OnTick.trigger()
        assert.equal(count + 2, #messages("examModel"))
        assert.equal("bleeding", last("examModel").model.parts.ForeArm_L.statuses[1].id)
        arm.flags, arm.health = {}, 100
        game.realMs = game.realMs + 1000
        game.events.OnTick.trigger()
        assert.equal(count + 3, #messages("examModel"))
        assert.same({}, last("examModel").model.parts.ForeArm_L.statuses)
    end)

    it("keeps the session alive with exam.keep and ends it when idle", function()
        local session = Exam.sessions["sp:1"]["sp:0"]
        local now = game.realMs / 1000
        session.expires = now + 5
        Client.send(doctor, "exam.keep", { target = "sp:1" })
        assert.near(now + Exam.IDLE_SECONDS, session.expires, 0.01)
        session.expires = now - 1
        game.advance(1)
        assert.is_false(Exam.isExamining("sp:0", "sp:1"))
        assert.equal("idle", last("examEnd").reason)
        assert.is_nil(ClientExam.window("sp:0", "sp:1"))
        assert.equal("UI_EHR_Exam_Ended_Idle", HaloTextHelper.shown[#HaloTextHelper.shown])
    end)

    it("ends the session when the patient walks away", function()
        game.realMs = game.realMs + 20000              -- past the consent ask rate limit
        assert.truthy(examine())
        patient.x = 110
        game.advance(1)
        assert.is_false(Exam.isExamining("sp:0", "sp:1"))
        assert.equal("too_far", last("examEnd").reason)
        assert.is_nil(ClientExam.window("sp:0", "sp:1"))
        patient.x = 101
    end)

    it("ends the session when the doctor closes the window", function()
        game.realMs = game.realMs + 20000
        assert.truthy(examine())
        local window = ClientExam.window("sp:0", "sp:1")
        window:onJoypadDown(Joypad.BButton)
        assert.is_nil(ClientExam.window("sp:0", "sp:1"))
        assert.is_false(Exam.isExamining("sp:0", "sp:1"))
        -- A model already on its way doesn't reopen it.
        Transport.toClient(doctor, "examModel", { target = "sp:1", patient = "sp:1", model = {}, owner = "sp:0" })
        assert.is_nil(ClientExam.window("sp:0", "sp:1"))
    end)

    it("lists what the doctor can give and starts the chosen dose through Client/Give", function()
        game.realMs = game.realMs + 20000
        assert.truthy(examine())
        local window = ClientExam.window("sp:0", "sp:1")
        window:openAdminister()
        assert.equal(2, #lastMenu.options)
        assert.equal("Painkillers", lastMenu.options[1].name)
        assert.is_true(lastMenu.options[2].notAvailable)
        assert.equal("UI_EHR_MedAction_RequiresIVKit", lastMenu.options[2].toolTip.description)
        lastMenu.options[1].onSelect(lastMenu.options[1].target, lastMenu.options[1].param1)
        assert.same({ doctor, patient, "pills" }, given[1])
        window:close()
    end)

    it("refuses exam.keep from a player who isn't examining", function()
        local before = #messages("examModel")
        Client.send(patient, "exam.keep", { target = "sp:0" })
        assert.equal("none", last("examEnd").reason)
        assert.equal(before, #messages("examModel"))
        assert.is_false(Exam.isExamining("sp:1", "sp:0"))
        -- Nor does a refusal start one.
        game.realMs = game.realMs + 20000
        ClientExam.onExamine(doctor, patient)
        Client.send(patient, "consent.answer", { from = "sp:0", purpose = "exam", accepted = false })
        assert.is_false(Exam.isExamining("sp:0", "sp:1"))
        assert.equal(before, #messages("examModel"))
    end)

    it("ends every session of a doctor who dies", function()
        game.realMs = game.realMs + 31000    -- past the cooldown after the patient's last "no"
        assert.truthy(examine())
        doctor.dead = true
        game.advance(1)
        assert.is_false(Exam.isExamining("sp:0", "sp:1"))
        rawset(_G, "instanceof", realInstanceof)
    end)
end)
