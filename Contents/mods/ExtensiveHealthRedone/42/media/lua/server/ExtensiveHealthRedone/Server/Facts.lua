-- Reads the plain facts the simulation systems need from a player: stats, sleep, vehicle, the surroundings, and per
-- body part the wound flags vanilla keeps. Systems never see game objects; this is the only translation from the game
-- to them.
--
-- facts = {
--   health, asleep, inVehicle, firstAid,
--   stats = { [NAME] = raw value }, norm = { [NAME] = share of the stat's range, 0-1 },
--   parts = { [part] = { health, bleeding, bandaged, bandageDirty, deep, glass, bullet, cut, bite, scratch, burn,
--                        stitched, infected, wound } },
--   env = { airC, vehicleC (nil outside a vehicle), indoors, shade, wetness 0-1, raining, snowing, groundSnow,
--           hour (0-24, fractional), month (1-12), sitOnGround, moving, running, sprinting, exerting, naturalFloor,
--           female },
--   plus whatever feature readers add (Facts.extend), e.g. facts.corpses.
-- }
--
-- Feature readers: Facts.extend("corpses", function(player, facts, ranges) facts.corpses = ... end). They run after
-- the base facts, in name order, every simulation step; keep them cheap or throttle them with their own state.

local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local WoundData = require "ExtensiveHealthRedone/Data/Wounds"

local Facts = {}

local readers = {}
local readerNames = {}

function Facts.extend(name, fn)
    if not readers[name] then
        readerNames[#readerNames + 1] = name
        table.sort(readerNames)
    end
    readers[name] = fn
end

Facts.STATS = { "HUNGER", "THIRST", "FATIGUE", "STRESS", "PANIC", "PAIN", "ENDURANCE", "TEMPERATURE", "SICKNESS",
    "WETNESS", "UNHAPPINESS", "BOREDOM", "FOOD_SICKNESS" }

-- The game object of a body part by our name (BodyPartType index order, see Data/BodyParts).
function Facts.bodyPart(player, name)
    for i, n in ipairs(BodyParts.names) do
        if n == name then
            return player:getBodyDamage():getBodyParts():get(i - 1)
        end
    end
    return nil
end

function Facts.partName(bodyPart)
    return BodyParts.names[bodyPart:getIndex() + 1]
end

local function part(bp)
    local infectedLevel = bp:getWoundInfectionLevel()
    local f = {
        health = bp:getHealth(),
        bleeding = bp:bleeding() or bp:getBleedingTime() > 0,
        bandaged = bp:bandaged(),
        bandageDirty = bp:isBandageDirty(),
        deep = bp:deepWounded(),
        glass = bp:haveGlass(),
        bullet = bp:haveBullet(),
        cut = bp:isCut(),
        bite = bp:bitten(),
        scratch = bp:scratched(),
        burn = bp:isBurnt(),
        stitched = bp:stitched(),
        infected = bp:isInfectedWound() or infectedLevel > WoundData.infection.VANILLA_EPSILON,
    }
    f.wound = bp:HasInjury() or f.stitched or f.bleeding or f.deep or f.glass or f.bullet
    return f
end

-- vanilla's own natural-ground test (ISEmptyGraves, ISShovelGroundCursor)
local function naturalFloor(square)
    local floor = square:getFloor()
    local name = floor and floor:getTextureName()
    if not name then
        return false
    end
    return name:find("^floors_exterior_natural") ~= nil or name:find("^blends_natural_0[12]") ~= nil
end

local function env(player, stats, ranges)
    local climate = getClimateManager()
    local square = player:getCurrentSquare()
    local vehicle = player:getVehicle()
    local time = getGameTime()
    local wetness = 0
    local range = ranges.WETNESS
    if range and range.max > range.min then
        wetness = (stats:get(CharacterStat.WETNESS) - range.min) / (range.max - range.min)
    end
    local e = {
        airC = climate:getAirTemperatureForCharacter(player, false),
        vehicleC = vehicle and vehicle:getInsideTemperature() or nil,
        indoors = square ~= nil and square:isInARoom(),
        shade = square ~= nil and not square:has(IsoFlagType.exterior),
        wetness = math.max(0, math.min(1, wetness)),
        raining = climate:isRaining(),
        snowing = climate:isSnowing(),
        groundSnow = square ~= nil and getCell():gridSquareIsSnow(square:getX(), square:getY(), square:getZ()),
        hour = time:getTimeOfDay(),
        month = time:getMonth() + 1,
        sitOnGround = player:isSitOnGround(),
        moving = player:isPlayerMoving(),
        running = player:isRunning(),
        sprinting = player:isSprinting(),
        naturalFloor = square ~= nil and naturalFloor(square),
        female = player:isFemale(),
    }
    e.exerting = e.running or e.sprinting or player:isAiming()
    return e
end

-- ranges: { [NAME] = { min, max } } from the stat writer.
function Facts.read(player, ranges)
    local stats = player:getStats()
    local body = player:getBodyDamage()
    local facts = {
        health = body:getOverallBodyHealth(),
        asleep = player:isAsleep(),
        inVehicle = player:getVehicle() ~= nil,
        firstAid = player:getPerkLevel(Perks.Doctor),
        stats = {},
        norm = {},
        parts = {},
    }
    for _, name in ipairs(Facts.STATS) do
        local stat = CharacterStat[name]
        local range = ranges[name]
        if stat and range then
            local value = stats:get(stat)
            facts.stats[name] = value
            if range.max > range.min then
                facts.norm[name] = (value - range.min) / (range.max - range.min)
            end
        end
    end
    local list = body:getBodyParts()
    for i, name in ipairs(BodyParts.names) do
        facts.parts[name] = part(list:get(i - 1))
    end
    facts.env = env(player, stats, ranges)
    facts.env.exerting = facts.env.exerting or (facts.norm.ENDURANCE or 1) < 0.5
    for _, name in ipairs(readerNames) do
        readers[name](player, facts, ranges)
    end
    return facts
end

-- Checks once that vanilla's body part order still matches Data/BodyParts. Returns a list of mismatches.
function Facts.checkOrder(player)
    local wrong = {}
    local list = player:getBodyDamage():getBodyParts()
    for i, name in ipairs(BodyParts.names) do
        local actual = BodyPartType.ToString(list:get(i - 1):getType())
        if actual ~= name then
            wrong[#wrong + 1] = name .. "=" .. tostring(actual)
        end
    end
    return wrong
end

return Facts
