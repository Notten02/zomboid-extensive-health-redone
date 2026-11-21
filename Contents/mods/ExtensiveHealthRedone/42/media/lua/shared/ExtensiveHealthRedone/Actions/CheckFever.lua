-- The "Check for Fever" timed action: a hand to the forehead (vanilla's head-bandaging animation), then the character
-- says how warm they feel (Body/FeverFeel.check). The EHR Monitor's header button queues it (Client/MonitorView).
--
--   EHRCheckFeverAction:new(character)
--
-- complete() hands the intent to temperature.checkFever through Actions/Authority; the server reads our fever and the
-- body's temperature and has the character say the result (Server/Temperature).

require "TimedActions/ISBaseTimedAction"

local Authority = require "ExtensiveHealthRedone/Actions/Authority"

---@class EHRCheckFeverAction : ISBaseTimedAction
EHRCheckFeverAction = ISBaseTimedAction:derive("EHRCheckFeverAction")

EHRCheckFeverAction.TICKS = 100

function EHRCheckFeverAction:isValid()
    return not self.character:isDead()
end

function EHRCheckFeverAction:start()
    self:setActionAnim(CharacterActionAnims.Bandage)
    self:setAnimVariable("BandageType", "Head")
    self:setOverrideHandModels(nil, nil)
end

function EHRCheckFeverAction:perform()
    ISBaseTimedAction.perform(self)
end

function EHRCheckFeverAction:complete()
    return Authority.run(self.character, "temperature.checkFever", {})
end

function EHRCheckFeverAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return EHRCheckFeverAction.TICKS
end

---@param character IsoPlayer
---@return EHRCheckFeverAction
function EHRCheckFeverAction:new(character)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRCheckFeverAction]]
    o.maxTime = o:getDuration()
    return o
end

return EHRCheckFeverAction
