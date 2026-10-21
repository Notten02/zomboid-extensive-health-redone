-- Which squares the wild searches are offered on, decided the same way by the client's context menu and the server.
--   Plant search: an outdoor square (no room) with a bush, whose hash passes the zone density. A bush is a tile whose
--   CustomName is "Bush", or with the canBeCut flag (vanilla's "Remove Bush" cursor), or an f_bushes_ sprite: in 42.21
--   most wild bushes carry only the name (45 + 52 "Bush" tiles in newtiledefinitions and the erosion tiles, canBeCut
--   on 32), so canBeCut alone missed most of them (found in game 2026-10-20). Hedges and ornamental bushes don't count. So only some bushes are search patches, the same ones for every
--   player and every visit.
--   Hive search: an outdoor square with a tree (square:getTree()).
-- From v0.9 c/EHR_HerbalSearch.lua:185-272 and c/EHR_HiveWebSearch.lua:107-166 (docs/porting/phase8/
-- herbal-and-hive-minigames.md sections 1, 5, 13.7). Changes: bushes instead of any grass floor (H13); the density is
-- checked on the server too (H14); the zone class comes from every zone at the point with vanilla's own type names
-- (H15).
--
-- Pure apart from calling methods on the square handed in: the game globals it needs come in an api table built by
-- the caller, { canBeCut = IsoFlagType.canBeCut, zonesAt = getZones }, so tests can pass fakes.

local Data = require "ExtensiveHealthRedone/Data/WildSearch"

local Vegetation = {}

-- v0.9's per-square hash, 0-9999.
function Vegetation.hash(x, y, z)
    local h = (x * 73856093 + y * 19349663 + z * 83492791) % 10000
    if h < 0 then
        h = -h
    end
    return h
end

-- Vanilla forage zone type names (shared/Foraging/forageZones.lua) by class. Anything else is "other".
local FOREST = {
    Forest = true, PHForest = true, PHMixForest = true, PRForest = true, FarmMixForest = true, FarmForest = true,
    BirchForest = true, BirchMixForest = true, OrganicForest = true,
}
local FARM = { Farm = true, FarmLand = true }
local RANK = { deepForest = 5, forest = 4, vegitation = 3, farm = 2, other = 1 }

function Vegetation.classOf(zoneType)
    if zoneType == "DeepForest" then
        return "deepForest"
    elseif FOREST[zoneType] then
        return "forest"
    elseif zoneType == "Vegitation" then
        return "vegitation"
    elseif FARM[zoneType] then
        return "farm"
    end
    return "other"
end

-- The best class among a list of zone type names (DeepForest first, then forests, Vegitation, farms).
function Vegetation.zoneClass(types)
    local best = "other"
    for _, zoneType in ipairs(types) do
        local class = Vegetation.classOf(zoneType)
        if RANK[class] > RANK[best] then
            best = class
        end
    end
    return best
end

-- Whether a bush square with this hash and zone class is a search patch.
function Vegetation.passesDensity(x, y, z, zoneClass)
    return Vegetation.hash(x, y, z) % 100 < (Data.herb.DENSITY[zoneClass] or Data.herb.DENSITY.other)
end

-- Square readers --------------------------------------------------------------------------------------------------

-- The zone type names at a point (ground level, as vanilla's forage lookup).
function Vegetation.zoneTypes(x, y, api)
    local types = {}
    local zones = api.zonesAt(x, y, 0)
    if zones then
        for i = 0, zones:size() - 1 do
            local zoneType = zones:get(i):getType()
            if zoneType then
                types[#types + 1] = tostring(zoneType)
            end
        end
    end
    return types
end

function Vegetation.isOutdoor(square)
    return square:getRoom() == nil and square:isOutside()
end

Vegetation.BUSH_NAME = "Bush"
Vegetation.BUSH_SPRITE = "f_bushes_"

function Vegetation.isBushSprite(sprite, api)
    if not sprite then
        return false
    end
    local props = sprite:getProperties()
    if props and (props:has(api.canBeCut) or props:get("CustomName") == Vegetation.BUSH_NAME) then
        return true
    end
    local name = sprite:getName()
    return name ~= nil and name:sub(1, #Vegetation.BUSH_SPRITE) == Vegetation.BUSH_SPRITE
end

function Vegetation.hasBush(square, api)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if Vegetation.isBushSprite(objects:get(i):getSprite(), api) then
            return true
        end
    end
    return false
end

-- The zone class of a square (for the find chance).
function Vegetation.squareClass(square, api)
    return Vegetation.zoneClass(Vegetation.zoneTypes(square:getX(), square:getY(), api))
end

-- A plant search patch: outdoor bush square passing the density hash.
function Vegetation.isPatch(square, api)
    if not square or not Vegetation.isOutdoor(square) or not Vegetation.hasBush(square, api) then
        return false
    end
    return Vegetation.passesDensity(square:getX(), square:getY(), square:getZ(), Vegetation.squareClass(square, api))
end

function Vegetation.isTreeSquare(square)
    return square ~= nil and square:getRoom() == nil and square:getTree() ~= nil
end

return Vegetation
