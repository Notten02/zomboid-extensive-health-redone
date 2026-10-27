-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, inject-field, need-check-nil, duplicate-set-field
-- Our tabs in vanilla's character window (Client/CharacterWindow) and the hotkeys (Client/Keys), against a stand-in of
-- ISCharacterInfoWindow that toggles views like vanilla's: the tabs are added after vanilla's (the Immune System tab
-- only while the system is on), PrimaryHealthPanel sends vanilla's Health toggle to the EHR Monitor except when the
-- Health tab is the open one, and J puts the window back as it was when it is also vanilla's Info key.
-- Drawing needs the game; this checks the wiring.

insulate("character window", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- A stand-in UI class: derive and new like ISUIElement's, with the methods our panels call at construction.
    local function class()
        local c = {}
        c.__index = c
        for _, name in ipairs({ "setTitle", "setResizable", "initialise", "setAnchorBottom", "setAnchorRight",
            "setOnMouseDownFunction", "setYScroll", "addToUIManager", "bringToTop", "removeFromUIManager",
            "prerender", "render", "update", "createChildren" }) do
            c[name] = function() end
        end
        function c:titleBarHeight() return 16 end
        function c:resizeWidgetHeight() return 8 end
        function c:getYScroll() return 0 end
        function c:setVisible(v) self.visible = v end
        function c:getIsVisible() return self.visible == true end
        function c:derive(name)
            local d = setmetatable({ Type = name }, { __index = self })
            d.__index = d
            return d
        end
        function c.new(self, x, y, w, h)
            return setmetatable({ x = x, y = y, width = w, height = h, children = {} }, self)
        end
        function c:instantiate() self:createChildren() end
        function c:addChild(child) self.children[#self.children + 1] = child end
        return c
    end
    for _, name in ipairs({ "XpSystem/ISUI/ISCharacterInfoWindow", "ISUI/ISPanelJoypad", "ISUI/ISButton",
        "ISUI/BodyParts/ISBodyPartPanel", "ISUI/ISCollapsableWindowJoypad", "ISUI/ISScrollingListBox", "ISUI/ISPanel",
        "ISUI/ISLayoutManager" }) do
        package.preload[name] = function() return true end
    end
    for _, name in ipairs({ "ISPanelJoypad", "ISButton", "ISBodyPartPanel", "ISCollapsableWindowJoypad", "ISPanel",
        "ISScrollingListBox" }) do
        _G[name] = class()
    end
    function ISScrollingListBox:clear() self.items = {} end
    function ISScrollingListBox:addItem(name, item)
        self.items = self.items or {}
        self.items[#self.items + 1] = { text = name, item = item, index = #self.items + 1 }
    end
    _G.ISLayoutManager = { RegisterWindow = function() end }
    -- Filled in a loop: LuaLS would otherwise take these strings as the type of UIFont's fields everywhere.
    local fonts = {}
    for _, name in ipairs({ "Small", "Medium", "Large" }) do
        fonts[name] = fonts[name] or name
    end
    rawset(_G, "UIFont", fonts)
    _G.getTextManager = function()
        return { getFontHeight = function() return 16 end, MeasureStringX = function(_, _, s) return #s * 7 end }
    end
    _G.Keyboard = { KEY_J = 36, KEY_G = 34, KEY_H = 35 }
    _G.KeybindId = { TOGGLE_INFO_PANEL = "info" }
    -- Vanilla binds J to its Info panel.
    _G.getCore = function()
        return {
            getGameMode = function() return "Sandbox" end,
            isKey = function(_, id, key) return id == "info" and key == Keyboard.KEY_J end,
            getScreenWidth = function() return 1920 end,
            getScreenHeight = function() return 1080 end,
        }
    end
    _G.Joypad = { BButton = "B", LBumper = "LB", RBumper = "RB" }
    _G.JoypadState = { players = {} }
    _G.setJoypadFocus = function() end
    _G.getPlayerData = function() return {} end
    for _, name in ipairs({ "getPlayerScreenLeft", "getPlayerScreenTop" }) do
        _G[name] = function() return 0 end
    end
    _G.getPlayerScreenWidth = function() return 1920 end
    _G.getPlayerScreenHeight = function() return 1080 end
    _G.Events.OnPlayerDeath = _G.Events.OnPlayerDeath or { Add = function() end }

    -- A Mod Options stand-in, so a test can switch PrimaryHealthPanel off.
    local optionValues = {}
    _G.PZAPI = { ModOptions = {} }
    function PZAPI.ModOptions:create()
        local page = { options = {} }
        local function add(_, id, _, value)
            page.options[id] = { getValue = function() if optionValues[id] ~= nil then return optionValues[id] end return value end }
        end
        page.addKeyBind, page.addTickBox = add, add
        function page:getOption(id) return self.options[id] end
        return page
    end

    -- Vanilla's window and tab panel, toggling like ISCharacterInfoWindow.toggleView.
    _G.xpSystemText = { info = "Info", skills = "Skills", health = "Health" }
    local function newTabPanel()
        local panel = { viewList = {}, x = 0, width = 400 }
        function panel:addView(name, view)
            self.viewList[#self.viewList + 1] = { name = name, view = view, tabWidth = 60 }
            self.active = self.active or view
        end
        function panel:getView(name)
            for _, v in ipairs(self.viewList) do
                if v.name == name then return v.view end
            end
        end
        function panel:getActiveView() return self.active end
        function panel:activateView(name) self.active = self:getView(name) or self.active end
        function panel:setWidth(w) self.width = w end
        function panel:getWidth() return self.width end
        function panel:getX() return self.x end
        function panel:getWidthOfAllTabs()
            local width = #self.viewList - 1
            for _, v in ipairs(self.viewList) do width = width + v.tabWidth end
            return width
        end
        return panel
    end
    _G.ISCharacterInfoWindow = {}
    function ISCharacterInfoWindow.createChildren(self)
        self.panel = newTabPanel()
        self.charScreen, self.characterView, self.healthView = {}, {}, {}
        self.panel:addView("Info", self.charScreen)
        self.panel:addView("Skills", self.characterView)
        self.panel:addView("Health", self.healthView)
    end
    function ISCharacterInfoWindow.toggleView(self, name)
        local view = self.panel:getView(name)
        if self.visible then
            if view == self.panel:getActiveView() then
                self:close()
            else
                self.panel:activateView(name)
            end
        else
            self.panel:activateView(name)
            self.visible = true
        end
    end
    local function newWindow(playerNum)
        local w = { playerNum = playerNum, visible = false }
        function w:getIsVisible() return self.visible end
        function w:setVisible(v) self.visible = v end
        function w:addToUIManager() end
        function w:close() self.visible = false end
        w.createChildren = ISCharacterInfoWindow.createChildren
        w.toggleView = function(...) return ISCharacterInfoWindow.toggleView(...) end
        return w
    end
    local window
    _G.getPlayerInfoPanel = function() return window end

    game.addPlayer({})
    require("ExtensiveHealthRedone/Client/Client")
    local CharacterWindow = require("ExtensiveHealthRedone/Client/CharacterWindow")
    local Keys = require("ExtensiveHealthRedone/Client/Keys")
    local Handbook = require("ExtensiveHealthRedone/Client/Handbook")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()

    local function build()
        window = newWindow(0)
        ISCharacterInfoWindow.createChildren(window)
        return window
    end

    local function activeName()
        for _, v in ipairs(window.panel.viewList) do
            if v.view == window.panel:getActiveView() then return v.name end
        end
    end

    local function press(key)
        game.events.OnKeyPressed.trigger(key)
    end

    -- Vanilla's own key handler, which the game adds after ours.
    local function vanillaKey(key)
        if getCore():isKey(KeybindId.TOGGLE_INFO_PANEL, key) then
            window:toggleView(xpSystemText.info)
        end
    end

    it("adds the EHR Monitor and Immune System tabs after vanilla's views", function()
        build()
        local names = {}
        for _, v in ipairs(window.panel.viewList) do names[#names + 1] = v.name end
        assert.same({ "Info", "Skills", "Health", "UI_EHR_Tab_EHR", "UI_EHR_Tab_Immunity" }, names)
        assert.truthy(window.ehrMonitorView)
        assert.equal(0, window.ehrMonitorView.playerNum)
    end)

    it("leaves the Immune System tab out while the immune system is off", function()
        game.sandbox.ImmunitySystemEnabled = false
        build()
        assert.equal(4, #window.panel.viewList)
        assert.is_nil(window.ehrImmuneView)
        game.sandbox.ImmunitySystemEnabled = nil
    end)

    it("never lets a narrow view shrink the window below its tabs (issue #2)", function()
        build()
        window.panel.parent = window
        function window:setWidth(w) self.width = w end
        -- A view sizing itself like vanilla's ISUIElement:setWidthAndParentWidth (Antibodies' Hygiene at 400).
        local function viewWidth(w)
            window.panel:setWidth(0 + w)
            window:setWidth(window.panel:getX() + window.panel:getWidth())
        end
        local tabs = window.panel:getWidthOfAllTabs()
        -- One pixel wider than the tabs, or the strip shows a needless scroll arrow (issue #8).
        local minWidth = tabs + 1
        viewWidth(tabs - 100)
        assert.equal(minWidth, window.panel.width)
        assert.equal(minWidth, window.width)
        viewWidth(tabs + 200)
        assert.equal(tabs + 200, window.width)
    end)

    it("opens the EHR Monitor where vanilla opens Health, and closes it on the second press", function()
        build()
        window:toggleView(xpSystemText.health)
        assert.is_true(window.visible)
        assert.equal("UI_EHR_Tab_EHR", activeName())
        window:toggleView(xpSystemText.health)
        assert.is_false(window.visible)
    end)

    it("lets the open Health tab close itself, and keeps vanilla's Health with the option off", function()
        build()
        window.visible = true
        window.panel:activateView("Health")
        window:toggleView(xpSystemText.health)
        assert.is_false(window.visible)
        optionValues.PrimaryHealthPanel = false
        window:toggleView(xpSystemText.health)
        assert.equal("Health", activeName())
        optionValues.PrimaryHealthPanel = nil
    end)

    it("toggles our tabs from code and opens one without toggling", function()
        build()
        CharacterWindow.toggle(0, "immune")
        assert.equal("UI_EHR_Tab_Immunity", activeName())
        CharacterWindow.open(0, "monitor")
        CharacterWindow.open(0, "monitor")
        assert.is_true(window.visible)
        assert.equal("UI_EHR_Tab_EHR", activeName())
    end)

    it("opens vanilla's treatment menu for a Monitor body part through the window's Health panel", function()
        build()
        local part, menus = { name = "Hand_L" }, {}
        local health = window.healthView
        function health:getAbsoluteX() return 100 end
        function health:getAbsoluteY() return 40 end
        function health:getPatient()
            return { getBodyDamage = function()
                return { getBodyPart = function(_, t) return t == "Hand_L" and part or nil end }
            end }
        end
        function health:doBodyPartContextMenu(bp, x, y) menus[#menus + 1] = { bp, x, y } end
        local speed = 1
        _G.UIManager = { getSpeedControls = function() return { getCurrentGameSpeed = function() return speed end } end }
        _G.getDebug = function() return false end
        window.panel:activateView("UI_EHR_Tab_EHR")
        window.ehrMonitorView:treat("Hand_L", 350, 240)
        assert.same({ { part, 250, 200 } }, menus)
        assert.equal("UI_EHR_Tab_EHR", activeName())     -- stays on the Monitor (issue #1)
        -- Paused: nothing, as on vanilla's Health tab.
        speed = 0
        window.ehrMonitorView:treat("Hand_L", 350, 240)
        assert.equal(1, #menus)
    end)

    it("treats a Monitor body part with items dropped on it through the window's Health panel", function()
        build()
        local part, drops = { name = "Foot_R" }, {}
        local health = window.healthView
        function health:getPatient()
            return { getBodyDamage = function()
                return { getBodyPart = function(_, t) return t == "Foot_R" and part or nil end }
            end }
        end
        function health:dropItemsOnBodyPart(bp, items) drops[#drops + 1] = { bp, items } end
        local bandage = { type = "Bandage" }
        window.ehrMonitorView:treatWith("Foot_R", { bandage })
        assert.same({ { part, { bandage } } }, drops)
    end)

    it("opens the handbook with J and undoes vanilla's Info toggle from the same press", function()
        build()
        Keys.onKey(Keyboard.KEY_J)
        vanillaKey(Keyboard.KEY_J)
        Keys.afterKey(Keyboard.KEY_J)
        assert.is_true(Handbook.isOpen(0))
        assert.is_false(window.visible)
        -- Open on Skills: J goes back to Skills, and closes the handbook.
        window.visible = true
        window.panel:activateView("Skills")
        Keys.onKey(Keyboard.KEY_J)
        vanillaKey(Keyboard.KEY_J)
        Keys.afterKey(Keyboard.KEY_J)
        assert.is_false(Handbook.isOpen(0))
        assert.is_true(window.visible)
        assert.equal("Skills", activeName())
    end)

    it("registers the restoring key handler after the game starts, behind ours", function()
        local handlers = game.events.OnKeyPressed.handlers
        local ours
        for i, h in ipairs(handlers) do
            if h == Keys.onKey then ours = i end
        end
        assert.truthy(ours)
        assert.equal(Keys.afterKey, handlers[#handlers])
        -- An unbound Monitor key does nothing on H.
        build()
        press(Keyboard.KEY_H)
        assert.is_false(window.visible)
    end)
end)
