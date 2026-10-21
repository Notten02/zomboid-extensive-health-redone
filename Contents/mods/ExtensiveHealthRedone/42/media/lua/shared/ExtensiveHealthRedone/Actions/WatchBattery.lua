-- The Medical Monitor Watch battery timed action (decision SA-6): insert a battery, or take the watch's battery out
-- (Client/Watch has the menu).
--
--   EHRWatchBatteryAction:new(character, watch, battery, label)   battery nil: remove; label: the progress text
--
-- complete() hands the intent to watch.insertBattery or watch.removeBattery through Actions/Authority; the server
-- reads the charges itself and moves them (Server/Watch).

require "TimedActions/ISBaseTimedAction"

local Authority = require "ExtensiveHealthRedone/Actions/Authority"
local Common = require "ExtensiveHealthRedone/Actions/Common"

local TICKS = 60

---@class EHRWatchBatteryAction : ISBaseTimedAction
---@field watch InventoryItem
---@field battery InventoryItem?
---@field label string?
EHRWatchBatteryAction = ISBaseTimedAction:derive("EHRWatchBatteryAction")

EHRWatchBatteryAction.TICKS = TICKS

function EHRWatchBatteryAction:isValid()
    return Common.carries(self.character, self.watch, true)
        and (self.battery == nil or Common.carries(self.character, self.battery, true))
end

function EHRWatchBatteryAction:start()
    self.watch = Common.current(self.character, self.watch, true)
    self.battery = Common.current(self.character, self.battery, true)
    self.watch:setJobType(self.label or "")
    self.watch:setJobDelta(0)
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
end

function EHRWatchBatteryAction:update()
    self.watch:setJobDelta(self:getJobDelta())
end

function EHRWatchBatteryAction:stop()
    self.watch:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function EHRWatchBatteryAction:perform()
    self.watch:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function EHRWatchBatteryAction:complete()
    if self.battery then
        return Authority.run(self.character, "watch.insertBattery",
            { watch = self.watch:getID(), battery = self.battery:getID() })
    end
    return Authority.run(self.character, "watch.removeBattery", { watch = self.watch:getID() })
end

function EHRWatchBatteryAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return TICKS
end

---@param character IsoPlayer
---@param watch InventoryItem
---@param battery InventoryItem?
---@param label string?
---@return EHRWatchBatteryAction
function EHRWatchBatteryAction:new(character, watch, battery, label)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRWatchBatteryAction]]
    o.watch = watch
    o.battery = battery
    o.label = label
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

return EHRWatchBatteryAction
