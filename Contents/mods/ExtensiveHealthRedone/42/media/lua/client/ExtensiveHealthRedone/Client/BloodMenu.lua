-- Inventory context menu for blood bags, saline and empty blood bags.
--   blood bag / saline: "Use" on yourself, and "Give to <player>" for a player within 3 tiles (Client/Give: asks
--     their consent for this bag, then the transfusion action)
--   empty blood bag: "Draw Blood"
-- The timed actions are shared (Actions/Blood): the authority applies the result when their time is up, after
-- checking everything again. Compatibility is shown only to characters who know blood types (Blood Types flyer, or
-- First Aid 8): on "Use" for their own type, in "Give to" for the patient's when it is known (Client/Give).

require "ISUI/ISInventoryPaneContextMenu"

local BloodData = require "ExtensiveHealthRedone/Data/Blood"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"
local Spoilage = require "ExtensiveHealthRedone/Blood/Spoilage"
local Transfusion = require "ExtensiveHealthRedone/Blood/Transfusion"
local Common = require "ExtensiveHealthRedone/Actions/Common"
local BloodActions = require "ExtensiveHealthRedone/Actions/Blood"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Give = require "ExtensiveHealthRedone/Client/Give"

local BloodMenu = {}

BloodMenu.RANGE = Common.RANGE
BloodMenu.inRange = Common.inRange
BloodMenu.nearbyPlayers = Give.nearbyPlayers
BloodMenu.TransfusionAction = BloodActions.Transfusion
BloodMenu.DrawAction = BloodActions.Draw

local function queue(player, item, action)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(action:new(player, item))
end

-- Helpers ------------------------------------------------------------------------------------------------------------

local function hasKit(player)
    return player:getInventory():getFirstEvalRecurse(function(item)
        return Supplies.ivKit[item:getFullType()] == true
    end) ~= nil
end

local function tooltip(option, name, lines)
    if #lines == 0 then
        return
    end
    local t = ISWorldObjectContextMenu.addToolTip()
    t:setName(name)
    t.description = table.concat(lines, " <LINE> ")
    option.toolTip = t
end

-- Menu ---------------------------------------------------------------------------------------------------------------

local function bagMenu(player, context, item)
    local fullType = item:getFullType()
    local saline = fullType == Supplies.saline
    local state = Give.spoilage(item)
    if state == Spoilage.ROTTEN then
        local option = context:addOption(getText("UI_EHR_Transfusion_UseBloodBagRotten"), nil, nil)
        option.notAvailable = true
        tooltip(option, getText("UI_EHR_Transfusion_Unusable"), {
            "<RGB:1,0.3,0.3> " .. getText("UI_EHR_Transfusion_BloodSpoiledDesc"),
            getText("UI_EHR_Transfusion_DisposeSafely"),
        })
        return
    end

    local label = getText(saline and "UI_EHR_Transfusion_UseSaline" or "UI_EHR_Transfusion_UseBloodBag")
    local lines = {}
    local title = saline and "UI_EHR_Transfusion_SalineInfusion" or nil
    if not saline then
        local identity = Client.section(player, "identity")
        local own = identity and identity.bloodType
        if Give.knowsTypes(player) and own then
            if Transfusion.compatible(Supplies.bloodTypeOf[fullType], own) then
                label = label .. " " .. getText("UI_EHR_Transfusion_CompatibleSuffix")
            else
                label = label .. " " .. getText("UI_EHR_Transfusion_IncompatibleSuffix")
                title = "UI_EHR_Transfusion_Warning"
                lines[#lines + 1] = "<RGB:1,0.3,0.3> " .. getText("UI_EHR_Transfusion_IncompatibleDesc", own)
                lines[#lines + 1] = getText("UI_EHR_Transfusion_SevereReaction")
            end
        else
            lines[#lines + 1] = "<RGB:0.7,0.7,0.7> " .. getText("UI_EHR_Transfusion_ReadBloodTypes")
            title = "UI_EHR_Transfusion_BloodCompatibilityUnknown"
        end
        if state == Spoilage.STALE then
            label = label .. " - " .. getText("UI_EHR_Transfusion_StaleSuffix")
            lines[#lines + 1] = "<RGB:1,0.5,0> " .. getText("UI_EHR_Transfusion_BloodStaleDesc")
            lines[#lines + 1] = getText("UI_EHR_Transfusion_SpoiledBloodRisk")
            title = title or "UI_EHR_Transfusion_Caution"
        end
    else
        lines[#lines + 1] = getText("UI_EHR_Transfusion_SalineRestores")
        lines[#lines + 1] = "<RGB:1,0.5,0> " .. getText("UI_EHR_Transfusion_SalineDeathCaution")
    end
    local kit = hasKit(player)
    if not kit then
        lines[#lines + 1] = "<RGB:1,0.3,0.3> " .. getText("UI_EHR_MedAction_RequiresIVKit")
    end

    local option = context:addOption(label, player, function() queue(player, item, BloodActions.Transfusion) end)
    option.notAvailable = not kit
    tooltip(option, getText(title or "UI_EHR_Transfusion_Caution"), lines)

    Give.addMenu(context, player, item, "UI_EHR_Transfusion_GiveTo")
end

local function drawMenu(player, context, item)
    local blood = Client.section(player, "blood")
    local share = blood and blood.volume / blood.max or 0
    local option = context:addOption(getText("UI_EHR_Transfusion_DrawBloodOption"), player,
        function() queue(player, item, BloodActions.Draw) end)
    local lines = {}
    if share < BloodData.DRAW_MINIMUM then
        option.notAvailable = true
        lines[#lines + 1] = "<RGB:1,0.3,0.3> " .. getText("UI_EHR_Transfusion_NeedBlood",
            math.floor(BloodData.DRAW_MINIMUM * 100))
    else
        lines[#lines + 1] = getText("UI_EHR_Transfusion_WillRemove", BloodData.DRAW_ML)
        lines[#lines + 1] = "<RGB:1,0.8,0.5> " .. getText("UI_EHR_Transfusion_AfterDonationDizzy")
    end
    if blood then
        lines[#lines + 1] = getText("UI_EHR_Transfusion_CurrentBloodPercent", math.floor(share * 100))
    end
    tooltip(option, getText("UI_EHR_Transfusion_BloodDonation"), lines)
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
    if Supplies.transfusable[fullType] then
        bagMenu(player, context, item)
    elseif Supplies.emptyBag[fullType] then
        drawMenu(player, context, item)
    end
end)

return BloodMenu
