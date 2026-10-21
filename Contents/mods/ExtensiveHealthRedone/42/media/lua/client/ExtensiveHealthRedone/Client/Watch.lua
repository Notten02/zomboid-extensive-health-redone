-- The Medical Monitor Watch on the client (Game/Watch, Items/WatchBattery; the authority is Server/Watch):
--   * the inventory context menu: "Insert Battery (N%)" with the best charged vanilla battery carried, or "Remove
--     Battery (N%)", each a short shared timed action (Actions/WatchBattery) that the server completes; vanilla's
--     "Set Alarm" is removed for a watch without power (it couldn't ring);
--   * the HUD clock: hidden while a local player wears or holds a dead medical watch and no local player has anything
--     else that tells the time. The decision is made about once a real second (never an inventory scan per frame);
--     only while suppressing is the clock touched, every frame, because the game may show it again itself;
--   * MP: the server's "watchBattery" message is written into our copy of the item, and every carried watch is asked
--     for when a player is created;
--   * the tooltip lines (time and alarm while powered, battery %), through Client/ItemTooltip when it is there.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Watch = require "ExtensiveHealthRedone/Game/Watch"
local WatchBattery = require "ExtensiveHealthRedone/Items/WatchBattery"
local Text = require "ExtensiveHealthRedone/UI/Text"
local Client = require "ExtensiveHealthRedone/Client/Client"
local BatteryAction = require "ExtensiveHealthRedone/Actions/WatchBattery"

local ClientWatch = {}

ClientWatch.ACTION_TICKS = BatteryAction.TICKS
ClientWatch.CLOCK_CHECK_MS = 1000

ClientWatch.Action = BatteryAction

-- Context menu --------------------------------------------------------------------------------------------------------

local function percentOf(charge)
    return math.max(1, math.floor(charge * 100 + 0.5))
end

-- Adds the battery option for a medical watch and removes "Set Alarm" when it has no power.
function ClientWatch.menu(player, context, watch)
    local state = Watch.state(watch)
    if state.installed then
        local label = getText("UI_EHR_WatchBattery_Remove", WatchBattery.percent(state))
        context:addOption(label, player, function()
            ISTimedActionQueue.add(BatteryAction:new(player, watch, nil, label))
        end)
    else
        local battery = Watch.bestBattery(player)
        if battery then
            local label = getText("UI_EHR_WatchBattery_Insert", percentOf(Watch.batteryCharge(battery)))
            context:addOption(label, player, function()
                ISTimedActionQueue.add(BatteryAction:new(player, watch, battery, label))
            end)
        end
    end
    if not WatchBattery.powered(state) then
        context:removeOptionByName(getText("ContextMenu_SetAlarm"))
    end
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then
        return
    end
    -- Each entry is an item, or a stack whose items list (a Lua table) starts with the item itself.
    local first = items[1]
    local item
    if first and instanceof(first, "InventoryItem") then
        item = first --[[@as InventoryItem]]
    elseif first then
        local stack = first --[[@as umbrella.ContextMenuItemStack]]
        item = stack.items and stack.items[1]
    end
    if item and Watch.isMedical(item) then
        ClientWatch.menu(player, context, item)
    end
end)

-- HUD clock -----------------------------------------------------------------------------------------------------------

local suppress = false      -- the last decision
local hidden = false        -- we are hiding the clock now
local wasVisible = false    -- the clock was visible when we started
local lastCheck = 0

-- Hide the clock: some local player wears or holds a dead medical watch, and nobody has a working clock.
function ClientWatch.shouldHideClock()
    local dead, working = false, false
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() then
            local d, w = Watch.clockState(player)
            dead = dead or d
            working = working or w
        end
    end
    return dead and not working
end

local function updateClock()
    local clock = UIManager.getClock()
    if not clock then
        return
    end
    if suppress then
        if not hidden then
            hidden = true
            wasVisible = clock:isVisible()
        end
        clock:setVisible(false)
    elseif hidden then
        hidden = false
        if wasVisible then
            clock:setVisible(true)
            clock:resize()
        end
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastCheck >= ClientWatch.CLOCK_CHECK_MS then
        lastCheck = now
        suppress = ClientWatch.shouldHideClock()
    end
end)

Events.OnPreUIDraw.Add(function()
    if suppress or hidden then
        updateClock()
    end
end)

-- MP sync -------------------------------------------------------------------------------------------------------------

Client.on("watchBattery", function(args)
    local player = Client.localPlayer(args.owner)
    if not player or type(args.watches) ~= "table" then
        return
    end
    for _, w in ipairs(args.watches) do
        local item = player:getInventory():getItemWithIDRecursiv(w.id)
        if item and Watch.isMedical(item) then
            Watch.save(item, { installed = w.installed == true, charge = tonumber(w.charge) or 0 })
        end
    end
    suppress = ClientWatch.shouldHideClock()
end)

Events.OnCreatePlayer.Add(function(_, player)
    if Env.isMultiplayer() then
        Client.send(player, "watch.sync", {})
    end
end)

-- Tooltip lines -------------------------------------------------------------------------------------------------------

local function clockText(hour, minute)
    if getCore():getOptionClock24Hour() then
        return string.format("%02d:%02d", hour, minute)
    end
    local suffix = hour < 12 and "AM" or "PM"
    local h = hour % 12
    return string.format("%d:%02d %s", h == 0 and 12 or h, minute, suffix)
end

-- The watch's tooltip lines (Client/ItemTooltip's provider format).
function ClientWatch.tooltipLines(item)
    if not Watch.isMedical(item) then
        return nil
    end
    local state = Watch.state(item)
    local lines = {}
    local battery = Text.key("UI_EHR_WatchBattery_Battery")
    if not state.installed then
        lines[#lines + 1] = { label = battery, value = Text.key("UI_EHR_WatchBattery_NotInstalled"), color = "dim" }
        return lines
    elseif not WatchBattery.powered(state) then
        lines[#lines + 1] = { label = battery, value = Text.key("UI_EHR_WatchBattery_Depleted"), color = "red" }
        return lines
    end
    local timeOfDay = getGameTime():getTimeOfDay()
    local hour = math.floor(timeOfDay)
    lines[#lines + 1] = { label = Text.key("UI_EHR_WatchBattery_Time"),
        value = Text.raw(clockText(hour, math.floor((timeOfDay - hour) * 60))) }
    if item:isAlarmSet() then
        lines[#lines + 1] = { label = Text.key("UI_EHR_WatchBattery_Alarm"),
            value = Text.raw(clockText(item:getHour(), item:getMinute())) }
    end
    local percent = WatchBattery.percent(state)
    local color = percent > 50 and "green" or (percent > 20 and "yellow" or "red")
    lines[#lines + 1] = { label = battery, value = Text.percent(percent), color = color, progress = state.charge }
    return lines
end

local ok, ItemTooltip = pcall(require, "ExtensiveHealthRedone/Client/ItemTooltip")
if ok and type(ItemTooltip) == "table" and ItemTooltip.addProvider then
    ItemTooltip.addProvider(function(item)
        return ClientWatch.tooltipLines(item)
    end)
end

return ClientWatch
