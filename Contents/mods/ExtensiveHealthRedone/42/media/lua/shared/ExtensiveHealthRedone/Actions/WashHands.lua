-- The "Wash Hands" timed action at a water source or from a carried container (Client/WashHands has the menus).
--
--   EHRWashHandsAction:new(character, sink)          at a world water source
--   EHRWashHandsAction:new(character, nil, item)     from a carried container of water (Game/WaterSource)
--
-- The length comes from the washing plan for the character's hands and arms (with The Only Cure: what is left of
-- them and the prostheses worn, or the face; Game/BodySoil) and the soap they carry (Diseases/Food/Washing), worked
-- out inside new(), so the authority, which rebuilds the action from its constructor arguments only, times it the
-- same way. A container that doesn't hold enough for everything washes what fits, so the water in it shortens the
-- plan too, and soapy water counts as soap. complete() hands the intent to food.washHands or food.washHandsFromItem through Actions/Authority;
-- the server checks the water, the soil and the soap again and does the washing (Server/Food).

require "TimedActions/ISBaseTimedAction"

local Washing = require "ExtensiveHealthRedone/Diseases/Food/Washing"
local BodySoil = require "ExtensiveHealthRedone/Game/BodySoil"
local WaterSource = require "ExtensiveHealthRedone/Game/WaterSource"
local Common = require "ExtensiveHealthRedone/Actions/Common"
local Authority = require "ExtensiveHealthRedone/Actions/Authority"

---@class EHRWashHandsAction : ISBaseTimedAction
---@field sink IsoObject?
---@field item InventoryItem?
---@field sound number?
EHRWashHandsAction = ISBaseTimedAction:derive("EHRWashHandsAction")

-- Blood and dirt on the parts washing cleans, as Washing.plan reads them, and the mode ("hands" or "face").
function EHRWashHandsAction.soil(character)
    return BodySoil.wash(character)
end

function EHRWashHandsAction.hasSoap(character)
    local soaps = character:getInventory():getSoapList(nil, false)
    for i = 0, soaps:size() - 1 do
        local soap = soaps:get(i)
        if instanceof(soap, "DrainableComboItem") and soap:getCurrentUses() > 0 then
            return true
        end
    end
    return false
end

-- The washing plan for this character now (nil: nothing to wash), and the mode ("hands" or "face").
-- available: the water in a carried container, which limits the plan to what fits (Washing.plan); soapy: that water
-- has a cleaning fluid in it, which washes like soap (Game/WaterSource).
function EHRWashHandsAction.plan(character, available, soapy)
    local soil, mode = EHRWashHandsAction.soil(character)
    return Washing.plan(soil, soapy or EHRWashHandsAction.hasSoap(character), available), mode
end

function EHRWashHandsAction:isValid()
    if self.item then
        return Common.carries(self.character, self.item)
            and WaterSource.carried(Common.current(self.character, self.item)) > 0
    end
    return self.sink:getFluidAmount() > 0
end

function EHRWashHandsAction:start()
    self.item = Common.current(self.character, self.item)
    self:setActionAnim("WashFace")
    self:setOverrideHandModels(nil, nil)
end

function EHRWashHandsAction:update()
    if self.sink then
        self.character:faceThisObjectAlt(self.sink)
    end
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function EHRWashHandsAction:animEvent(event)
    if event == "PlayWashSound" then
        self:stopSound()
        self.sound = self.character:playSound("WashYourself")
    end
end

function EHRWashHandsAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function EHRWashHandsAction:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function EHRWashHandsAction:perform()
    self:stopSound()
    ISBaseTimedAction.perform(self)
end

function EHRWashHandsAction:complete()
    if self.item then
        return Authority.run(self.character, "food.washHandsFromItem", { item = self.item:getID() })
    end
    local square = self.sink:getSquare()
    return Authority.run(self.character, "food.washHands", { x = square:getX(), y = square:getY(), z = square:getZ() })
end

function EHRWashHandsAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local plan
    if self.item then
        plan = EHRWashHandsAction.plan(self.character, WaterSource.carried(self.item))
    else
        plan = EHRWashHandsAction.plan(self.character)
    end
    return plan and plan.ticks or 1
end

---@param character IsoPlayer
---@param sink IsoObject?
---@param item InventoryItem?
---@return EHRWashHandsAction
function EHRWashHandsAction:new(character, sink, item)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRWashHandsAction]]
    o.sink = sink
    o.item = item
    o.maxTime = o:getDuration()
    o.forceProgressBar = true
    return o
end

return EHRWashHandsAction
