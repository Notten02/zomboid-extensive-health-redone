-- The "Wash Hands" timed action (decision SA-6) at a water source (Client/WashHands has the menu).
--
--   EHRWashHandsAction:new(character, sink)
--
-- The length comes from the washing plan for the character's hands and arms and the soap they carry
-- (Diseases/Food/Washing), worked out inside new(), so the authority, which rebuilds the action from its constructor
-- arguments only, times it the same way. complete() hands the intent to food.washHands through Actions/Authority;
-- the server checks the water source, the soil and the soap again and does the washing (Server/Food).

require "TimedActions/ISBaseTimedAction"

local Washing = require "ExtensiveHealthRedone/Diseases/Food/Washing"
local Authority = require "ExtensiveHealthRedone/Actions/Authority"

---@class EHRWashHandsAction : ISBaseTimedAction
---@field sink IsoObject
---@field sound number?
EHRWashHandsAction = ISBaseTimedAction:derive("EHRWashHandsAction")

-- Blood and dirt on the parts washing cleans, as Washing.plan reads them.
function EHRWashHandsAction.soil(character)
    local visual = character:getHumanVisual()
    local result = {}
    for _, name in ipairs(Washing.PARTS) do
        local part = BloodBodyPartType[name]
        result[name] = { blood = visual:getBlood(part), dirt = visual:getDirt(part) }
    end
    return result
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

-- The washing plan for this character now (nil: nothing to wash).
function EHRWashHandsAction.plan(character)
    return Washing.plan(EHRWashHandsAction.soil(character), EHRWashHandsAction.hasSoap(character))
end

function EHRWashHandsAction:isValid()
    return self.sink:getFluidAmount() > 0
end

function EHRWashHandsAction:start()
    self:setActionAnim("WashFace")
    self:setOverrideHandModels(nil, nil)
end

function EHRWashHandsAction:update()
    self.character:faceThisObjectAlt(self.sink)
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
    local square = self.sink:getSquare()
    return Authority.run(self.character, "food.washHands", { x = square:getX(), y = square:getY(), z = square:getZ() })
end

function EHRWashHandsAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local plan = EHRWashHandsAction.plan(self.character)
    return plan and plan.ticks or 1
end

---@param character IsoPlayer
---@param sink IsoObject
---@return EHRWashHandsAction
function EHRWashHandsAction:new(character, sink)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRWashHandsAction]]
    o.sink = sink
    o.maxTime = o:getDuration()
    o.forceProgressBar = true
    return o
end

return EHRWashHandsAction
