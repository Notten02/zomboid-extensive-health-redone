-- World state of the wild searches: per-square cooldowns for the plant search and per-tree contents for the hive
-- search. Pure: the store table is passed in (Server/WildSearch keeps it in server-only global ModData, which it never
-- transmits, so clients learn it only from command replies). Times are game hours (world age).
--   store.herb[key] = untilHour
--   store.tree[key] = { hive = bool, webs = n, untilHour = h|nil, seenHour = h|nil }
--   (untilHour only on an empty tree; seenHour: the last search started there)
-- Square modData keys the original mod left are ignored.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local SpotCooldowns = {}

function SpotCooldowns.key(x, y, z)
    return x .. "," .. y .. "," .. z
end

-- Makes sure the two sub-tables exist (a fresh ModData table, or one from an older save).
function SpotCooldowns.prepare(store)
    if type(store.herb) ~= "table" then
        store.herb = {}
    end
    if type(store.tree) ~= "table" then
        store.tree = {}
    end
    return store
end

function SpotCooldowns.herbCooling(store, key, hours)
    local untilHour = store.herb[key]
    return untilHour ~= nil and hours < untilHour
end

function SpotCooldowns.startHerb(store, key, hours, cooldownHours)
    store.herb[key] = hours + cooldownHours
end

-- The tree's stored contents, or nil when it was never inspected (or was pruned).
function SpotCooldowns.tree(store, key)
    return store.tree[key]
end

function SpotCooldowns.setTree(store, key, content)
    store.tree[key] = content
end

-- An empty tree still cooling down.
function SpotCooldowns.treeCooling(store, key, hours)
    local tree = store.tree[key]
    return tree ~= nil and tree.untilHour ~= nil and hours < tree.untilHour
end

-- Drops expired plant cooldowns, empty trees whose cooldown has run out, and trees that still hold something but
-- were not searched for forgetHours (so the table can't grow with every tree anyone looked at). A dropped tree rolls
-- again on its next inspection. Returns the number of entries removed.
function SpotCooldowns.prune(store, hours, forgetHours)
    local removed = 0
    for _, key in ipairs(Tables.sortedKeys(store.herb)) do
        if hours >= store.herb[key] then
            store.herb[key] = nil
            removed = removed + 1
        end
    end
    for _, key in ipairs(Tables.sortedKeys(store.tree)) do
        local tree = store.tree[key]
        local empty = not tree.hive and (tree.webs or 0) <= 0
        local stale = not empty and forgetHours ~= nil and hours - (tree.seenHour or 0) >= forgetHours
        if (empty and (tree.untilHour == nil or hours >= tree.untilHour)) or stale then
            store.tree[key] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Forgets everything (debug).
function SpotCooldowns.clear(store)
    store.herb = {}
    store.tree = {}
end

return SpotCooldowns
