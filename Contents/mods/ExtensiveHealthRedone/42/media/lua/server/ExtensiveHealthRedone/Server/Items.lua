-- Server-side item helpers: finding supplies in a player's own inventory (worn and carried bags included), using
-- them up, adding new items, and blood bag spoilage data. Changes are sent to the client on a dedicated server.

local Env = require "ExtensiveHealthRedone/Game/Env"
local BloodData = require "ExtensiveHealthRedone/Data/Blood"
local Spoilage = require "ExtensiveHealthRedone/Blood/Spoilage"

local log = Env.logger("Items")

local Items = {}

-- The first item in the player's inventory or carried containers whose full type is in the set.
function Items.findFirst(player, set)
    return player:getInventory():getFirstEvalRecurse(function(item)
        return set[item:getFullType()] == true
    end)
end

-- Every such item, as a Lua list.
function Items.findAll(player, set)
    local found = player:getInventory():getAllEvalRecurse(function(item)
        return set[item:getFullType()] == true
    end)
    local list = {}
    for i = 0, found:size() - 1 do
        list[#list + 1] = found:get(i)
    end
    return list
end

function Items.remove(item)
    local container = item:getContainer()
    if not container then
        return false
    end
    container:Remove(item)
    if isServer() then
        sendRemoveItemFromContainer(container, item)
    end
    return true
end

-- Uses one use of a drainable (an IV kit has one), or removes a normal item.
function Items.useOne(item)
    if instanceof(item, "DrainableComboItem") then
        item:UseAndSync()
    else
        Items.remove(item)
    end
end

function Items.add(player, fullType)
    local inventory = player:getInventory()
    local item = inventory:AddItem(fullType)
    if item and isServer() then
        sendAddItemToContainer(inventory, item)
    end
    return item
end

local syncWarned = false

-- Sends an item's modData to its owner on a dedicated server (a failure is logged once).
function Items.syncModData(player, item)
    if not isServer() then
        return
    end
    local ok, err = pcall(syncItemModData, player, item)
    if not ok and not syncWarned then
        syncWarned = true
        log:warn("syncItemModData failed; clients may show stale bag freshness:", err)
    end
end

function Items.isFrozen(item)
    return instanceof(item, "Food") and item:isFrozen()
end

-- Brings a blood bag's spoilage up to now and returns its state ("fresh", "stale", "rotten").
function Items.spoilage(player, item)
    local modData = item:getModData()
    local before = modData[BloodData.SPOILAGE_KEY]
    local wasState = type(before) == "table" and before.stale and (before.rotten and "rotten" or "stale") or "fresh"
    local state, data = Spoilage.update(before, Env.gameMinutes() / 60, Items.isFrozen(item))
    modData[BloodData.SPOILAGE_KEY] = data
    if state ~= wasState or before == nil then
        Items.syncModData(player, item)
    end
    return state
end

-- Marks a newly filled bag as fresh, with the donor's type.
function Items.markDrawn(player, item, bloodType)
    local modData = item:getModData()
    modData[BloodData.SPOILAGE_KEY] = Spoilage.new(Env.gameMinutes() / 60)
    modData[BloodData.DONOR_KEY] = bloodType
    Items.syncModData(player, item)
end

return Items
