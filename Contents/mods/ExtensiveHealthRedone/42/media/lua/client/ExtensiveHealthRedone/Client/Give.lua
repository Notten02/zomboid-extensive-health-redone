-- Giving another player medication, a blood bag or saline: the one flow behind the inventory menus' "Give to
-- <player>" (Client/BloodMenu, Client/MedicationMenu) and the exam panel's Administer list.
--
--   Give.options(doctor, patient, bloodType?)  what the doctor carries (bags included) that can be given to patient:
--       an array of { item, label, kind = "medicate" | "transfuse", available, reason, count }, sorted by label.
--       label and reason are translated text; reason says why it is unavailable (nil when available); count is how
--       many items of that type the entry stands for (medication and saline are listed once per type, blood bags
--       once per bag, because each bag has its own freshness).
--       bloodType: the patient's blood type when the caller knows it (the exam model); otherwise the mirror's, which
--       only split screen has. A bag's label says whether it suits the patient only when both are known and the
--       DOCTOR knows blood types (Blood Types flyer or First Aid 8).
--   Give.start(doctor, patient, item)  asks the patient's consent for this one item (purpose medicate or transfuse,
--       Client/Consent), and on a yes queues the timed action (Actions/Medication, Actions/Blood), which applies it
--       on the authority when its time is up. Returns false when the item can't be given at all.
--   Give.addMenu(context, doctor, item, labelKey)  the "Give to" submenu of nearby players for an inventory item.
--
-- What can be given: our own medication that may be given (Data.ownRoute, remote ~= false), the vanilla pills and
-- antibiotics (Data.giveVanilla), blood bags and saline. Only the doctor's side (supplies, freshness, range) is known
-- here; the server checks the patient's side when the action completes and tells the doctor why it refused.

require "ISUI/ISInventoryPaneContextMenu"

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local BloodData = require "ExtensiveHealthRedone/Data/Blood"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"
local Spoilage = require "ExtensiveHealthRedone/Blood/Spoilage"
local Transfusion = require "ExtensiveHealthRedone/Blood/Transfusion"
local Data = require "ExtensiveHealthRedone/Medication/Data"
local Common = require "ExtensiveHealthRedone/Actions/Common"
local BloodActions = require "ExtensiveHealthRedone/Actions/Blood"
local MedicationAction = require "ExtensiveHealthRedone/Actions/Medication"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Consent = require "ExtensiveHealthRedone/Client/Consent"

local Give = {}

-- "medicate", "transfuse", or nil when this item can't be given to someone else.
function Give.kindOf(item)
    local fullType = item:getFullType()
    if Supplies.transfusable[fullType] then
        return "transfuse"
    end
    local med = Data.byType[fullType]
    if med and ((Data.ownRoute[fullType] and med.remote ~= false) or Data.giveVanilla[fullType]) then
        return "medicate"
    end
    return nil
end

-- Other living players within reach (other local players in single player).
function Give.nearbyPlayers(player)
    local list = {}
    local candidates = {}
    if isClient() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do
            candidates[#candidates + 1] = online:get(i)
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            candidates[#candidates + 1] = getSpecificPlayer(i)
        end
    end
    for _, other in ipairs(candidates) do
        if other and other ~= player and not other:isDead() and Common.inRange(player, other) then
            list[#list + 1] = other
        end
    end
    return list
end

-- A bag's freshness as this client sees it (the server decides at completion).
function Give.spoilage(item)
    if item:getFullType() == Supplies.saline then
        return Spoilage.FRESH
    end
    local frozen = instanceof(item, "Food") and item:isFrozen()
    return Spoilage.peek(item:getModData()[BloodData.SPOILAGE_KEY], Env.gameMinutes() / 60, frozen)
end

-- Does this character know blood types (their own mirrored knowledge, or First Aid)?
function Give.knowsTypes(player)
    return Transfusion.knowsTypes(Client.section(player, "knowledge"), player:getPerkLevel(Perks.Doctor))
end

-- The patient's blood type as far as this client knows it: the caller's (exam model), else the mirror's.
function Give.patientBloodType(patient, bloodType)
    if bloodType then
        return bloodType
    end
    local identity = Client.mirror:section(PlayerKey.of(patient), "identity")
    return identity and identity.bloodType or nil
end

-- " (Compatible)" / " (Incompatible)" for a blood bag given to the patient, or "" when the doctor can't tell.
function Give.compatibility(doctor, patient, item, bloodType)
    local donor = Supplies.bloodTypeOf[item:getFullType()]
    local recipient = Give.patientBloodType(patient, bloodType)
    if not (donor and recipient and Give.knowsTypes(doctor)) then
        return ""
    end
    return " " .. getText(Transfusion.compatible(donor, recipient) and "UI_EHR_Transfusion_CompatibleSuffix"
        or "UI_EHR_Transfusion_IncompatibleSuffix")
end

local function has(player, set)
    return player:getInventory():getFirstEvalRecurse(function(item)
        return set[item:getFullType()] == true
    end) ~= nil
end

-- One entry for item (see Give.options), or nil when it can't be given.
function Give.entry(doctor, patient, item, bloodType)
    local kind = Give.kindOf(item)
    if not kind then
        return nil
    end
    local entry = { item = item, kind = kind, label = item:getDisplayName(), available = true, count = 1 }
    local reason
    if kind == "transfuse" then
        local state = Give.spoilage(item)
        entry.label = entry.label .. Give.compatibility(doctor, patient, item, bloodType)
        if state == Spoilage.STALE then
            entry.label = entry.label .. " - " .. getText("UI_EHR_Transfusion_StaleSuffix")
        end
        if state == Spoilage.ROTTEN then
            reason = "UI_EHR_Transfusion_BloodSpoiledDesc"
        elseif not has(doctor, Supplies.ivKit) then
            reason = "UI_EHR_MedAction_RequiresIVKit"
        end
    else
        local med = Data.byType[item:getFullType()]
        if med.supply == "ivKit" and not has(doctor, Supplies.ivKit) then
            reason = "UI_EHR_MedReason_RequiresIVKit"
        elseif med.supply == "syringe" and not has(doctor, Supplies.syringe) then
            reason = "UI_EHR_MedReason_RequiresSyringe"
        end
    end
    if patient:isDead() then
        reason = "UI_EHR_MPMedication_ItemMissing"
    elseif not Common.inRange(doctor, patient) then
        reason = "UI_EHR_MPMedication_TooFar"
    end
    if reason then
        entry.available = false
        entry.reason = getText(reason)
    end
    return entry
end

function Give.options(doctor, patient, bloodType)
    local found = doctor:getInventory():getAllEvalRecurse(function(item)
        return Give.kindOf(item) ~= nil
    end)
    local list = {}
    local byType = {}
    for i = 0, found:size() - 1 do
        local item = found:get(i)
        local fullType = item:getFullType()
        local perItem = Supplies.bloodTypeOf[fullType] ~= nil
        local same = not perItem and byType[fullType]
        if same then
            same.count = same.count + 1
        else
            local entry = Give.entry(doctor, patient, item, bloodType)
            if entry then
                list[#list + 1] = entry
                if not perItem then
                    byType[fullType] = entry
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.label ~= b.label then
            return a.label < b.label
        end
        return a.item:getID() < b.item:getID()
    end)
    return list
end

-- Queues the action for an answered consent, if the patient and the item are still there.
function Give.queue(doctor, patient, item)
    local kind = Give.kindOf(item)
    if not kind or not Common.reachable(doctor, patient) or not doctor:getInventory():containsRecursive(item) then
        return false
    end
    ISInventoryPaneContextMenu.transferIfNeeded(doctor, item)
    if kind == "transfuse" then
        ISTimedActionQueue.add(BloodActions.Transfusion:new(doctor, item, patient))
    else
        ISTimedActionQueue.add(MedicationAction:new(doctor, item, patient))
    end
    return true
end

function Give.start(doctor, patient, item)
    local kind = Give.kindOf(item)
    if not kind or patient == doctor then
        return false
    end
    local ref = PlayerKey.ref(patient)
    Consent.ask(doctor, patient, kind, function(answeredDoctor, targetRef)
        if targetRef == ref then
            Give.queue(answeredDoctor, patient, item)
        end
    end, item)
    return true
end

local function tooltip(option, text)
    local t = ISWorldObjectContextMenu.addToolTip()
    t.description = "<RGB:1,0.3,0.3> " .. text
    option.toolTip = t
end

-- "Give to" (labelKey) with a submenu of nearby players; an entry is greyed out with the reason in its tooltip.
-- Returns the parent option, or nil when nobody is near.
function Give.addMenu(context, doctor, item, labelKey)
    local others = Give.nearbyPlayers(doctor)
    if #others == 0 or not Give.kindOf(item) then
        return nil
    end
    local parent = context:addOption(getText(labelKey), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)
    for _, other in ipairs(others) do
        local entry = Give.entry(doctor, other, item) --[[@as table]]
        local name = other:getUsername()
        if entry.kind == "transfuse" then
            name = name .. Give.compatibility(doctor, other, item)
        end
        local option = sub:addOption(name, doctor, function() Give.start(doctor, other, item) end)
        if not entry.available then
            option.notAvailable = true
            tooltip(option, entry.reason)
        end
    end
    return parent
end

return Give
