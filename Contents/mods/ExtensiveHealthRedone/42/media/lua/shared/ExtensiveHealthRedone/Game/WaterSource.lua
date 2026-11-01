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

return WaterSource
