-- Conditions from add-on mods, added to the one condition registry (Conditions/Registry) that every EHR system, the
-- Monitor, the exam and the handbook read. Call it from the add-on's shared code at load, so MP clients (which build
-- the Monitor from the registry) know the condition too.
--
--   local Registration = require "ExtensiveHealthRedone/Conditions/Registration"
--   Registration.register("myaddon_scurvy", {
--       name = "UI_MyAddon_Scurvy", driven = true, drive = function(p, c, dt) ... end,
--       master = false, xp = false, strand = "nutrition", alert = false, pressure = false,
--       enabledOption = "MyAddon.ScurvyEnabled",
--       display = { icon = "MyAddon_Scurvy", category = "nutrition", unknownName = "UI_MyAddon_Unknown_Fatigue",
--           unknownDesc = "UI_MyAddon_Unknown_Fatigue_Desc", handbook = true },
--   })
--
-- The definition has the fields Conditions/Engine lists. Fields that matter most for an add-on:
--   master = false     the DiseaseEnabled master switch leaves it alone
--   xp = false         ending it gives no First Aid XP
--   enabledOption, speedOption   may name another mod's sandbox option as "Namespace.Option" (Game/Env.sandbox)
--   strand             a knowledge strand (Conditions/Knowledge.registerStrand) decides what a reader knows of it
--   alert = false      it never raises the Medical Alert moodle (UI/MoodleLevels)
--   pressure = false | "half"    it adds no (or half) disease pressure to the immune system (Immunity/Immunity)
--   monitorRow(row, c, known, input)   optional: changes the condition's Monitor row after EHR built it (UI/Monitor),
--                      for a description or the progress and status of a driven condition
--   display            how it is shown (Data/DiseaseInfo): icon (texture name without ".png"), category (handbook
--                      UI_EHR_Codex_Category_<category>), lethal, unknownName/unknownDesc (translation keys shown before
--                      it is identified), handbook = true to list it in the handbook (UI_EHR_Codex_<id>_* texts),
--                      lockedDesc (a translation key: how to unlock its handbook entry, instead of the flyer text)
-- An admin's full heal ends every condition, these too (Admin/FullHeal.onHeal lets the add-on reset what drives them).

local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local DiseaseInfo = require "ExtensiveHealthRedone/Data/DiseaseInfo"

local Registration = {}

local PRESSURE = { [false] = true, half = true }

function Registration.register(id, def)
    if type(id) ~= "string" or not id:match("^[%a_][%w_]*$") then
        error("condition ids are plain names: " .. tostring(id), 2)
    end
    if defs[id] then
        error("condition " .. id .. " is defined twice", 2)
    end
    if type(def) ~= "table" or type(def.name) ~= "string" then
        error("condition " .. id .. " needs a name key", 2)
    end
    if def.pressure ~= nil and not PRESSURE[def.pressure] then
        error("condition " .. id .. ": pressure must be false or \"half\"", 2)
    end
    if def.driven and type(def.drive) ~= "function" then
        error("driven condition " .. id .. " needs drive(p, c, dt)", 2)
    end
    if def.monitorRow ~= nil and type(def.monitorRow) ~= "function" then
        error("condition " .. id .. ": monitorRow must be a function", 2)
    end
    local display = def.display
    if display then
        DiseaseInfo.BY_ID[id] = {
            icon = display.icon, category = display.category, lethal = display.lethal == true,
            unknownName = display.unknownName, unknownDesc = display.unknownDesc, lockedDesc = display.lockedDesc,
        }
        if display.handbook then
            DiseaseInfo.ORDER[#DiseaseInfo.ORDER + 1] = id
        end
    end
    defs[id] = def
    return def
end

return Registration
