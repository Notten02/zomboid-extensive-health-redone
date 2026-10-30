-- The Medical Monitor Watch battery on the authority (Items/WatchBattery, Game/Watch): draining the batteries of
-- watches online players wear or hold, inserting and removing batteries, and telling an MP client its watches'
-- state. An MP client loads this file too and stops at the first line.
--
-- Drain: every DRAIN_MINUTES of game time (the runtime's scheduler, so it follows game time at any FPS and pauses for
-- offline players). A watch that runs out has its alarm switched off.
-- Sync (MP only; single player shares the item objects): our own small "watchBattery" message, sent when a watch's
-- whole percent or powered state changes, after a swap, and when the client asks on joining. The client writes it
-- into its copy of the item's modData.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Watch = require "ExtensiveHealthRedone/Game/Watch"
local WatchBattery = require "ExtensiveHealthRedone/Items/WatchBattery"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"

local log = Env.logger("Watch")

local ServerWatch = {}

ServerWatch.DRAIN_MINUTES = 10

-- Sends the battery state of these watches to the owner's client (MP only).
function ServerWatch.sync(key, player, watches)
    if not isServer() or #watches == 0 then
        return
    end
    local list = {}
    for _, item in ipairs(watches) do
        local state = Watch.state(item)
        list[#list + 1] = { id = item:getID(), installed = state.installed, charge = state.charge }
    end
    Transport.toClient(player, "watchBattery", { owner = key, watches = list })
end

-- One drain step for one player's worn and held watches.
function ServerWatch.drain(key, player, minutes)
    local changed = {}
    for _, item in ipairs(Watch.worn(player)) do
        local state = Watch.state(item)
        local percent = WatchBattery.percent(state)
        local moved, depleted = WatchBattery.drain(state, minutes)
        if moved then
            Watch.save(item, state)
            if depleted then
                Watch.silence(item)
                log:debug(key, "medical watch battery ran out")
            end
            if depleted or WatchBattery.percent(state) ~= percent then
                changed[#changed + 1] = item
            end
        end
    end
    ServerWatch.sync(key, player, changed)
end

Runtime.scheduler:every("watchBattery", ServerWatch.DRAIN_MINUTES, function(dt)
    Runtime.eachAttached(function(key, player)
        if not player:isDead() then
            ServerWatch.drain(key, player, dt)
        end
    end)
end)

-- Commands ------------------------------------------------------------------------------------------------------------

Runtime.registry:register("watch.insertBattery", {
    args = {
        watch = { type = "item", types = WatchBattery.TYPES },
        battery = { type = "item", types = { [WatchBattery.BATTERY] = true } },
    },
    action = true,     -- Actions/WatchBattery's EHRWatchBatteryAction, like watch.removeBattery
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local watch, battery = args.watch.item, args.battery.item
        local state = Watch.state(watch)
        local charge = Watch.batteryCharge(battery)
        local refusal = WatchBattery.insertRefusal(state, charge)
        if refusal then
            log:debug(ctx.actor.key, "battery not inserted:", refusal)
            return
        end
        if not Items.remove(battery) then
            return
        end
        WatchBattery.insert(state, charge)
        Watch.save(watch, state)
        ServerWatch.sync(ctx.actor.key, ctx.actor.player, { watch })
    end,
})

Runtime.registry:register("watch.removeBattery", {
    args = { watch = { type = "item", types = WatchBattery.TYPES } },
    action = true,
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local player, watch = ctx.actor.player, args.watch.item
        local state = Watch.state(watch)
        if WatchBattery.removeRefusal(state) then
            return
        end
        local charge = WatchBattery.remove(state)
        Watch.save(watch, state)
        Watch.silence(watch)
        -- The battery comes out with the charge it had.
        local battery = Items.add(player, WatchBattery.BATTERY)
        if battery then
            battery:setCurrentUsesFloat(charge)
            if isServer() then
                syncItemFields(player, battery)
            end
        end
        ServerWatch.sync(ctx.actor.key, player, { watch })
    end,
})

-- The client asks for the state of every watch it carries when its player is created (MP).
Runtime.registry:register("watch.sync", {
    rate = { count = 2, seconds = 10 },
    handler = function(ctx)
        ServerWatch.sync(ctx.actor.key, ctx.actor.player, Watch.carried(ctx.actor.player))
    end,
})

log:info("medical watch loaded")

return ServerWatch
