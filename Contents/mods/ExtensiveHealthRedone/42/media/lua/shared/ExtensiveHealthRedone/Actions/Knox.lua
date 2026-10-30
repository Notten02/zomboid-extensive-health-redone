-- The Knox item timed action: gene therapy, the antibody test, the immunobooster and Phalanx, each
-- used on yourself.
--
--   EHRKnoxAction:new(character, item)
--
-- The kind, the length and the command come from the item's type, inside new(), because the authority rebuilds the
-- action from its constructor arguments only. complete() hands the intent to that knox.<kind> command through
-- Actions/Authority; the server runs the Knox rules and uses the item up as they say (Server/Knox).

require "TimedActions/ISBaseTimedAction"

local Authority = require "ExtensiveHealthRedone/Actions/Authority"
local Common = require "ExtensiveHealthRedone/Actions/Common"

---@class EHRKnoxAction : ISBaseTimedAction
---@field item InventoryItem
---@field kind string?
EHRKnoxAction = ISBaseTimedAction:derive("EHRKnoxAction")

-- kind -> item full type, action length (ticks; ours) and server command.
EHRKnoxAction.KINDS = {
    geneTherapy = { fullType = "ExtensiveHealth.GeneTherapyKit", time = 150, command = "knox.geneTherapy" },
    antibodyTest = { fullType = "ExtensiveHealth.AntibodyTestKit", time = 200, command = "knox.antibodyTest" },
    immunobooster = { fullType = "ExtensiveHealth.ImmunoboosterShot", time = 100, command = "knox.immunobooster" },
    phalanx = { fullType = "ExtensiveHealth.PhalanxPills", time = 80, command = "knox.phalanx" },
}

-- item full type -> kind
EHRKnoxAction.kindOf = {}
for kind, def in pairs(EHRKnoxAction.KINDS) do
    EHRKnoxAction.kindOf[def.fullType] = kind
end

function EHRKnoxAction:isValid()
    return self.kind ~= nil and Common.carries(self.character, self.item, false)
end

function EHRKnoxAction:start()
    self.item = Common.current(self.character, self.item, false)
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    self.item:setJobDelta(0)
    if self.kind == "antibodyTest" then
        self.character:Say(getText("UI_EHR_KnoxCure_RunningTest"))
    end
end

function EHRKnoxAction:update()
    self.item:setJobDelta(self:getJobDelta())
end

function EHRKnoxAction:stop()
    self.item:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function EHRKnoxAction:perform()
    self.item:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function EHRKnoxAction:complete()
    if not self.kind then
        return false
    end
    return Authority.run(self.character, EHRKnoxAction.KINDS[self.kind].command, { item = self.item:getID() })
end

function EHRKnoxAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return self.kind and EHRKnoxAction.KINDS[self.kind].time or 1
end

---@param character IsoPlayer
---@param item InventoryItem
---@return EHRKnoxAction
function EHRKnoxAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRKnoxAction]]
    o.item = item
    o.kind = item and EHRKnoxAction.kindOf[item:getFullType()]
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

return EHRKnoxAction
