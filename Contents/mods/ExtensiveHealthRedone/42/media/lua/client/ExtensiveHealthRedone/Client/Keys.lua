-- Our hotkeys (Client/Options): the EHR Monitor key (unbound by default; with PrimaryHealthPanel vanilla's H already
-- opens the Monitor) and the handbook key (J). Like vanilla's own keys they act for player 0, the keyboard player.
-- The debug key is Client/DebugMenu's.
--
-- J is also vanilla's "Toggle Info Panel" key (maintainer, Phase 7: keep J). When our key is vanilla's Info key too,
-- the character window is put back as it was before the press: a window that was closed is closed again, one open
-- on another tab goes back to it. Windows the player had open are never closed. Vanilla's key handler
-- (XpUpdate.displayCharacterInfo) is added when its file loads, after ours; the restoring handler is added at game
-- start so it runs after vanilla's (events run in the order they were added: unverified in game).

local Options = require "ExtensiveHealthRedone/Client/Options"
local CharacterWindow = require "ExtensiveHealthRedone/Client/CharacterWindow"
local Handbook = require "ExtensiveHealthRedone/Client/Handbook"

local Keys = {}

local PLAYER = 0

local function ready()
    if MainScreen and MainScreen.instance and MainScreen.instance:isVisible() then
        return false
    end
    local player = getSpecificPlayer(PLAYER)
    return player ~= nil and not player:isDead() and getPlayerData(PLAYER) ~= nil
end

local function bound(id, key)
    local k = Options.key(id)
    return k ~= 0 and k == key
end

-- The window as it was before a journal key press that vanilla also handles, or nil.
local restore

local function snapshot()
    local window = getPlayerInfoPanel(PLAYER)
    if not window then
        return nil
    end
    local active = window.panel:getActiveView()
    local name
    for _, v in ipairs(window.panel.viewList) do
        if v.view == active then
            name = v.name
        end
    end
    return { window = window, visible = window:getIsVisible(), view = name }
end

function Keys.onKey(key)
    if not ready() then
        return
    end
    if bound("MonitorKey", key) then
        CharacterWindow.toggle(PLAYER, "monitor")
    end
    if bound("JournalKey", key) then
        if getCore():isKey(KeybindId.TOGGLE_INFO_PANEL, key) then
            restore = snapshot()
        end
        Handbook.toggle(PLAYER)
    end
end

-- Runs after vanilla's key handler.
function Keys.afterKey()
    local before = restore
    restore = nil
    if not before then
        return
    end
    local window = before.window
    if not before.visible then
        if window:getIsVisible() then
            window:close()
        end
    elseif before.view then
        window.panel:activateView(before.view)
    end
end

Events.OnKeyPressed.Add(Keys.onKey)
Events.OnGameStart.Add(function()
    Events.OnKeyPressed.Add(Keys.afterKey)
end)

return Keys
