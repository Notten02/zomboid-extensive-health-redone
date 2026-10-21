-- Server-side store of every loaded player's health state, with per-section dirty tracking.
--
-- The state table itself lives in the player's modData (the adapter attaches it), so it saves with the character.
-- Code that changes a section calls markDirty(key, section); takeDelta(key) then returns copies of the changed
-- sections with new revision numbers, ready to send. Revisions are per player and per section and live in memory
-- only. They never go down during a server run: attaching a player again (after a logout, say) continues from the
-- last revision plus one, so a client that kept its mirror still accepts what follows. Together with the store's
-- epoch, which changes on every server start, they let a client tell new data from old.
--
-- Section names come from the schema. Each section is a top-level field of the state table and is sent whole.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local StateStore = {}
StateStore.__index = StateStore

-- sections: ordered list of section names. epoch: any string unique to this server run.
function StateStore.new(sections, epoch)
    local known = {}
    for _, name in ipairs(sections) do
        known[name] = true
    end
    return setmetatable({
        sections = sections, known = known, epoch = epoch, players = {}, revisions = {},
        withChanges = {},   -- key -> true while the player has a dirty section (dirtyKeys)
    }, StateStore)
end

function StateStore:attach(key, state)
    local revs = self.revisions[key]
    if revs then
        -- The state may have changed while detached (or be a new character's), so every section moves on.
        for _, name in ipairs(self.sections) do
            revs[name] = revs[name] + 1
        end
    else
        revs = {}
        for _, name in ipairs(self.sections) do
            revs[name] = 1
        end
        self.revisions[key] = revs
    end
    self.players[key] = { state = state, revs = revs, dirty = {} }
end

function StateStore:detach(key)
    self.players[key] = nil
    self.withChanges[key] = nil
end

function StateStore:get(key)
    local p = self.players[key]
    return p and p.state
end

function StateStore:has(key)
    return self.players[key] ~= nil
end

-- Attached player keys, sorted.
function StateStore:keys()
    return Tables.sortedKeys(self.players)
end

local function player(self, key)
    local p = self.players[key]
    if not p then
        error("no state attached for " .. tostring(key), 3)
    end
    return p
end

function StateStore:markDirty(key, section)
    if not self.known[section] then
        error("unknown state section " .. tostring(section), 2)
    end
    player(self, key).dirty[section] = true
    self.withChanges[key] = true
end

-- Attached player keys with a dirty section, sorted: cheap when few players changed (Runtime flushes after a command).
function StateStore:dirtyKeys()
    return Tables.sortedKeys(self.withChanges)
end

function StateStore:isDirty(key, section)
    local p = self.players[key]
    return p ~= nil and p.dirty[section] == true
end

function StateStore:revision(key, section)
    return player(self, key).revs[section]
end

local function message(self, key, full)
    return { epoch = self.epoch, owner = key, full = full, sections = {} }
end

-- Changed sections since the last call, as a sync message, or nil when nothing changed. Bumps their revisions.
function StateStore:takeDelta(key)
    local p = player(self, key)
    local msg
    for _, name in ipairs(self.sections) do
        if p.dirty[name] then
            msg = msg or message(self, key, false)
            p.revs[name] = p.revs[name] + 1
            msg.sections[name] = { rev = p.revs[name], data = Tables.deepCopy(p.state[name]) }
        end
    end
    p.dirty = {}
    self.withChanges[key] = nil
    return msg
end

-- Every section at its current revision: the answer to a client's hello. Pending dirty flags stay set, so the next
-- delta still goes out (with a higher revision) and nothing is lost if a change raced the snapshot.
function StateStore:snapshot(key)
    local p = player(self, key)
    local msg = message(self, key, true)
    for _, name in ipairs(self.sections) do
        msg.sections[name] = { rev = p.revs[name], data = Tables.deepCopy(p.state[name]) }
    end
    return msg
end

return StateStore
