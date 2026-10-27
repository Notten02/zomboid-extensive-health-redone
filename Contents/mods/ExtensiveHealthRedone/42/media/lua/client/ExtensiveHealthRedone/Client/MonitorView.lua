-- The EHR Monitor tab of vanilla's character window (Client/CharacterWindow adds it). It draws UI/Monitor's model:
-- blood (with a powered Medical Monitor Watch), the overview (healing, body and room temperature), the body diagram
-- with per-part statuses and the wound-infection hint, and, expanded, the details column: conditions, medication,
-- overdose, side effects and drug interactions.
--
-- Compact (blood, overview, body) or expanded (plus details) follows the OpenHealthPanelCompact mod option each time
-- the tab is opened; the +/- button switches. The model is rebuilt when the mirror changes and at most once a real
-- second otherwise; drawing only reads it. Treatment is vanilla's, through the window's own Health panel (so other mods'
-- additions apply too): right click on a part of the diagram opens vanilla's treatment menu for it in place, items
-- dragged from the inventory onto a part treat it as on vanilla's Health tab, and A on a controller opens that tab.
--
-- Controller: B closes, LB/RB switch tabs, d-pad up/down picks a body part, left/right scroll the details, X switches
-- compact/expanded, Y opens the handbook.
--
-- The same view draws another player's Monitor in an exam window (Client/Exam): there a source replaces the local
-- mirror. MonitorView:new(x, y, playerNum, source) with
--   source = { subject = IsoPlayer (the diagram's body shape), read = function() return model, overall end,
--              health = function(bodyPartType) return ISHealthPanel, BodyPart end (optional) }
-- reads a finished model (built by the server with the doctor's knowledge) instead of building one, and the diagram
-- treats through source.health's panel (the patient's), never the doctor's own; without it, it does not treat. The
-- window owns the controller then.

require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/BodyParts/ISBodyPartPanel"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Watch = require "ExtensiveHealthRedone/Game/Watch"
local IndoorClimate = require "ExtensiveHealthRedone/Game/IndoorClimate"
local BodyFacts = require "ExtensiveHealthRedone/Game/BodyFacts"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Monitor = require "ExtensiveHealthRedone/UI/Monitor"
local BodyStatus = require "ExtensiveHealthRedone/UI/BodyStatus"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Options = require "ExtensiveHealthRedone/Client/Options"
local Draw = require "ExtensiveHealthRedone/Client/Draw"
local Text = require "ExtensiveHealthRedone/Client/Text"
local Handbook = require "ExtensiveHealthRedone/Client/Handbook"

local t = Text.t
local C = Draw.C

local PAD = Draw.PAD
local LEFT_W = 420
local RIGHT_W = 560
local HEIGHT = 640
local DIAGRAM_W, DIAGRAM_H = 123, 302
local REBUILD_MS = 1000

-- The sections the model reads.
local SECTIONS = { "identity", "knowledge", "blood", "body", "wounds", "conditions", "exposure", "meds", "knox" }

-- The diagram's colour scheme by BodyStatus value: healthy, green, yellow, orange, purple, red.
local SCHEME = {
    { 0.00, 0.76, 0.86, 0.80 }, { 0.20, C.green[1], C.green[2], C.green[3] },
    { 0.40, C.yellow[1], C.yellow[2], C.yellow[3] }, { 0.60, C.orange[1], C.orange[2], C.orange[3] },
    { 0.80, C.purple[1], C.purple[2], C.purple[3] }, { 1.00, C.red[1], C.red[2], C.red[3] },
}

-- Body parts in the order the d-pad walks them: head to feet.
local WALK = { "Head", "Neck", "Torso_Upper", "Torso_Lower", "Groin", "UpperArm_L", "UpperArm_R", "ForeArm_L",
    "ForeArm_R", "Hand_L", "Hand_R", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R" }

-- The diagram: vanilla's ISBodyPartPanel, read-only; right click on a part opens vanilla's treatment menu for it, and
-- items dropped on a part treat it.
---@class ExtensiveHealthRedoneMonitorDiagram : ISBodyPartPanel
local Diagram = ISBodyPartPanel:derive("ExtensiveHealthRedoneMonitorDiagram")

function Diagram:onRightMouseUp(x, y)
    ISBodyPartPanel.onRightMouseUp(self, x, y)
    local bp = self:getPartForCoordinate(x, y)
    if bp then
        self.functionTarget:treat(bp.bodyPartType, self:getAbsoluteX() + x, self:getAbsoluteY() + y)
    end
end

function Diagram:onMouseUp(x, y)
    ISBodyPartPanel.onMouseUp(self, x, y)
    ---@diagnostic disable-next-line: undefined-field
    local dragging = ISMouseDrag.dragging
    local bp = dragging and self:getPartForCoordinate(x, y)
    if bp then
        self.functionTarget:treatWith(bp.bodyPartType, ISInventoryPane.getActualItems(dragging))
    end
end

---@class ExtensiveHealthRedoneMonitorView : ISPanelJoypad
---@field playerNum integer
---@field expanded boolean
---@field scrollY number
---@field contentH number
---@field leftH number?    the left column's height as last drawn (the view grows to fit it)
---@field builtAt number
---@field selected string?
---@field model table      nil before the first snapshot (render checks)
---@field overall number?
---@field diagram ExtensiveHealthRedoneMonitorDiagram
---@field expandButton ISButton
---@field handbookButton ISButton
---@field source table?    nil: the local player's own Monitor (the mirror); else a provided model (an exam)
---@field headerButtons ISButton[]
local MonitorView = ISPanelJoypad:derive("ExtensiveHealthRedoneMonitorView")

-- Reading the game ------------------------------------------------------------------------------------------------

-- The mirror sections, or nil before the first snapshot.
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

-- Construction ----------------------------------------------------------------------------------------------------------

---@param playerNum integer
---@param source table?
---@return ExtensiveHealthRedoneMonitorView
function MonitorView:new(x, y, playerNum, source)
    local o = ISPanelJoypad.new(self, x, y, LEFT_W, HEIGHT) --[[@as ExtensiveHealthRedoneMonitorView]]
    o.playerNum = playerNum
    o.source = source
    o.headerButtons = {}
    o.background = false
    o.expanded = false
    o.scrollY = 0
    o.contentH = 0
    o.builtAt = 0
    o.selected = nil
    return o
end

function MonitorView:createChildren()
    ISPanelJoypad.createChildren(self)
    local player = self.source and self.source.subject or getSpecificPlayer(self.playerNum)
    self.diagram = Diagram:new(player, PAD, 0, self, MonitorView.onPartSelected) --[[@as ExtensiveHealthRedoneMonitorDiagram]]
    self.diagram.minValue = 0
    self.diagram.maxValue = 1
    local scheme = {}
    for i, s in ipairs(SCHEME) do
        scheme[i] = { val = s[1], color = Color.new(s[2], s[3], s[4], 1) }
    end
    self.diagram:initialise()
    self.diagram:setColorScheme(scheme)
    self.diagram:setAlphas(0.62, 1.0, 1.0, 0.38, 0.38)
    self.diagram:enableNodes("media/ui/BodyParts/bps_node_diamond", "media/ui/BodyParts/bps_node_diamond_outline")
    self:addChild(self.diagram)

    local bh = Draw.SMALL + 6
    self.expandButton = ISButton:new(0, PAD, bh + 6, bh, "+", self, MonitorView.toggleExpanded)
    self.expandButton:initialise()
    Draw.styleButton(self.expandButton)
    self:addChild(self.expandButton)
    local label = getText("UI_EHR_HandbookButton")
    self.handbookButton = ISButton:new(0, PAD, Draw.width(label) + 16, bh, label, self, MonitorView.openHandbook)
    self.handbookButton:initialise()
    Draw.styleButton(self.handbookButton)
    self:addChild(self.handbookButton)
end

-- An extra button in the header, left of the handbook button (the exam window's Administer).
function MonitorView:addHeaderButton(button)
    Draw.styleButton(button)
    button:setY(PAD)
    self.headerButtons[#self.headerButtons + 1] = button
    self:addChild(button)
end

-- Called by Client/CharacterWindow whenever the tab is opened from a hotkey or the heart button.
function MonitorView:onOpened()
    self.expanded = Options.get("OpenHealthPanelCompact") == false
    self.scrollY = 0
    self.builtAt = 0
end

function MonitorView:toggleExpanded()
    self.expanded = not self.expanded
    self.scrollY = 0
end

function MonitorView:openHandbook()
    Handbook.toggle(self.playerNum, self)
end

-- Vanilla's Health tab (treatment lives there; option B). Not from an exam: that would be the doctor's own.
function MonitorView:openHealth()
    if self.source then
        return
    end
    local window = getPlayerInfoPanel(self.playerNum)
    if window then
        window.panel:activateView(xpSystemText.health)
        if JoypadState.players[self.playerNum + 1] then
            setJoypadFocus(self.playerNum, window.panel:getActiveView())
        end
    end
end

-- The vanilla Health panel and the patient's body part for treatment from the diagram: the character window's own, or
-- in an exam the one the source provides (nil: none).
function MonitorView:healthPart(bodyPartType)
    if self.source then
        if self.source.health then
            return self.source.health(bodyPartType)
        end
        return nil
    end
    local window = getPlayerInfoPanel(self.playerNum)
    local health = window and window.healthView
    if not health then
        return nil
    end
    return health, health:getPatient():getBodyDamage():getBodyPart(bodyPartType)
end

-- Vanilla's treatment menu for one body part at a screen position, as its Health tab's list opens it on right click
-- (not while the game is paused unless in debug).
function MonitorView:treat(bodyPartType, screenX, screenY)
    local health, bodyPart = self:healthPart(bodyPartType)
    if health and bodyPart and (UIManager.getSpeedControls():getCurrentGameSpeed() ~= 0 or getDebug()) then
        health:doBodyPartContextMenu(bodyPart, screenX - health:getAbsoluteX(), screenY - health:getAbsoluteY())
    end
end

-- Items dropped on one body part, as on vanilla's Health tab: the first treatment that takes them runs.
function MonitorView:treatWith(bodyPartType, items)
    local health, bodyPart = self:healthPart(bodyPartType)
    if health and bodyPart then
        health:dropItemsOnBodyPart(bodyPart, items)
    end
end

function MonitorView:onPartSelected(bp)
    self.selected = bp and BodyPartType.ToString(bp.bodyPartType) or nil
end

-- The model ---------------------------------------------------------------------------------------------------------------

-- Sets the diagram's colours from the model's parts.
function MonitorView:paintDiagram()
    for _, name in ipairs(BodyParts.names) do
        local part = self.model.parts[name]
        if part then
            self.diagram:setValue(BodyPartType.FromString(name), part.value, true)
        end
    end
end

function MonitorView:rebuild()
    if self.source then
        self.model, self.overall = self.source.read()
        if self.model then
            self:paintDiagram()
        end
        return
    end
    local player = getSpecificPlayer(self.playerNum)
    local state = player and mirrored(player)
    if not state then
        self.model = nil
        return
    end
    self.model = Monitor.build({
        state = state,
        firstAid = player:getPerkLevel(Perks.Doctor),
        defs = defs,
        sandbox = Env.sandbox,
        watch = Watch.poweredWorn(player),
        bodyC = player:getStats():get(CharacterStat.TEMPERATURE),
        airC = IndoorClimate.sample(player),
        parts = BodyFacts.read(player),
    })
    self.overall = player:getBodyDamage():getOverallBodyHealth()
    self:paintDiagram()
end

function MonitorView:markStale()
    self.builtAt = 0
end

-- Everything is drawn here, not in render(): the game draws a panel's children (the body diagram, the buttons) after
-- its prerender and before its render, so drawing in render would cover them.
function MonitorView:prerender()
    ISPanelJoypad.prerender(self)
    local now = getTimestampMs()
    if now - self.builtAt >= REBUILD_MS then
        self.builtAt = now
        self:rebuild()
    end
    self:draw()
end

-- Drawing -------------------------------------------------------------------------------------------------------------------

function MonitorView:drawHeader(w)
    local m = self.model
    local y = PAD
    if m and m.bloodType then
        Draw.text(self, getText("UI_EHR_LabelValue", getText("UI_EHR_BloodTypeLabel"), m.bloodType), PAD, y + 3, "green",
            UIFont.Small)
    end
    self.expandButton:setTitle(self.expanded and "-" or "+")
    self.expandButton:setX(w - PAD - self.expandButton:getWidth())
    self.handbookButton:setX(self.expandButton:getX() - 6 - self.handbookButton:getWidth())
    local left = self.handbookButton:getX()
    for _, button in ipairs(self.headerButtons) do
        button:setX(left - 6 - button:getWidth())
        left = button:getX()
    end
    return y + self.expandButton:getHeight() + 8
end

function MonitorView:drawBlood(x, y, w)
    local b = self.model.blood
    local h = Draw.MEDIUM + 40 + Draw.SMALL + 2 * PAD
    local top = Draw.frame(self, x, y, w, h, getText("UI_EHR_BloodComposition"))
    local icon = Draw.texture(b.visible and b.bag or "Item_EhrWatch")
    local iconW = 32
    if icon then
        self:drawTextureScaledAspect(icon, x + PAD, top, iconW, 40, b.visible and 1 or 0.42, 1, 1, 1)
    end
    local barX = x + PAD + iconW + PAD
    local percentW = Draw.width("100%", UIFont.Large) + 4
    local barW = w - (barX - x) - PAD - percentW - 6
    if b.visible then
        Draw.bar(self, barX, top + 6, barW, 22, b.percent / 100, "red")
        if b.saline > 0 then
            -- Saline is part of the volume: its share of the red fill, at its right end.
            local fill = (barW - 2) * b.percent / 100
            local salineW = math.max(1, math.floor(fill * b.salineShare))
            self:drawRect(barX + 1 + fill - salineW, top + 7, salineW, 20, 0.85, C.blue[1], C.blue[2], C.blue[3])
        end
        Draw.text(self, string.format("%d%%", math.floor(b.percent + 0.5)), x + w - PAD, top + 2, "red", UIFont.Large,
            nil, "right")
        local line = string.format("%d / %d mL", b.ml, b.max) .. "   " .. t(b.salineText) .. "   " .. t(b.salineStatus)
        Draw.text(self, line, barX, top + 34, "blue", UIFont.Small, w - (barX - x) - PAD)
    else
        Draw.bar(self, barX, top + 6, barW, 22, 0, "red")
        Draw.text(self, getText("UI_EHR_MedicalWatchRequired"), barX + barW / 2, top + 9, "dim", UIFont.Small, barW,
            "centre")
    end
    return y + h + 8
end

function MonitorView:drawOverview(x, y, w)
    local m = self.model
    local lines = {}
    local h = m.healing
    lines[#lines + 1] = { t(h.text), h.blocked and "orange" or "green" }
    if h.reason then
        lines[#lines + 1] = { getText("UI_EHR_LabelValue", getText("UI_EHR_ReasonLabel"), t(h.reason)), "dim" }
    end
    local temps = {}
    if m.temperature.body then
        temps[#temps + 1] = t(m.temperature.body)
    end
    if m.temperature.air then
        temps[#temps + 1] = t(m.temperature.air)
    end
    if #temps > 0 then
        lines[#lines + 1] = { table.concat(temps, "   "), "text" }
    end
    local height = Draw.MEDIUM + 18 + #lines * (Draw.SMALL + 2) + PAD
    local top = Draw.frame(self, x, y, w, height, getText("UI_EHR_Overview"), Draw.texture("EHR_Overview"))
    for i, line in ipairs(lines) do
        Draw.text(self, line[1], x + PAD, top + (i - 1) * (Draw.SMALL + 2), line[2], UIFont.Small, w - 2 * PAD)
    end
    return y + height + 8
end

function MonitorView:drawBody(x, y, w)
    local height = Draw.MEDIUM + 18 + 26 + DIAGRAM_H + PAD
    local top = Draw.frame(self, x, y, w, height, getText("UI_EHR_BodyStatus"), Draw.texture("EHR_BodyStatus"))
    local overall = math.max(0, math.min(100, self.overall or 100))
    local color = overall >= 80 and "green" or (overall >= 50 and "yellow" or "red")
    Draw.bar(self, x + PAD, top, w - 2 * PAD - 50, 16, overall / 100, color)
    Draw.text(self, string.format("%d%%", math.floor(overall + 0.5)), x + w - PAD, top, color, UIFont.Small, nil, "right")
    local dy = top + 26
    self.diagram:setX(x + PAD)
    self.diagram:setY(dy)

    -- Legend, then the selected part.
    local lx = x + PAD + DIAGRAM_W + 16
    local lw = w - (lx - x) - PAD
    local ly = dy
    for _, entry in ipairs(BodyStatus.LEGEND) do
        Draw.swatch(self, lx, ly + 4, entry.color)
        Draw.text(self, getText(entry.label), lx + 14, ly, "dim", UIFont.Small, lw - 14)
        ly = ly + Draw.SMALL + 2
    end
    ly = ly + 10
    local name = self.selected
    if not name then
        Draw.text(self, getText("UI_EHR_HoverBodyPart"), lx, ly, "dim", UIFont.Small, lw)
        return y + height + 8
    end
    Draw.text(self, BodyPartType.getDisplayName(BodyPartType.FromString(name)), lx, ly, "green", UIFont.Medium, lw)
    ly = ly + Draw.MEDIUM + 4
    local part = self.model.parts[name]
    if #part.statuses == 0 then
        Draw.text(self, getText("UI_EHR_NoActiveIssues"), lx, ly, "dim", UIFont.Small, lw)
        ly = ly + Draw.SMALL + 2
    end
    local maxY = dy + DIAGRAM_H - Draw.SMALL
    for i, status in ipairs(part.statuses) do
        if ly > maxY - (part.hint and 2 * Draw.SMALL or 0) then
            Draw.text(self, getText("UI_EHR_MoreStatuses", #part.statuses - i + 1), lx, ly, "dim", UIFont.Small, lw)
            ly = ly + Draw.SMALL + 2
            break
        end
        Draw.swatch(self, lx, ly + 4, status.color)
        Draw.text(self, t(status.label), lx + 14, ly, status.color, UIFont.Small, lw - 14)
        ly = ly + Draw.SMALL + 2
    end
    if part.hint then
        for _, line in ipairs(Draw.wrap(t(part.hint), UIFont.Small, lw)) do
            Draw.text(self, line, lx, ly + 4, "yellow", UIFont.Small)
            ly = ly + Draw.SMALL
        end
    end
    return y + height + 8
end

-- One condition row; returns its height.
function MonitorView:drawCondition(row, x, y, w)
    local iconS = 48
    local tx = x + PAD + iconS + PAD
    local tw = w - (tx - x) - PAD
    local h = PAD + Draw.MEDIUM + (Draw.SMALL + 2) * (row.description and 2 or 1) + 16
    Draw.rect(self, x, y, w, h, C.panelSoft, 0.48)
    Draw.border(self, x, y, w, h, C.borderDim)
    local icon = Draw.texture(row.icon)
    if icon then
        self:drawTextureScaledAspect(icon, x + PAD, y + (h - iconS) / 2, iconS, iconS, 1, 1, 1, 1)
    end
    local statusW = 0
    if row.status then
        local s = t(row.status)
        statusW = Draw.width(s) + PAD
        Draw.text(self, s, x + w - PAD, y + PAD, row.statusColor, UIFont.Small, nil, "right")
    end
    Draw.text(self, t(row.name), tx, y + 6, row.known and "text" or "dim", UIFont.Medium, tw - statusW)
    local ly = y + 6 + Draw.MEDIUM + 2
    if row.detail then
        Draw.text(self, t(row.detail), tx, ly, row.detailColor or "dim", UIFont.Small, tw - 50)
    end
    if row.progressText then
        Draw.text(self, t(row.progressText), x + w - PAD, ly, "dim", UIFont.Small, nil, "right")
    end
    if row.description then
        ly = ly + Draw.SMALL + 2
        Draw.text(self, t(row.description), tx, ly, row.descriptionColor or "dim", UIFont.Small, tw)
    end
    Draw.bar(self, tx, y + h - 10, tw, 5, row.progress or 0, row.exposure and (row.detailColor or "yellow") or "green")
    return h
end

local function itemIcon(fullType)
    local script = fullType and getScriptManager():FindItem(fullType)
    local icon = script and script:getIcon()
    return icon and Draw.texture("Item_" .. icon) or nil
end

function MonitorView:drawMedication(row, x, y, w)
    local iconS = 32
    local tx = x + PAD + iconS + PAD
    local tw = w - (tx - x) - PAD
    local h = 8 + Draw.SMALL * (row.doses and 2 or 1) + 4 + 14
    Draw.rect(self, x, y, w, h, C.panelSoft, 0.32)
    Draw.border(self, x, y, w, h, C.borderDim)
    local icon = itemIcon(row.item)
    if icon then
        self:drawTextureScaledAspect(icon, x + PAD, y + (h - iconS) / 2, iconS, iconS, 1, 1, 1, 1)
    end
    local top = t(row.top)
    local topW = Draw.width(top) + PAD
    Draw.text(self, t(row.name) .. "  (" .. t(row.tier) .. ")", tx, y + 6, "text", UIFont.Small, tw - topW)
    Draw.text(self, top, x + w - PAD, y + 6, row.topColor, UIFont.Small, nil, "right")
    if row.doses then
        local ly = y + 6 + Draw.SMALL + 2
        Draw.text(self, t(row.doses), tx, ly, "dim", UIFont.Small)
        if row.schedule then
            Draw.text(self, t(row.schedule), x + w - PAD, ly, row.scheduleColor, UIFont.Small, nil, "right")
        end
    end
    Draw.bar(self, tx, y + h - 9, tw, 5, row.progress or 0, "green")
    return h
end

-- A simple "name ... time" line; returns its height.
function MonitorView:drawTimedLine(row, x, y, w, color)
    local left = row.left and t(row.left) or ""
    Draw.text(self, t(row.name), x + PAD, y, color, UIFont.Small, w - 2 * PAD - Draw.width(left) - PAD)
    Draw.text(self, left, x + w - PAD, y, "dim", UIFont.Small, nil, "right")
    return Draw.SMALL + 4
end

-- The details column, drawn at an offset (scrolling); returns the content height.
function MonitorView:drawDetails(x, y, w)
    local m = self.model
    local start = y
    y = Draw.section(self, getText("UI_EHR_ActiveConditions"), x, y, w)
    if #m.conditions == 0 then
        Draw.text(self, getText("UI_EHR_NoConditions"), x + PAD, y, "green", UIFont.Medium)
        y = y + Draw.MEDIUM + 8
    end
    for _, row in ipairs(m.conditions) do
        y = y + self:drawCondition(row, x, y, w) + 6
    end
    y = Draw.section(self, getText("UI_EHR_ActiveMedications"), x, y + 4, w)
    if m.overdose then
        y = y + self:drawTimedLine(m.overdose, x, y, w, "red")
    end
    if #m.medications == 0 then
        Draw.text(self, getText("UI_EHR_NoMedications"), x + PAD, y, "dim", UIFont.Medium)
        y = y + Draw.MEDIUM + 8
    end
    for _, row in ipairs(m.medications) do
        y = y + self:drawMedication(row, x, y, w) + 6
    end
    y = Draw.section(self, getText("UI_EHR_SideEffects"), x, y + 4, w)
    if #m.sideEffects == 0 then
        Draw.text(self, getText("UI_EHR_NoSideEffects"), x + PAD, y, "dim", UIFont.Medium)
        y = y + Draw.MEDIUM + 8
    end
    for _, row in ipairs(m.sideEffects) do
        y = y + self:drawTimedLine(row, x, y, w, "yellow")
    end
    if #m.interactions > 0 then
        y = Draw.section(self, getText("UI_EHR_DrugInteractions"), x, y + 4, w)
        for _, line in ipairs(m.interactions) do
            for _, wrapped in ipairs(Draw.wrap(t(line), UIFont.Small, w - 2 * PAD)) do
                Draw.text(self, wrapped, x + PAD, y, "orange", UIFont.Small)
                y = y + Draw.SMALL + 2
            end
        end
    end
    return y - start
end

function MonitorView:draw()
    local w = math.max(self.expanded and (LEFT_W + RIGHT_W + PAD) or LEFT_W, Draw.tabsWidth(self))
    -- At least HEIGHT, and tall enough for the left column as last drawn: its boxes grow with the font sizes and the
    -- overview's lines, and a fixed height cut off the bottom of the body diagram (issue #14).
    local h = math.max(HEIGHT, self.leftH or 0)
    self:setWidthAndParentWidth(w)
    self:setHeightAndParentHeight(h)
    Draw.fitTabs(self)
    Draw.rect(self, 0, 0, self.width, self.height, C.background)
    if not self.model then
        self.diagram:setVisible(false)
        Draw.text(self, getText("UI_EHR_Monitor_Waiting"), self.width / 2, h / 2, "dim", UIFont.Medium, nil,
            "centre")
        return
    end
    self.diagram:setVisible(true)
    local y = self:drawHeader(w)
    -- Compact: the boxes take the whole width (the window is at least as wide as its tabs). Expanded: a fixed left
    -- column and the details in the rest.
    local leftW = (self.expanded and LEFT_W or w) - 2 * PAD
    local rightW = w - LEFT_W - PAD
    y = self:drawBlood(PAD, y, leftW)
    y = self:drawOverview(PAD, y, leftW)
    -- drawBody's bottom includes the 8 gap before a next box; the view ends PAD below the box instead.
    self.leftH = self:drawBody(PAD, y, leftW) - 8 + PAD
    if self.expanded then
        local rx = LEFT_W
        local top = self.expandButton:getY() + self.expandButton:getHeight() + 8
        local viewH = h - top - PAD
        self:setStencilRect(rx, top, rightW, viewH)
        self.contentH = self:drawDetails(rx, top - self.scrollY, rightW)
        self:clearStencilRect()
        local maxScroll = math.max(0, self.contentH - viewH)
        self.scrollY = math.max(0, math.min(self.scrollY, maxScroll))
        if maxScroll > 0 then
            local thumbH = math.max(32, viewH * viewH / self.contentH)
            local thumbY = top + (viewH - thumbH) * self.scrollY / maxScroll
            Draw.rect(self, rx + rightW - 4, thumbY, 4, thumbH, C.border, 0.8)
        end
    end
end

-- Input -----------------------------------------------------------------------------------------------------------------------

function MonitorView:scroll(dy)
    self.scrollY = math.max(0, self.scrollY + dy)
end

function MonitorView:onMouseWheel(del)
    if self.expanded and self:getMouseX() >= LEFT_W then
        self:scroll(del * 40)
        return true
    end
    return false
end

-- Walks the d-pad selection through the body parts.
function MonitorView:stepPart(step)
    local index = 0
    for i, name in ipairs(WALK) do
        if name == self.selected then
            index = i
        end
    end
    index = ((index - 1 + step) % #WALK) + 1
    self.selected = WALK[index]
    for _, bp in ipairs(self.diagram.bps or {}) do
        if BodyPartType.ToString(bp.bodyPartType) == self.selected then
            ---@diagnostic disable-next-line: assign-type-mismatch
            self.diagram.selectedBp = bp
            self.diagram.lockedSelection = true
        end
    end
end

function MonitorView:onJoypadDown(button)
    local window = getPlayerInfoPanel(self.playerNum)
    if button == Joypad.BButton then
        if window then
            window:toggleView(getText("UI_EHR_Tab_EHR"))
        end
        setJoypadFocus(self.playerNum, nil)
    elseif button == Joypad.LBumper or button == Joypad.RBumper then
        if window then
            window:onJoypadDown(button)
        end
    elseif button == Joypad.AButton then
        self:openHealth()
    elseif button == Joypad.XButton then
        self:toggleExpanded()
    elseif button == Joypad.YButton then
        self:openHandbook()
    end
end

function MonitorView:onJoypadDirUp()
    self:stepPart(-1)
end

function MonitorView:onJoypadDirDown()
    self:stepPart(1)
end

function MonitorView:onJoypadDirLeft()
    self:scroll(-60)
end

function MonitorView:onJoypadDirRight()
    self:scroll(60)
end

return MonitorView
