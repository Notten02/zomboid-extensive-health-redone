-- Scalpel Master on the authority (single player and the dedicated server): keeps every attached player's main-hand
-- scalpel at the values Items/Scalpel gives (x9 damage, x100 ConditionLowerChance for a Scalpel Master; the script's
-- values for anyone else), and puts it back to base when it leaves the hand, on death and on detach. The owning MP
-- client does the same for its local players (Client/Scalpel), so both sides agree without a packet of ours.
-- Main hand only, and nothing is kept in the item's modData, so a buffed scalpel never leaks into the world.
--
-- When: every tick, one getter per player and an identity compare (the work happens only when the main hand changed);
-- every simulation step a full pass re-evaluates held scalpels (trait added or removed by an admin); OnEquipPrimary,
-- OnEquipSecondary and OnWeaponSwing where they fire (harmless where they don't).
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local GameScalpel = require "ExtensiveHealthRedone/Game/Scalpel"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"
local Data = require "ExtensiveHealthRedone/Data/Professions"

local log = Env.logger("Scalpel")

local ServerScalpel = {}

local syncWarned = false

-- Dedicated server: the owner's copy gets the server's fields too (syncHandWeaponFields, as vanilla after attaching
-- weapon parts); the client computes the same values anyway, so this is a cheap extra. Only while the owner still
-- carries the item.
local function sync(player, item)
    if not isServer() or not player:getInventory():containsRecursive(item) then
        return
    end
    local ok, err = pcall(syncHandWeaponFields, player, item)
    if not ok and not syncWarned then
        syncWarned = true
        log:warn("syncHandWeaponFields failed (logged once):", tostring(err))
    end
end

ServerScalpel.tracker = GameScalpel.Tracker.new(function(player, item, boosted)
    log:debug(player:getUsername(), boosted and "boosted" or "reset", "a scalpel")
    sync(player, item)
end)

local tracker = ServerScalpel.tracker

-- Forgets players who left, died or were re-attached as a new character (their scalpel goes back to base first),
-- then reconciles the living attached players.
function ServerScalpel.pass(full)
    tracker:releaseWhere(function(key, player)
        return Runtime.playerFor(key) ~= player or player:isDead()
    end)
    Runtime.eachAttached(function(key, player)
        if not player:isDead() then
            tracker:reconcile(key, player, full)
        end
    end)
end

-- The attached key of a character, or nil (zombies, animals, players we don't serve).
local function keyOf(character)
    local found
    Runtime.eachAttached(function(key, player)
        if player == character then
            found = key
        end
    end)
    return found
end

local function onEquip(character)
    local key = character and keyOf(character)
    if key and not character:isDead() then
        tracker:reconcile(key, character, true)
    end
end

-- Events that may be renamed or missing in a later build (or in the offline fake game) are skipped with a warning.
local function on(name, fn)
    local event = Events[name]
    if event then
        event.Add(fn)
    else
        log:warn("event", name, "does not exist; Scalpel Master relies on the other checks")
    end
end

on("OnTick", function()
    ServerScalpel.pass(false)
end)
on("OnEquipPrimary", onEquip)
on("OnEquipSecondary", onEquip)
on("OnWeaponSwing", function(attacker, weapon)
    tracker:guard(attacker, weapon)
end)
on("OnCharacterDeath", function(character)
    tracker:releasePlayer(character)
end)

Runtime.scheduler:every("scalpelMaster", Runtime.STEP, function()
    ServerScalpel.pass(true)
end, { coalesce = true })

-- Debug --------------------------------------------------------------------------------------------------------------

local function describe(player)
    local item = player:getPrimaryHandItem()
    if not GameScalpel.isScalpel(item) then
        return "main hand: " .. (item and item:getFullType() or "empty") .. "\nScalpel Master: "
            .. tostring(GameScalpel.hasTrait(player))
    end
    ---@cast item HandWeapon
    local current, base = GameScalpel.read(item)
    if not current or not base then
        return "main hand: Base.Scalpel without a script item"
    end
    return string.format("main hand: Base.Scalpel\nScalpel Master: %s\nboosted now: %s\ndamage %.2f-%.2f (script %.2f-%.2f)"
        .. "\nConditionLowerChance %d (script %d)\ncondition %d/%d",
        tostring(GameScalpel.hasTrait(player)), tostring(GameScalpel.shouldBoost(player, item)),
        current.minDamage, current.maxDamage, base.minDamage, base.maxDamage,
        current.conditionLowerChance, base.conditionLowerChance, item:getCondition(), item:getConditionMax())
end

-- trait / untrait: add or remove Scalpel Master; give: a Base.Scalpel; inspect: the held item's fields.
Runtime.registry:register("debug.scalpel", {
    args = { action = { type = "string", oneOf = { trait = true, untrait = true, give = true, inspect = true } } },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        local player = ctx.actor.player
        local token = EHRCharacterTraits and EHRCharacterTraits.scalpelmaster
        if (args.action == "trait" or args.action == "untrait") and token then
            if args.action == "trait" then
                player:getCharacterTraits():add(token)
            else
                player:getCharacterTraits():remove(token)
            end
            if isServer() then
                -- vanilla's PF_Recipes + PF_Traits + PF_AlreadyReadBook (ISReadABook:complete)
                sendSyncPlayerFields(player, 0x00000007)
            end
        elseif args.action == "give" then
            Items.add(player, Data.SCALPEL_TYPE)
        end
        ServerScalpel.pass(true)
        if args.action == "inspect" then
            Transport.toClient(player, "debugDump", { text = describe(player) })
        end
        log:info(ctx.actor.key, "debug: scalpel", args.action)
    end,
})

log:info("scalpel master loaded")

return ServerScalpel
