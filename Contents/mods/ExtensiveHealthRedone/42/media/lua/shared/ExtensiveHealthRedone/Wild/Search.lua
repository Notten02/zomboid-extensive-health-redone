-- The server's sessions for the two wild searches: one plant search and one hive search per player, each with an id
-- and a real-time deadline. Pure: Server/WildSearch checks the world (square, distance, knowledge), then calls these
-- with an env table and carries out what they return (items, XP, injuries, replies).
--   env = { now = real seconds, hours = world age hours, rng, store = Wild/SpotCooldowns store, exists = fn|nil }
--
-- Plant search: the server holds the board and reveals one cell per pick; the result is rolled from its own counts.
-- Cancelling or walking away costs nothing before the first pick and spends the spot after it (no roll). Time running
-- out after a pick finishes with the roll, as in v0.9; with no pick the session is just dropped.
-- Hive search: the server rolls and keeps the tree's contents. A grab needs a live session, at least MIN_REACH_S
-- since it started and MIN_GAP_S since the last grab, and the target still in the tree. A sting ends the session and
-- leaves the contents, so an instant retry is allowed (v0.9 H17, kept by decision).
-- From docs/porting/phase8/herbal-and-hive-minigames.md sections 13.2-13.4; fixes v0.9 H2, H5, H6, H9, H16.
-- Residual trust (accepted): a modified hive client can skip the dodging and never report a sting; its gain is capped
-- by the server-rolled contents and the cooldown.

local Data = require "ExtensiveHealthRedone/Data/WildSearch"
local HerbalBoard = require "ExtensiveHealthRedone/Wild/HerbalBoard"
local HiveTree = require "ExtensiveHealthRedone/Wild/HiveTree"
local SpotCooldowns = require "ExtensiveHealthRedone/Wild/SpotCooldowns"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local HERB = Data.herb
local HIVE = Data.hive

local Search = {}

function Search.new()
    return { herb = {}, hive = {}, nextId = 0 }
end

local function newId(state)
    state.nextId = state.nextId + 1
    return state.nextId
end

-- The part a thorn, sting or bite hurts when no gloves are worn.
function Search.injuryPart(rng)
    return Data.INJURY_PARTS[rng.int(1, #Data.INJURY_PARTS)]
end

-- Worn hand clothing protects while it has condition left and no holes (fingerless gloves count).
function Search.glovesProtect(condition, holes)
    return condition > 0 and holes == 0
end

-- Plant search ----------------------------------------------------------------------------------------------------

-- spot: { key, x, y, z, zoneClass, month }; skills: { firstAid, foraging }. force (debug) skips the cooldown.
-- Returns the session, or nil, "depleted". A previous session of this player is abandoned first.
function Search.herbBegin(state, actor, spot, skills, env, force)
    if state.herb[actor] then
        Search.herbAbandon(state, actor, env)
    end
    if not force and SpotCooldowns.herbCooling(env.store, spot.key, env.hours) then
        return nil, "depleted"
    end
    local s = {
        id = newId(state), key = spot.key, x = spot.x, y = spot.y, z = spot.z,
        zoneClass = spot.zoneClass, month = spot.month, force = force == true,
        board = HerbalBoard.newBoard(env.rng), picked = {},
        picks = 0, hits = 0, misses = 0, hazards = 0,
        firstAid = skills.firstAid or 0, foraging = skills.foraging or 0,
        maxPicks = HerbalBoard.maxPicks(skills.foraging),
        started = env.now, deadline = env.now + HERB.SECONDS + HERB.GRACE,
    }
    state.herb[actor] = s
    return s
end

-- The player's live session with this id, or nil, "noSession" / "expired".
function Search.herbSession(state, actor, id, now)
    local s = state.herb[actor]
    if not s or s.id ~= id then
        return nil, "noSession"
    end
    if now > s.deadline then
        return nil, "expired"
    end
    return s
end

-- One pick; cell 1-16, or 0 for empty space (a miss, as in v0.9). Returns { cell, kind, outcome, done, session }
-- (kind "empty" for cell 0), or nil and a reason: "noSession", "expired", "badCell", "picked".
function Search.herbPick(state, actor, id, cell, env)
    local s, reason = Search.herbSession(state, actor, id, env.now)
    if not s then
        return nil, reason
    end
    if cell ~= math.floor(cell) or cell < 0 or cell > HERB.CELLS then
        return nil, "badCell"
    end
    if cell > 0 and s.picked[cell] then
        return nil, "picked"
    end
    local kind = "empty"
    if cell > 0 then
        kind = s.board[cell]
        s.picked[cell] = true
    end
    local outcome = HerbalBoard.outcome(kind)
    s.picks = s.picks + 1
    if outcome == "hit" then
        s.hits = s.hits + 1
    elseif outcome == "hazard" then
        s.hazards = s.hazards + 1
    else
        s.misses = s.misses + 1
    end
    local done = s.hits >= HERB.REQUIRED_HITS or s.picks >= s.maxPicks
    return { cell = cell, kind = kind, outcome = outcome, done = done, session = s }
end

-- Ends the session with the roll and starts the spot's cooldown. Returns { session, depleted = true } when another
-- player finished this spot meanwhile, else { session, roll = HerbalBoard.roll result }.
function Search.herbFinish(state, actor, env)
    local s = state.herb[actor]
    state.herb[actor] = nil
    if not s then
        return nil
    end
    if not s.force and SpotCooldowns.herbCooling(env.store, s.key, env.hours) then
        return { session = s, depleted = true }
    end
    SpotCooldowns.startHerb(env.store, s.key, env.hours, HERB.COOLDOWN_HOURS)
    return { session = s, roll = HerbalBoard.roll(s, env.rng, env.exists) }
end

-- Cancel or walk away. Returns "dropped" (no pick: free retry) or "spent" (cooldown started, no roll), nil when
-- there was no session.
function Search.herbAbandon(state, actor, env)
    local s = state.herb[actor]
    state.herb[actor] = nil
    if not s then
        return nil
    end
    if s.picks == 0 then
        return "dropped"
    end
    if not s.force then
        SpotCooldowns.startHerb(env.store, s.key, env.hours, HERB.COOLDOWN_HOURS)
    end
    return "spent"
end

-- The client stops: reason "cancel" (button, walked away) or "time" (its timer ran out). Returns "dropped", "spent",
-- "finish" (the caller then calls herbFinish), "early" (time claimed too soon: ignored, the sweep ends it), or nil
-- and a reason when there is no live session.
function Search.herbStop(state, actor, id, reason, env)
    local s, why = Search.herbSession(state, actor, id, env.now)
    if not s then
        return nil, why
    end
    if reason == "cancel" then
        return Search.herbAbandon(state, actor, env)
    end
    if env.now - s.started < HERB.SECONDS - HERB.TIME_TOLERANCE then
        return "early"
    end
    if s.picks == 0 then
        state.herb[actor] = nil
        return "dropped"
    end
    return "finish"
end

-- Sessions past their deadline. Returns a list of { actor, result } in actor order: result is a herbFinish result
-- for a session with picks, nil for one that was dropped.
function Search.herbSweep(state, env)
    local ended = {}
    for _, actor in ipairs(Tables.sortedKeys(state.herb)) do
        local s = state.herb[actor]
        if env.now > s.deadline then
            if s.picks > 0 then
                ended[#ended + 1] = { actor = actor, result = Search.herbFinish(state, actor, env) }
            else
                state.herb[actor] = nil
                ended[#ended + 1] = { actor = actor }
            end
        end
    end
    return ended
end

-- Hive search -----------------------------------------------------------------------------------------------------

-- spot: { key, x, y, z }. content (debug) replaces whatever the tree holds. Returns the session and the tree's
-- contents, or nil and "depleted" (an empty tree cooling down) or "none" (just rolled empty: cooldown starts).
function Search.hiveBegin(state, actor, spot, env, content)
    state.hive[actor] = nil
    local store = env.store
    local tree = SpotCooldowns.tree(store, spot.key)
    if content then
        tree = { hive = content.hive == true, webs = math.min(HIVE.MAX_WEBS, content.webs or 0) }
        SpotCooldowns.setTree(store, spot.key, tree)
    elseif SpotCooldowns.treeCooling(store, spot.key, env.hours) then
        return nil, "depleted"
    elseif not tree or HiveTree.isEmpty(tree) then
        tree = HiveTree.roll(env.rng)
        if HiveTree.isEmpty(tree) then
            tree.untilHour = env.hours + HIVE.COOLDOWN_HOURS
        end
        SpotCooldowns.setTree(store, spot.key, tree)
        if tree.untilHour then
            return nil, "none"
        end
    end
    if HiveTree.isEmpty(tree) then
        return nil, "none"
    end
    tree.seenHour = env.hours
    local s = {
        id = newId(state), key = spot.key, x = spot.x, y = spot.y, z = spot.z,
        started = env.now, deadline = env.now + HIVE.SECONDS + HIVE.GRACE,
    }
    state.hive[actor] = s
    return s, tree
end

function Search.hiveSession(state, actor, id, now)
    local s = state.hive[actor]
    if not s or s.id ~= id then
        return nil, "noSession"
    end
    if now > s.deadline then
        return nil, "expired"
    end
    return s
end

-- A grab at "hive" or "web". Returns { item, done, hive, webs, session }, or nil and a reason: "noSession",
-- "expired", "tooFast", "absent". When the tree is empty the session ends and the cooldown starts.
function Search.hiveCollect(state, actor, id, target, env)
    local s, reason = Search.hiveSession(state, actor, id, env.now)
    if not s then
        return nil, reason
    end
    if env.now - s.started < HIVE.MIN_REACH_S or (s.lastCollect and env.now - s.lastCollect < HIVE.MIN_GAP_S) then
        return nil, "tooFast"
    end
    local tree = SpotCooldowns.tree(env.store, s.key)
    local item = tree and HiveTree.collect(tree, target)
    if not item then
        return nil, "absent"
    end
    s.lastCollect = env.now
    local done = HiveTree.isEmpty(tree)
    if done then
        tree.untilHour = env.hours + HIVE.COOLDOWN_HOURS
        state.hive[actor] = nil
    end
    return { item = item, done = done, hive = tree.hive, webs = tree.webs, session = s }
end

-- A bee or spider touched the hand: the session ends, the contents stay. Returns the session, or nil and a reason.
function Search.hiveSting(state, actor, id, env)
    local s, reason = Search.hiveSession(state, actor, id, env.now)
    if not s then
        return nil, reason
    end
    state.hive[actor] = nil
    return s
end

-- Drops hive sessions past their deadline (silently, as v0.9's timeout). Returns how many.
function Search.hiveSweep(state, env)
    local dropped = 0
    for _, actor in ipairs(Tables.sortedKeys(state.hive)) do
        if env.now > state.hive[actor].deadline then
            state.hive[actor] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

return Search
