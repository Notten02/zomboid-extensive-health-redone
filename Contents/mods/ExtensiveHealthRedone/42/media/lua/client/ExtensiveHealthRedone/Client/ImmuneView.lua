-- The Immune System tab of vanilla's character window (Client/CharacterWindow adds it while ImmunitySystemEnabled is
-- on). It draws UI/Immune's model in v0.9's layout: score, band, bar with the target marker, trend, target and
-- infection risk on top; the six factors on the lower left; dirtiness, bloodiness, the hygiene penalty, the current
-- pressures (as many as fit) and the system state on the lower right.
-- Controller: B closes, LB/RB switch tabs.

require "ISUI/ISPanelJoypad"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Immune = require "ExtensiveHealthRedone/UI/Immune"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Draw = require "ExtensiveHealthRedone/Client/Draw"
local Text = require "ExtensiveHealthRedone/Client/Text"

local t = Text.t
local C = Draw.C

local PAD = Draw.PAD
local WIDTH = 640
local HEIGHT = 600

---@class ExtensiveHealthRedoneImmuneView : ISPanelJoypad
---@field playerNum integer
local ImmuneView = ISPanelJoypad:derive("ExtensiveHealthRedoneImmuneView")

---@param playerNum integer
---@return ExtensiveHealthRedoneImmuneView
function ImmuneView:new(x, y, playerNum)
    local o = ISPanelJoypad.new(self, x, y, WIDTH, HEIGHT) --[[@as ExtensiveHealthRedoneImmuneView]]
    o.playerNum = playerNum
    o.background = false
    return o
end

function ImmuneView:onOpened()
end

function ImmuneView:drawTop(m, x, y, w)
    local h = 150
    local top = Draw.frame(self, x, y, w, h, getText("UI_EHR_Immunity_Title"))
    Draw.text(self, t(m.scoreText), x + PAD + 8, top, m.color, UIFont.Large)
    Draw.text(self, t(m.band), x + w - PAD - 8, top + 4, m.color, UIFont.Medium, nil, "right")
    if m.awaiting then
        Draw.text(self, getText("UI_EHR_Immunity_AwaitingData"), x + w / 2, top + Draw.LARGE + 12, "dim",
            UIFont.Medium, nil, "centre")
        return y + h + PAD
    end
    local barY = top + Draw.LARGE + 8
    local barW = w - 2 * (PAD + 8)
    Draw.bar(self, x + PAD + 8, barY, barW, 20, m.score / 100, m.color, m.target / 100)
    local lineY = barY + 26
    Draw.text(self, t(m.trend), x + PAD + 8, lineY, "dim", UIFont.Small, barW / 2)
    Draw.text(self, t(m.targetText), x + PAD + 8 + barW, lineY, "dim", UIFont.Small, nil, "right")
    Draw.text(self, t(m.risk), x + w / 2, lineY + Draw.SMALL + 4, m.riskColor, UIFont.Small, nil, "centre")
    return y + h + PAD
end

function ImmuneView:drawFactors(m, x, y, w, h)
    local top = Draw.frame(self, x, y, w, h, getText("UI_EHR_Immunity_SystemicFactors"))
    local rowH = math.max(Draw.SMALL + 18, math.floor((y + h - top - PAD) / 6))
    for i, f in ipairs(m.factors) do
        local ry = top + (i - 1) * rowH
        Draw.text(self, t(f.label), x + PAD + 6, ry, "text", UIFont.Small, w - 80)
        Draw.text(self, t(f.valueText), x + w - PAD - 6, ry, f.color, UIFont.Small, nil, "right")
        Draw.bar(self, x + PAD + 6, ry + Draw.SMALL + 4, w - 2 * (PAD + 6), 8, f.value / 100, f.color, f.value / 100)
    end
end

function ImmuneView:drawHygiene(m, x, y, w, h)
    local top = Draw.frame(self, x, y, w, h, getText("UI_EHR_Immunity_BarrierDefense"))
    local iw = w - 2 * (PAD + 6)
    local ix = x + PAD + 6
    local ry = top
    for _, entry in ipairs({ { "UI_EHR_Immunity_HandsArms", m.dirtiness }, { "UI_EHR_Immunity_BloodContamination",
        m.bloodiness } }) do
        Draw.text(self, getText(entry[1]), ix, ry, "text", UIFont.Small, iw - 50)
        Draw.text(self, t(entry[2].text), ix + iw, ry, entry[2].color, UIFont.Small, nil, "right")
        Draw.bar(self, ix, ry + Draw.SMALL + 4, iw, 12, entry[2].value / 100, entry[2].color)
        ry = ry + Draw.SMALL + 24
    end
    Draw.text(self, t(m.penalty), ix, ry, m.penaltyColor, UIFont.Small, iw)
    ry = Draw.section(self, getText("UI_EHR_Immunity_CurrentPressures"), x + 6, ry + Draw.SMALL + 10, w - 12)
    -- As many pressure rows as fit above the state line (v0.9 overlapped it at the minimum height).
    local stateY = y + h - PAD - Draw.SMALL
    local rowH = Draw.SMALL + 6
    if #m.pressures == 0 then
        Draw.text(self, getText("UI_EHR_Immunity_NoMajorPressures"), ix, ry, "green", UIFont.Small, iw)
    end
    for _, p in ipairs(m.pressures) do
        if ry + rowH > stateY - 4 then
            break
        end
        Draw.swatch(self, ix, ry + 4, p.color)
        local value = t(p.value)
        Draw.text(self, t(p.label), ix + 14, ry, "text", UIFont.Small, iw - 14 - Draw.width(value) - 8)
        Draw.text(self, value, ix + iw, ry, p.color, UIFont.Small, nil, "right")
        ry = ry + rowH
    end
    Draw.text(self, t(m.state), ix, stateY, "dim", UIFont.Small, iw)
end

function ImmuneView:render()
    ISPanelJoypad.render(self)
    local w = math.max(WIDTH, Draw.tabsWidth(self))
    self:setWidthAndParentWidth(w)
    self:setHeightAndParentHeight(HEIGHT)
    Draw.fitTabs(self)
    Draw.rect(self, 0, 0, self.width, self.height, C.background)
    local player = getSpecificPlayer(self.playerNum)
    local m = player and Immune.build(Client.section(player, "immunity"), Env.sandbox)
    if not m then
        Draw.text(self, getText("UI_EHR_Immunity_AwaitingData"), w / 2, HEIGHT / 2, "dim", UIFont.Medium, nil, "centre")
        return
    end
    local y = self:drawTop(m, PAD, PAD, w - 2 * PAD)
    if m.awaiting then
        return
    end
    local lowerH = HEIGHT - y - PAD
    local leftW = math.floor((w - 3 * PAD) * 0.55)
    self:drawFactors(m, PAD, y, leftW, lowerH)
    self:drawHygiene(m, 2 * PAD + leftW, y, w - 3 * PAD - leftW, lowerH)
end

function ImmuneView:onJoypadDown(button)
    local window = getPlayerInfoPanel(self.playerNum)
    if button == Joypad.BButton then
        if window then
            window:toggleView(getText("UI_EHR_Tab_Immunity"))
        end
        setJoypadFocus(self.playerNum, nil)
    elseif (button == Joypad.LBumper or button == Joypad.RBumper) and window then
        window:onJoypadDown(button)
    end
end

return ImmuneView
