-- The blood timed actions (decision SA-6): a transfusion of a blood bag or saline, on yourself or on another player
-- within reach (with their consent for that bag), and drawing your own blood into an empty bag.
--
--   EHRTransfusionAction:new(character, item, target)   target: another IsoPlayer, or nil for yourself
--   EHRDrawBloodAction:new(character, item)
--
-- Shared B42 actions: the client plays them, the authority rebuilds them from these constructor arguments (so the
-- fields keep the arguments' names) and runs complete(), which hands the intent to the server's blood.transfuse or
-- blood.draw command through Actions/Authority. Those commands accept nothing else (`action = true`), and check the
-- bag, the IV kit, the patient's state, range and consent again.

require "TimedActions/ISBaseTimedAction"

local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Authority = require "ExtensiveHealthRedone/Actions/Authority"
local Common = require "ExtensiveHealthRedone/Actions/Common"

local TRANSFUSE_TICKS = 300
local DRAW_TICKS = 400

-- Transfusion ----------------------------------------------------------------------------------------------------------

---@class EHRTransfusionAction : ISBaseTimedAction
---@field item InventoryItem
---@field target IsoPlayer?
EHRTransfusionAction = ISBaseTimedAction:derive("EHRTransfusionAction")

function EHRTransfusionAction:isValid()
    return Common.carries(self.character, self.item, false) and Common.reachable(self.character, self.target)
end

function EHRTransfusionAction:start()
    self.item = Common.current(self.character, self.item, false)
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    self.item:setJobType(getText("UI_EHR_Transfusion_UseBloodBag"))
    self.item:setJobDelta(0)
end

function EHRTransfusionAction:update()
    self.item:setJobDelta(self:getJobDelta())
    if self.target and self.target ~= self.character then
        self.character:faceThisObject(self.target)
    end
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function EHRTransfusionAction:stop()
    self.item:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function EHRTransfusionAction:perform()
    self.item:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function EHRTransfusionAction:complete()
    local args = { bag = self.item:getID() }
    if self.target and self.target ~= self.character then
        args.target = PlayerKey.ref(self.target)
    end
    return Authority.run(self.character, "blood.transfuse", args)
end

function EHRTransfusionAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return TRANSFUSE_TICKS
end

---@param character IsoPlayer
---@param item InventoryItem
---@param target IsoPlayer?
---@return EHRTransfusionAction
function EHRTransfusionAction:new(character, item, target)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRTransfusionAction]]
    o.item = item
    o.target = target
    o.maxTime = o:getDuration()
    return o
end

-- Blood draw -----------------------------------------------------------------------------------------------------------

---@class EHRDrawBloodAction : ISBaseTimedAction
---@field item InventoryItem
EHRDrawBloodAction = ISBaseTimedAction:derive("EHRDrawBloodAction")

function EHRDrawBloodAction:isValid()
    return Common.carries(self.character, self.item, false)
end

function EHRDrawBloodAction:start()
    self.item = Common.current(self.character, self.item, false)
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    self.item:setJobType(getText("UI_EHR_Transfusion_DrawBloodOption"))
    self.item:setJobDelta(0)
end

function EHRDrawBloodAction:update()
    self.item:setJobDelta(self:getJobDelta())
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function EHRDrawBloodAction:stop()
    self.item:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function EHRDrawBloodAction:perform()
    self.item:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function EHRDrawBloodAction:complete()
    return Authority.run(self.character, "blood.draw", { bag = self.item:getID() })
end

function EHRDrawBloodAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return DRAW_TICKS
end

---@param character IsoPlayer
---@param item InventoryItem
---@return EHRDrawBloodAction
function EHRDrawBloodAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRDrawBloodAction]]
    o.item = item
    o.maxTime = o:getDuration()
    return o
end

return { Transfusion = EHRTransfusionAction, Draw = EHRDrawBloodAction }
