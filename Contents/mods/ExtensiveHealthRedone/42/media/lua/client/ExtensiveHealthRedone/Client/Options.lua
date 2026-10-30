-- Our page in Mod Options (not sandbox): the hotkeys and three display switches. PZAPI.ModOptions reads saved values
-- only when the options screen is built (main menu and game start), so the page is created when this file loads.
-- The values are global to the game install (ModOptions.ini), shared by every save and every local player.
--
--   Options.get("ShowEHRMoodles")      -- true / false
--   Options.key("JournalKey")          -- a Keyboard key code, or 0 when unbound
--
-- Keys (Client/Keys.lua): the Monitor key is unbound by default, because with PrimaryHealthPanel on vanilla's own
-- Health key (H) and the heart button open the EHR Monitor (Client/CharacterWindow.lua). J opens the handbook.
-- The debug key only works with the sandbox DebugMode option.
-- The page has its own id: the original mod's id ("ExtensiveHealthRework") would carry over a saved H for the Monitor
-- key, which now belongs to vanilla.

local Options = {}

Options.ID = "ExtensiveHealthRedone"

-- id -> default; read through the page once it exists.
local DEFAULTS = {
    MonitorKey = 0,
    JournalKey = Keyboard.KEY_J,
    DebugKey = Keyboard.KEY_G,
    PrimaryHealthPanel = true,
    OpenHealthPanelCompact = true,
    ShowEHRMoodles = true,
}

local page

if PZAPI and PZAPI.ModOptions then
    page = PZAPI.ModOptions:create(Options.ID, "UI_EHR_ModOptions_Title")
    page:addKeyBind("MonitorKey", "UI_EHR_ToggleMedicalMonitor", DEFAULTS.MonitorKey, "UI_EHR_ToggleMedicalMonitor_tt")
    page:addKeyBind("JournalKey", "UI_EHR_ToggleMedicalJournal", DEFAULTS.JournalKey, "UI_EHR_ToggleMedicalJournal_tt")
    page:addKeyBind("DebugKey", "UI_EHR_ToggleDebugMenu", DEFAULTS.DebugKey, "UI_EHR_ToggleDebugMenu_tt")
    page:addTickBox("PrimaryHealthPanel", "UI_EHR_PrimaryHealthPanel", DEFAULTS.PrimaryHealthPanel,
        "UI_EHR_PrimaryHealthPanel_tt")
    page:addTickBox("OpenHealthPanelCompact", "UI_EHR_OpenHealthPanelCompact", DEFAULTS.OpenHealthPanelCompact,
        "UI_EHR_OpenHealthPanelCompact_tt")
    page:addTickBox("ShowEHRMoodles", "UI_EHR_ShowMoodles", DEFAULTS.ShowEHRMoodles, "UI_EHR_ShowMoodles_tt")
end

function Options.get(id)
    local option = page and page:getOption(id)
    if option then
        return option:getValue()
    end
    return DEFAULTS[id]
end

-- The key bound to id; 0 means unbound.
function Options.key(id)
    return tonumber(Options.get(id)) or 0
end

return Options
