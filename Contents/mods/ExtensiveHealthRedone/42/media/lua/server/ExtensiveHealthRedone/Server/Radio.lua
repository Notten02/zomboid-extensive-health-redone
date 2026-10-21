-- Airs The Last Prescription on 47.0 MHz from the authority (Phase 8; docs/porting/phase8/flyers-knowledge-radio.md
-- Part C) and rewards its listeners. The rules are Radio/Station and Knowledge/Learn, the constants Data/Radio; this
-- file only translates. An MP client loads this file too and stops at the first line.
--
-- Fixed against v0.9 (sv/EHR_Radio.lua, s/EHR_RadioInteractions.lua):
--   - It airs on a dedicated server: our scheduler (game time, driven by Server/Main in SP and on a server) replaces
--     v0.9's EveryHours hook, which was only added from the client-only OnGameStart.
--   - The channel is registered once, by us, at OnLoadRadioScripts; DynamicRadio.channels and .cache are left alone
--     (v0.9 inserted it there too, risking a double registration that depended on load order). It is not registered
--     when TheLastPrescriptionEnabled is off and the sandbox is readable then (otherwise registered and silent).
--   - Who heard it is decided here, from the server's view of each player's devices, when the final line airs; v0.9's
--     OnDeviceText handler ran on server and client alike and rewarded everyone for lines sent with -1,-1,-1.
--   - Lines have no interaction codes (v0.9's EHX+4 / EHK=<id>): nothing on the client acts on them.
--
-- World state: { lastSlot, story } in global ModData under Data/Radio.WORLD_KEY, written on the authority only and saved
-- with the world, so the story index and the last slot survive a restart. The server never transmits it and clients
-- never read it. The authority keeps its own copy for the session and writes it back on every change, so a table a
-- client might transmit is overwritten at once (if the server reports it) or at the next airing, and Station.clean
-- repairs whatever is loaded.
--
-- Uncertain until tested in game (spec 4.1): that the server sees inventory radios' on/channel/volume state, that it
-- advances the broadcast's line number (otherwise Station's fallback window applies), and whether a channel registered
-- while the station was on stays on the dial after it is switched off.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Data = require "ExtensiveHealthRedone/Data/Radio"
local Station = require "ExtensiveHealthRedone/Radio/Station"
local Learn = require "ExtensiveHealthRedone/Knowledge/Learn"

local log = Env.logger("Radio")

local ServerRadio = {}

local channel     -- our DynamicRadioChannel, once registered
local world       -- the authority's copy of the station state (Station.clean)
local watching    -- the broadcast being judged (Station.watch), or nil

local function enabled()
    return Env.sandbox("TheLastPrescriptionEnabled", true) ~= false
end

-- Radio events don't exist in the offline test game; every real game has them.
local function onEvent(name, fn)
    local event = Events[name]
    if event then
        event.Add(fn)
    else
        log:debug("no event", name)
    end
end

-- Channel ----------------------------------------------------------------------------------------------------------------

-- Runs at every world load, before the scheduler: the channel belongs to the world being loaded.
local function register(scriptManager)
    channel, watching, world = nil, nil, nil
    if Env.sandbox("TheLastPrescriptionEnabled", nil) == false then
        log:info(Data.NAME, "is off; channel not registered")
        return
    end
    -- A Java constructor and the script manager: a boundary, so a failure is logged instead of breaking radio loading.
    local ok, result = pcall(function()
        local ch = DynamicRadioChannel.new(Data.NAME, Data.FREQUENCY, ChannelCategory[Data.CATEGORY], Data.UUID)
        ch:setAirCounterMultiplier(Data.AIR_COUNTER_MULTIPLIER)
        scriptManager:AddChannel(ch, false)
        return ch
    end)
    if ok and result then
        channel = result
        log:info(Data.NAME, "registered on", Data.FREQUENCY / 1000, "MHz")
    else
        log:error("could not register", Data.NAME, ":", tostring(result))
    end
end

onEvent("OnLoadRadioScripts", register)

-- World state ------------------------------------------------------------------------------------------------------------

local function loadWorld()
    if not world then
        world = Station.clean(ModData.getOrCreate(Data.WORLD_KEY))
    end
    return world
end

local function saveWorld()
    local stored = ModData.getOrCreate(Data.WORLD_KEY)
    stored.lastSlot = world.lastSlot
    stored.story = world.story
end

-- A client transmitting our table: put the authority's copy back.
onEvent("OnReceiveGlobalModData", function(key)
    if key == Data.WORLD_KEY and world then
        log:warn("received", key, "from outside; restoring the station state")
        saveWorld()
    end
end)

-- Airing -------------------------------------------------------------------------------------------------------------------

-- getText on the authority, as vanilla's AEBS does: MP players see the server's language.
local function translate(line)
    if line.args then
        ---@diagnostic disable-next-line: redundant-parameter
        return getText(line.key, getText(line.args[1]))
    end
    return getText(line.key)
end

-- Airs a slot now. forced (debug): the real slot later today still airs.
local function air(slot, day, now, forced)
    local w = loadWorld()
    local b = Station.build(slot, day, w, Env.rng.int(100000, 999999))
    if not b then
        return nil
    end
    local broadcast = RadioBroadCast.new(b.id, -1, -1)
    for _, line in ipairs(b.lines) do
        broadcast:AddRadioLine(RadioLine.new(translate(line), line.color[1], line.color[2], line.color[3]))
    end
    channel:setAiringBroadcast(broadcast)
    local lastSlot = w.lastSlot
    Station.aired(w, b)
    if forced then
        w.lastSlot = lastSlot
    end
    saveWorld()
    watching = b.heard and Station.watch(b, now) or nil
    log:info("aired", slot, "day", day, "tip", tostring(b.tip), "story", tostring(b.story), "file", tostring(b.file),
        forced and "(debug)" or "")
    return b
end

-- Listeners ----------------------------------------------------------------------------------------------------------------

local function device(data, kind, square)
    return {
        kind = kind,
        on = data:getIsTurnedOn(),
        channel = data:getChannel(),
        battery = data:getIsBatteryPowered(),
        power = data:getPower(),
        volume = data:getDeviceVolume(),
        headphones = data:getHeadphoneType(),
        x = square and square:getX(),
        y = square and square:getY(),
        z = square and square:getZ(),
        outside = square and square:isOutside(),
    }
end

-- Radios the player carries (main inventory, worn or held), their vehicle's radio, and radios and TVs standing within
-- range on their floor.
local function devicesFor(player)
    local list = {}
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "Radio") then
            local data = item:getDeviceData()
            if data then
                list[#list + 1] = device(data, "carried")
            end
        end
    end
    local vehicle = player:getVehicle()
    local part = vehicle and vehicle:getPartById("Radio")
    local vehicleData = part and part:getDeviceData()
    if vehicleData then
        list[#list + 1] = device(vehicleData, "vehicle")
    end
    local cell = getCell()
    local px, py, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for dx = -Data.RANGE, Data.RANGE do
        for dy = -Data.RANGE, Data.RANGE do
            local square = cell:getGridSquare(px + dx, py + dy, z)
            if square then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    if instanceof(object, "IsoWaveSignal") then
                        ---@cast object IsoWaveSignal
                        local data = object:getDeviceData()
                        if data then
                            list[#list + 1] = device(data, "world", square)
                        end
                    end
                end
            end
        end
    end
    return list
end

local function listener(player)
    local square = player:getCurrentSquare()
    return {
        alive = not player:isDead(),
        awake = not player:isAsleep(),
        x = player:getX(),
        y = player:getY(),
        z = player:getZ(),
        outside = square ~= nil and square:isOutside(),
    }
end

function ServerRadio.listening(player)
    return Station.listening(listener(player), devicesFor(player))
end

local function judge(watch)
    Runtime.eachAttached(function(key, player, state)
        if state.knowledge.radioHeard[watch.heard] or not ServerRadio.listening(player) then
            return
        end
        local rewarded = Runtime.applyNow(key, function(p)
            return Learn.radio(p, watch.heard, watch.reward, watch.day)
        end)
        if rewarded then
            log:info(key, "heard", watch.heard)
        end
    end)
end

local function progress(watch)
    local airing = channel:getAiringBroadcast()
    local ours = airing ~= nil and airing:getID() == watch.id
    return { ours = ours, line = ours and airing:getCurrentLineNumber() or nil }
end

-- Every game minute: air a due slot, then judge the broadcast being watched.
Runtime.scheduler:every("radio", 1, function(_, now)
    if not channel then
        return
    end
    local gameTime = getGameTime()
    local day = Station.day(gameTime:getNightsSurvived())
    local slot = Station.due(loadWorld(), day, gameTime:getHour(), enabled())
    if slot then
        air(slot, day, now, false)
    end
    if watching then
        if Station.check(watching, now, progress(watching)) then
            judge(watching)
        end
        if watching.done then
            watching = nil
        end
    end
end, { coalesce = true })

-- Debug --------------------------------------------------------------------------------------------------------------------

local function status(player)
    local w = loadWorld()
    local gameTime = getGameTime()
    local day = Station.day(gameTime:getNightsSurvived())
    local lines = {
        "The Last Prescription, " .. Data.FREQUENCY / 1000 .. " MHz",
        "enabled: " .. tostring(enabled()) .. ", channel registered: " .. tostring(channel ~= nil),
        "day " .. day .. ", hour " .. gameTime:getHour() .. ", last slot aired: " .. tostring(w.lastSlot),
        "story: last aired " .. w.story .. ", next " .. Station.nextStory(w),
        "today: tip " .. Station.tipFor(day) .. ", file " .. Station.fileFor(day) .. " (" .. Data.FILES[Station.fileFor(day)] .. ")",
        "judging: " .. (watching and (watching.heard .. ", started at minute " .. watching.started) or "nothing"),
        "you are listening: " .. tostring(ServerRadio.listening(player)),
    }
    for _, d in ipairs(devicesFor(player)) do
        lines[#lines + 1] = string.format("  %s radio: on %s, channel %s, battery %s, power %s, volume %s, headphones %s",
            d.kind, tostring(d.on), tostring(d.channel), tostring(d.battery), tostring(d.power), tostring(d.volume),
            tostring(d.headphones))
    end
    return table.concat(lines, "\n")
end

-- morning / afternoon / evening: air that slot now (today's tip or file, the next story episode); status: the station
-- state and what the server sees of your radios; resetStory: the next 15:00 airs episode 1 again.
Runtime.registry:register("debug.radio", {
    args = {
        action = { type = "string", oneOf = { morning = true, afternoon = true, evening = true, status = true,
            resetStory = true } },
    },
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 3, seconds = 5 },
    handler = function(ctx, args)
        local player = ctx.actor.player
        if args.action == "resetStory" then
            loadWorld().story = 0
            saveWorld()
        elseif Data.HOURS[args.action] then
            if channel then
                air(args.action, Station.day(getGameTime():getNightsSurvived()), Env.gameMinutes(), true)
            else
                log:warn("debug: no channel to air on (station off, or not registered)")
            end
        end
        Transport.toClient(player, "debugDump", { text = status(player) })
        log:info(ctx.actor.key, "debug: radio", args.action)
    end,
})

log:info("radio loaded")

return ServerRadio
