-- The disease handbook window (J, or the Handbook button on the EHR Monitor): the disease index on the left, the
-- selected entry on the right. The content comes from UI/Handbook (pure); this file only draws it.
-- Modelled on vanilla's ISLiteratureUI: an ISCollapsableWindowJoypad, one per local player, removed on close.
--   mouse       click an entry; the wheel scrolls the list or the details under it
--   controller  d-pad up/down picks an entry, the right stick or LB/RB scroll the details, B closes and gives the
--               focus back to whatever opened it
-- It refreshes when the mirror's knowledge section changes (a flyer read with the handbook open) or First Aid levels.
-- Position and size are remembered for player 0 (ISLayoutManager "ehrhandbook", saved with the game).
--
--   Handbook.toggle(playerNum, owner)   -- owner: a UI element to give the joypad focus back to, or nil
--   Handbook.open(playerNum, owner), Handbook.close(playerNum), Handbook.isOpen(playerNum)

require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISPanel"
require "ISUI/ISLayoutManager"

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Model = require "ExtensiveHealthRedone/UI/Handbook"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Draw = require "ExtensiveHealthRedone/Client/Draw"
local Text = require "ExtensiveHealthRedone/Client/Text"

local Handbook = {}

local WIDTH, HEIGHT = 900, 640
local LIST_WIDTH = 326
local ROW_HEIGHT = 76
local ROW_ICON = 52
local DETAIL_ICON = 86
local SCROLL_STEP = 40
local STICK_SPEED = 12          -- px per frame at 30 fps while the right stick is pushed

local BADGE_KNOWN = { 0.18, 0.92, 0.32, 1 }
local BADGE_LOCKED = { 1.0, 0.78, 0.12, 1 }
local BADGE_LETHAL = { 0.95, 0.08, 0.07, 1 }

-- playerNum -> open window
local windows = {}

local function firstAid(player)
    return player:getPerkLevel(Perks.Doctor)
end

-- The details pane ------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneHandbookDetails : ISPanel
---@field entry table?
---@field scroll number
---@field contentHeight number
local Details = ISPanel:derive("ExtensiveHealthRedoneHandbookDetails")

---@return ExtensiveHealthRedoneHandbookDetails
function Details:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height) --[[@as ExtensiveHealthRedoneHandbookDetails]]
    o.background = false
    o.scroll = 0
    o.contentHeight = 0
    return o
end

function Details:setEntry(entry, keepScroll)
    self.entry = entry
    if not keepScroll then
        self.scroll = 0
    end
end

function Details:scrollBy(dy)
    local max = math.max(0, self.contentHeight - self.height)
    self.scroll = math.max(0, math.min(max, self.scroll + dy))
end

function Details:onMouseWheel(del)
    self:scrollBy(del * SCROLL_STEP)
    return true
end

-- Draws a wrapped paragraph from y; returns the y below it.
local function paragraph(ui, text, x, y, w, color)
    local lineH = Draw.SMALL + 3
    for _, line in ipairs(Draw.wrap(text, UIFont.Small, w)) do
        Draw.text(ui, line, x, y, color, UIFont.Small)
        y = y + lineH
    end
    return y
end

function Details:render()
    local e = self.entry
    Draw.rect(self, 0, 0, self.width, self.height, Draw.C.panel)
    Draw.border(self, 0, 0, self.width, self.height, Draw.C.borderDim)
    if not e then
        return
    end
    self:setStencilRect(0, 0, self.width, self.height)
    local pad = 18
    local x, w = pad, self.width - 2 * pad
    local y = pad - self.scroll
    local icon = Draw.texture(e.icon)
    if icon then
        self:drawTextureScaled(icon, x, y, DETAIL_ICON, DETAIL_ICON, e.known and 1 or 0.72, 1, 1, 1)
    end
    local tx = x + DETAIL_ICON + 18
    local tw = self.width - pad - tx
    Draw.text(self, Text.t(e.name), tx, y + 4, e.known and "text" or "dim", UIFont.Large, tw)
    Draw.text(self, Text.t(e.category), tx, y + 4 + Draw.LARGE + 4, "dim", UIFont.Medium, tw)
    local badgeY = y + 4 + Draw.LARGE + Draw.MEDIUM + 14
    Draw.text(self, getText(e.known and "UI_EHR_Codex_KnownUpper" or "UI_EHR_Codex_LockedUpper"), tx, badgeY,
        e.known and BADGE_KNOWN or BADGE_LOCKED, UIFont.Small)
    if e.lethal then
        Draw.text(self, getText("UI_EHR_Codex_LethalRisk"), self.width - pad, badgeY, BADGE_LETHAL, UIFont.Small,
            nil, "right")
    end
    y = math.max(y + DETAIL_ICON, badgeY + Draw.SMALL) + 14
    Draw.rect(self, x, y, w, 1, Draw.C.border, 0.6)
    y = y + 12
    if not e.known then
        Draw.text(self, getText("UI_EHR_Codex_KnowledgeUnavailable"), x, y, "red", UIFont.Medium, w)
        y = y + Draw.MEDIUM + 8
        y = paragraph(self, Text.t(e.locked), x + 8, y, w - 8, "text")
    else
        for _, section in ipairs(e.sections) do
            Draw.text(self, Text.t(section.label), x, y, "red", UIFont.Medium, w)
            y = y + Draw.MEDIUM + 4
            y = paragraph(self, Text.t(section.body), x + 8, y, w - 8, "text")
            y = y + 10
        end
    end
    self.contentHeight = y + self.scroll + pad
    self:clearStencilRect()
    if self.contentHeight > self.height then
        -- A thin scroll indicator on the right edge.
        local trackH = self.height - 8
        local thumbH = math.max(24, trackH * self.height / self.contentHeight)
        local thumbY = 4 + (trackH - thumbH) * self.scroll / (self.contentHeight - self.height)
        Draw.rect(self, self.width - 7, 4, 3, trackH, Draw.C.track)
        Draw.rect(self, self.width - 7, thumbY, 3, thumbH, Draw.C.border)
    end
end

-- The index list ---------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneHandbookList : ISScrollingListBox
local List = ISScrollingListBox:derive("ExtensiveHealthRedoneHandbookList")

function List:doDrawItem(y, item, alt)
    local e = item.item --[[@as table]]
    local h = item.height or self.itemheight
    if y + self:getYScroll() + h < 0 or y + self:getYScroll() >= self.height then
        return y + h
    end
    local w = self.width
    if self.selected == item.index then
        Draw.rect(self, 0, y, w, h - 1, Draw.C.redDark, 0.82)
    else
        Draw.rect(self, 0, y, w, h - 1, Draw.C.panelSoft, alt and 0.24 or 0.38)
    end
    Draw.border(self, 0, y, w, h, Draw.C.borderDim)
    local icon = Draw.texture(e.icon)
    if icon then
        self:drawTextureScaled(icon, 14, y + 12, ROW_ICON, ROW_ICON, e.known and 1 or 0.72, 1, 1, 1)
    end
    local tx = 14 + ROW_ICON + 10
    local statusText = getText(e.known and "UI_EHR_Codex_Known" or "UI_EHR_Codex_Locked")
    local statusW = Draw.width(statusText, UIFont.Small)
    Draw.text(self, Text.t(e.name), tx, y + 14, e.known and "text" or "dim", UIFont.Medium, w - tx - 18)
    Draw.text(self, Text.t(e.category), tx, y + 42, "dim", UIFont.Small, w - tx - statusW - 30)
    Draw.text(self, statusText, w - 18, y + 42, e.known and BADGE_KNOWN or BADGE_LOCKED, UIFont.Small, nil, "right")
    return y + h
end

-- The window -------------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneHandbook : ISCollapsableWindowJoypad
---@field playerNum integer
---@field character IsoPlayer
---@field owner ISUIElement?
---@field list ExtensiveHealthRedoneHandbookList
---@field details ExtensiveHealthRedoneHandbookDetails
---@field model table
---@field firstAid integer
---@field drawJoypadFocus boolean?
local Window = ISCollapsableWindowJoypad:derive("ExtensiveHealthRedoneHandbook")

---@param x number
---@param y number
---@param playerNum integer
---@param character IsoPlayer
---@param owner ISUIElement?
---@return ExtensiveHealthRedoneHandbook
function Window:new(x, y, playerNum, character, owner)
    local o = ISCollapsableWindowJoypad.new(self, x, y, WIDTH, HEIGHT) --[[@as ExtensiveHealthRedoneHandbook]]
    o:setTitle(getText("UI_EHR_DiseaseHandbook_Title"))
    o.character = character
    o.playerNum = playerNum
    o.owner = owner
    o.minimumWidth = 720
    o.minimumHeight = 420
    o:setResizable(true)
    return o
end

local function headerY(self)
    return self:titleBarHeight() + Draw.PAD
end

local function sectionHeight()
    return Draw.MEDIUM + 8
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local pad = Draw.PAD + 4
    local top = headerY(self) + sectionHeight() + 6
    local bottom = self:resizeWidgetHeight() + pad
    self.list = List:new(pad, top, LIST_WIDTH, self.height - top - bottom) --[[@as ExtensiveHealthRedoneHandbookList]]
    self.list:initialise()
    self.list.itemheight = ROW_HEIGHT
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list:setAnchorBottom(true)
    self.list:setOnMouseDownFunction(self, Window.onSelect)
    self:addChild(self.list)
    local dx = pad + LIST_WIDTH + 12
    self.details = Details:new(dx, top, self.width - dx - pad, self.height - top - bottom)
    self.details:initialise()
    self.details:setAnchorRight(true)
    self.details:setAnchorBottom(true)
    self:addChild(self.details)
    self:refresh()
end

-- Rebuilds the model from the mirror, keeping the selected entry.
function Window:refresh()
    local selectedId = self.details.entry and self.details.entry.id
    local knowledge = Client.section(self.character, "knowledge")
    self.firstAid = firstAid(self.character)
    self.model = Model.build(knowledge, self.firstAid, defs, Env.sandbox)
    local scroll = self.list:getYScroll()
    self.list:clear()
    local selected = 1
    for i, e in ipairs(self.model.entries) do
        self.list:addItem(e.id, e)
        if e.id == selectedId then
            selected = i
        end
    end
    self.list.selected = selected
    self.list:setYScroll(scroll)
    local entry = self.model.entries[selected]
    self.details:setEntry(entry, entry and entry.id == selectedId)
end

function Window:onSelect(entry)
    self.details:setEntry(entry)
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    local player = getSpecificPlayer(self.playerNum)
    if player ~= self.character or not player or player:isDead() then
        Handbook.close(self.playerNum)
        return
    end
    if firstAid(player) ~= self.firstAid then
        self:refresh()
    end
end

function Window:render()
    ISCollapsableWindowJoypad.render(self)
    if self.isCollapsed then
        return
    end
    local pad = Draw.PAD + 4
    local y = headerY(self)
    Draw.section(self, getText("UI_EHR_DiseaseHandbook_Index"), pad, y, LIST_WIDTH)
    ---@diagnostic disable-next-line: redundant-parameter
    local count = getText("UI_EHR_DiseaseHandbook_KnownCount", self.model.known, self.model.total)
    Draw.text(self, count, pad + LIST_WIDTH - 8, y + 4 + (Draw.MEDIUM - Draw.SMALL) / 2, "green", UIFont.Small, nil,
        "right")
    local dx = pad + LIST_WIDTH + 12
    Draw.section(self, getText("UI_EHR_DiseaseHandbook_Details"), dx, y, self.width - dx - pad)
    if self.drawJoypadFocus then
        self:drawRectBorder(0, 0, self:getWidth(), self:getHeight(), 0.4, 0.2, 1.0, 1.0)
        self:drawRectBorder(1, 1, self:getWidth() - 2, self:getHeight() - 2, 0.4, 0.2, 1.0, 1.0)
    end
end

function Window:update()
    ISCollapsableWindowJoypad.update(self)
    if self.joyfocus and self.joyfocus.id and self.joyfocus.id >= 0 then
        local axis = getJoypadAimingAxisY(self.joyfocus.id)
        if math.abs(axis) > 0.75 then
            local step = STICK_SPEED * UIManager.getMillisSinceLastRender() / 33.3
            self.details:scrollBy(axis > 0 and step or -step)
        end
    end
end

function Window:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    self.drawJoypadFocus = true
end

function Window:onLoseJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onLoseJoypadFocus(self, joypadData)
    self.drawJoypadFocus = false
end

function Window:onJoypadDown(button)
    if button == Joypad.BButton then
        Handbook.close(self.playerNum)
    elseif button == Joypad.LBumper then
        self.details:scrollBy(-(self.details.height - SCROLL_STEP))
    elseif button == Joypad.RBumper then
        self.details:scrollBy(self.details.height - SCROLL_STEP)
    end
end

function Window:onJoypadDirUp()
    self.list:onJoypadDirUp()
end

function Window:onJoypadDirDown()
    self.list:onJoypadDirDown()
end

function Window:close()
    Handbook.close(self.playerNum)
end

-- Only the geometry is remembered: a saved "visible" must not reopen or hide the handbook, and it is never collapsed.
function Window:RestoreLayout(_, layout)
    ISLayoutManager.DefaultRestoreWindow(self, { name = layout.name, x = layout.x, y = layout.y,
        width = layout.width, height = layout.height })
end

function Window:SaveLayout(_, layout)
    layout.x = self:getX()
    layout.y = self:getY()
    layout.width = self:getWidth()
    layout.height = self:getHeight()
end

-- API --------------------------------------------------------------------------------------------------------------

function Handbook.isOpen(playerNum)
    return windows[playerNum] ~= nil
end

function Handbook.open(playerNum, owner)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then
        return nil
    end
    local window = windows[playerNum]
    if not window then
        local x = getPlayerScreenLeft(playerNum) + (getPlayerScreenWidth(playerNum) - WIDTH) / 2
        local y = getPlayerScreenTop(playerNum) + (getPlayerScreenHeight(playerNum) - HEIGHT) / 2
        window = Window:new(math.max(0, x), math.max(0, y), playerNum, player, owner)
        window:initialise()
        window:instantiate()
        windows[playerNum] = window
        if playerNum == 0 then
            ISLayoutManager.RegisterWindow("ehrhandbook", Window, window)
        end
    else
        window.owner = owner or window.owner
    end
    window:setVisible(true)
    window:addToUIManager()
    window:bringToTop()
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, window)
    end
    return window
end

function Handbook.close(playerNum)
    local window = windows[playerNum]
    if not window then
        return
    end
    windows[playerNum] = nil
    window:setVisible(false)
    window:removeFromUIManager()
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, window.owner)
    end
end

function Handbook.toggle(playerNum, owner)
    if windows[playerNum] then
        Handbook.close(playerNum)
    else
        Handbook.open(playerNum, owner)
    end
end

-- A flyer read (or a radio broadcast heard) with the handbook open unlocks the entry at once.
Client.onChange(function(ownerKey, sections)
    local changed = false
    for _, name in ipairs(sections) do
        if name == "knowledge" then
            changed = true
        end
    end
    if not changed then
        return
    end
    for _, window in pairs(windows) do
        if PlayerKey.of(window.character) == ownerKey then
            window:refresh()
        end
    end
end)

Events.OnPlayerDeath.Add(function(player)
    for playerNum, window in pairs(windows) do
        if window.character == player then
            Handbook.close(playerNum)
        end
    end
end)

return Handbook
