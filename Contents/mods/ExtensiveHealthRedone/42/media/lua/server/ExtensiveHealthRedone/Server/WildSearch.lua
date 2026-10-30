-- The authority for the two wild searches (rules: Wild/Search, Wild/HerbalBoard, Wild/HiveTree, Wild/SpotCooldowns,
-- Wild/Vegetation; numbers: Data/WildSearch). Clients only send intents: start at this square, pick this cell, grab
-- this target, got stung, stop. The server checks the square, the distance and (plant search) the knowledge, keeps
-- the sessions, the plant board and the tree contents, and gives the items, XP and injuries.
--   Plant search:  herb.begin {x,y,z} -> herbSession | herbDenied; herb.pick {session, cell} -> herbReveal (and at
--                  3 hits or the last pick herbResult); herb.stop {session, reason}.
--   Hive search:   hive.begin {x,y,z} -> hiveSession | hiveDenied; hive.collect {session, target} -> hiveCollected;
--                  hive.sting {session, kind} -> hiveStung.
-- World state (cooldowns, tree contents) lives in a server-only global ModData table that is never transmitted
-- (no client can write it); square modData the original mod left is ignored.
-- XP: First Aid "herb" per herb found, Foraging "forage" per finished plant search and per honeycomb or spiderweb.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"
local Data = require "ExtensiveHealthRedone/Data/WildSearch"
local Search = require "ExtensiveHealthRedone/Wild/Search"
local HerbalBoard = require "ExtensiveHealthRedone/Wild/HerbalBoard"
local SpotCooldowns = require "ExtensiveHealthRedone/Wild/SpotCooldowns"
local Vegetation = require "ExtensiveHealthRedone/Wild/Vegetation"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local log = Env.logger("WildSearch")

local WildSearch = {}

local sessions = Search.new()
WildSearch.sessions = sessions      -- read by tests and debugging only

-- World state --------------------------------------------------------------------------------------------------------

local store

-- The global ModData table, fetched on first use (commands only arrive once the world is loaded).
function WildSearch.store()
    if not store then
        store = SpotCooldowns.prepare(ModData.getOrCreate(Data.STORE_TAG))
    end
    return store
end

local known = {}

-- Whether an item script exists (the reward pools name vanilla items; a missing one is skipped, logged once).
local function exists(fullType)
    if known[fullType] == nil then
        known[fullType] = getScriptManager():FindItem(fullType) ~= nil
        if not known[fullType] then
            log:warn("reward item missing, skipped:", fullType)
        end
    end
    return known[fullType]
end

local function env()
    return {
        now = Env.realSeconds(),
        hours = getGameTime():getWorldAgeHours(),
        rng = Env.rng,
        store = WildSearch.store(),
        exists = exists,
    }
end

local vegetationApi
local function api()
    if not vegetationApi then
        vegetationApi = { canBeCut = IsoFlagType.canBeCut, zonesAt = getZones }
    end
    return vegetationApi
end

-- Helpers ------------------------------------------------------------------------------------------------------------

local function reply(player, key, command, args)
    args.owner = key
    Transport.toClient(player, command, args)
end

-- The player stands within range tiles of the square's centre, on its floor.
local function within(player, x, y, z, range)
    if math.floor(player:getZ()) ~= z then
        return false
    end
    local dx, dy = player:getX() - (x + 0.5), player:getY() - (y + 0.5)
    return dx * dx + dy * dy <= range * range
end

local function knowsPlants(key, player)
    local state = Runtime.store:get(key)
    local guide = state ~= nil and state.knowledge.wildPlants == true
    return HerbalBoard.canSearch(guide, player:getPerkLevel(Perks.Doctor), player:getPerkLevel(Perks.PlantScavenging))
end

local handLocations
-- Worn hand clothing that still protects (Search.glovesProtect), or nil.
local function gloves(player)
    handLocations = handLocations or { ItemBodyLocation.HANDS, ItemBodyLocation.HANDS_LEFT, ItemBodyLocation.HANDS_RIGHT }
    for _, location in ipairs(handLocations) do
        local item = player:getWornItem(location)
        if item and instanceof(item, "Clothing") then
            local clothing = item --[[@as Clothing]]
            if Search.glovesProtect(clothing:getCondition(), clothing:getHolesNumber()) then
                return clothing
            end
        end
    end
    return nil
end

-- A thorn, sting or bite. Gloves take it (losing condition); otherwise a hand or forearm gets a scratch through the
-- body writer (no Knox). Returns true when gloves absorbed it.
local function hurt(key, player, source)
    local worn = gloves(player)
    if worn then
        worn:setCondition(math.max(0, worn:getCondition() - Data.GLOVE_WEAR))
        if isServer() then
            syncItemFields(player, worn)
        end
        log:debug(key, source, "absorbed by", worn:getFullType(), "condition now", worn:getCondition())
        return true
    end
    local part = Search.injuryPart(Env.rng)
    Runtime.applyNow(key, function(p)
        p.body:scratch(part, source)
    end)
    log:debug(key, source, "scratched", part)
    return false
end

-- Plant search -------------------------------------------------------------------------------------------------------

-- Hands over a finished search (Search.herbFinish result): items, XP and the reply.
local function deliverHerb(key, result)
    local player = Runtime.playerFor(key)
    local s = result.session
    if not player then
        log:debug(key, "plant search finished while offline; nothing given")
        return
    end
    if result.depleted then
        reply(player, key, "herbResult", { id = s.id, depleted = true })
        return
    end
    local roll = result.roll
    if roll.found then
        for _ = 1, roll.count do
            Items.add(player, roll.item)
        end
    end
    Runtime.applyNow(key, function(p)
        for _ = 1, roll.count do
            p.xp("herb")
        end
        p.xp("forage")
    end)
    reply(player, key, "herbResult", { id = s.id, found = roll.found, item = roll.item, count = roll.count,
        band = roll.band })
    log:debug(key, "plant search at", s.key, s.zoneClass, "hits", s.hits, "misses", s.misses, "hazards", s.hazards,
        "quality", string.format("%.2f", roll.quality), "found", roll.item or "nothing", "x" .. roll.count)
end

local function herbSpot(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    return { key = SpotCooldowns.key(x, y, z), x = x, y = y, z = z, zoneClass = Vegetation.squareClass(square, api()),
        month = getGameTime():getMonth() + 1 }
end

local function openHerb(ctx, square, force)
    local player, key = ctx.actor.player, ctx.actor.key
    local skills = { firstAid = player:getPerkLevel(Perks.Doctor), foraging = player:getPerkLevel(Perks.PlantScavenging) }
    local s, why = Search.herbBegin(sessions, key, herbSpot(square), skills, env(), force)
    if not s then
        return reply(player, key, "herbDenied", { reason = why })
    end
    reply(player, key, "herbSession", { id = s.id, x = s.x, y = s.y, z = s.z, maxPicks = s.maxPicks,
        seconds = Data.herb.SECONDS })
end

-- A plant search only pays out to a player still at the bush: finishing it (the last pick, "time's up" or the
-- deadline sweep) from out of range spends the spot with no roll, as walking away does (Search.herbAbandon).
local function walkedAway(key)
    local s = sessions.herb[key]
    local player = Runtime.playerFor(key)
    return s ~= nil and (not player or not within(player, s.x, s.y, s.z, Data.PLAY_RANGE))
end

local SQUARE_ARGS = {
    x = { type = "number", integer = true },
    y = { type = "number", integer = true },
    z = { type = "number", integer = true },
}

Runtime.registry:register("herb.begin", {
    args = SQUARE_ARGS,
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local player, key = ctx.actor.player, ctx.actor.key
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        if player:getVehicle() or not knowsPlants(key, player) or not square
            or not within(player, args.x, args.y, args.z, Data.BEGIN_RANGE) or not Vegetation.isPatch(square, api()) then
            log:debug(key, "plant search refused at", args.x, args.y, args.z)
            return reply(player, key, "herbDenied", { reason = "invalid" })
        end
        openHerb(ctx, square, false)
    end,
})

Runtime.registry:register("herb.pick", {
    args = {
        session = { type = "number", integer = true, min = 1 },
        cell = { type = "number", integer = true, min = 0, max = Data.herb.CELLS },
    },
    rate = { count = 6, seconds = 2 },
    handler = function(ctx, args)
        local player, key = ctx.actor.player, ctx.actor.key
        local live = Search.herbSession(sessions, key, args.session, Env.realSeconds())
        if live and not within(player, live.x, live.y, live.z, Data.PLAY_RANGE) then
            Search.herbAbandon(sessions, key, env())
            log:debug(key, "plant search abandoned: walked away")
            return reply(player, key, "herbClosed", { id = args.session })
        end
        local e = env()
        local r, why = Search.herbPick(sessions, key, args.session, args.cell, e)
        if not r then
            log:debug(key, "plant pick refused:", why)
            return reply(player, key, "herbReveal", { id = args.session, cell = args.cell, refused = why })
        end
        local gloved
        if r.outcome == "hazard" then
            gloved = hurt(key, player, "thorn")
        end
        local s = r.session
        reply(player, key, "herbReveal", { id = s.id, cell = r.cell, kind = r.kind, outcome = r.outcome,
            gloved = gloved, picks = s.picks, hits = s.hits, misses = s.misses, hazards = s.hazards, done = r.done })
        if r.done then
            deliverHerb(key, Search.herbFinish(sessions, key, e))
        end
    end,
})

Runtime.registry:register("herb.stop", {
    args = {
        session = { type = "number", integer = true, min = 1 },
        reason = { type = "string", oneOf = { cancel = true, time = true } },
    },
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local key = ctx.actor.key
        local e = env()
        local outcome, why = Search.herbStop(sessions, key, args.session, args.reason, e)
        log:debug(key, "plant search stop", args.reason, "->", outcome or why)
        if outcome == "finish" then
            if walkedAway(key) then
                Search.herbAbandon(sessions, key, e)
                log:debug(key, "plant search abandoned: walked away")
                return reply(ctx.actor.player, key, "herbClosed", { id = args.session })
            end
            deliverHerb(key, Search.herbFinish(sessions, key, e))
        end
    end,
})

-- Hive search --------------------------------------------------------------------------------------------------------

local function openHive(ctx, square, content)
    local player, key = ctx.actor.player, ctx.actor.key
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local spot = { key = SpotCooldowns.key(x, y, z), x = x, y = y, z = z }
    local s, tree = Search.hiveBegin(sessions, key, spot, env(), content)
    if not s then
        log:debug(key, "hive search at", spot.key, "denied:", tree)
        return reply(player, key, "hiveDenied", { reason = tree })
    end
    reply(player, key, "hiveSession", { id = s.id, x = x, y = y, z = z, hive = tree.hive, webs = tree.webs,
        seconds = Data.hive.SECONDS })
end

Runtime.registry:register("hive.begin", {
    args = SQUARE_ARGS,
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local player, key = ctx.actor.player, ctx.actor.key
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        if player:getVehicle() or not Vegetation.isTreeSquare(square)
            or not within(player, args.x, args.y, args.z, Data.BEGIN_RANGE) then
            log:debug(key, "hive search refused at", args.x, args.y, args.z)
            return reply(player, key, "hiveDenied", { reason = "invalid" })
        end
        openHive(ctx, square, nil)
    end,
})

Runtime.registry:register("hive.collect", {
    args = {
        session = { type = "number", integer = true, min = 1 },
        target = { type = "string", oneOf = { hive = true, web = true } },
    },
    rate = { count = 4, seconds = 5 },
    handler = function(ctx, args)
        local player, key = ctx.actor.player, ctx.actor.key
        local live = Search.hiveSession(sessions, key, args.session, Env.realSeconds())
        if live and not within(player, live.x, live.y, live.z, Data.PLAY_RANGE) then
            sessions.hive[key] = nil
            return reply(player, key, "hiveCollected", { id = args.session, target = args.target, ok = false,
                done = true })
        end
        local r, why = Search.hiveCollect(sessions, key, args.session, args.target, env())
        if not r then
            log:debug(key, "hive grab refused:", why)
            return reply(player, key, "hiveCollected", { id = args.session, target = args.target, ok = false,
                reason = why })
        end
        Items.add(player, r.item)
        Runtime.applyNow(key, function(p)
            p.xp("forage")
        end)
        reply(player, key, "hiveCollected", { id = args.session, target = args.target, ok = true, item = r.item,
            done = r.done })
        log:debug(key, "hive search at", r.session.key, "took", r.item, r.done and "(tree now empty)" or "")
    end,
})

Runtime.registry:register("hive.sting", {
    args = {
        session = { type = "number", integer = true, min = 1 },
        kind = { type = "string", oneOf = { bee = true, spider = true } },
    },
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local player, key = ctx.actor.player, ctx.actor.key
        if not Search.hiveSting(sessions, key, args.session, env()) then
            return
        end
        local gloved = hurt(key, player, args.kind == "bee" and "sting" or "bite")
        reply(player, key, "hiveStung", { id = args.session, kind = args.kind, gloved = gloved })
    end,
})

-- Upkeep -------------------------------------------------------------------------------------------------------------

-- Sessions past their deadline: a plant search with picks finishes with its roll, others end
-- silently. Checked every game minute (a few real seconds at normal speed).
Runtime.scheduler:every("wildSearchSessions", 1, function()
    if Tables.isEmpty(sessions.herb) and Tables.isEmpty(sessions.hive) then
        return
    end
    local e = env()
    for _, key in ipairs(Tables.sortedKeys(sessions.herb)) do
        if e.now > sessions.herb[key].deadline and walkedAway(key) then
            Search.herbAbandon(sessions, key, e)
            log:debug(key, "plant search abandoned at its deadline: walked away")
        end
    end
    for _, ended in ipairs(Search.herbSweep(sessions, e)) do
        if ended.result then
            deliverHerb(ended.actor, ended.result)
        end
    end
    Search.hiveSweep(sessions, e)
end, { coalesce = true })

-- Once a game day: expired cooldowns, empty cooled-down trees and long-unvisited trees are dropped. Only once the
-- table was loaded.
Runtime.scheduler:every("wildSearchPrune", 24 * 60, function()
    if store then
        local removed = SpotCooldowns.prune(store, getGameTime():getWorldAgeHours(), Data.hive.FORGET_HOURS)
        log:debug("pruned", removed, "spots")
    end
end, { coalesce = true })

-- Debug --------------------------------------------------------------------------------------------------------------
-- reset: forget every cooldown and tree, and this player's sessions. herb / hive: open a game on the square under the
-- player (or the bush or tree square named), skipping knowledge, patch and cooldown checks; hive gets a full tree.

Runtime.registry:register("debug.wildSearch", {
    args = {
        action = { type = "string", oneOf = { reset = true, herb = true, hive = true } },
        x = { type = "number", integer = true, optional = true },
        y = { type = "number", integer = true, optional = true },
        z = { type = "number", integer = true, optional = true },
    },
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 5, seconds = 10 },
    handler = function(ctx, args)
        local player, key = ctx.actor.player, ctx.actor.key
        if args.action == "reset" then
            SpotCooldowns.clear(WildSearch.store())
            sessions.herb[key], sessions.hive[key] = nil, nil
            log:info(key, "debug: wild search cooldowns and trees reset")
            return
        end
        local square = player:getCurrentSquare()
        if args.x and args.y and args.z then
            square = getCell():getGridSquare(args.x, args.y, args.z)
        end
        if not square then
            return
        end
        log:info(key, "debug: open", args.action, "search at", square:getX(), square:getY(), square:getZ())
        if args.action == "herb" then
            openHerb(ctx, square, true)
        else
            openHive(ctx, square, { hive = true, webs = Data.hive.MAX_WEBS })
        end
    end,
})

return WildSearch
