-- Slim debug window, toggled with the debug key (Mod Options, default G). Only available with the sandbox DebugMode
-- option and, in MP, the medicalAdmin permission (Game/Permissions). The server checks both again for every debug
-- command; this gate only hides the UI.
--
-- Live status lines show body temperature, the held fever, immunity and the active conditions. Inspect the server
-- state and the client mirror, skip health-simulation time, force a resync, set blood volume and saline, infect a
-- wound, pick any condition to start, advance, put at a stage, or cure, and pick any medication to take a dose of (no
-- supplies needed), finish its running course now, or clear all medication state.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISRichTextPanel"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Permissions = require "ExtensiveHealthRedone/Game/Permissions"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Dump = require "ExtensiveHealthRedone/Core/Dump"
local Tables = require "ExtensiveHealthRedone/Core/Tables"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Options = require "ExtensiveHealthRedone/Client/Options"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local MedData = require "ExtensiveHealthRedone/Medication/Data"

local log = Env.logger("Debug")

---@class ExtensiveHealthRedoneDebugWindow : ISCollapsableWindow
---@field character IsoPlayer
---@field output ISRichTextPanel
---@field condition ISComboBox
---@field medication ISComboBox
local DebugWindow = ISCollapsableWindow:derive("ExtensiveHealthRedoneDebugWindow")

local BUTTONS = {
    { id = "server", label = "Server state" },
    { id = "mirror", label = "Client mirror" },
    { id = "resync", label = "Resync" },
    { id = "skip60", label = "Skip 1 h", minutes = 60 },
    { id = "skip360", label = "Skip 6 h", minutes = 360 },
    { id = "skip1440", label = "Skip 24 h", minutes = 1440 },
    { label = "Blood 100%", command = "debug.setBlood", args = { percent = 100, saline = 0 } },
    { label = "Blood 75%", command = "debug.setBlood", args = { percent = 75 } },
    { label = "Blood 60%", command = "debug.setBlood", args = { percent = 60 } },
    { label = "Blood 15%", command = "debug.setBlood", args = { percent = 15 } },
    { label = "Saline 45%", command = "debug.setBlood", args = { percent = 100, saline = 2250 } },
    { label = "Infect hand", command = "debug.woundInfection", args = { part = 0, stage = 0 } },
    { label = "Infect st. 3", command = "debug.woundInfection", args = { part = 0, stage = 3 } },
    -- Server/Admin: the admin full heal and state reset on yourself (the single-player route; MP admins also have
    -- /ehrfullheal and /ehrreset in chat).
    { label = "Full heal", command = "debug.healAll", args = {} },
    { label = "Reset state", command = "debug.resetState", args = {} },
    -- Server/DebugItems: watches (one nearly empty), a battery, bags, pills and supplies for trying the UI.
    { label = "Test items", command = "debug.testItems", args = {} },
}

-- Immunity (Server/Immunity): set the score; the next step recomputes the target.
for _, score in ipairs({ 100, 50, 10 }) do
    BUTTONS[#BUTTONS + 1] = { label = "Immunity " .. score, command = "debug.immunity", args = { score = score } }
end

-- Weather meters (Server/Weather).
for _, b in ipairs({ { "Cold meter 100%", "cold", 100 }, { "Heat meter 90%", "heat", 90 }, { "Heat meter 0%", "heat", 0 } }) do
    BUTTONS[#BUTTONS + 1] = { label = b[1], command = "debug.weatherMeter", args = { meter = b[2], percent = b[3] } }
end

-- World content: the 47.0 MHz radio (Server/Radio; "Radio status" and the loot report answer in the
-- output), knowledge (Server/Flyers, Server/Professions), recipes (Server/Recipes), the scalpel (Server/Scalpel) and
-- loot (Server/Loot).
for _, b in ipairs({
    { "Air 09:00 tip", "debug.radio", { action = "morning" } },
    { "Air 15:00 story", "debug.radio", { action = "afternoon" } },
    { "Air 21:00 file", "debug.radio", { action = "evening" } },
    { "Radio status", "debug.radio", { action = "status" } },
    { "Story to ep. 1", "debug.radio", { action = "resetStory" } },
    { "Forget knowl.", "debug.knowledge", { action = "forget" } },
    { "Doctor knowl.", "debug.professionKnowledge", { action = "doctor" } },
    { "Reset prof.", "debug.professionKnowledge", { action = "reset" } },
    { "Forget recipes", "debug.recipes", { action = "forget" } },
    { "Learn recipes", "debug.recipes", { action = "autoLearn" } },
    { "Give scalpel", "debug.scalpel", { action = "give" } },
    { "Scalpel Master", "debug.scalpel", { action = "trait" } },
    { "No Scalpel M.", "debug.scalpel", { action = "untrait" } },
    { "Scalpel stats", "debug.scalpel", { action = "inspect" } },
    { "Loot report", "debug.lootReport", {} },
    { "Loot re-apply", "debug.lootReapply", {} },
    -- Server/WildSearch: herb and hive open a game on the square under the player, skipping access and cooldowns.
    { "Wild cooldowns", "debug.wildSearch", { action = "reset" } },
    { "Herb search here", "debug.wildSearch", { action = "herb" } },
    { "Hive search here", "debug.wildSearch", { action = "hive" } },
}) do
    BUTTONS[#BUTTONS + 1] = { label = b[1], command = b[2], args = b[3] }
end

-- Load test (Server/Perf): counters on/off, the report, and the ghost load (N throwaway copies of this
-- player's state for 10 game minutes, in one server tick). Each answers in the output.
for _, b in ipairs({
    { "Perf on", "debug.perf", { on = true } },
    { "Perf off", "debug.perf", { on = false } },
    { "Perf report", "debug.perfReport", {} },
    { "Ghosts 8x10", "debug.perfLoad", { players = 8, minutes = 10 } },
    { "Ghosts 16x10", "debug.perfLoad", { players = 16, minutes = 10 } },
    { "Ghosts 32x10", "debug.perfLoad", { players = 32, minutes = 10 } },
}) do
    BUTTONS[#BUTTONS + 1] = { label = b[1], command = b[2], args = b[3] }
end

-- Actions on the condition picked in the combo box (debug.condition).
local CONDITION_BUTTONS = {
    { label = "Start", action = "start" },
    { label = "Next stage", action = "next" },
    { label = "Stage 1", action = "stage", stage = 1 },
    { label = "Stage 2", action = "stage", stage = 2 },
    { label = "Stage 3", action = "stage", stage = 3 },
    { label = "Stage 4", action = "stage", stage = 4 },
    { label = "Cure", action = "cure" },
}

-- Actions on the medication picked in its combo box (debug.medication).
local MEDICATION_BUTTONS = {
    { label = "Dose", action = "dose" },
    { label = "Finish course", action = "finish" },
    { label = "Clear all meds", action = "clear" },
}

local window
-- button -> its BUTTONS entry
local actionOf = {}

---@param x number
---@param y number
---@param character IsoPlayer
---@return ExtensiveHealthRedoneDebugWindow
function DebugWindow:new(x, y, character)
    local o = ISCollapsableWindow.new(self, x, y, 540, 760) --[[@as ExtensiveHealthRedoneDebugWindow]]
    o.title = "Extensive Health Redone: debug"
    o.character = character
    o:setResizable(true)
    return o
end

-- Live status lines above the buttons: vanilla's body temperature, the fever we hold (Body/Temperature), immunity, the
-- held floor and ceiling, the pre-disease stages, the exposure meters and the active conditions, from the player and
-- the client mirror.
local STATUS_LINES = 3
local STATUS_LINE_HEIGHT = 16

local function round(v, places)
    local m = 10 ^ places
    return tostring(math.floor(v * m + 0.5) / m)
end

local function statusLines(player)
    local body = player:getStats():get(CharacterStat.TEMPERATURE)
    local t = Client.section(player, "temperature")
    local fever = "none"
    if t and t.fever then
        fever = round(t.fever, 2) .. " C (" .. tostring(t.source or "?") .. ")"
    end
    local im = Client.section(player, "immunity")
    local immunity = im and (round(im.score, 1) .. " " .. tostring(im.trend)) or "?"
    local conditions = {}
    local c = Client.section(player, "conditions")
    for _, id in ipairs(Tables.sortedKeys(c and c.active or {})) do
        conditions[#conditions + 1] = id .. " " .. tostring(c.active[id].stage)
    end
    local bounds, stages = "none", "?"
    if t then
        bounds = (t.floor and round(t.floor, 2) or "-") .. " / " .. (t.ceiling and round(t.ceiling, 2) or "-")
        stages = "cold " .. tostring(t.cold) .. "  hot " .. tostring(t.hot)
    end
    local ex = Client.section(player, "exposure")
    local meters = ex and ("cold " .. round(ex.cold or 0, 0) .. "  heat " .. round(ex.heat or 0, 0)) or "?"
    return {
        "Body " .. round(body, 2) .. " C   held fever " .. fever .. "   immunity " .. immunity,
        "Hold floor/ceiling " .. bounds .. "   pre-disease " .. stages .. "   meters " .. meters,
        "Conditions: " .. (#conditions > 0 and table.concat(conditions, ", ") or "none"),
    }
end

function DebugWindow:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then
        return
    end
    local y = self:titleBarHeight() + 6
    for i, line in ipairs(statusLines(self.character)) do
        self:drawText(line, 8, y + (i - 1) * STATUS_LINE_HEIGHT, 1, 1, 0.6, 1, UIFont.Small)
    end
end

function DebugWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad, w, h = 8, 100, 22
    local x, y = pad, self:titleBarHeight() + pad + STATUS_LINES * STATUS_LINE_HEIGHT
    for _, def in ipairs(BUTTONS) do
        if x + w > self.width - pad then
            x, y = pad, y + h + 4
        end
        local button = ISButton:new(x, y, w, h, def.label, self, DebugWindow.onButton)
        actionOf[button] = def
        button:initialise()
        button:setEnable(not def.disabled)
        self:addChild(button)
        x = x + w + 4
    end
    x, y = pad, y + h + pad
    self.condition = ISComboBox:new(x, y, 2 * w + 4, h, self, nil)
    self.condition:initialise()
    for _, id in ipairs(Tables.sortedKeys(defs)) do
        self.condition:addOption(id)
    end
    self:addChild(self.condition)
    x = x + 2 * w + 8
    for _, def in ipairs(CONDITION_BUTTONS) do
        if x + w > self.width - pad then
            x, y = pad, y + h + 4
        end
        local button = ISButton:new(x, y, w, h, def.label, self, DebugWindow.onConditionButton)
        actionOf[button] = def
        button:initialise()
        self:addChild(button)
        x = x + w + 4
    end
    x, y = pad, y + h + pad
    self.medication = ISComboBox:new(x, y, 2 * w + 4, h, self, nil)
    self.medication:initialise()
    for _, id in ipairs(Tables.sortedKeys(MedData.byId)) do
        self.medication:addOption(id)
    end
    self:addChild(self.medication)
    x = x + 2 * w + 8
    for _, def in ipairs(MEDICATION_BUTTONS) do
        if x + w > self.width - pad then
            x, y = pad, y + h + 4
        end
        local button = ISButton:new(x, y, w, h, def.label, self, DebugWindow.onMedicationButton)
        actionOf[button] = def
        button:initialise()
        self:addChild(button)
        x = x + w + 4
    end
    y = y + h + pad
    self.output = ISRichTextPanel:new(pad, y, self.width - 2 * pad, self.height - y - pad)
    self.output:initialise()
    self.output.autosetheight = false
    self.output.clip = true
    self.output.background = false
    self.output:setAnchorRight(true)
    self.output:setAnchorBottom(true)
    self:addChild(self.output)
    self.output:addScrollBars()
    self:show("Press a button. Output is also written to console.txt.")
end

function DebugWindow:show(text)
    self.output.text = text
    self.output:paginate()
end

function DebugWindow:onButton(button)
    local def = actionOf[button]
    if def.id == "server" then
        Client.send(self.character, "debug.dump", {})
        self:show("Waiting for the server...")
    elseif def.id == "mirror" then
        local key = PlayerKey.of(self.character)
        local owner = Client.mirror.owners[key]
        local text = owner and Dump.lines(owner) or "No snapshot received yet."
        log:info("client mirror of", key, "\n" .. text)
        self:show(text)
    elseif def.id == "resync" then
        Client.mirror:forget(PlayerKey.of(self.character))
        Client.hello(self.character)
        self:show("Asked the server for a snapshot.")
    elseif def.command then
        -- Shown first: in single player the answer (debugDump) arrives during send() and must not be overwritten.
        self:show("Sent " .. def.command .. ". Press \"Server state\" to see the result.")
        Client.send(self.character, def.command, def.args)
    elseif def.minutes then
        Client.send(self.character, "debug.skipTime", { minutes = def.minutes })
        self:show("Asked the server to skip " .. def.minutes .. " minutes of health simulation.")
    end
end

function DebugWindow:onConditionButton(button)
    local def = actionOf[button]
    local id = self.condition:getSelectedText()
    Client.send(self.character, "debug.condition", { id = id, action = def.action, stage = def.stage })
    self:show("Sent " .. def.action .. " for " .. tostring(id) .. ". Press \"Server state\" to see the result.")
end

function DebugWindow:onMedicationButton(button)
    local def = actionOf[button]
    local id = self.medication:getSelectedText()
    Client.send(self.character, "debug.medication", { id = id, action = def.action })
    self:show("Sent " .. def.action .. " for " .. tostring(id) .. ". Press \"Server state\" to see the result.")
end

function DebugWindow:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    window = nil
end

local function allowed(player)
    return Env.debugMode() and Permissions.has(player, "medicalAdmin")
end

local function toggle()
    if window then
        window:close()
        return
    end
    local player = getSpecificPlayer(0)
    if not player or not allowed(player) then
        return
    end
    window = DebugWindow:new(100, 100, player)
    window:initialise()
    window:addToUIManager()
end

Client.on("debugDump", function(args)
    log:info("server state\n" .. tostring(args.text))
    if window then
        window:show(tostring(args.text))
    end
end)

Events.OnKeyPressed.Add(function(key)
    local bound = Options.key("DebugKey")
    if bound ~= 0 and key == bound then
        toggle()
    end
end)
