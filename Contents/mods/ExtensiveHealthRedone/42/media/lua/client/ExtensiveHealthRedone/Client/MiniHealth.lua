-- Mini Health Panel companion: a small "EHR Status" panel docked beside Mini Health Panel's wound diagram (blood,
-- infected wounds, sepsis, worst illness; UI/MiniHealth). It follows the host panel's position, visibility and fade,
-- and docks left when the right side would leave the screen. Optional mod, id MiniHealthPanel, checked against
-- v1.6.1.42 (its 42/ folder, versionMin 42.13): it keeps one global `mhpHandle` (an ISPanel, created at
-- OnCreatePlayer for the first local player, player available through mhpHandle:getPlayer()). Without the mod this
-- file does nothing. The data is the mirror, so it works in MP too.

require "ISUI/ISPanel"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Watch = require "ExtensiveHealthRedone/Game/Watch"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local MiniHealth = require "ExtensiveHealthRedone/UI/MiniHealth"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Draw = require "ExtensiveHealthRedone/Client/Draw"
local Text = require "ExtensiveHealthRedone/Client/Text"

local log = Env.logger("MiniHealth")

local SECTIONS = { "identity", "knowledge", "blood", "body", "wounds", "conditions", "exposure", "meds", "knox" }

---@class ExtensiveHealthRedoneMiniHealthPanel : ISPanel
---@field host table        Mini Health Panel's panel
---@field model table?      UI/MiniHealth's model, nil before the first snapshot
---@field refreshAt number
---@field docked boolean
local Panel = ISPanel:derive("ExtensiveHealthRedoneMiniHealthPanel")

local MiniHealthPanel = { Panel = Panel }

MiniHealthPanel.MOD_ID = "MiniHealthPanel"
MiniHealthPanel.MIN_WIDTH = 96
MiniHealthPanel.GAP = 2
MiniHealthPanel.PAD = 6
MiniHealthPanel.REFRESH_MS = 1000
MiniHealthPanel.CHECK_TICKS = 60

local panel                     -- the one companion panel
local broken = false            -- the host did not look as expected: off for the session

local function modActive()
    local mods = getActivatedMods()
    return mods:contains(MiniHealthPanel.MOD_ID) or mods:contains("\\" .. MiniHealthPanel.MOD_ID)
end

-- Mini Health Panel's handle, a third-party global; nil without the mod or before it has made its panel.
function MiniHealthPanel.host()
    local host = rawget(_G, "mhpHandle")
    if type(host) == "table" and type(host.getX) == "function" and type(host.isVisible) == "function" then
        return host
    end
    return nil
end

local function mirrored(player)
    local state = {}
    for _, name in ipairs(SECTIONS) do
        state[name] = Client.section(player, name)
        if state[name] == nil then
            return nil
        end
    end
    return state
end

-- The player the host shows, or nil (dead, none yet).
local function hostPlayer(host)
    local player = type(host.getPlayer) == "function" and host:getPlayer() or host.player
    if player == nil or player:isDead() then
        return nil
    end
    return player
end

---@param host table
function Panel:new(host)
    local o = ISPanel:new(0, 0, MiniHealthPanel.MIN_WIDTH, 100) --[[@as ExtensiveHealthRedoneMiniHealthPanel]]
    setmetatable(o, self)
    self.__index = self
    o.host = host
    o.refreshAt = 0
    o.docked = true
    o.model = nil
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.6 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end

function Panel:rebuild(player)
    local state = mirrored(player)
    if not state then
        self.model = nil
        return
    end
    self.model = MiniHealth.build({
        state = state,
        firstAid = player:getPerkLevel(Perks.Doctor),
        defs = defs,
        sandbox = Env.sandbox,
        watch = Watch.poweredWorn(player),
    })
    local rowHeight = Draw.SMALL + 3
    local widest = 0
    self.lines = {}
    for _, row in ipairs(self.model.rows) do
        local label, value = getText(row.label), Text.t(row.value)
        self.lines[#self.lines + 1] = { label = label, value = value, color = row.color }
        widest = math.max(widest, Draw.width(label) + 8 + Draw.width(value))
    end
    local title = getText("UI_EHR_Mini_Title")
    self:setWidth(math.max(MiniHealthPanel.MIN_WIDTH, widest + 2 * MiniHealthPanel.PAD, Draw.width(title)
        + 2 * MiniHealthPanel.PAD))
    self:setHeight(MiniHealthPanel.PAD * 2 + rowHeight * (#self.model.rows + 1) + 4)
end

-- Follows the host. Reads of the host are a boundary to another mod: the first failure switches the panel off.
function Panel:update()
    local ok, err = pcall(function()
        local host = self.host
        local player = hostPlayer(host)
        local alpha = tonumber(host.alpha) or 1
        if not player or not host:isVisible() or alpha <= 0 then
            self:setVisible(false)
            return
        end
        self:setVisible(true)
        self.backgroundColor.a = 0.6 * alpha
        self.borderColor.a = alpha
        local now = getTimestampMs()
        if now >= self.refreshAt then
            self.refreshAt = now + MiniHealthPanel.REFRESH_MS
            self:rebuild(player)
        end
        local x, y, right = MiniHealth.dock({ x = host:getX(), y = host:getY(), width = host:getWidth() },
            self:getWidth(), getCore():getScreenWidth(), MiniHealthPanel.GAP)
        self:setX(x)
        self:setY(y)
        self.docked = right
    end)
    if not ok then
        broken = true
        log:warn("Mini Health Panel did not look as expected, the companion is off:", tostring(err))
        self:setVisible(false)
        self:removeFromUIManager()
        panel = nil
    end
end

function Panel:prerender()
    if not self.model then
        return
    end
    local a = self.backgroundColor.a
    self:drawRect(0, 0, self.width, self.height, a, self.backgroundColor.r, self.backgroundColor.g,
        self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g,
        self.borderColor.b)
end

function Panel:render()
    if not self.model then
        return
    end
    local pad = MiniHealthPanel.PAD
    local rowHeight = Draw.SMALL + 3
    local y = pad
    local alpha = self.borderColor.a
    local function colour(name)
        local c = Draw.color(name)
        return { c[1], c[2], c[3], c[4] * alpha }
    end
    Draw.text(self, getText("UI_EHR_Mini_Title"), self.width / 2, y, colour("text"), Draw.FONT_SMALL, nil, "centre")
    y = y + rowHeight
    Draw.rect(self, pad, y, self.width - 2 * pad, 1, Draw.C.dim, 0.5 * alpha)
    y = y + 4
    for _, line in ipairs(self.lines) do
        Draw.text(self, line.label, pad, y, colour("dim"))
        Draw.text(self, line.value, self.width - pad, y, colour(line.color), Draw.FONT_SMALL, nil, "right")
        y = y + rowHeight
    end
end

-- Creating and keeping the panel ---------------------------------------------------------------------------------------

local function create(host)
    local p = Panel:new(host)
    p:initialise()
    p:instantiate()
    p:addToUIManager()
    p:setVisible(false)
    log:info("Mini Health Panel found: the EHR status panel is docked beside it")
    return p
end

local ticks = 0

-- Looks for the host every CHECK_TICKS ticks: it makes its panel when the player is created, and a different handle
-- (a new game in the same session) gets a new companion.
function MiniHealthPanel.tick()
    ticks = ticks + 1
    if ticks < MiniHealthPanel.CHECK_TICKS or broken then
        return
    end
    ticks = 0
    local host = MiniHealthPanel.host()
    if panel and panel.host ~= host then
        panel:removeFromUIManager()
        panel = nil
    end
    if host and not panel and modActive() then
        panel = create(host)
    end
end

-- The companion panel now, or nil (tests).
function MiniHealthPanel.panelForTest()
    return panel
end

Events.OnTick.Add(MiniHealthPanel.tick)

return MiniHealthPanel
