-- What the owning client does for the health simulation, which only it can do: speak lines, show notices, fall
-- asleep in a blackout and wake up again (epinephrine), fall over (tetanus spasm, tendon weakness), walk slower or not
-- sprint, swing faster (combat stimulants) or move faster (Last Chance Epinephrine) (state.effects), and refuse food
-- with lockjaw.
-- The server decides all of it; this file only carries it out. Everything here reads the mirror, never modData.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"

local log = Env.logger("Effects")

local Effects = {}

local function owner(args)
    return Client.localPlayer(args.owner)
end

Client.on("say", function(args)
    local player = owner(args)
    if player and not player:isDead() then
        player:Say(getText(tostring(args.key)))
    end
end)

Client.on("notice", function(args)
    local player = owner(args)
    if player then
        HaloTextHelper.addBadText(player, getText(tostring(args.key)))
    end
end)

-- Blood-loss blackout: forced sleep for a while, the way vanilla's sleep option starts it.
Client.on("blackout", function(args)
    local player = owner(args)
    if not player or player:isDead() or player:isAsleep() then
        return
    end
    local hours = tonumber(args.hours) or 1
    local wake = getGameTime():getTimeOfDay() + hours
    if wake >= 24 then
        wake = wake - 24
    end
    player:setForceWakeUpTime(wake)
    player:setAsleepTime(0.0)
    player:setAsleep(true)
    if not isClient() then
        getSleepingEvent():setPlayerFallAsleep(player, hours)
    end
    UIManager.setFadeBeforeUI(player:getIndex(), true)
    UIManager.FadeOut(player:getIndex(), 1)
    log:info(PlayerKey.of(player), "blacked out for", hours, "h")
end)

local function canFall(player)
    return not (player:isAsleep() or player:isClimbing() or player:isKnockedDown() or player:isOnFloor()
        or player:isSitOnGround() or player:getVehicle() ~= nil or player:getVariableBoolean("BumpFall"))
end

-- Woken by the server (an epinephrine shot during a blackout). SleepingEvent:wakeUp is what ends vanilla's sleep
-- cleanly, but no vanilla Lua calls it, so it is guarded; the plain flags below end the sleep either way.
Client.on("wake", function(args)
    local player = owner(args)
    if not player or player:isDead() or not player:isAsleep() then
        return
    end
    local ok, err = pcall(function() getSleepingEvent():wakeUp(player) end)
    if not ok then
        log:warn("SleepingEvent:wakeUp failed, waking with setAsleep:", tostring(err))
    end
    if player:isAsleep() then
        player:setAsleep(false)
    end
    player:setForceWakeUpTime(-1)
    UIManager.setFadeBeforeUI(player:getIndex(), false)
    UIManager.FadeIn(player:getIndex(), 1)
    log:info(PlayerKey.of(player), "woken:", tostring(args.reason))
end)

local FALL_TYPES = { pushedFront = true, pushedBehind = true }

-- A spasm or a weak tendon throws the character to the ground (vanilla's debug "fall" recipe). fallType:
-- "pushedFront" (default) or "pushedBehind" (falling while running).
Client.on("fall", function(args)
    local player = owner(args)
    if not player or player:isDead() or not canFall(player) then
        return
    end
    player:setBumpType("stagger")
    player:setVariable("BumpDone", false)
    player:setVariable("BumpFall", true)
    player:setVariable("BumpFallType", FALL_TYPES[args.fallType] and args.fallType or "pushedFront")
end)

-- Combat stimulants: the weapon in the primary hand swings faster (HandWeapon base speed x attackSpeed, v0.9's
-- method; B42 scales melee swings by a speed computed from it). The original speed is kept in the weapon's modData
-- so it can always be put back: on unequip or swap, when the effect ends, and on any weapon that reaches a hand still
-- boosted (dropped or handed over mid-effect, or saved that way). Work happens only when the hands or the multiplier
-- change. stim = { primary, secondary, multiplier, boosted } per player.
Effects.STIM_KEY = "EHR_StimBaseSpeed"

local function isWeapon(item)
    return item ~= nil and instanceof(item, "HandWeapon")
end

function Effects.restoreWeapon(weapon)
    local data = weapon:getModData()
    local original = data[Effects.STIM_KEY]
    if original ~= nil then
        weapon:setBaseSpeed(original)
        data[Effects.STIM_KEY] = nil
    end
end

local function boostWeapon(weapon, multiplier)
    local data = weapon:getModData()
    if data[Effects.STIM_KEY] == nil then
        data[Effects.STIM_KEY] = weapon:getBaseSpeed()
    end
    weapon:setBaseSpeed(data[Effects.STIM_KEY] * multiplier)
end

function Effects.applyAttackSpeed(stim, player, multiplier)
    local primary, secondary = player:getPrimaryHandItem(), player:getSecondaryHandItem()
    if primary == stim.primary and secondary == stim.secondary and multiplier == stim.multiplier then
        return
    end
    stim.primary, stim.secondary, stim.multiplier = primary, secondary, multiplier
    local want = multiplier > 1 and isWeapon(primary) and primary or nil
    if stim.boosted and stim.boosted ~= want then
        Effects.restoreWeapon(stim.boosted)
    end
    if isWeapon(primary) and primary ~= want then
        Effects.restoreWeapon(primary)
    end
    if isWeapon(secondary) and secondary ~= want then
        Effects.restoreWeapon(secondary)
    end
    if want then
        boostWeapon(want, multiplier)
    end
    stim.boosted = want
end

-- Last Chance Epinephrine: extra movement on top of this frame's animation movement (v0.9's method; collision still
-- resolves afterwards). Only while walking or running on foot. getDeferredMovement and moveUnmodded aren't used by
-- vanilla Lua, so the first error turns the boost off for the session.
Effects.MAX_BOOST = 0.25
local moveVec
local boostBroken = false

local function canBoost(player)
    return player:isPlayerMoving() and not (player:isAsleep() or player:getVehicle() ~= nil or player:isOnFloor()
        or player:isClimbing() or player:isSitOnGround() or player:isKnockedDown() or player:isBumped())
end

local function boostStep(player, extra)
    moveVec = moveVec or Vector2.new()
    player:getDeferredMovement(moveVec)
    player:moveUnmodded(moveVec:getX() * extra, moveVec:getY() * extra)
end

local function applyBoost(player, boost)
    if boost <= 1 or boostBroken or not canBoost(player) then
        return
    end
    local ok, err = pcall(boostStep, player, math.min(boost - 1, Effects.MAX_BOOST))
    if not ok then
        boostBroken = true
        log:warn("movement boost disabled:", tostring(err))
    end
end

-- Movement: the server's resolved speed multiplier and sprint block (low blood, diseases; Core/ClientEffects). Both
-- are put back once, when nothing slows or blocks the character any more. v0.9's setCanSprint doesn't exist in
-- 42.21; setAllowSprint does. Then the attack speed and movement boost above.
local slowed = {}
local sprintBlocked = {}
local stims = {}

Events.OnPlayerUpdate.Add(function(player)
    local key = PlayerKey.of(player)
    local effects = Client.section(player, "effects")
    local speed = effects and tonumber(effects.speed) or 1
    if speed < 1 then
        player:setSpeedMod(speed)
        slowed[key] = true
    elseif slowed[key] then
        player:setSpeedMod(1.0)
        slowed[key] = nil
    end
    local noSprint = effects ~= nil and effects.noSprint == true
    if noSprint ~= (sprintBlocked[key] == true) then
        player:setAllowSprint(not noSprint)
        sprintBlocked[key] = noSprint or nil
    end
    stims[key] = stims[key] or {}
    Effects.applyAttackSpeed(stims[key], player, effects and tonumber(effects.attackSpeed) or 1)
    applyBoost(player, effects and tonumber(effects.boost) or 1)
end)

-- Tetanus lockjaw: food (anything that changes hunger) can't be eaten. The server refuses it again on completion.
-- One of the two intercepts allowed by Core/PatchPoints.
local lastWarning = {}

function Effects.lockjaw(player)
    local conditions = Client.section(player, "conditions")
    local tetanus = conditions and conditions.active and conditions.active.tetanus
    return tetanus ~= nil and tetanus.data ~= nil and tetanus.data.lockjaw == true
end

Patches.on("eatValid", {
    name = "tetanusLockjaw",
    intercept = function(action)
        local player = action.character
        if not (action.item and action.item:getHungChange() ~= 0 and Effects.lockjaw(player)) then
            return false
        end
        local key = PlayerKey.of(player)
        local now = Env.realSeconds()
        if not lastWarning[key] or now - lastWarning[key] > 5 then
            lastWarning[key] = now
            player:Say(getText("UI_EHR_Tetanus_CantEat"))
        end
        return true, false
    end,
})

return Effects
