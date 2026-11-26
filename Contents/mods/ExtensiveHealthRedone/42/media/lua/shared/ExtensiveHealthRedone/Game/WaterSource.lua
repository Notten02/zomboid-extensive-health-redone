-- A usable world water source (sink, rain collector, bathtub, ...), found the same way by the "Wash Hands" menu
-- (Client/WashHands) and by the authority that does the washing (Server/Food).
--
-- Always by square, never by the clicked object alone: a mouse right-click hands the menu only the object under the
-- cursor (a sink's tap, or the cabinet the tap stands on), a gamepad the first object of up to four squares (usually
-- the floor), and vanilla's own menu looks at every object on those squares. Looking at the clicked objects alone
-- missed the sink whenever the click landed on its cabinet, while vanilla still offered Drink and Wash there.
--
--   WaterSource.at(square)            -- the first source on the square with water in it, or nil
--   WaterSource.near(worldobjects)    -- the first one on any clicked object's square, or nil
--
-- And a carried container (bottle, canteen, bucket, pot, ...), for the same menu on an inventory item:
--
--   WaterSource.carried(item)         -- the water in it to wash with (0 when it is no use), and whether it is soapy
--
-- Any item with a fluid container counts, read through the fluid API: nothing here names an item.

local WaterSource = {}

-- Not a puddle or a dropped item, with water in it.
function WaterSource.at(square)
    if not square then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object:getFluidAmount() > 0 and not instanceof(object, "IsoWorldInventoryObject") then
            return object
        end
    end
    return nil
end

-- worldobjects: the list OnFillWorldObjectContextMenu passes. Each square is looked at once.
function WaterSource.near(worldobjects)
    local seen = {}
    for _, object in ipairs(worldobjects or {}) do
        local square = object:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local source = WaterSource.at(square)
            if source then
                return source
            end
        end
    end
    return nil
end

-- Fluids that make water soapy, by fluid type name: vanilla's own cleaning liquids (ISWorldObjectContextMenu's
-- predicateCleaningLiquid), as the game has no fluid category for them. A mod can add its own name.
WaterSource.CLEANERS = { "CleaningLiquid", "Bleach" }

-- Whether a fluid container has a cleaning fluid in it.
function WaterSource.soapy(fluid)
    for _, name in ipairs(WaterSource.CLEANERS) do
        local cleaner = Fluid.Get(name)
        if cleaner and fluid:contains(cleaner) then
            return true
        end
    end
    return false
end

-- It has to be mostly water: the primary fluid is in the Water category (clean or tainted as at a river, carbonated,
-- or a mod's own water). So not petrol, neat bleach or a drink, but water with something mixed in still washes, and
-- with a cleaning fluid in it, it washes like soap. A sealed bottle has to be opened first, as for drinking.
function WaterSource.carried(item)
    local fluid = item and item:getFluidContainer()
    if not fluid or fluid:isEmpty() or item:isSealed() then
        return 0, false
    end
    local primary = fluid:getPrimaryFluid()
    if not primary or not primary:isCategory(FluidCategory.Water) then
        return 0, false
    end
    return fluid:getAmount(), WaterSource.soapy(fluid)
end

return WaterSource
