-- Scalpel Master on game objects, used the same way by the authority (Server/Scalpel) and the owning MP client
-- (Client/Scalpel). The rules are Items/Scalpel; this file reads the item, its script and the holder, and writes the
-- three weapon fields.
--
-- Both sides compute the same values from the same inputs (the trait, the script item, the held item; vanilla syncs
-- equipment and traits), so they agree without a packet of ours, whichever side computes a melee hit in 42.21 MP.
--
-- The tracker follows each player's main-hand item. When it changes, the old item goes back to base wherever it is
-- now (bag, floor, corpse, another inventory: it is reached through the item object) and the new one gets this
-- player's values. A full pass re-evaluates the held scalpel too (trait added or removed, a game loaded with a
-- boosted scalpel). release() puts the item back to base before a player is forgotten (death, disconnect, detach).
-- guard() is the swing check: whoever swings a scalpel gets the values that holder deserves, so no buffed scalpel can
-- ever hit for anyone but a Scalpel Master holding it in the main hand.

local Rules = require "ExtensiveHealthRedone/Items/Scalpel"

local GameScalpel = {}

-- The Scalpel Master trait token from media/registries.lua.
local function traitToken()
    return EHRCharacterTraits and EHRCharacterTraits.scalpelmaster or nil
end

function GameScalpel.isScalpel(item)
    return item ~= nil and Rules.isScalpel(item:getFullType())
end

function GameScalpel.hasTrait(player)
    local token = traitToken()
    return token ~= nil and player:hasTrait(token)
end

-- Whether item should carry the boost: player is alive, a Scalpel Master, and holds it in the main hand.
function GameScalpel.shouldBoost(player, item)
    if not player or not item then
        return false
    end
    return Rules.boosted({
        alive = not player:isDead(),
        hasTrait = GameScalpel.hasTrait(player),
        inPrimaryHand = player:getPrimaryHandItem() == item,
    })
end

-- The weapon fields of a scalpel and of its script.
---@param item HandWeapon
function GameScalpel.read(item)
    local script = item:getScriptItem()
    if not script then
        return nil, nil
    end
    local current = {
        minDamage = item:getMinDamage(),
        maxDamage = item:getMaxDamage(),
        conditionLowerChance = item:getConditionLowerChance(),
    }
    local base = {
        minDamage = script:getMinDamage(),
        maxDamage = script:getMaxDamage(),
        conditionLowerChance = script:getConditionLowerChance(),
    }
    return current, base
end

-- Writes the fields that differ from what the rule says. Returns true when something changed. Anything that is not
-- a Base.Scalpel is left alone.
---@param item HandWeapon
function GameScalpel.normalize(item, boosted)
    if not GameScalpel.isScalpel(item) then
        return false
    end
    local current, base = GameScalpel.read(item)
    if not current then
        return false
    end
    local writes, any = Rules.plan(current, base, boosted)
    if writes.minDamage then
        item:setMinDamage(writes.minDamage)
    end
    if writes.maxDamage then
        item:setMaxDamage(writes.maxDamage)
    end
    if writes.conditionLowerChance then
        item:setConditionLowerChance(writes.conditionLowerChance)
    end
    return any
end

-- Tracker ------------------------------------------------------------------------------------------------------------

local Tracker = {}
Tracker.__index = Tracker
GameScalpel.Tracker = Tracker

-- onChange(player, item, boosted): called after a scalpel's fields were written (the server syncs it to its owner).
function Tracker.new(onChange)
    -- key -> { player = the player object, held = the main-hand item last seen (any item, or nil) }
    return setmetatable({ entries = {}, onChange = onChange }, Tracker)
end

function Tracker:apply(player, item, boosted)
    if GameScalpel.normalize(item, boosted) and self.onChange then
        self.onChange(player, item, boosted)
    end
end

-- One pass for one living player. full: re-evaluate the held scalpel even when the main hand did not change.
function Tracker:reconcile(key, player, full)
    local entry = self.entries[key]
    if entry and entry.player ~= player then
        self:release(key)
        entry = nil
    end
    local held = player:getPrimaryHandItem()
    if entry and entry.held == held then
        if full and GameScalpel.isScalpel(held) then
            self:apply(player, held, GameScalpel.shouldBoost(player, held))
        end
        return
    end
    if entry and GameScalpel.isScalpel(entry.held) then
        -- It left the hand: back to base wherever it is now (another master's next pass boosts it again).
        self:apply(player, entry.held, false)
    end
    if GameScalpel.isScalpel(held) then
        self:apply(player, held, GameScalpel.shouldBoost(player, held))
    end
    self.entries[key] = { player = player, held = held }
end

-- Puts the tracked item back to base and forgets the player.
function Tracker:release(key)
    local entry = self.entries[key]
    if not entry then
        return
    end
    self.entries[key] = nil
    if GameScalpel.isScalpel(entry.held) then
        self:apply(entry.player, entry.held, false)
    end
end

-- Releases every tracked player for whom stale(key, player) is true.
function Tracker:releaseWhere(stale)
    local keys = {}
    for key, entry in pairs(self.entries) do
        if stale(key, entry.player) then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        self:release(key)
    end
end

-- Releases a player by object (a death event names the character, not our key).
function Tracker:releasePlayer(player)
    self:releaseWhere(function(_, tracked)
        return tracked == player
    end)
end

-- The swing check (OnWeaponSwing): the weapon gets the values its attacker deserves before the hit.
function Tracker:guard(attacker, weapon)
    if GameScalpel.isScalpel(weapon) then
        self:apply(attacker, weapon, GameScalpel.shouldBoost(attacker, weapon))
    end
end

-- The main-hand item last seen for key (tests and the debug inspect).
function Tracker:held(key)
    local entry = self.entries[key]
    return entry and entry.held or nil
end

return GameScalpel
