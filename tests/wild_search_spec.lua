-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Results of calls that return nil on refusal are indexed directly; a nil there fails the test anyway.
---@diagnostic disable: need-check-nil
-- The wild searches: the medicinal plant search and the hive and spiderweb search. Pure rules (board,
-- quality, find chance, pools, tree contents, cooldowns, square classification, hive scene) and the server's session
-- machine (Wild/Search), which is where the command checks live.
local Sim = require("support/sim")
local Data = require("ExtensiveHealthRedone/Data/WildSearch")
local HerbalBoard = require("ExtensiveHealthRedone/Wild/HerbalBoard")
local HiveTree = require("ExtensiveHealthRedone/Wild/HiveTree")
local HiveScene = require("ExtensiveHealthRedone/Wild/HiveScene")
local SpotCooldowns = require("ExtensiveHealthRedone/Wild/SpotCooldowns")
local Vegetation = require("ExtensiveHealthRedone/Wild/Vegetation")
local Search = require("ExtensiveHealthRedone/Wild/Search")

-- A deterministic pseudo-random source for distribution tests.
local function seeded(seed)
    local s = seed
    local function nextFloat()
        s = (s * 1103515245 + 12345) % 2147483648
        return s / 2147483648
    end
    return {
        float = nextFloat,
        int = function(lo, hi)
            return lo + math.floor(nextFloat() * (hi - lo + 1))
        end,
    }
end

local function count(list, value)
    local n = 0
    for _, v in ipairs(list) do
        if v == value then
            n = n + 1
        end
    end
    return n
end

describe("HerbalBoard", function()
    it("deals 5 targets, 2 hazards and 9 decoys on every board", function()
        for seed = 1, 50 do
            local board = HerbalBoard.newBoard(seeded(seed))
            assert.equal(16, #board)
            assert.equal(5, count(board, "target"))
            assert.equal(2, count(board, "hazard"))
            assert.equal(9, count(board, "decoy"))
        end
    end)

    it("shuffles: thorns don't always sit in the same cells", function()
        local seen = {}
        for seed = 1, 40 do
            for i, kind in ipairs(HerbalBoard.newBoard(seeded(seed))) do
                if kind == "hazard" then
                    seen[i] = true
                end
            end
        end
        local cells = 0
        for _ in pairs(seen) do
            cells = cells + 1
        end
        assert.truthy(cells >= 10, "hazards seen in only " .. cells .. " cells")
    end)

    it("allows 8, 9 or 10 picks by Foraging", function()
        assert.equal(8, HerbalBoard.maxPicks(0))
        assert.equal(8, HerbalBoard.maxPicks(3))
        assert.equal(9, HerbalBoard.maxPicks(4))
        assert.equal(9, HerbalBoard.maxPicks(7))
        assert.equal(10, HerbalBoard.maxPicks(8))
        assert.equal(10, HerbalBoard.maxPicks(10))
    end)

    it("grants access with the guide or First Aid 4 plus Foraging 4", function()
        assert.is_true(HerbalBoard.canSearch(true, 0, 0))
        assert.is_true(HerbalBoard.canSearch(false, 4, 4))
        assert.is_false(HerbalBoard.canSearch(false, 4, 3))
        assert.is_false(HerbalBoard.canSearch(false, 10, 0))
    end)

    it("rates a run from its counts, penalties included (no latching)", function()
        assert.near(0.83, HerbalBoard.quality(3, 0, 0, 4, 4), 0.001)
        assert.near(0.90, HerbalBoard.quality(3, 0, 0, 10, 10), 0.001)
        -- A miss and a thorn after the last hit still count.
        assert.near(0.83 - 0.08 - 0.12, HerbalBoard.quality(3, 1, 1, 4, 4), 0.001)
        assert.equal(0.05, HerbalBoard.quality(0, 8, 2, 0, 0))
        assert.equal("excellent", HerbalBoard.band(0.83))
        assert.equal("good", HerbalBoard.band(0.6))
        assert.equal("rough", HerbalBoard.band(0.38))
        assert.equal("poor", HerbalBoard.band(0.37))
    end)

    it("matches the spec's find chance table at First Aid 4 / Foraging 4", function()
        local function chance(class, month, q)
            return math.floor(HerbalBoard.findChance(class, month, q, 4, 4) + 0.5)
        end
        assert.equal(70, chance("deepForest", 7, 0.83))
        assert.equal(41, chance("deepForest", 7, 0.25))
        assert.equal(47, chance("forest", 10, 0.83))
        assert.equal(24, chance("vegitation", 3, 0.25))
        assert.equal(23, chance("farm", 1, 0.83))
        assert.equal(12, chance("other", 12, 0.25))
    end)

    it("clamps the find chance to 4..78", function()
        assert.equal(78, HerbalBoard.findChance("deepForest", 6, 1, 10, 10))
        -- The lowest the data allows (town, winter, worst run, no skill) stays just above the floor.
        assert.near(16 * 0.58 * (0.42 + 0.05 * 0.96), HerbalBoard.findChance("other", 1, 0.05, 0, 0), 1e-9)
    end)

    it("raises the rare share with quality and Foraging", function()
        assert.equal(8, HerbalBoard.rareChance(0, 0))
        assert.equal(8 + 14 + 4, HerbalBoard.rareChance(0.83, 4))
        assert.equal(8 + 18 + 12, HerbalBoard.rareChance(1, 10))
    end)

    it("weights the pool and skips missing items", function()
        local herbs, berries = 0, 0
        local rng = seeded(7)
        for _ = 1, 4000 do
            local item = HerbalBoard.choose(Data.herb.COMMON, rng)
            if item:find("^Base%.Berry") then
                berries = berries + 1
            else
                herbs = herbs + 1
            end
        end
        -- Berries: 7 of 21 weight = one third.
        assert.truthy(math.abs(berries / 4000 - 1 / 3) < 0.04, "berry share " .. berries / 4000)
        local only = HerbalBoard.choose(Data.herb.RARE, rng, function(t) return t == "Base.Comfrey" end)
        assert.equal("Base.Comfrey", only)
        assert.is_nil(HerbalBoard.choose(Data.herb.RARE, rng, function() return false end))
    end)

    it("finds nothing on a failed roll, one herb on a good run and two on an excellent one", function()
        local s = { hits = 3, misses = 0, hazards = 0, firstAid = 4, foraging = 4, zoneClass = "forest", month = 7 }
        local miss = HerbalBoard.roll(s, Sim.rng({ floats = { 0.99 } }))
        assert.is_false(miss.found)
        assert.equal(0, miss.count)
        local excellent = HerbalBoard.roll(s, Sim.rng({ floats = { 0.0 }, ints = { 99, 1 } }))
        assert.is_true(excellent.found)
        assert.equal("excellent", excellent.band)
        assert.equal(2, excellent.count)
        assert.equal("Base.Plantain", excellent.item)
        s.misses = 1
        local good = HerbalBoard.roll(s, Sim.rng({ floats = { 0.0 }, ints = { 0, 1 } }))
        assert.equal("good", good.band)
        assert.equal(1, good.count)
        assert.is_true(good.rare)
        assert.equal("Base.BlackSage", good.item)
    end)
end)

describe("HiveTree", function()
    it("rolls about 40% of trees with contents, never a full-but-empty tree", function()
        local rng = seeded(11)
        local withContents, hives = 0, 0
        for _ = 1, 5000 do
            local tree = HiveTree.roll(rng)
            assert.truthy(tree.webs >= 0 and tree.webs <= 3)
            if not HiveTree.isEmpty(tree) then
                withContents = withContents + 1
                if tree.hive then
                    hives = hives + 1
                else
                    assert.truthy(tree.webs >= 1, "no hive and no web")
                end
            end
        end
        assert.truthy(math.abs(withContents / 5000 - 0.40) < 0.03, "content share " .. withContents / 5000)
        assert.truthy(math.abs(hives / withContents - 0.32) < 0.04, "hive share " .. hives / withContents)
    end)

    it("turns 'no hive and 0 webs' into one web", function()
        -- content yes (0 < 40), no hive (99), 0 webs (0 < 35)
        local tree = HiveTree.roll(Sim.rng({ ints = { 0, 99, 0 } }))
        assert.same({ hive = false, webs = 1 }, tree)
    end)

    it("collects one item at a time until empty", function()
        local tree = { hive = true, webs = 2 }
        assert.equal(Data.hive.HONEYCOMB, HiveTree.collect(tree, "hive"))
        assert.is_nil(HiveTree.collect(tree, "hive"))
        assert.equal(Data.hive.SPIDERWEB, HiveTree.collect(tree, "web"))
        assert.is_false(HiveTree.isEmpty(tree))
        assert.equal(Data.hive.SPIDERWEB, HiveTree.collect(tree, "web"))
        assert.is_true(HiveTree.isEmpty(tree))
        assert.is_nil(HiveTree.collect(tree, "web"))
    end)
end)

describe("SpotCooldowns", function()
    it("starts, checks, expires and prunes", function()
        local store = SpotCooldowns.prepare({})
        local key = SpotCooldowns.key(10, 20, 0)
        assert.equal("10,20,0", key)
        assert.is_false(SpotCooldowns.herbCooling(store, key, 100))
        SpotCooldowns.startHerb(store, key, 100, 48)
        assert.is_true(SpotCooldowns.herbCooling(store, key, 147.9))
        assert.is_false(SpotCooldowns.herbCooling(store, key, 148))
        SpotCooldowns.setTree(store, "a", { hive = false, webs = 0, untilHour = 120 })
        SpotCooldowns.setTree(store, "b", { hive = true, webs = 0 })
        SpotCooldowns.setTree(store, "c", { hive = false, webs = 0, untilHour = 200 })
        assert.is_true(SpotCooldowns.treeCooling(store, "a", 110))
        assert.equal(2, SpotCooldowns.prune(store, 150))
        assert.is_nil(store.herb[key])
        assert.is_nil(store.tree.a)
        assert.is_not_nil(store.tree.b)     -- still holds a hive
        assert.is_not_nil(store.tree.c)     -- still cooling
    end)

    it("forgets a tree that still holds something once nobody searched it for a while", function()
        local store = SpotCooldowns.prepare({})
        SpotCooldowns.setTree(store, "old", { hive = true, webs = 1, seenHour = 10 })
        SpotCooldowns.setTree(store, "recent", { hive = true, webs = 0, seenHour = 100 })
        assert.equal(0, SpotCooldowns.prune(store, 177, 168))
        assert.equal(1, SpotCooldowns.prune(store, 178, 168))
        assert.is_nil(store.tree.old)
        assert.is_not_nil(store.tree.recent)
    end)
end)

-- A fake tile: flag (canBeCut or nil), CustomName, sprite name.
local function fakeObject(flag, customName, spriteName)
    return { getSprite = function()
        return {
            getProperties = function()
                return {
                    has = function(_, f) return f == flag end,
                    get = function(_, key) return key == "CustomName" and customName or nil end,
                }
            end,
            getName = function() return spriteName end,
        }
    end }
end

-- Fake squares for Vegetation: { x, y, z, room, outside, bush, tree, zones }. bush: true (a canBeCut tile) or a fake
-- tile from fakeObject.
local function fakeSquare(o)
    local objects = {}
    if o.bush == true then
        objects[1] = fakeObject("canBeCut")
    elseif o.bush then
        objects[1] = o.bush
    end
    return {
        getX = function() return o.x end, getY = function() return o.y end, getZ = function() return o.z or 0 end,
        getRoom = function() return o.room end,
        isOutside = function() return o.outside ~= false end,
        getTree = function() return o.tree end,
        getObjects = function()
            return { size = function() return #objects end, get = function(_, i) return objects[i + 1] end }
        end,
    }
end

local function fakeApi(zoneTypes)
    return {
        canBeCut = "canBeCut",
        zonesAt = function()
            return {
                size = function() return #zoneTypes end,
                get = function(_, i)
                    return { getType = function() return zoneTypes[i + 1] end }
                end,
            }
        end,
    }
end

describe("Vegetation", function()
    it("knows a bush by its name, the canBeCut flag or an f_bushes_ sprite, not hedges or grass", function()
        local api = fakeApi({})
        local function bush(object)
            return Vegetation.hasBush(fakeSquare({ x = 1, y = 1, bush = object }), api)
        end
        assert.is_true(bush(fakeObject(nil, "Bush", "vegetation_foliage_01_3")))
        assert.is_true(bush(fakeObject("canBeCut", nil, "x")))
        assert.is_true(bush(fakeObject(nil, nil, "f_bushes_1_42")))
        assert.is_false(bush(fakeObject(nil, "Hedge", "vegetation_ornamental_01_0")))
        assert.is_false(bush(fakeObject(nil, "Ornamental Bush", "x")))
        assert.is_false(bush(fakeObject(nil, nil, "e_newgrass_1_12")))
        assert.is_false(bush(nil))
    end)

    it("keeps v0.9's square hash", function()
        assert.equal((10 * 73856093 + 20 * 19349663) % 10000, Vegetation.hash(10, 20, 0))
        assert.truthy(Vegetation.hash(-5, 3, 0) >= 0)
    end)

    it("ranks zone classes, deep forest first", function()
        assert.equal("other", Vegetation.zoneClass({}))
        assert.equal("other", Vegetation.zoneClass({ "TownZone", "Nav" }))
        assert.equal("farm", Vegetation.zoneClass({ "FarmLand", "TownZone" }))
        assert.equal("vegitation", Vegetation.zoneClass({ "Farm", "Vegitation" }))
        assert.equal("forest", Vegetation.zoneClass({ "BirchMixForest", "Vegitation" }))
        assert.equal("deepForest", Vegetation.zoneClass({ "Forest", "DeepForest" }))
    end)

    it("offers the plant search only on outdoor bushes that pass the zone density", function()
        local api = fakeApi({ "DeepForest" })
        local hits, total = 0, 0
        for x = 0, 99 do
            local sq = fakeSquare({ x = x, y = 7, bush = true })
            total = total + 1
            if Vegetation.isPatch(sq, api) then
                hits = hits + 1
                assert.truthy(Vegetation.hash(x, 7, 0) % 100 < 68)
            end
        end
        assert.truthy(hits > 40 and hits < 95, hits .. " of " .. total)
        -- The same bush in town needs a lower hash.
        local town = fakeApi({ "TownZone" })
        for x = 0, 99 do
            if Vegetation.isPatch(fakeSquare({ x = x, y = 7, bush = true }), town) then
                assert.truthy(Vegetation.hash(x, 7, 0) % 100 < 24)
            end
        end
        -- Find a square that passes, then take its bush away, put it indoors, or under a roof.
        local x = 0
        while not Vegetation.isPatch(fakeSquare({ x = x, y = 7, bush = true }), api) do
            x = x + 1
        end
        assert.is_false(Vegetation.isPatch(fakeSquare({ x = x, y = 7 }), api))
        assert.is_false(Vegetation.isPatch(fakeSquare({ x = x, y = 7, bush = true, room = {} }), api))
        assert.is_false(Vegetation.isPatch(fakeSquare({ x = x, y = 7, bush = true, outside = false }), api))
    end)

    it("offers the hive search on outdoor tree squares", function()
        assert.is_true(Vegetation.isTreeSquare(fakeSquare({ x = 1, y = 1, tree = {} })))
        assert.is_false(Vegetation.isTreeSquare(fakeSquare({ x = 1, y = 1 })))
        assert.is_false(Vegetation.isTreeSquare(fakeSquare({ x = 1, y = 1, tree = {}, room = {} })))
        assert.is_false(Vegetation.isTreeSquare(nil))
    end)
end)

describe("Search sessions", function()
    local SPOT = { key = "5,5,0", x = 5, y = 5, z = 0, zoneClass = "forest", month = 7 }
    local SKILLS = { firstAid = 4, foraging = 4 }

    -- A board with targets in cells 1-5, hazards in 6-7, decoys after (newBoard swaps with int(1, i) = i: identity).
    local function env(now, hours, store, rng)
        return { now = now, hours = hours or 100, rng = rng or Sim.rng({ ints = {} }), store = store,
            exists = function() return true end }
    end
    local function identityRng()
        local rng = Sim.rng({})
        rng.int = function(_, hi) return hi end
        return rng
    end

    local state, store
    before_each(function()
        state = Search.new()
        store = SpotCooldowns.prepare({})
    end)

    local function begin(now)
        return Search.herbBegin(state, "p1", SPOT, SKILLS, env(now or 0, 100, store, identityRng()))
    end

    it("refuses a pick without a session, with a wrong id, after the deadline, or on a picked cell", function()
        local e = env(1, 100, store)
        assert.same({ nil, "noSession" }, { Search.herbPick(state, "p1", 1, 1, e) })
        local s = begin(0)
        assert.same({ nil, "noSession" }, { Search.herbPick(state, "p1", s.id + 1, 1, e) })
        local r = Search.herbPick(state, "p1", s.id, 1, e)
        assert.equal("target", r.kind)
        assert.equal("hit", r.outcome)
        assert.same({ nil, "picked" }, { Search.herbPick(state, "p1", s.id, 1, e) })
        assert.same({ nil, "badCell" }, { Search.herbPick(state, "p1", s.id, 17, e) })
        local late = env(Data.herb.SECONDS + Data.herb.GRACE + 0.1, 100, store)
        assert.same({ nil, "expired" }, { Search.herbPick(state, "p1", s.id, 2, late) })
    end)

    it("counts empty space as a miss and a thorn as a hazard", function()
        local s = begin(0)
        local e = env(1, 100, store)
        assert.equal("miss", Search.herbPick(state, "p1", s.id, 0, e).outcome)
        assert.equal("miss", Search.herbPick(state, "p1", s.id, 0, e).outcome)
        local thorn = Search.herbPick(state, "p1", s.id, 6, e)
        assert.equal("hazard", thorn.kind)
        assert.equal(2, s.misses)
        assert.equal(1, s.hazards)
        assert.equal(3, s.picks)
    end)

    it("is done at three hits, then finishes with a roll and spends the spot", function()
        local s = begin(0)
        local e = env(1, 100, store, Sim.rng({ floats = { 0 }, ints = { 99, 1 } }))
        assert.is_false(Search.herbPick(state, "p1", s.id, 1, e).done)
        assert.is_false(Search.herbPick(state, "p1", s.id, 2, e).done)
        assert.is_true(Search.herbPick(state, "p1", s.id, 3, e).done)
        local result = Search.herbFinish(state, "p1", e)
        assert.is_true(result.roll.found)
        assert.equal(2, result.roll.count)     -- 0.83 is Excellent
        assert.is_nil(state.herb.p1)
        assert.is_true(SpotCooldowns.herbCooling(store, SPOT.key, 147))
        assert.same({ nil, "depleted" }, { begin(2) })
    end)

    it("is done when the picks run out", function()
        local s = begin(0)
        local e = env(1, 100, store)
        local r
        for _ = 1, 9 do
            r = Search.herbPick(state, "p1", s.id, 0, e)
        end
        assert.is_true(r.done)
    end)

    it("lets a cancel before any pick go free, but spends the spot after one", function()
        local s = begin(0)
        assert.equal("dropped", Search.herbStop(state, "p1", s.id, "cancel", env(1, 100, store)))
        assert.is_false(SpotCooldowns.herbCooling(store, SPOT.key, 100))
        s = begin(2)
        Search.herbPick(state, "p1", s.id, 9, env(3, 100, store))
        assert.equal("spent", Search.herbStop(state, "p1", s.id, "cancel", env(4, 100, store)))
        assert.is_true(SpotCooldowns.herbCooling(store, SPOT.key, 100))
        assert.is_nil(state.herb.p1)
    end)

    it("spends the old spot when a new search starts over a picked one", function()
        local s = begin(0)
        Search.herbPick(state, "p1", s.id, 9, env(1, 100, store))
        local other = { key = "9,9,0", x = 9, y = 9, z = 0, zoneClass = "other", month = 1 }
        assert.is_not_nil(Search.herbBegin(state, "p1", other, SKILLS, env(2, 100, store, identityRng())))
        assert.is_true(SpotCooldowns.herbCooling(store, SPOT.key, 100))
    end)

    it("accepts 'time is up' only near the end, then finishes (or drops a pickless session)", function()
        local s = begin(0)
        assert.equal("early", Search.herbStop(state, "p1", s.id, "time", env(10, 100, store)))
        assert.equal("dropped", Search.herbStop(state, "p1", s.id, "time", env(41, 100, store)))
        s = begin(50)
        Search.herbPick(state, "p1", s.id, 1, env(51, 100, store))
        assert.equal("finish", Search.herbStop(state, "p1", s.id, "time", env(50 + 41, 100, store)))
    end)

    it("finishes abandoned sessions with picks at the deadline and drops the rest", function()
        local s = begin(0)
        Search.herbPick(state, "p1", s.id, 1, env(1, 100, store))
        Search.herbBegin(state, "p2", { key = "1,1,0", x = 1, y = 1, z = 0, zoneClass = "other", month = 7 }, SKILLS,
            env(0, 100, store, identityRng()))
        assert.same({}, Search.herbSweep(state, env(20, 100, store)))
        local ended = Search.herbSweep(state, env(Data.herb.SECONDS + Data.herb.GRACE + 1, 100, store))
        assert.equal(2, #ended)
        assert.equal("p1", ended[1].actor)
        assert.is_not_nil(ended[1].result.roll)
        assert.equal("p2", ended[2].actor)
        assert.is_nil(ended[2].result)
        assert.is_true(SpotCooldowns.herbCooling(store, SPOT.key, 100))
        assert.is_false(SpotCooldowns.herbCooling(store, "1,1,0", 100))
    end)

    it("gives nothing when another player finished the same bush first", function()
        local a = Search.herbBegin(state, "p1", SPOT, SKILLS, env(0, 100, store, identityRng()))
        local b = Search.herbBegin(state, "p2", SPOT, SKILLS, env(0, 100, store, identityRng()))
        Search.herbPick(state, "p1", a.id, 1, env(1, 100, store))
        Search.herbPick(state, "p2", b.id, 1, env(1, 100, store))
        assert.is_not_nil(Search.herbFinish(state, "p1", env(2, 100, store)).roll)
        assert.is_true(Search.herbFinish(state, "p2", env(2, 100, store)).depleted)
    end)

    describe("hive", function()
        local TREE = { key = "3,3,0", x = 3, y = 3, z = 0 }

        it("rolls an empty tree once and makes it wait 48 hours", function()
            -- content roll 99 >= 40: empty
            local s, why = Search.hiveBegin(state, "p1", TREE, env(0, 100, store, Sim.rng({ ints = { 99 } })))
            assert.is_nil(s)
            assert.equal("none", why)
            assert.same({ nil, "depleted" }, { Search.hiveBegin(state, "p1", TREE, env(1, 120, store)) })
            -- After the cooldown it rolls again: content (0), a hive (0), webs roll 70 -> 2 webs (35 + 30 <= 70 < 87).
            local again, tree = Search.hiveBegin(state, "p1", TREE, env(2, 148, store, Sim.rng({ ints = { 0, 0, 70 } })))
            assert.is_not_nil(again)
            assert.same({ hive = true, webs = 2, seenHour = 148 }, tree)
        end)

        it("needs a live session, the minimum reach time, a gap between grabs, and a target present", function()
            local s = Search.hiveBegin(state, "p1", TREE, env(0, 100, store), { hive = true, webs = 1 })
            assert.same({ nil, "noSession" }, { Search.hiveCollect(state, "p2", s.id, "hive", env(5, 100, store)) })
            assert.same({ nil, "tooFast" }, { Search.hiveCollect(state, "p1", s.id, "hive", env(0.9, 100, store)) })
            local r = Search.hiveCollect(state, "p1", s.id, "hive", env(1.0, 100, store))
            assert.equal(Data.hive.HONEYCOMB, r.item)
            assert.is_false(r.done)
            assert.same({ nil, "tooFast" }, { Search.hiveCollect(state, "p1", s.id, "web", env(1.3, 100, store)) })
            assert.same({ nil, "absent" }, { Search.hiveCollect(state, "p1", s.id, "hive", env(2, 100, store)) })
            local last = Search.hiveCollect(state, "p1", s.id, "web", env(3, 100, store))
            assert.equal(Data.hive.SPIDERWEB, last.item)
            assert.is_true(last.done)
            assert.is_nil(state.hive.p1)
            assert.is_true(SpotCooldowns.treeCooling(store, TREE.key, 147))
        end)

        it("refuses a grab after the deadline", function()
            local s = Search.hiveBegin(state, "p1", TREE, env(0, 100, store), { hive = true, webs = 0 })
            local late = Data.hive.SECONDS + Data.hive.GRACE + 0.5
            assert.same({ nil, "expired" }, { Search.hiveCollect(state, "p1", s.id, "hive", env(late, 100, store)) })
        end)

        it("ends the session on a sting but leaves the contents for an instant retry", function()
            local s = Search.hiveBegin(state, "p1", TREE, env(0, 100, store), { hive = false, webs = 2 })
            assert.is_not_nil(Search.hiveSting(state, "p1", s.id, env(2, 100, store)))
            assert.is_nil(Search.hiveSting(state, "p1", s.id, env(2, 100, store)))
            local again, tree = Search.hiveBegin(state, "p1", TREE, env(3, 100, store))
            assert.is_not_nil(again)
            assert.equal(2, tree.webs)
        end)

        it("drops sessions past their deadline", function()
            Search.hiveBegin(state, "p1", TREE, env(0, 100, store), { hive = true, webs = 0 })
            assert.equal(0, Search.hiveSweep(state, env(10, 100, store)))
            assert.equal(1, Search.hiveSweep(state, env(60, 100, store)))
        end)
    end)

    it("protects with intact gloves only and hurts a hand or forearm otherwise", function()
        assert.is_true(Search.glovesProtect(10, 0))
        assert.is_false(Search.glovesProtect(0, 0))
        assert.is_false(Search.glovesProtect(10, 1))
        local parts = {}
        for i = 1, 4 do
            parts[Search.injuryPart(Sim.rng({ ints = { i } }))] = true
        end
        assert.same({ Hand_L = true, Hand_R = true, ForeArm_L = true, ForeArm_R = true }, parts)
    end)
end)

describe("HiveScene", function()
    local BOARD = { x = 24, y = 112, w = 612, h = 390 }

    it("builds the scene the server's counts describe", function()
        local scene = HiveScene.new(seeded(3), BOARD, true, 2)
        assert.is_not_nil(scene.hive)
        assert.equal(9, #scene.bees)
        assert.equal(2, #scene.webs)
        assert.equal(3, #scene.spiders)
        local bare = HiveScene.new(seeded(3), BOARD, true, 0)
        assert.equal(0, #bare.spiders)
    end)

    it("keeps the hand in the corridor, reaching the hive at the top", function()
        local scene = HiveScene.new(seeded(5), BOARD, true, 0)
        local x, y = HiveScene.constrain(scene, 0, 10000)
        assert.equal(scene.start.y + scene.start.h / 2, y)
        assert.equal(scene.tree.x + HiveScene.HAND_W / 2, x)
        local hx, hy = HiveScene.constrain(scene, scene.hive.x + 50, 0)
        assert.is_not_nil(HiveScene.targetAt(scene, hx, hy))
    end)

    it("catches a bee the hand passes through between two updates", function()
        local scene = HiveScene.new(seeded(5), BOARD, false, 1)
        scene.spiders = {}
        scene.bees = { { kind = "bee", x = 300, y = 300, w = 22, h = 18, vx = 0, vy = 0 } }
        -- Both ends are clear of the bee; the path crosses it.
        assert.is_nil(HiveScene.touch(scene, 311, 200, 311, 200))
        assert.is_nil(HiveScene.touch(scene, 311, 400, 311, 400))
        assert.equal("bee", HiveScene.touch(scene, 311, 200, 311, 400))
    end)

    it("bounces movers inside their zone with a clamped step", function()
        local scene = HiveScene.new(seeded(9), BOARD, false, 3)
        assert.equal(HiveScene.DT_MAX, HiveScene.step(scene, 5))
        for _ = 1, 500 do
            HiveScene.step(scene, 0.05)
        end
        for _, spider in ipairs(scene.spiders) do
            local z = spider.zone
            assert.truthy(spider.x >= z.x and spider.x + spider.w <= z.x + z.w + 0.001)
            assert.truthy(spider.y >= z.y and spider.y + spider.h <= z.y + z.h + 0.001)
        end
    end)
end)
