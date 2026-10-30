-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, inject-field, need-check-nil, duplicate-set-field
-- The disease handbook (UI/Handbook): which entries are known or locked (the monitor's knowledge rule, Knox only from
-- the Kentucky Herald), what a known entry shows, the timing source, "LETHAL RISK" only when known, and that every key
-- and icon it names exists. The window (Client/Handbook) is loaded against stand-ins for the vanilla UI classes.
local LuaSource = require("LuaSource")
local Text = require("ExtensiveHealthRedone/UI/Text")
local Handbook = require("ExtensiveHealthRedone/UI/Handbook")
local DiseaseInfo = require("ExtensiveHealthRedone/Data/DiseaseInfo")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")

local MOD = "Contents/mods/ExtensiveHealthRedone/"
local UI_JSON = MOD .. "42/media/lua/shared/Translate/EN/UI.json"
local TEXTURES = MOD .. "common/media/textures/"

local function sandbox(values)
    return function(name, default)
        local v = values and values[name]
        if v == nil then
            return default
        end
        return v
    end
end

local function knowledge(fields)
    local k = { diseases = {}, knoxHerald = false }
    for key, value in pairs(fields or {}) do
        k[key] = value
    end
    return k
end

local function byId(model)
    local map = {}
    for _, e in ipairs(model.entries) do
        map[e.id] = e
    end
    return map
end

local function sectionKeys(e)
    local keys = {}
    for _, s in ipairs(e.sections or {}) do
        keys[#keys + 1] = s.label.key
    end
    return table.concat(keys, ",")
end

local function timing(e)
    for _, s in ipairs(e.sections or {}) do
        if s.label.key == "UI_EHR_Codex_Timing" then
            return s.body
        end
    end
    return nil
end

-- Renders text with "key(args)" so a test can compare whole lines.
local function render(t)
    return Text.render(t, function(key, ...)
        local args = { ... }
        if #args == 0 then
            return key
        end
        for i = 1, #args do
            args[i] = tostring(args[i])
        end
        return key .. "(" .. table.concat(args, ",") .. ")"
    end)
end

describe("handbook", function()
    it("lists the 23 diseases in v0.9's order, without tuberculosis", function()
        local model = Handbook.build(knowledge(), 0, defs, sandbox())
        assert.equal(23, model.total)
        assert.equal(23, #model.entries)
        assert.equal("food_poisoning", model.entries[1].id)
        assert.equal("knox_infection", model.entries[23].id)
        assert.is_nil(byId(model).tuberculosis)
    end)

    it("starts a new character with the 8 self-evident diseases known", function()
        local model = Handbook.build(knowledge(), 0, defs, sandbox())
        assert.equal(8, model.known)
        local known = {}
        for _, e in ipairs(model.entries) do
            if e.known then
                known[#known + 1] = e.id
            end
        end
        assert.same({ "food_poisoning", "hypothermia", "heat_exhaustion", "heat_stroke", "concussion", "delirium",
            "insomnia", "painkiller_addiction" }, known)
    end)

    it("shows a locked entry by its category, with the unlock hint and nothing else", function()
        local e = byId(Handbook.build(knowledge(), 0, defs, sandbox())).trichinosis
        assert.is_false(e.known)
        assert.equal("UI_EHR_Codex_UnknownCategory_food", e.name.key)
        assert.equal("UI_EHR_Codex_Category_food", e.category.key)
        assert.equal(DiseaseInfo.UNKNOWN_ICON, e.icon)
        assert.equal("UI_EHR_Codex_LockedDesc", e.locked.key)
        assert.is_false(e.lethal)
        assert.is_nil(e.sections)
    end)

    it("unlocks a disease from its flyer, including cellulitis, sepsis, tetanus, AHTR and wound infection", function()
        local k = knowledge({ diseases = { sepsis = true, cellulitis = true, tetanus = true, ahtr = true,
            wound_infection = true, trichinosis = true } })
        local model = byId(Handbook.build(k, 0, defs, sandbox()))
        for _, id in ipairs({ "sepsis", "cellulitis", "tetanus", "ahtr", "wound_infection", "trichinosis" }) do
            assert.is_true(model[id].known, id)
            assert.equal("UI_EHR_Codex_" .. id .. "_Name", model[id].name.key)
            assert.equal(DiseaseInfo.BY_ID[id].icon, model[id].icon)
        end
        assert.is_false(model.pneumonia.known)
    end)

    it("unlocks everything but Knox with First Aid 8 or a medical profession", function()
        assert.equal(22, Handbook.build(knowledge(), 8, defs, sandbox()).known)
        assert.equal(8, Handbook.build(knowledge(), 7, defs, sandbox()).known)
        local model = Handbook.build(knowledge({ professionGrant = "ehrdoctor" }), 0, defs, sandbox())
        assert.equal(22, model.known)
        assert.is_false(byId(model).knox_infection.known)
    end)

    it("unlocks Knox only with the Kentucky Herald, and says so when locked", function()
        local without = byId(Handbook.build(knowledge({ diseases = { knox_infection = true } }), 10, defs, sandbox()))
        assert.is_false(without.knox_infection.known)
        assert.equal("UI_EHR_Codex_LockedDescKnox", without.knox_infection.locked.key)
        local with = byId(Handbook.build(knowledge({ diseases = { knox_infection = true }, knoxHerald = true }), 0,
            defs, sandbox()))
        assert.is_true(with.knox_infection.known)
        assert.is_true(with.knox_infection.lethal)
    end)

    it("marks lethal diseases only once they are known", function()
        local locked = byId(Handbook.build(knowledge(), 0, defs, sandbox()))
        local known = byId(Handbook.build(knowledge(), 8, defs, sandbox()))
        assert.is_false(locked.pneumonia.lethal)
        assert.is_true(known.pneumonia.lethal)
        assert.is_true(known.hypothermia.lethal)
        assert.is_false(known.common_cold.lethal)
        assert.is_false(known.food_poisoning.lethal)
    end)

    it("shows Cause, Symptoms, Timing, Prevention and Treatment, leaving out Timing it can't give", function()
        local model = byId(Handbook.build(knowledge(), 8, defs, sandbox()))
        local all = "UI_EHR_Codex_Cause,UI_EHR_Codex_Symptoms,UI_EHR_Codex_Timing,UI_EHR_Codex_Prevention," ..
            "UI_EHR_Codex_Treatment"
        local noTiming = "UI_EHR_Codex_Cause,UI_EHR_Codex_Symptoms,UI_EHR_Codex_Prevention,UI_EHR_Codex_Treatment"
        assert.equal(all, sectionKeys(model.food_poisoning))
        assert.equal("UI_EHR_Codex_food_poisoning_Cause", model.food_poisoning.sections[1].body.key)
        for _, id in ipairs({ "hypothermia", "heat_exhaustion", "concussion", "delirium", "wound_infection" }) do
            assert.equal(noTiming, sectionKeys(model[id]), id)
        end
    end)

    it("computes timing from the definition and its speed option", function()
        local model = byId(Handbook.build(knowledge(), 8, defs, sandbox()))
        assert.equal("UI_EHR_Codex_TimingText(UI_EHR_Codex_Range(UI_EHR_Codex_Hours(2),UI_EHR_Codex_Hours(12))," ..
            "UI_EHR_Codex_Range(UI_EHR_Codex_Days(1),UI_EHR_Codex_Days(3)))", render(timing(model.food_poisoning)))
        local fast = byId(Handbook.build(knowledge(), 8, defs, sandbox({ DiseaseSpeed = 2, SepsisSpeed = 4 })))
        assert.equal("UI_EHR_Codex_TimingText(UI_EHR_Codex_Range(UI_EHR_Codex_Hours(1),UI_EHR_Codex_Hours(6))," ..
            "UI_EHR_Codex_Range(UI_EHR_Codex_Hours(12),UI_EHR_Codex_Days(1.5)))", render(timing(fast.food_poisoning)))
        assert.equal("UI_EHR_Codex_TimingText(UI_EHR_Codex_Range(UI_EHR_Codex_Hours(1.5),UI_EHR_Codex_Hours(6))," ..
            "UI_EHR_Codex_Range(UI_EHR_Codex_Hours(12),UI_EHR_Codex_Days(1)))", render(timing(fast.sepsis)))
    end)

    it("uses the authored timing texts where they exist", function()
        local model = byId(Handbook.build(knowledge({ diseases = { knox_infection = true }, knoxHerald = true }), 8,
            defs, sandbox()))
        for id in pairs(Handbook.AUTHORED_TIMING) do
            assert.equal("UI_EHR_Codex_TimingNotes(UI_EHR_Codex_" .. id .. "_Incubation,UI_EHR_Codex_" .. id ..
                "_Duration)", render(timing(model[id])), id)
        end
    end)

    it("names only keys and icons that exist", function()
        local keys = {}
        for key in LuaSource.read(UI_JSON):gmatch('"([%w_]+)"%s*:') do
            keys[key] = true
        end
        local function check(t)
            if type(t) ~= "table" then
                return
            end
            if t.key then
                assert.truthy(keys[t.key], "missing key " .. t.key)
            end
            for _, a in ipairs(t.args or {}) do
                check(a)
            end
        end
        local everything = knowledge({ diseases = { knox_infection = true }, knoxHerald = true })
        for _, model in ipairs({ Handbook.build(knowledge(), 0, defs, sandbox()),
            Handbook.build(everything, 10, defs, sandbox()) }) do
            for _, e in ipairs(model.entries) do
                check(e.name)
                check(e.category)
                check(e.locked)
                for _, s in ipairs(e.sections or {}) do
                    check(s.label)
                    check(s.body)
                end
                local f = io.open(TEXTURES .. e.icon .. ".png", "rb")
                assert.truthy(f, "missing icon " .. e.icon)
                if f then
                    f:close()
                end
            end
        end
        for _, key in ipairs({ "UI_EHR_DiseaseHandbook_Title", "UI_EHR_DiseaseHandbook_KnownCount",
            "UI_EHR_DiseaseHandbook_Index", "UI_EHR_DiseaseHandbook_Details", "UI_EHR_Codex_KnownUpper",
            "UI_EHR_Codex_LockedUpper", "UI_EHR_Codex_Known", "UI_EHR_Codex_Locked", "UI_EHR_Codex_LethalRisk",
            "UI_EHR_Codex_KnowledgeUnavailable" }) do
            assert.truthy(keys[key], "missing key " .. key)
        end
    end)
end)

insulate("handbook window", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- A stand-in class with the ISUIElement methods the window calls; derive and new work like ISUIElement's.
    local function class()
        local c = {}
        c.__index = c
        for _, name in ipairs({ "setTitle", "setResizable", "initialise", "setAnchorBottom", "setAnchorRight",
            "setOnMouseDownFunction", "setYScroll", "setVisible", "addToUIManager", "bringToTop", "removeFromUIManager",
            "prerender", "render", "update" }) do
            c[name] = function() end
        end
        function c:titleBarHeight() return 16 end
        function c:resizeWidgetHeight() return 8 end
        function c:getYScroll() return 0 end
        function c:derive(name)
            local d = setmetatable({ Type = name }, { __index = self })
            d.__index = d
            return d
        end
        function c.new(self, x, y, w, h)
            return setmetatable({ x = x, y = y, width = w, height = h, children = {} }, self)
        end
        function c:instantiate() self:createChildren() end
        function c:createChildren() end
        function c:addChild(child) self.children[#self.children + 1] = child end
        return c
    end
    for _, name in ipairs({ "ISUI/ISCollapsableWindowJoypad", "ISUI/ISScrollingListBox", "ISUI/ISPanel",
        "ISUI/ISLayoutManager" }) do
        package.preload[name] = function() return true end
    end
    _G.ISCollapsableWindowJoypad = class()
    _G.ISPanel = class()
    _G.ISScrollingListBox = class()
    function ISScrollingListBox:clear() self.items = {} end
    function ISScrollingListBox:addItem(name, item)
        self.items = self.items or {}
        self.items[#self.items + 1] = { text = name, item = item, index = #self.items + 1 }
    end
    _G.ISLayoutManager = { registered = {}, RegisterWindow = function(name) ISLayoutManager.registered[name] = true end }
    -- Filled in a loop: LuaLS would otherwise take these strings as the type of UIFont's fields everywhere.
    local fonts = {}
    for _, name in ipairs({ "Small", "Medium", "Large" }) do
        fonts[name] = fonts[name] or name
    end
    rawset(_G, "UIFont", fonts)
    _G.getTextManager = function()
        return { getFontHeight = function() return 16 end, MeasureStringX = function(_, _, s) return #s * 7 end }
    end
    _G.Joypad = { BButton = "B", LBumper = "LB", RBumper = "RB" }
    _G.JoypadState = { players = {} }
    _G.setJoypadFocus = function() end
    for _, name in ipairs({ "getPlayerScreenLeft", "getPlayerScreenTop" }) do
        _G[name] = function() return 0 end
    end
    _G.getPlayerScreenWidth = function() return 1920 end
    _G.getPlayerScreenHeight = function() return 1080 end
    if not _G.Events.OnPlayerDeath then
        _G.Events.OnPlayerDeath = { Add = function() end }
    end

    local Window = require("ExtensiveHealthRedone/Client/Handbook")
    local player = game.addPlayer({})
    player.firstAid = 0

    it("opens one window per player, built from the mirror, and toggles closed", function()
        local window = Window.open(0)
        assert.truthy(window)
        assert.is_true(Window.isOpen(0))
        assert.equal(8, window.model.known)
        assert.equal(23, #window.list.items)
        assert.equal("food_poisoning", window.details.entry.id)
        assert.is_true(ISLayoutManager.registered.ehrhandbook)
        assert.equal(window, Window.open(0))
        Window.toggle(0)
        assert.is_false(Window.isOpen(0))
    end)

    it("rebuilds when First Aid changes, keeping the selected entry", function()
        local window = Window.open(0)
        window:onSelect(window.model.entries[3])
        player.firstAid = 8
        window:prerender()
        assert.equal(22, window.model.known)
        assert.equal("trichinosis", window.details.entry.id)
        assert.is_true(window.details.entry.known)
        Window.close(0)
        player.firstAid = 0
    end)
end)
