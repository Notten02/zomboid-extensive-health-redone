---@diagnostic disable: need-check-nil
-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake game and UI objects are deliberately partial.
---@diagnostic disable: missing-fields, duplicate-set-field
-- The Mini Health Panel companion: the pure view model and the docking, then the panel following a fake host panel
-- (the mod's `mhpHandle`).
local MiniHealth = require("ExtensiveHealthRedone/UI/MiniHealth")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Sim = require("support/sim")

local function input(opts)
    opts = opts or {}
    local state = Sim.neutralState()
    state.knowledge.diseases = opts.known or {}
    return {
        state = state, firstAid = opts.firstAid or 0, defs = defs, watch = opts.watch ~= false,
        sandbox = function(name, default)
            if opts.sandbox and opts.sandbox[name] ~= nil then return opts.sandbox[name] end
            return default
        end,
    }
end

local function rows(i)
    local out = {}
    for _, row in ipairs(MiniHealth.build(i).rows) do
        out[row.label] = row
    end
    return out
end

describe("Mini Health companion model", function()
    it("shows full blood green and nothing else wrong on a healthy character", function()
        local r = rows(input())
        assert.equal("100%", r.UI_EHR_Mini_Blood.value.raw)
        assert.equal("green", r.UI_EHR_Mini_Blood.color)
        assert.equal("0", r.UI_EHR_Mini_Infection.value.raw)
        assert.equal("--", r.UI_EHR_Mini_Sepsis.value.raw)
        assert.equal("--", r.UI_EHR_Mini_Disease.value.raw)
    end)

    it("colours blood by share (v0.9's 70, 50 and 30) and needs the watch like the Monitor", function()
        local i = input()
        local function colorAt(volume)
            i.state.blood.volume = volume
            return rows(i).UI_EHR_Mini_Blood.color
        end
        local max = i.state.blood.max
        assert.equal("green", colorAt(max * 0.71))
        assert.equal("yellow", colorAt(max * 0.6))
        assert.equal("orange", colorAt(max * 0.4))
        assert.equal("red", colorAt(max * 0.2))
        local without = rows(input({ watch = false }))
        assert.equal("?", without.UI_EHR_Mini_Blood.value.raw)
        local free = rows(input({ watch = false, sandbox = { MedicalWatchRequired = false } }))
        assert.equal("100%", free.UI_EHR_Mini_Blood.value.raw)
    end)

    it("counts infected wounds only", function()
        local i = input()
        i.state.wounds.parts = { Hand_L = { phase = "infected", stage = 1, left = 5 },
            Hand_R = { phase = "incubating", stage = 1, left = 5 }, Foot_L = { phase = "infected", stage = 2, left = 5 } }
        local r = rows(i).UI_EHR_Mini_Infection
        assert.equal("2", r.value.raw)
        assert.equal("orange", r.color)
    end)

    it("names sepsis and the worst illness by stage for a reader who can tell stages, else shows a question mark", function()
        local i = input({ firstAid = 6, known = { common_cold = true, pneumonia = true, sepsis = true } })
        i.state.conditions.active.sepsis = { stage = 3, left = 10, len = {}, duration = 100, extra = 0 }
        i.state.conditions.active.common_cold = { stage = 2, left = 10, len = {}, duration = 100, extra = 0 }
        i.state.conditions.active.pneumonia = { stage = 4, left = 10, len = {}, duration = 100, extra = 0 }
        local r = rows(i)
        assert.equal("UI_EHR_Mini_SepsisStage_3", r.UI_EHR_Mini_Sepsis.value.key)
        assert.equal("UI_EHR_Mini_DiseaseStage_4", r.UI_EHR_Mini_Disease.value.key)
        local novice = rows(input({ firstAid = 0, known = { common_cold = true } }))
        assert.equal("--", novice.UI_EHR_Mini_Sepsis.value.raw)
        local n = input({ firstAid = 0, known = { common_cold = true } })
        n.state.conditions.active.sepsis = { stage = 3, left = 10, len = {}, duration = 100, extra = 0 }
        n.state.conditions.active.common_cold = { stage = 2, left = 10, len = {}, duration = 100, extra = 0 }
        local nr = rows(n)
        assert.equal("?", nr.UI_EHR_Mini_Sepsis.value.raw)
        assert.equal("?", nr.UI_EHR_Mini_Disease.value.raw)
    end)

    it("docks to the right of the host, or to the left near the screen edge", function()
        local host = { x = 25, y = 700, width = 120 }
        assert.same({ 147, 700, true }, { MiniHealth.dock(host, 100, 1920, 2) })
        assert.same({ 1700 - 100 - 2, 40, false }, { MiniHealth.dock({ x = 1700, y = 40, width = 120 }, 100, 1800, 2) })
    end)
end)

insulate("Mini Health companion panel", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- A fake ISPanel with the parts the companion uses.
    package.preload["ISUI/ISPanel"] = function() return true end
    local PanelBase = {}
    PanelBase.__index = PanelBase
    function PanelBase:derive(name)
        local d = setmetatable({ Type = name }, { __index = self })
        d.__index = d
        return d
    end
    function PanelBase.new(_, x, y, w, h)
        return setmetatable({ x = x, y = y, width = w, height = h, visible = true, added = false }, PanelBase)
    end
    function PanelBase:initialise() end
    function PanelBase:instantiate() end
    function PanelBase:addToUIManager() self.added = true end
    function PanelBase:removeFromUIManager() self.added = false end
    function PanelBase:setVisible(v) self.visible = v end
    function PanelBase:isVisible() return self.visible end
    function PanelBase:setX(v) self.x = v end
    function PanelBase:setY(v) self.y = v end
    function PanelBase:setWidth(v) self.width = v end
    function PanelBase:setHeight(v) self.height = v end
    function PanelBase:getWidth() return self.width end
    function PanelBase:getX() return self.x end
    function PanelBase:getY() return self.y end
    _G.ISPanel = PanelBase
    local fonts = rawget(_G, "UIFont") or {}
    for _, name in ipairs({ "Small", "Medium", "Large" }) do fonts[name] = fonts[name] or name end
    rawset(_G, "UIFont", fonts)
    _G.getTextManager = function()
        return { getFontHeight = function() return 12 end, MeasureStringX = function(_, _, s) return 6 * #s end }
    end
    _G.getCore = function() return { getScreenWidth = function() return 1920 end } end
    _G.getText = function(key) return key end
    local perks = rawget(_G, "Perks") or {}
    for _, name in ipairs({ "Doctor" }) do perks[name] = perks[name] or name end
    rawset(_G, "Perks", perks)
    -- Keep the fake game's OnTick working and capture the handler the companion registers.
    local companionTick
    do
        local original = _G.Events.OnTick
        _G.Events.OnTick = setmetatable({ Add = function(fn) companionTick = fn; original.Add(fn) end },
            { __index = original })
    end

    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local MiniHealthPanel = require("ExtensiveHealthRedone/Client/MiniHealth")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local host
    local function newHost()
        host = { x = 25, y = 700, width = 120, shown = true, alpha = 1 }
        function host:getX() return self.x end
        function host:getY() return self.y end
        function host:getWidth() return self.width end
        function host:isVisible() return self.shown end
        function host:getPlayer() return player end
        _G.mhpHandle = host
    end
    local function tick()
        for _ = 1, MiniHealthPanel.CHECK_TICKS do
            companionTick()
        end
    end

    after_each(function()
        _G.mhpHandle = nil
        game.mods.MiniHealthPanel = nil
    end)

    it("does nothing without the mod or its panel", function()
        tick()
        assert.is_nil(MiniHealthPanel.host())
        newHost()
        tick()                                -- the host exists, the mod is not enabled
        assert.is_nil(MiniHealthPanel.panelForTest())
    end)

    it("docks beside the host, follows it and its visibility, and shows the model", function()
        game.mods.MiniHealthPanel = true
        newHost()
        tick()
        local panel = MiniHealthPanel.panelForTest()
        assert.truthy(panel)
        panel:update()
        assert.is_true(panel:isVisible())
        assert.equal(host.x + host.width + MiniHealthPanel.GAP, panel:getX())
        assert.equal(host.y, panel:getY())
        assert.truthy(panel.model)
        assert.equal(4, #panel.lines)
        host.x = 1900
        panel.refreshAt = 0
        panel:update()
        assert.is_true(panel:getX() < host.x)
        host.shown = false
        panel:update()
        assert.is_false(panel:isVisible())
        host.shown, host.alpha = true, 0
        panel:update()
        assert.is_false(panel:isVisible())
    end)

    it("hides while the host's player is dead and switches off if the host is not what it was", function()
        game.mods.MiniHealthPanel = true
        newHost()
        tick()
        local panel = MiniHealthPanel.panelForTest()
        player.dead = true
        panel:update()
        assert.is_false(panel:isVisible())
        player.dead = false
        host.getX = function() error("different mod version") end
        panel:update()
        assert.is_false(panel:isVisible())
        assert.is_false(panel.added)
        assert.is_nil(MiniHealthPanel.panelForTest())
        assert.is_true(game.logged("did not look as expected"))
    end)
end)
