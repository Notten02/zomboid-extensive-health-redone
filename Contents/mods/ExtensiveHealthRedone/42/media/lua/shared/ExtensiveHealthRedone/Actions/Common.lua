-- Helpers our shared timed actions (Actions/*.lua) have in common: is the item still carried, is the patient still
-- in reach, and the item a client-side action should hold on to.
--
-- isValid runs on the client while the action plays and on the authority before complete(). Like vanilla's shared
-- actions (ISTakePillAction, ISApplyBandage), the client checks the item by ID, because the object it holds may be
-- a stale copy after a transfer; the authority checks the object it rebuilt the action with.

local StitchData = require("ExtensiveHealthRedone/Data/Wounds").stitch

local Common = {}

-- Tiles to another player for every remote treatment (3, same floor or same vehicle; Server/Consent asks within it).
Common.RANGE = StitchData.RANGE

-- recursive: also in carried bags (the watch and its battery); otherwise the main inventory, where the menus put the
-- item first (ISInventoryPaneContextMenu.transferIfNeeded).
function Common.carries(character, item, recursive)
    if not item then
        return false
    end
    local inventory = character:getInventory()
    if isClient() then
        if recursive then
            return inventory:getItemWithIDRecursiv(item:getID()) ~= nil
        end
        return inventory:containsID(item:getID())
    end
    if recursive then
        return inventory:containsRecursive(item)
    end
    return inventory:contains(item)
end

-- The client's current object for an item the action was made with (vanilla does this in start()).
function Common.current(character, item, recursive)
    if not (isClient() and item) then
        return item
    end
    local inventory = character:getInventory()
    local found
    if recursive then
        found = inventory:getItemWithIDRecursiv(item:getID())
    else
        found = inventory:getItemById(item:getID())
    end
    return found or item
end

-- Same vehicle, or the same floor and within RANGE tiles.
function Common.inRange(a, b)
    local vehicle = a:getVehicle()
    if vehicle and vehicle == b:getVehicle() then
        return true
    end
    if math.floor(a:getZ()) ~= math.floor(b:getZ()) then
        return false
    end
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return dx * dx + dy * dy <= Common.RANGE * Common.RANGE
end

-- A patient another player treats: alive and in reach. target nil means the character treats themselves.
function Common.reachable(character, target)
    return target == nil or target == character or (not target:isDead() and Common.inRange(character, target))
end

return Common
