-- The medication timed action (decision SA-6): one dose of a medication (Medication/Data) on yourself, or given to
-- another player within reach with their consent for that item (Client/Give).
--
--   EHRMedicationAction:new(character, item, target)   target: another IsoPlayer, or nil for yourself
--
-- The record, the length (the route's ticks) and the command come from the item's type, inside new(), because the
-- authority rebuilds the action from its constructor arguments only:
--   our own items (Data.ownRoute)         medication.take  (yourself or another player)
--   vanilla items others may be given     medication.give  (Data.giveVanilla, another player only; on yourself
--                                                           vanilla's own Take/Eat action stays in charge)
-- complete() hands the intent to that command through Actions/Authority; the server checks the item, supplies,
-- range, consent and the patient's state again and applies the dose (Server/Medication).

require "TimedActions/ISBaseTimedAction"

local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Data = require "ExtensiveHealthRedone/Medication/Data"
local Authority = require "ExtensiveHealthRedone/Actions/Authority"
local Common = require "ExtensiveHealthRedone/Actions/Common"

---@class EHRMedicationAction : ISBaseTimedAction
---@field item InventoryItem
---@field target IsoPlayer?
---@field med table?
---@field command string?
EHRMedicationAction = ISBaseTimedAction:derive("EHRMedicationAction")

-- Tier names for the progress text (and the menu's option).
EHRMedicationAction.TIERS = {
    [0] = "UI_EHR_MedAction_Tier_Basic",
    [1] = "UI_EHR_MedAction_Tier_OTC",
    [2] = "UI_EHR_MedAction_Tier_Prescription",
    [3] = "UI_EHR_MedAction_Tier_Clinical",
}

-- The command that applies a dose of fullType, given to someone else or not, or nil when there is none.
function EHRMedicationAction.commandFor(fullType, remote)
    if Data.ownRoute[fullType] then
        return "medication.take"
    end
    if remote and Data.giveVanilla[fullType] then
        return "medication.give"
    end
    return nil
end

local function remote(self)
    return self.target ~= nil and self.target ~= self.character
end

function EHRMedicationAction:isValid()
    return self.command ~= nil and Common.carries(self.character, self.item, false)
        and Common.reachable(self.character, self.target)
end

-- On yourself: pills like vanilla's ISTakePillAction, liquids like ISDrinkFluidAction, the rest (creams, injections,
-- IVs, inhalers) the loot animation like our other medical actions. On someone else always the loot animation.
function EHRMedicationAction:animate()
    local anim = remote(self) and "loot" or Data.ROUTES[self.med.route].anim
    if anim == "pills" then
        self:setActionAnim(CharacterActionAnims.TakePills)
    elseif anim == "drink" then
        self:setAnimVariable("FoodType", "bottle")
        self:setActionAnim(CharacterActionAnims.Drink)
    else
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Mid")
    end
    return anim
end

-- The progress text: "Use <name> (<tier>)" on yourself, "Administering <name>" on someone else.
function EHRMedicationAction:label()
    local name = self.item:getDisplayName()
    if remote(self) then
        return getText("UI_EHR_MPMedication_Job", name)
    end
    return getText("UI_EHR_MedAction_UseWithTier", name,
        getText(EHRMedicationAction.TIERS[self.med.tier] or EHRMedicationAction.TIERS[0]))
end

function EHRMedicationAction:start()
    self.item = Common.current(self.character, self.item, false)
    self.item:setJobType(self:label())
    self.item:setJobDelta(0)
    if self:animate() ~= "loot" then
        self:setOverrideHandModels(nil, self.item)
    end
end

function EHRMedicationAction:update()
    self.item:setJobDelta(self:getJobDelta())
    if remote(self) then
        self.character:faceThisObject(self.target)
    end
    self.character:setMetabolicTarget(Data.ROUTES[self.med.route].work and Metabolics.HeavyWork
        or Metabolics.LightWork)
end

function EHRMedicationAction:stop()
    self.item:setJobDelta(0)
    ISBaseTimedAction.stop(self)
end

function EHRMedicationAction:perform()
    self.item:setJobDelta(0)
    ISBaseTimedAction.perform(self)
end

function EHRMedicationAction:complete()
    if not self.command then
        return false
    end
    local args = { item = self.item:getID() }
    if remote(self) then
        args.target = PlayerKey.ref(self.target)
    end
    return Authority.run(self.character, self.command, args)
end

function EHRMedicationAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return self.med and Data.ROUTES[self.med.route].ticks or 1
end

---@param character IsoPlayer
---@param item InventoryItem
---@param target IsoPlayer?
---@return EHRMedicationAction
function EHRMedicationAction:new(character, item, target)
    local o = ISBaseTimedAction.new(self, character) --[[@as EHRMedicationAction]]
    o.item = item
    o.target = target
    local fullType = item and item:getFullType()
    o.med = fullType and Data.byType[fullType]
    o.command = o.med and EHRMedicationAction.commandFor(fullType, remote(o)) or nil
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

return EHRMedicationAction
