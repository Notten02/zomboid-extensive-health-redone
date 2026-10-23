-- Our tabs in vanilla's character window (UI option B, maintainer Phase 7): "EHR Monitor" and, while
-- ImmunitySystemEnabled is on, "Immune System", after vanilla's Info, Skills, Health, Protection and Temperature views.
-- Vanilla keeps its Health tab and all wound treatment.
--
-- PrimaryHealthPanel (mod option, default on): vanilla's own ways to open its Health view, the H key and the heart
-- button, open the EHR Monitor instead; the Health tab is one click away. While the Health view is the open tab, its
-- own toggles still close it (vanilla's controller B button on the Health tab calls the same toggle).
--
-- The windows are rebuilt by vanilla for every local player (split screen joins, respawns), so everything is looked
-- up through getPlayerInfoPanel(playerNum), never ISCharacterInfoWindow.instance.

require "XpSystem/ISUI/ISCharacterInfoWindow"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local Immune = require "ExtensiveHealthRedone/UI/Immune"
local Options = require "ExtensiveHealthRedone/Client/Options"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"
local MonitorView = require "ExtensiveHealthRedone/Client/MonitorView"
local ImmuneView = require "ExtensiveHealthRedone/Client/ImmuneView"

local CharacterWindow = {}

function CharacterWindow.monitorName()
    return getText("UI_EHR_Tab_EHR")
end

function CharacterWindow.immuneName()
    return getText("UI_EHR_Tab_Immunity")
end

local function addView(window, name, view)
    view:initialise()
    window.panel:addView(name, view)
    return view
end

-- Each view sets the window to its own width every frame (setWidthAndParentWidth through the tab panel), and vanilla
-- sizes its views for its own five tabs only. With our tabs and other mods' (Antibodies' Hygiene, made at the window's
-- starting 400) a narrow view shrank the window below its tab strip and left the strip scrolled (issue #2). The tab
-- panel, and so the window, is never narrower than all its tabs.
local function keepTabsInView(panel)
    local setWidth = panel.setWidth
    function panel:setWidth(w)
        setWidth(self, math.max(w, self:getWidthOfAllTabs()))
    end
end

Patches.on("characterInfoCreate", {
    name = "ehrTabs",
    after = function(_, window)
        keepTabsInView(window.panel)
        local playerNum = window.playerNum
        window.ehrMonitorView = addView(window, CharacterWindow.monitorName(), MonitorView:new(0, 8, playerNum))
        if Immune.visible(Env.sandbox) then
            window.ehrImmuneView = addView(window, CharacterWindow.immuneName(), ImmuneView:new(0, 8, playerNum))
        end
    end,
})

local function isOpenOn(window, view)
    return window:getIsVisible() and window.panel:getActiveView() == view
end

Patches.on("characterInfoToggle", {
    name = "primaryHealthPanel",
    intercept = function(window, viewName)
        if viewName ~= xpSystemText.health or not window.ehrMonitorView or Options.get("PrimaryHealthPanel") == false
            or getCore():getGameMode() == "Tutorial" or isOpenOn(window, window.healthView) then
            return nil
        end
        CharacterWindow.toggle(window.playerNum, "monitor")
        return true
    end,
})

local function viewOf(window, which)
    if which == "immune" then
        return window.ehrImmuneView, CharacterWindow.immuneName()
    end
    return window.ehrMonitorView, CharacterWindow.monitorName()
end

local function focus(window, playerNum)
    if JoypadState.players[playerNum + 1] and window:getIsVisible() then
        setJoypadFocus(playerNum, window.panel:getActiveView())
    end
end

-- Toggles one of our tabs like vanilla's hotkeys do: opens the window on it, switches to it, or closes the window
-- when it is already the open tab. which: "monitor" or "immune".
function CharacterWindow.toggle(playerNum, which)
    local window = getPlayerInfoPanel(playerNum)
    local view, name = viewOf(window or {}, which)
    if not window or not view then
        return
    end
    if not isOpenOn(window, view) and view.onOpened then
        view:onOpened()
    end
    window:toggleView(name)
    focus(window, playerNum)
end

-- Opens the window on one of our tabs (no toggling).
function CharacterWindow.open(playerNum, which)
    local window = getPlayerInfoPanel(playerNum)
    local view, name = viewOf(window or {}, which)
    if not window or not view then
        return
    end
    if not isOpenOn(window, view) then
        if view.onOpened then
            view:onOpened()
        end
        window.panel:activateView(name)
        window:setVisible(true)
        window:addToUIManager()
    end
    focus(window, playerNum)
end

-- A sync for a local player's mirror: their Monitor rebuilds at its next frame.
Client.onChange(function(ownerKey)
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        local window = player and PlayerKey.of(player) == ownerKey and getPlayerInfoPanel(i)
        local view = window and window.ehrMonitorView --[[@as ExtensiveHealthRedoneMonitorView?]]
        if view then
            view:markStale()
        end
    end
end)

return CharacterWindow
