-- Consent permits: a patient allows one actor to do one kind of thing to them for a while.
--
--   permits:grant("patient", "doctor", "exam", now, 5)     -- valid for 5 time units from now
--   permits:check("patient", "doctor", "exam", now)        -- true while valid
--
-- Permits are server memory only (they don't survive a restart), so storing an absolute expiry is fine here.
-- Times are in whatever unit the caller uses consistently; the server adapter uses real-time seconds so a paused or
-- fast-forwarded game clock doesn't stretch a consent window.

local Permits = {}
Permits.__index = Permits

function Permits.new()
    -- entries[patient][actor][purpose] = expiry
    return setmetatable({ entries = {} }, Permits)
end

function Permits:grant(patient, actor, purpose, now, duration)
    local byActor = self.entries[patient]
    if not byActor then
        byActor = {}
        self.entries[patient] = byActor
    end
    local byPurpose = byActor[actor]
    if not byPurpose then
        byPurpose = {}
        byActor[actor] = byPurpose
    end
    byPurpose[purpose] = now + duration
end

function Permits:revoke(patient, actor, purpose)
    local byActor = self.entries[patient]
    local byPurpose = byActor and byActor[actor]
    if byPurpose then
        byPurpose[purpose] = nil
    end
end

function Permits:check(patient, actor, purpose, now)
    local byActor = self.entries[patient]
    local byPurpose = byActor and byActor[actor]
    local expires = byPurpose and byPurpose[purpose]
    if expires == nil then
        return false
    end
    if now >= expires then
        byPurpose[purpose] = nil
        return false
    end
    return true
end

-- Drops every permit that involves this player as patient or actor (on logout or death).
function Permits:forget(playerKey)
    self.entries[playerKey] = nil
    for _, byActor in pairs(self.entries) do
        byActor[playerKey] = nil
    end
end

-- Removes expired permits. Collects first, then deletes, so no table changes during traversal.
function Permits:prune(now)
    local expired = {}
    for patient, byActor in pairs(self.entries) do
        for actor, byPurpose in pairs(byActor) do
            for purpose, expires in pairs(byPurpose) do
                if now >= expires then
                    expired[#expired + 1] = { patient, actor, purpose }
                end
            end
        end
    end
    for _, e in ipairs(expired) do
        self:revoke(e[1], e[2], e[3])
    end
end

return Permits
