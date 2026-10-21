-- Carries out delirium episodes the server decides (Diseases/Mind/Delirium): a hallucinated sound only this player
-- hears, a strange line over the head, the coloured screen tint, and the unsafe impulse. W31: the tint shows in MP
-- too. The tint strength comes from the mirrored state.effects.tint; its colour from the last episode message.

require "ISUI/ISUIElement"

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Data = require("ExtensiveHealthRedone/Diseases/Mind/Data").delirium

local log = Env.logger("Delirium")

local Delirium = {}

-- [ownerKey] = { r, g, b } of the current tint
local colourOf = {}
-- [ownerKey] = alpha drawn last frame, eased toward the target so the tint fades in and out
local shown = {}

-- Impulses: each checks again that it can act, then uses vanilla's own actions.

local function nearestWindow(player)
    local square = player:getCurrentSquare()
    if not square then
        return nil
    end
    local best, bestDist
    local r = Data.WINDOW_RADIUS
    for dx = -r, r do
        for dy = -r, r do
            local sq = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            local window = sq and sq:getWindow()
            if window and not window:isDestroyed() and not window:isSmashed() and not window:isInvincible() then
                local dist = dx * dx + dy * dy
                if not bestDist or dist < bestDist then
                    best, bestDist = window, dist
                end
            end
        end
    end
    return best
end

local IMPULSES = {
    window = function(player)
        local window = nearestWindow(player)
        if not window then
            return false
        end
        -- Unlike v0.9, the smash is only queued when the walk to the window could be planned.
        if not luautils.walkAdjWindowOrDoor(player, window:getSquare(), window) then
            return false
        end
        ISTimedActionQueue.add(ISSmashWindow:new(player, window))
        return true
    end,
    dropBackpack = function(player)
        local backpack = player:getClothingItem_Back()
        if not backpack then
            return false
        end
        ISInventoryPaneContextMenu.dropItem(backpack, player:getIndex())
        return true
    end,
    firearm = function(player)
        local weapon = player:getPrimaryHandItem()
        if not (weapon and instanceof(weapon, "HandWeapon") and weapon:isRanged()
            and ISReloadWeaponAction.canShoot(player, weapon)) then
            return false
        end
        ISReloadWeaponAction.attackHook(player, 0, weapon)
        return true
    end,
    -- The shout itself is the server's noise (voice and world sound); nothing more to do here.
    shout = function()
        return true
    end,
}

function Delirium.onEpisode(args)
    local player = Client.localPlayer(args.owner)
    if not player or player:isDead() then
        return
    end
    local key = PlayerKey.of(player)
    -- Only this player hears it: a UI sound is local and never networked.
    if args.sound then
        getSoundManager():playUISound(tostring(args.sound))
    end
    if args.line then
        player:setHaloNote(getText(tostring(args.line)), 255, 230, 185, 600)
    end
    colourOf[key] = Data.COLOURS[tonumber(args.colour) or 1] or Data.COLOURS[1]
    local act = args.impulse and IMPULSES[args.impulse]
    if act and not act(player) then
        log:debug(key, "delirium impulse could not act:", args.impulse)
    end
end

Client.on("delirium", Delirium.onEpisode)

-- The tint: drawn over the world and the HUD in this player's part of the screen, pulsing slowly.
local canvas

local function draw()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then
            local key = PlayerKey.of(player)
            local effects = Client.section(player, "effects")
            local target = effects and tonumber(effects.tint) or 0
            if player:isDead() then
                target = 0
            end
            local alpha = shown[key] or 0
            alpha = alpha + (target - alpha) * 0.05
            if alpha < 0.002 then
                alpha = 0
            end
            shown[key] = alpha
            if alpha > 0 then
                if not canvas then
                    canvas = ISUIElement:new(0, 0, 1, 1)
                    canvas:initialise()
                    canvas:instantiate()
                end
                local colour = colourOf[key] or Data.COLOURS[1]
                local pulse = 0.78 + 0.22 * math.sin(getGameTime():getWorldAgeHours() * 320)
                -- No texture: a plain coloured rectangle, as v0.9 drew it.
                ---@diagnostic disable-next-line: param-type-mismatch
                canvas.javaObject:DrawTextureScaledColor(nil, getPlayerScreenLeft(i), getPlayerScreenTop(i),
                    getPlayerScreenWidth(i), getPlayerScreenHeight(i), colour[1], colour[2], colour[3], alpha * pulse)
            end
        end
    end
end

Events.OnPostUIDraw.Add(draw)

return Delirium
