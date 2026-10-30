-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake items and players are deliberately partial.
---@diagnostic disable: missing-fields
-- Scalpel Master: the pure rule, the shared tracker on fake objects, and the authority's wiring against the fake game.
local Rules = require("ExtensiveHealthRedone/Items/Scalpel")
local Data = require("ExtensiveHealthRedone/Data/Professions")

local SCRIPT = { minDamage = 0.1, maxDamage = 0.4, conditionLowerChance = 1 }   -- vanilla 42.21 Base.Scalpel

-- Java keeps these fields as single-precision floats.
local function f32(v)
    return tonumber(string.format("%.7g", v))
end

-- A fake HandWeapon with a fake script item. item.writes counts setter calls.
local function weapon(fullType)
    local item = { fullType = fullType or "Base.Scalpel", min = f32(SCRIPT.minDamage), max = f32(SCRIPT.maxDamage),
        lower = SCRIPT.conditionLowerChance, writes = 0 }
    local script = {
        getMinDamage = function() return f32(SCRIPT.minDamage) end,
        getMaxDamage = function() return f32(SCRIPT.maxDamage) end,
        getConditionLowerChance = function() return SCRIPT.conditionLowerChance end,
    }
    function item:getFullType() return self.fullType end
    function item:getScriptItem() return script end
    function item:getMinDamage() return self.min end
    function item:getMaxDamage() return self.max end
    function item:getConditionLowerChance() return self.lower end
    function item:setMinDamage(v) self.min, self.writes = f32(v), self.writes + 1 end
    function item:setMaxDamage(v) self.max, self.writes = f32(v), self.writes + 1 end
    function item:setConditionLowerChance(v) self.lower, self.writes = v, self.writes + 1 end
    function item:getCondition() return 5 end
    function item:getConditionMax() return 5 end
    return item
end

local function isBoosted(item)
    return math.abs(item.min - 0.9) < 1e-4 and math.abs(item.max - 3.6) < 1e-4 and item.lower == 100
end

local function isBase(item)
    return math.abs(item.min - 0.1) < 1e-6 and math.abs(item.max - 0.4) < 1e-6 and item.lower == 1
end

describe("Scalpel Master rules", function()
    it("takes the exact Base.Scalpel only", function()
        assert.is_true(Rules.isScalpel("Base.Scalpel"))
        assert.is_false(Rules.isScalpel("Other.Scalpel"))
        assert.is_false(Rules.isScalpel("Base.HuntingKnife"))
        assert.is_false(Rules.isScalpel(nil))
    end)

    it("boosts only a living Scalpel Master's main-hand scalpel", function()
        assert.is_true(Rules.boosted({ alive = true, hasTrait = true, inPrimaryHand = true }))
        assert.is_false(Rules.boosted({ alive = false, hasTrait = true, inPrimaryHand = true }))
        assert.is_false(Rules.boosted({ alive = true, hasTrait = false, inPrimaryHand = true }))
        assert.is_false(Rules.boosted({ alive = true, hasTrait = true, inPrimaryHand = false }))
        assert.is_false(Rules.boosted(nil))
    end)

    it("keeps v0.9's x9 damage and x100 durability, on ConditionLowerChance", function()
        assert.equal(9, Data.SCALPEL_DAMAGE)
        assert.equal(100, Data.SCALPEL_DURABILITY)
        local boosted = Rules.targets(SCRIPT, true)
        assert.near(0.9, boosted.minDamage, 1e-9)
        assert.near(3.6, boosted.maxDamage, 1e-9)
        assert.equal(100, boosted.conditionLowerChance)
        assert.same(SCRIPT, Rules.targets(SCRIPT, false))
    end)

    it("plans only the fields that differ, so normalizing twice writes nothing", function()
        local writes, any = Rules.plan(SCRIPT, SCRIPT, true)
        assert.is_true(any)
        assert.equal(100, writes.conditionLowerChance)
        local current = { minDamage = f32(writes.minDamage), maxDamage = f32(writes.maxDamage),
            conditionLowerChance = writes.conditionLowerChance }
        local again, anyAgain = Rules.plan(current, SCRIPT, true)
        assert.is_false(anyAgain)
        assert.same({}, again)
        local back = Rules.plan(current, SCRIPT, false)
        assert.equal(1, back.conditionLowerChance)
    end)
end)

insulate("Scalpel Master tracker", function()
    _G.EHRCharacterTraits = { scalpelmaster = "ExtensiveHealth:scalpelmaster" }
    local GameScalpel = require("ExtensiveHealthRedone/Game/Scalpel")

    local function person(master)
        local p = { dead = false, traits = { ["ExtensiveHealth:scalpelmaster"] = master or nil } }
        function p:isDead() return self.dead end
        function p:hasTrait(t) return self.traits[t] == true end
        function p:getPrimaryHandItem() return self.primary end
        return p
    end

    it("boosts the held scalpel and resets it when it leaves the hand, wherever it went", function()
        local changes = {}
        local tracker = GameScalpel.Tracker.new(function(_, _, boosted) changes[#changes + 1] = boosted end)
        local master, s = person(true), weapon()
        master.primary = s
        tracker:reconcile("a", master, false)
        assert.is_true(isBoosted(s))
        local writes = s.writes
        tracker:reconcile("a", master, true)
        assert.equal(writes, s.writes)          -- nothing to write while it stays right
        master.primary = nil                    -- dropped, bagged, traded: only the item object is needed
        tracker:reconcile("a", master, false)
        assert.is_true(isBase(s))
        assert.same({ true, false }, changes)
    end)

    it("never boosts for a non-master, the secondary hand, or another module's scalpel", function()
        local tracker = GameScalpel.Tracker.new()
        local other, s = person(false), weapon()
        other.primary = s
        tracker:reconcile("b", other, true)
        assert.is_true(isBase(s))
        local master, odd = person(true), weapon("Other.Scalpel")
        master.primary = odd
        tracker:reconcile("c", master, true)
        assert.equal(0, odd.writes)
        local offhand = weapon()
        master.primary, master.secondary = nil, offhand
        tracker:reconcile("c", master, true)
        assert.equal(0, offhand.writes)
    end)

    it("resets a boosted scalpel a non-master picks up, on equip and on swing", function()
        local tracker = GameScalpel.Tracker.new()
        local master, other, s = person(true), person(false), weapon()
        master.primary = s
        tracker:reconcile("m", master, false)
        assert.is_true(isBoosted(s))
        other.primary = s
        tracker:reconcile("o", other, false)
        assert.is_true(isBase(s))
        tracker:reconcile("m", master, true)    -- the master's next pass boosts it again (both hold it in this test)
        tracker:guard(other, s)
        assert.is_true(isBase(s))
        tracker:guard(master, s)
        assert.is_true(isBoosted(s))
    end)

    it("follows the trait on a full pass and resets on death and release", function()
        local tracker = GameScalpel.Tracker.new()
        local master, s = person(false), weapon()
        master.primary = s
        tracker:reconcile("m", master, false)
        assert.is_true(isBase(s))
        master.traits["ExtensiveHealth:scalpelmaster"] = true
        tracker:reconcile("m", master, false)
        assert.is_true(isBase(s))               -- a light pass only looks at hand changes
        tracker:reconcile("m", master, true)
        assert.is_true(isBoosted(s))
        master.traits["ExtensiveHealth:scalpelmaster"] = nil
        tracker:reconcile("m", master, true)
        assert.is_true(isBase(s))
        master.traits["ExtensiveHealth:scalpelmaster"] = true
        tracker:reconcile("m", master, true)
        master.dead = true
        tracker:releasePlayer(master)
        assert.is_true(isBase(s))
        assert.is_nil(tracker:held("m"))
    end)

    it("resets the old character's scalpel when a key gets a new character", function()
        local tracker = GameScalpel.Tracker.new()
        local old, new, s = person(true), person(true), weapon()
        old.primary = s
        tracker:reconcile("k", old, false)
        tracker:reconcile("k", new, false)
        assert.is_true(isBase(s))
    end)
end)

insulate("single-player wiring: Scalpel Master", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.EHRCharacterTraits = { scalpelmaster = "ExtensiveHealth:scalpelmaster",
        patientzero = "ExtensiveHealth:patientzero" }
    for _, name in ipairs({ "OnEquipPrimary", "OnEquipSecondary", "OnWeaponSwing", "OnCharacterDeath" }) do
        local event = { handlers = {} }
        function event.Add(fn) event.handlers[#event.handlers + 1] = fn end
        function event.trigger(...)
            for _, fn in ipairs(event.handlers) do fn(...) end
        end
        game.events[name] = event
    end
    local MASTER = "ExtensiveHealth:scalpelmaster"

    local master = game.addPlayer({})
    master.traits[MASTER] = true
    rawset(master, "getCharacterTraits", function()
        return {
            add = function(_, t) master.traits[t] = true end,
            remove = function(_, t) master.traits[t] = nil end,
        }
    end)
    local other = game.addPlayer({})
    local doomed = game.addPlayer({})
    doomed.traits[MASTER] = true
    require("ExtensiveHealthRedone/Server/Main")
    local Client = require("ExtensiveHealthRedone/Client/Client")
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("boosts a master's main-hand scalpel within a tick, and resets it when unequipped", function()
        local s = weapon()
        master.hands.primary = s
        game.advance(0.1)
        assert.is_true(isBoosted(s))
        master.hands.primary = nil
        game.advance(0.1)
        assert.is_true(isBase(s))
    end)

    it("applies at once on the equip event", function()
        local s = weapon()
        master.hands.primary = s
        game.events.OnEquipPrimary.trigger(master, s)
        assert.is_true(isBoosted(s))
        master.hands.primary = nil
        game.events.OnEquipPrimary.trigger(master, nil)
        assert.is_true(isBase(s))
    end)

    it("resets a buffed scalpel when a non-master swings it", function()
        local s = weapon()
        s.min, s.max, s.lower = 0.9, 3.6, 100      -- as saved from a master's hand
        other.hands.primary = s
        game.events.OnWeaponSwing.trigger(other, s)
        assert.is_true(isBase(s))
    end)

    it("resets the scalpel of a master who dies", function()
        local s = weapon()
        doomed.hands.primary = s
        game.advance(0.1)
        assert.is_true(isBoosted(s))
        doomed.dead = true
        game.advance(0.1)
        assert.is_true(isBase(s))
    end)

    it("follows an admin removing the trait within a simulation step", function()
        local s = weapon()
        master.hands.primary = s
        game.advance(0.1)
        assert.is_true(isBoosted(s))
        master.traits[MASTER] = nil
        game.advance(1)
        assert.is_true(isBase(s))
        master.traits[MASTER] = true
        game.advance(1)
        assert.is_true(isBoosted(s))
        master.hands.primary = nil
        game.advance(0.1)
    end)

    it("debug: gives a scalpel, toggles the trait and inspects the held scalpel", function()
        local text
        Client.on("debugDump", function(args) text = args.text end)
        game.sandbox.DebugMode = true
        local before = master.inventory:count(Data.SCALPEL_TYPE)
        Client.send(master, "debug.scalpel", { action = "give" })
        assert.equal(before + 1, master.inventory:count(Data.SCALPEL_TYPE))
        local s = weapon()
        master.hands.primary = s
        Client.send(master, "debug.scalpel", { action = "untrait" })
        assert.is_nil(master.traits[MASTER])
        assert.is_true(isBase(s))
        Client.send(master, "debug.scalpel", { action = "trait" })
        assert.is_true(isBoosted(s))
        Client.send(master, "debug.scalpel", { action = "inspect" })
        assert.truthy(text and text:find("boosted now: true", 1, true))
        game.sandbox.DebugMode = false
        master.hands.primary = nil
    end)
end)
