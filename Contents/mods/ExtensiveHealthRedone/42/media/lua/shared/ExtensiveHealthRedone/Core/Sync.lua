-- The state sync protocol between the server (StateStore) and the client (Sync.Mirror).
--
-- Messages (server -> client, command "sync"):
--   { v = PROTOCOL, epoch = "...", owner = "<player key>", full = bool,
--     sections = { [name] = { rev = n, data = <section copy> }, ... } }
--   full = true is a snapshot of every section (sent once, in answer to "hello"); otherwise it is a delta with only
--   the sections that changed.
--
-- Client -> server, command "hello": { v = PROTOCOL }. The client sends it when it joins, and again when it receives
-- a delta it can't place (a new server epoch, so its mirror is stale). There are no periodic full snapshots.
--
-- The mirror keeps one entry per owner, so a client can hold its own state and, later, an examined patient's.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Sync = {}

Sync.PROTOCOL = 1

-- Wraps a store message for sending.
function Sync.encode(msg)
    msg.v = Sync.PROTOCOL
    return msg
end

local Mirror = {}
Mirror.__index = Mirror

function Sync.newMirror()
    return setmetatable({ owners = {} }, Mirror)
end

-- Applies a sync message. Returns the sorted list of changed section names, plus a status:
--   "ok", "protocol" (wrong version, ignored) or "needHello" (stale epoch: send hello and wait for a snapshot).
function Mirror:apply(msg)
    if type(msg) ~= "table" or msg.v ~= Sync.PROTOCOL then
        return {}, "protocol"
    end
    local owner = self.owners[msg.owner]
    if msg.full then
        if not owner or owner.epoch ~= msg.epoch then
            owner = { epoch = msg.epoch, revs = {}, sections = {} }
            self.owners[msg.owner] = owner
        end
    elseif not owner or owner.epoch ~= msg.epoch then
        return {}, "needHello"
    end
    local changed = {}
    for _, name in ipairs(Tables.sortedKeys(msg.sections or {})) do
        local section = msg.sections[name]
        local known = owner.revs[name]
        -- A snapshot may repeat a revision the mirror already has; >= keeps it idempotent.
        if known == nil or section.rev > known or (msg.full and section.rev >= known) then
            owner.revs[name] = section.rev
            owner.sections[name] = section.data
            changed[#changed + 1] = name
        end
    end
    return changed, "ok"
end

-- The mirrored section, or nil before the first snapshot. Treat it as read-only.
function Mirror:section(ownerKey, name)
    local owner = self.owners[ownerKey]
    return owner and owner.sections[name]
end

function Mirror:has(ownerKey)
    return self.owners[ownerKey] ~= nil
end

function Mirror:forget(ownerKey)
    self.owners[ownerKey] = nil
end

return Sync
