-- Inventory context menu for medication (Medication/Data).
--   our own items (Data.ownRoute): "Use <name> (<tier>)" on yourself, and "Give to <player>" for a player within
--     range (Client/Give: asks their consent for this one item, purpose "medicate"). The tooltip says what it treats,
--     how it is given, the doses left, the course progress and what it needs; a refused dose is greyed out with the
--     reason in red, a dose that would be wasted stays available with the reason in orange.
--   vanilla pills and eaten medication (Data.vanillaRoute): no option of ours on yourself. Vanilla's own option gets
--     the warning in orange instead, because vanilla's action consumes the item anyway and the server wastes the
--     dose. The vanilla pills and antibiotics (Data.giveVanilla) get "Give to <player>" too (Phase 9).
-- Our homemade pills carry base:consumable, so vanilla adds "Take pills" for them too; that duplicate is removed.
-- The menu only shows what the mirror says; the shared timed action (Actions/Medication) applies the dose on the
-- authority when its time is up, and the server checks everything again (Server/Medication).

require "ISUI/ISInventoryPaneContextMenu"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"
local Data = require "ExtensiveHealthRedone/Medication/Data"
local Doses = require "ExtensiveHealthRedone/Medication/Doses"
local ItemInfo = require "ExtensiveHealthRedone/UI/ItemInfo"
local MedicationAction = require "ExtensiveHealthRedone/Actions/Medication"
local Text = require "ExtensiveHealthRedone/Client/Text"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Give = require "ExtensiveHealthRedone/Client/Give"

local MedicationMenu = {}

MedicationMenu.TIERS = MedicationAction.TIERS

local RED, ORANGE = "<RGB:1,0.3,0.3> ", "<RGB:1,0.6,0.2> "

MedicationMenu.Action = MedicationAction

local function queue(player, item)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(MedicationAction:new(player, item, nil))
end

-- What the menu knows ------------------------------------------------------------------------------------------------

-- The mirrored state as Medication/Doses expects it, or nil before the first sync.
function MedicationMenu.state(player)
    local meds = Client.section(player, "meds")
    local conditions = Client.section(player, "conditions")
    local wounds = Client.section(player, "wounds")
    if not (meds and conditions and wounds) then
        return nil
    end
    return { meds = meds, conditions = conditions, wounds = wounds }
end

local function has(player, set)
    return player:getInventory():getFirstEvalRecurse(function(item)
        return set[item:getFullType()] == true
    end) ~= nil
end

-- Any open wound, the way Server/Facts counts one.
local function anyWound(player)
    local list = player:getBodyDamage():getBodyParts()
    for i = 0, list:size() - 1 do
        local part = list:get(i)
        if part:HasInjury() or part:stitched() or part:bleeding() or part:deepWounded() or part:haveGlass()
            or part:haveBullet() then
            return true
        end
    end
    return false
end

-- The refusal context for this player (Doses.refusal).
function MedicationMenu.context(player)
    return {
        supplies = { syringe = has(player, Supplies.syringe), ivKit = has(player, Supplies.ivKit) },
        wound = anyWound(player),
        sandbox = Env.sandbox,
    }
end

-- "1 h 20 min" or "20 min".
function MedicationMenu.duration(minutes)
    minutes = math.max(0, math.ceil(minutes))
    local hours = math.floor(minutes / 60)
    if hours > 0 then
        ---@diagnostic disable-next-line: redundant-parameter
        return getText("UI_EHR_Med_Tooltip_HoursMinutes", hours, minutes - hours * 60)
    end
    return getText("UI_EHR_Med_Tooltip_Minutes", minutes)
end

local function conditionName(id)
    return Text.t(ItemInfo.conditionName(id))
end

-- The verdict for a dose now: { refusal = key or nil, waste = key or nil }. state may be nil (not synced yet).
function MedicationMenu.verdict(state, med, ctx)
    if not state then
        return {}
    end
    local refusal = Doses.refusal(state, med, ctx)
    return { refusal = refusal, waste = not refusal and Doses.wasteReason(state, med) or nil }
end

-- The warning line(s) for a wasted dose. Doses' generic reason is a past-tense line the character says, so the
-- tooltip shows its own wording instead.
local function wasteLines(lines, key, color)
    if key ~= "UI_EHR_Med_DoseWasted" then
        lines[#lines + 1] = color .. getText(key)
    end
    lines[#lines + 1] = color .. getText("UI_EHR_Med_Tooltip_Wasted")
end

-- The tooltip lines for our option. uses: { current, max } for a drainable, or nil for a single item.
function MedicationMenu.lines(state, med, uses, verdict)
    local lines = {}
    if #med.targets > 0 then
        local names = {}
        for i, id in ipairs(med.targets) do
            names[i] = conditionName(id)
        end
        lines[#lines + 1] = getText("UI_EHR_MedAction_Treats", table.concat(names, ", "))
    else
        lines[#lines + 1] = getText("UI_EHR_MedAction_SymptomReliefEmergency")
    end
    local route = Data.ROUTES[med.route]
    ---@diagnostic disable-next-line: redundant-parameter
    lines[#lines + 1] = getText("UI_EHR_MedAction_Administration", getText("UI_EHR_MedAction_AdminType_" .. med.route),
        math.floor(route.ticks / 30 + 0.5))
    if uses then
        ---@diagnostic disable-next-line: redundant-parameter
        lines[#lines + 1] = getText("UI_EHR_MedAction_Remaining", uses[1], uses[2])
    else
        lines[#lines + 1] = getText("UI_EHR_MedAction_SingleUse")
    end
    if Data.curesAnything(med) then
        local times = {}
        for i, t in ipairs(ItemInfo.cureTimes(med)) do
            times[i] = Text.t(t)
        end
        lines[#lines + 1] = getText("UI_EHR_MedAction_TreatmentTime", table.concat(times, ", "))
    end
    if state and Data.isCourse(med) then
        local course = Doses.course(state, med)
        if course then
            ---@diagnostic disable-next-line: redundant-parameter
            lines[#lines + 1] = getText("UI_EHR_Med_Tooltip_Dose", course.count, med.doses)
            local wait = Doses.nextDoseIn(state, med)
            if wait and wait > 0 then
                lines[#lines + 1] = getText("UI_EHR_Med_Tooltip_NextDoseIn", MedicationMenu.duration(wait))
            elseif wait then
                lines[#lines + 1] = getText("UI_EHR_Med_Tooltip_NextDoseNow")
            end
        end
    end
    -- A missing supply is the refusal below, in red.
    if med.supply == "syringe" then
        lines[#lines + 1] = getText("UI_EHR_MedAction_RequiresSyringe")
    elseif med.supply == "ivKit" then
        lines[#lines + 1] = getText("UI_EHR_MedAction_RequiresIVKit")
    end
    if verdict.refusal then
        lines[#lines + 1] = RED .. getText(verdict.refusal)
    elseif verdict.waste then
        wasteLines(lines, verdict.waste, ORANGE)
    end
    return lines
end

local function usesOf(item)
    if instanceof(item, "DrainableComboItem") then
        return { item:getCurrentUses(), item:getMaxUses() }
    end
    return nil
end

local function tooltip(option, name, lines)
    local t = ISWorldObjectContextMenu.addToolTip()
    t:setName(name)
    t.description = table.concat(lines, " <LINE> ")
    option.toolTip = t
end

-- Menus --------------------------------------------------------------------------------------------------------------

-- Our own option, and the "Give to" submenu.
function MedicationMenu.ownMenu(player, context, item, med)
    local state = MedicationMenu.state(player)
    local ctx = MedicationMenu.context(player)
    local verdict = MedicationMenu.verdict(state, med, ctx)
    local name = item:getDisplayName()
    local label = getText("UI_EHR_MedAction_UseWithTier", name, getText(MedicationMenu.TIERS[med.tier] or
        MedicationMenu.TIERS[0]))
    local option = context:addOption(label, player, function() queue(player, item) end)
    option.notAvailable = verdict.refusal ~= nil
    tooltip(option, name, MedicationMenu.lines(state, med, usesOf(item), verdict))

    -- Only the giver's supplies are known here; the server checks the patient's side.
    Give.addMenu(context, player, item, "UI_EHR_Med_GiveTo")
    return option
end

-- A vanilla-route item: warn on vanilla's own option when the dose would be refused or wasted.
function MedicationMenu.vanillaWarning(player, context, item, med)
    local verdict = MedicationMenu.verdict(MedicationMenu.state(player), med, MedicationMenu.context(player))
    local key = verdict.refusal or verdict.waste
    if not key then
        return nil
    end
    local label = item:getCustomMenuOption()
    if not label and med.vanilla == "pill" then
        label = getText("ContextMenu_Take_pills")
    end
    local option = label and context:getOptionFromName(label)
    if not option then
        return nil
    end
    local lines = {}
    wasteLines(lines, key, ORANGE)
    local existing = option.toolTip
    if existing then
        existing.description = (existing.description ~= nil and existing.description ~= "" and
            (existing.description .. " <LINE> ") or "") .. table.concat(lines, " <LINE> ")
    else
        tooltip(option, item:getDisplayName(), lines)
    end
    return option
end

-- Vanilla's duplicate "Take pills" for our own items that carry base:consumable.
local function removeVanillaPills(context, item)
    local custom = item:getCustomMenuOption()
    if custom then
        context:removeOptionByName(custom)
    end
    context:removeOptionByName(getText("ContextMenu_Take_pills"))
end

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
    if not item then
        return
    end
    local fullType = item:getFullType()
    local med = Data.byType[fullType]
    if not med then
        return
    end
    if Data.ownRoute[fullType] then
        removeVanillaPills(context, item)
        MedicationMenu.ownMenu(player, context, item, med)
    else
        MedicationMenu.vanillaWarning(player, context, item, med)
        if Data.giveVanilla[fullType] then
            Give.addMenu(context, player, item, "UI_EHR_Med_GiveTo")
        end
    end
end)

return MedicationMenu
