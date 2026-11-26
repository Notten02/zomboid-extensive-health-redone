-- "Wash Hands" on a water source (sink, rain collector, river, ...) and on a carried container of water (bottle,
-- canteen, bucket, ...): washes visible blood and dirt off the hands and arms with less water than vanilla's "Wash
-- yourself"; soap makes it quicker and lifts the mood. Clean hands lower the gastroenteritis risk. The shared timed
-- action (Actions/WashHands) has the server check the water, the soil and the soap again and do the washing
-- (Server/Food) when its time is up. Rules: Diseases/Food/Washing.
-- A container that doesn't hold enough for everything (a full wash without soap takes 1.5, a bottle holds 1) washes
-- what fits, the hands first; a world source has to hold it all, as before. Water with a cleaning fluid mixed in
-- washes like soap, without using the soap carried (Game/WaterSource).
-- With The Only Cure a character with no hand or prosthesis left gets "Wash Face" instead: they eat face first, so
-- the face is what touches the food (Game/BodySoil).

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"

local Washing = require "ExtensiveHealthRedone/Diseases/Food/Washing"
local WashAction = require "ExtensiveHealthRedone/Actions/WashHands"
local WaterSource = require "ExtensiveHealthRedone/Game/WaterSource"

local WashHands = {}

WashHands.Action = WashAction

-- Context menus ----------------------------------------------------------------------------------------------------------

function WashHands.onWash(player, sink)
    if luautils.walkAdjObject(player, sink, true, true) then
        ISTimedActionQueue.add(WashAction:new(player, sink))
    end
end

-- From a carried container: into the main inventory first, as vanilla does before using an item.
function WashHands.onWashFrom(player, item)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    ISTimedActionQueue.add(WashAction:new(player, nil, item))
end

-- Sets the option's state and tooltip. available: the water in the source; limited: a carried container, which
-- washes what fits; soapy: the water has a cleaning fluid in it.
local function describe(option, player, available, limited, soapy)
    local plan, mode = WashAction.plan(player, limited and available or nil, soapy)
    local face = mode == "face"
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = getText(face and "UI_EHR_Context_WashFaceDesc" or "UI_EHR_Context_WashHandsDesc")
    if not plan then
        option.notAvailable = true
        tooltip.description = getText(face and "UI_EHR_Context_WashFaceClean" or "UI_EHR_Context_WashHandsClean")
    elseif not Washing.enough(plan, available) then
        option.notAvailable = true
        tooltip.description = getText("UI_EHR_Context_WashHandsNoWater")
    else
        if plan.partial then
            tooltip.description = tooltip.description .. " <LINE> " .. getText("UI_EHR_Context_WashHandsPartial")
        end
        if soapy or WashAction.hasSoap(player) then
            tooltip.description = tooltip.description .. " <LINE> " .. getText("UI_EHR_Context_WashHandsSoap")
        end
    end
    option.toolTip = tooltip
end

-- "Wash Hands", or "Wash Face" for a character with no hand or prosthesis left.
local function label(player)
    local _, mode = WashAction.soil(player)
    return getText(mode == "face" and "UI_EHR_Context_WashFace" or "UI_EHR_Context_WashHands")
end

local function fill(playerIndex, context, worldobjects, test)
    local player = getSpecificPlayer(playerIndex)
    if not player or player:getVehicle() then
        return
    end
    -- By square: the click may have landed on the sink's cabinet rather than its tap (Game/WaterSource).
    local sink = WaterSource.near(worldobjects)
    if not sink then
        return
    end
    if test then
        return true
    end
    local option = context:addOptionOnTop(label(player), player, WashHands.onWash, sink)
    describe(option, player, sink:getFluidAmount(), false)
end

Events.OnFillWorldObjectContextMenu.Add(fill)

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
    local available, soapy = WaterSource.carried(item)
    if available <= 0 then
        return
    end
    local option = context:addOption(label(player), player, WashHands.onWashFrom, item)
    describe(option, player, available, true, soapy)
end)

return WashHands
