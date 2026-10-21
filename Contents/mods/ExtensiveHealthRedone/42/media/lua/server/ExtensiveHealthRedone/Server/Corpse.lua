-- Server side of the corpse, scabies and concussion diseases (Diseases/Corpse, Scabies, Concussion): the facts they
-- need from the world (corpses sharing the player's air, face protection, a sealed vehicle, natural ground, head
-- trauma), the concussion trauma report, and debug commands. An MP client loads this file too and stops at the first
-- line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local Concussion = require "ExtensiveHealthRedone/Diseases/Concussion/Concussion"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"

local log = Env.logger("Corpse")

local Corpse = {}

Corpse.RADIUS = 10              -- tiles, same floor only (v0.9 SEARCH_RADIUS)
Corpse.SCAN_EVERY = 5 / 60      -- game hours between corpse scans per player (ours; v0.9 scanned every ~4 game min)
Corpse.AGE = { decomposing = 24, rotten = 48 }      -- hours since death
Corpse.ENV = { outdoors = 1, indoors = 1.5, smallRoom = 2 }
Corpse.SMALL_ROOM = 20          -- RoomDef area in squares (v0.9's dead getAreaSquares branch, restored)

-- Corpses ------------------------------------------------------------------------------------------------------------

-- Indoors, only the player's own room shares the air (closed rooms don't); outdoors, any outdoor square does.
local function sharesAir(room, square)
    if room then
        return square:getRoom() == room
    end
    return not square:isInARoom()
end

local function envMultiplier(room)
    if not room then
        return Corpse.ENV.outdoors
    end
    local def = room:getRoomDef()
    if def and def:getArea() <= Corpse.SMALL_ROOM then
        return Corpse.ENV.smallRoom
    end
    return Corpse.ENV.indoors
end

-- Counts the corpses around the player by age class. Skeletons and animal carcasses don't count.
function Corpse.scan(player)
    local seen = { fresh = 0, decomposing = 0, rotten = 0, env = 1 }
    local square = player:getCurrentSquare()
    if not square then
        return seen
    end
    local room = square:getRoom()
    seen.env = envMultiplier(room)
    local cell = getCell()
    local now = getGameTime():getWorldAgeHours()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local r = Corpse.RADIUS
    for dx = -r, r do
        for dy = -r, r do
            if dx * dx + dy * dy <= r * r then
                local sq = cell:getGridSquare(px + dx, py + dy, pz)
                if sq and sharesAir(room, sq) then
                    local bodies = sq:getDeadBodys()
                    for i = 0, bodies:size() - 1 do
                        local body = bodies:get(i)
                        if not (body:isSkeleton() or body:isAnimal()) then
                            local death = body:getDeathTime()
                            local age = death > 0 and now - death or 0
                            if age >= Corpse.AGE.rotten then
                                seen.rotten = seen.rotten + 1
                            elseif age >= Corpse.AGE.decomposing then
                                seen.decomposing = seen.decomposing + 1
                            else
                                seen.fresh = seen.fresh + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return seen
end

-- Face protection: a gas mask, improvised gas mask or respirator with a working filter blocks corpse air fully; any
-- other worn item vanilla gives a corpse-sickness defence (dust and surgical masks, bandanas, shemaghs) halves it.
local FILTER_MASKS = { "GAS_MASK", "IMPROVISED_GAS_MASK", "RESPIRATOR" }

local function filtered(item)
    local without = item:getWithoutDrainable()
    return without ~= nil and without ~= "" and instanceof(item, "Clothing") and item:getUsedDelta() > 0
end

function Corpse.protection(player)
    local best = 0
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and instanceof(item, "Clothing") then
            for _, tag in ipairs(FILTER_MASKS) do
                if item:hasTag(ItemTag[tag]) and filtered(item) then
                    return 1
                end
            end
            if item:getCorpseSicknessDefense() > 0 then
                best = 0.5
            end
        end
    end
    return best
end

-- A closed vehicle: it has doors or windows, and every one is closed and whole.
function Corpse.sealed(player)
    local vehicle = player:getVehicle()
    if not vehicle then
        return false
    end
    local boundary = false
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        local door, window = part:getDoor(), part:getWindow()
        if door or window then
            boundary = true
            if part:getCondition() <= 0 or (door and door:isOpen())
                or (window and (window:isOpen() or window:isDestroyed())) then
                return false
            end
        end
    end
    return boundary
end

-- [player key] = { at = world hour of the scan, seen = counts }
local scans = {}

Facts.extend("corpses", function(player, facts)
    local key = PlayerKey.of(player)
    local now = getGameTime():getWorldAgeHours()
    local cached = scans[key]
    if not cached or now - cached.at >= Corpse.SCAN_EVERY or now < cached.at then
        cached = { at = now, seen = Corpse.scan(player) }
        scans[key] = cached
    end
    local seen = cached.seen
    facts.corpses = {
        fresh = seen.fresh, decomposing = seen.decomposing, rotten = seen.rotten, env = seen.env,
        protection = Corpse.protection(player), sealed = Corpse.sealed(player),
    }
end)

-- Scabies: v0.9 also counted floors named grass, dirt or soil, beyond vanilla's natural-floor prefixes.
Facts.extend("ground", function(player, facts)
    local square = player:getCurrentSquare()
    local floor = square and square:getFloor()
    local name = floor and floor:getTextureName()
    name = name and name:lower() or ""
    facts.ground = { natural = name:find("grass", 1, true) ~= nil or name:find("dirt", 1, true) ~= nil
        or name:find("soil", 1, true) ~= nil }
end)

-- Concussion: head pain and fractures, for the trauma check; height and vehicle speed for the server-side causes
-- (Diseases/Concussion SA-4). Unverified in game: that a dedicated server's getZ follows a fall closely enough, and
-- that its copy of the vehicle reports getCurrentSpeedKmHour (vanilla calls it in server/Vehicles/Vehicles.lua, but
-- the driver's client simulates the vehicle). If either stays flat on the server, the client report still works.
Facts.extend("trauma", function(player, facts)
    local parts = player:getBodyDamage():getBodyParts()
    local vehicle = player:getVehicle()
    local trauma = { headPain = 0, fractures = {}, z = player:getZ(),
        speed = vehicle and math.abs(vehicle:getCurrentSpeedKmHour()) or nil }
    for i, name in ipairs(BodyParts.names) do
        local part = parts:get(i - 1)
        if name == "Head" then
            trauma.headPain = part:getAdditionalPain()
        end
        if part:getFractureTime() > 0 then
            trauma.fractures[name] = true
        end
    end
    facts.trauma = trauma
end)

-- Commands -------------------------------------------------------------------------------------------------------------

-- The owning client saw fall or crash damage. The server checks the body itself before rolling, and takes the kind
-- from its own facts (the client's kind is only logged); the server also opens the window by itself (SA-4).
Runtime.registry:register("concussion.trauma", {
    args = { kind = { type = "string", oneOf = { fall = true, crash = true } } },
    rate = { count = 2, seconds = 5 },
    handler = function(ctx, args)
        local opened, kind
        Runtime.applyNow(ctx.actor.key, function(p)
            opened, kind = Concussion.report(p, defs)
        end)
        log:debug(ctx.actor.key, "reported", args.kind, "damage, server says", kind, "; window opened:", opened)
    end,
})

Runtime.registry:register("debug.corpseExposure", {
    args = {
        meter = { type = "string", oneOf = { corpse = true, spores = true } },
        value = { type = "number", min = 0, max = 150 },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            p.state.exposure[args.meter] = args.value
            p.dirty("exposure")
        end)
        log:info(ctx.actor.key, "debug:", args.meter, "exposure set to", args.value)
    end,
})

log:info("corpse, scabies and concussion loaded")

return Corpse
