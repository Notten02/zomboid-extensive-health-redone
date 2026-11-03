-- "Wash Hands" on a water source (sink, rain collector, river, ...): washes visible blood and dirt off the hands and
-- arms with less water than vanilla's "Wash yourself"; soap makes it quicker and lifts the mood. Clean hands lower the
-- gastroenteritis risk. The shared timed action (Actions/WashHands) has the server check the water source, the
-- soil and the soap again and do the washing (Server/Food) when its time is up. Rules: Diseases/Food/Washing.
-- With The Only Cure a character with no hand or prosthesis left gets "Wash Face" instead: they eat face first, so
-- the face is what touches the food (Game/BodySoil).

require "ISUI/ISWorldObjectContextMenu"

local WashAction = require "ExtensiveHealthRedone/Actions/WashHands"
local WaterSource = require "ExtensiveHealthRedone/Game/WaterSource"

local WashHands = {}

WashHands.Action = WashAction

-- Context menu -----------------------------------------------------------------------------------------------------------

function WashHands.onWash(player, sink)
    if luautils.walkAdjObject(player, sink, true, true) then
        ISTimedActionQueue.add(WashAction:new(player, sink))
    end
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
    local soap = WashAction.hasSoap(player)
    local plan, mode = WashAction.plan(player)
    local face = mode == "face"
    local option = context:addOptionOnTop(getText(face and "UI_EHR_Context_WashFace" or "UI_EHR_Context_WashHands"),
        player, WashHands.onWash, sink)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = getText(face and "UI_EHR_Context_WashFaceDesc" or "UI_EHR_Context_WashHandsDesc")
    if not plan then
        option.notAvailable = true
        tooltip.description = getText(face and "UI_EHR_Context_WashFaceClean" or "UI_EHR_Context_WashHandsClean")
    elseif sink:getFluidAmount() < plan.water then
        option.notAvailable = true
        tooltip.description = getText("UI_EHR_Context_WashHandsNoWater")
    elseif soap then
        tooltip.description = tooltip.description .. " <LINE> " .. getText("UI_EHR_Context_WashHandsSoap")
    end
    option.toolTip = tooltip
end

Events.OnFillWorldObjectContextMenu.Add(fill)

return WashHands
