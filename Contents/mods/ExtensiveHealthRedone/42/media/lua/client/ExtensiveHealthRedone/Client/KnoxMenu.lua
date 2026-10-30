-- Inventory context menu for the four Knox items, and the Knox messages from the server (formatted lines such as the
-- antibody test result, and immunobooster tremors).
-- The menu only shows what the mirror says; the shared timed action (Actions/Knox) has the server decide everything
-- again when its time is up.

require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISModalDialog"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Effects = require "ExtensiveHealthRedone/Client/Effects"

local Data = require "ExtensiveHealthRedone/Diseases/Knox/Data"
local Knox = require "ExtensiveHealthRedone/Diseases/Knox/Knox"
local KnoxItems = require "ExtensiveHealthRedone/Diseases/Knox/Items"
local KnoxAction = require "ExtensiveHealthRedone/Actions/Knox"

local KnoxMenu = {}

KnoxMenu.Action = KnoxAction
-- kind -> item full type, action length (ticks; ours) and server command.
KnoxMenu.KINDS = KnoxAction.KINDS

local function queue(player, item)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(KnoxAction:new(player, item))
end

-- What the menu knows -------------------------------------------------------------------------------------------------

-- The mirrored state as Diseases/Knox expects it, plus the local view of vanilla's infection (display only).
local function view(player)
    local state = {
        knox = Client.section(player, "knox") or {},
        identity = Client.section(player, "identity") or {},
    }
    local damage = player:getBodyDamage()
    local bitten, partInfected = false, false
    local list = damage:getBodyParts()
    for i = 0, list:size() - 1 do
        local part = list:get(i)
        bitten = bitten or part:bitten()
        partInfected = partInfected or part:IsInfected()
    end
    local k = { infected = damage:IsInfected(), partInfected = partInfected, bitten = bitten }
    return state, k
end

local function tooltip(option, title, lines)
    local t = ISWorldObjectContextMenu.addToolTip()
    t:setName(getText(title))
    t.description = table.concat(lines, " <LINE> ")
    option.toolTip = t
end

local function percent(share)
    return tostring(math.floor(share * 100 + 0.5)) .. "%"
end

-- Menus --------------------------------------------------------------------------------------------------------------

local function geneTherapyMenu(player, context, item, state, k)
    if Knox.permanentlyImmune(state) then
        local option = context:addOption(getText("UI_EHR_KnoxCure_GeneTherapyAlreadyImmuneOption"), nil, nil)
        option.notAvailable = true
        tooltip(option, "UI_EHR_KnoxCure_AlreadyImmuneTitle", { getText("UI_EHR_KnoxCure_AlreadyImmuneDescription") })
        return
    end
    local infected = Knox.infected(k)
    local option = context:addOption(getText("UI_EHR_KnoxCure_UseGeneTherapy"), player, function()
        local w, h = 300, 150
        local modal = ISModalDialog:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2,
            w, h, getText("UI_EHR_KnoxCure_GeneTherapyConfirmation"), true, nil, function(_, button)
                if button.internal == "YES" then
                    queue(player, item)
                end
            end, player:getPlayerNum())
        modal:initialise()
        modal:addToUIManager()
    end)
    option.notAvailable = not infected
    local lines = {
        getText("UI_EHR_KnoxCure_GeneTherapyDescription"),
        getText("UI_EHR_KnoxCure_GeneTherapyCompatibility"),
        getText("UI_EHR_KnoxCure_GeneTherapyTestAdvice"),
        getText(infected and "UI_EHR_KnoxCure_GeneTherapyInfectedWarning" or "UI_EHR_KnoxCure_GeneTherapyNotInfected"),
    }
    if Env.sandbox("PatientZeroTraitDisabled", false) == true then
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_GeneTherapySuccessNoImmunity")
    else
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_GeneTherapySuccessImmunity")
    end
    lines[#lines + 1] = "<RGB:1,0.6,0.3> " .. getText("UI_EHR_Knox_GeneTherapyHealthCost", Data.GENE_THERAPY_HEALTH_COST)
    tooltip(option, "UI_EHR_KnoxCure_GeneTherapyTitle", lines)
end

local function antibodyMenu(player, context, item, state)
    local option = context:addOption(getText("UI_EHR_KnoxCure_UseAntibodyTest"), player, function()
        queue(player, item)
    end)
    local lines = {
        getText("UI_EHR_KnoxCure_AntibodyTestDescription"),
        getText("UI_EHR_KnoxCure_AntibodyTestChance"),
        getText("UI_EHR_KnoxCure_AntibodyTestSingleUse"),
    }
    local last = state.knox.lastTest
    if last then
        local rating, chance = getText(tostring(last.rating)), tostring(last.chance) .. "%"
        ---@diagnostic disable-next-line: redundant-parameter
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_AntibodyLastResult", rating, chance)
    end
    tooltip(option, "UI_EHR_KnoxCure_AntibodyTestTitle", lines)
end

local BOOSTER_OPTIONS = {
    immune = "UI_EHR_KnoxCure_ImmunoboosterAlreadyImmuneOption",
    active = "UI_EHR_KnoxCure_ImmunoboosterActiveOption",
    cooldown = "UI_EHR_KnoxCure_ImmunoboosterCooldownOption",
    infected = "UI_EHR_KnoxCure_ImmunoboosterAlreadyInfectedOption",
    bitten = "UI_EHR_KnoxCure_ImmunoboosterAlreadyBittenOption",
}

local function boosterMenu(player, context, item, state, k)
    local refusal = KnoxItems.boosterRefusal(state, k)
    local label
    if not refusal then
        label = getText("UI_EHR_KnoxCure_UseImmunobooster")
    elseif refusal.outcome == "active" then
        label = getText(BOOSTER_OPTIONS.active, math.ceil(state.knox.boosterLeft / 60))
    elseif refusal.outcome == "cooldown" then
        label = getText(BOOSTER_OPTIONS.cooldown, math.ceil(state.knox.boosterCooldown / 60))
    else
        label = getText(BOOSTER_OPTIONS[refusal.outcome])
    end
    local option = context:addOption(label, player, function() queue(player, item) end)
    option.notAvailable = refusal ~= nil
    local lines = {
        getText("UI_EHR_KnoxCure_ImmunoboosterDescription"),
        getText("UI_EHR_KnoxCure_ImmunoboosterTiming"),
        getText("UI_EHR_KnoxCure_ImmunoboosterSideEffectsHeading"),
        getText("UI_EHR_KnoxCure_ImmunoboosterSideEffectNausea"),
        getText("UI_EHR_KnoxCure_ImmunoboosterSideEffectStamina"),
        getText("UI_EHR_KnoxCure_ImmunoboosterSideEffectTremors"),
    }
    if not refusal then
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_ImmunoboosterReady")
    end
    tooltip(option, "UI_EHR_KnoxCure_ImmunoboosterTitle", lines)
end

local function phalanxMenu(player, context, item, state, k)
    if Knox.permanentlyImmune(state) then
        local option = context:addOption(getText("UI_EHR_KnoxCure_PhalanxAlreadyImmuneOption"), nil, nil)
        option.notAvailable = true
        return
    end
    local uses = state.knox.phalanxUses or 0
    local resetTo = Knox.phalanxResetFor(uses)
    local label
    if not resetTo then
        label = getText("UI_EHR_KnoxCure_PhalanxNoEffectOption")
    elseif resetTo == 0 then
        label = getText("UI_EHR_KnoxCure_PhalanxFullResetOption")
    else
        label = getText("UI_EHR_KnoxCure_PhalanxResetToOption", percent(resetTo))
    end
    local option = context:addOption(label, player, function() queue(player, item) end)
    option.notAvailable = not resetTo or not Knox.infected(k)
    local lines = { getText("UI_EHR_KnoxCure_PhalanxDescription") }
    ---@diagnostic disable-next-line: redundant-parameter
    lines[2] = getText("UI_EHR_KnoxCure_PhalanxTimesUsed", uses, #Data.PHALANX_RESET)
    if not resetTo then
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_PhalanxBodyAdapted")
    elseif resetTo == 0 then
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_PhalanxNextFullReset", percent(0))
    else
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_PhalanxNextResetTo", percent(resetTo))
    end
    lines[#lines + 1] = getText("UI_EHR_KnoxCure_SideEffectsHeading")
    lines[#lines + 1] = getText("UI_EHR_KnoxCure_PhalanxSideEffectNausea")
    lines[#lines + 1] = getText("UI_EHR_KnoxCure_PhalanxSideEffectFever")
    lines[#lines + 1] = getText("UI_EHR_KnoxCure_PhalanxSideEffectImmunity")
    if not Knox.infected(k) then
        lines[#lines + 1] = getText("UI_EHR_KnoxCure_NotInfected")
    end
    tooltip(option, "UI_EHR_KnoxCure_PhalanxTitle", lines)
end

local MENUS = {
    geneTherapy = geneTherapyMenu,
    antibodyTest = antibodyMenu,
    immunobooster = boosterMenu,
    phalanx = phalanxMenu,
}

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then
        return
    end
    -- Each entry is an item, or a stack whose items list (a Lua table) starts with the item itself.
    local first = items[1]
    local item
    if first and instanceof(first, "InventoryItem") then
        item = first --[[@as InventoryItem]]
    elseif first then
        local stack = first --[[@as umbrella.ContextMenuItemStack]]
        item = stack.items and stack.items[1]
    end
    local kind = item and KnoxAction.kindOf[item:getFullType()]
    if kind then
        local state, k = view(player)
        MENUS[kind](player, context, item, state, k)
    end
end)

-- Server messages ----------------------------------------------------------------------------------------------------

-- A line with arguments; arguments that are translation keys (rating names) are translated too.
Client.on("knoxSay", function(args)
    local player = Client.localPlayer(args.owner)
    if not player or player:isDead() then
        return
    end
    local values = {}
    local list = args.args or {}
    for i = 1, 3 do
        local v = list[i]
        if type(v) == "string" and v:find("^UI_") then
            v = getText(v)
        end
        values[i] = v ~= nil and tostring(v) or ""
    end
    ---@diagnostic disable-next-line: redundant-parameter
    player:Say(getText(tostring(args.key), values[1], values[2], values[3]))
end)

-- Immunobooster tremor: a stagger that doesn't knock the character down.
Client.on("knoxTremor", function(args)
    Effects.stagger(Client.localPlayer(args.owner))
end)

return KnoxMenu
