-- Real Room Temperature 2.0 (Workshop 3741066319, mod id RealRoomHeat): whether its Body Temperature Rework is on, and
-- whether its cold model owns a player's body right now. Server/RealRoomTemperature does the work. Never errors.
--
-- With the rework on (sandbox RRH2.BodyTempRework), RRT models cold rooms and vehicle cabins itself: it writes the
-- thermoregulator's core and Stats TEMPERATURE together, and before every write it requires the two to agree within
-- 4e-6. A foreign TEMPERATURE write in between latches a fault (preexisting_core_stat_disagreement) that switches its
-- cold model off for the character. So while RRT owns the body, our temperature hold must not write.
--
-- When RRT owns it, read from its globals (RealRoomHeat2, read against RRT's code, docs/competability):
--   * single player: its client cold model (RealRoomHeat2.BodyCold) holds a lease on the player, from admission until
--     the lease is fully given back (BodyCold.blocks). Before admitting, RRT itself waits while TEMPERATURE and the
--     core disagree, so a hold that is already running keeps the cold model out.
--   * dedicated server: its server body model (RealRoomHeat2.BodyServer) admits without that wait and faults on the
--     first write instead. So we treat the body as owned whenever RRT's route for the player is its cold model
--     (BodyServerInput.resolve: "lua_cold_trajectory"), and while it still holds a generation (BodyServer.snapshot).
-- Anything unexpected from RRT (a missing function, an error) counts as owned: not writing is always safe.

local Env = require "ExtensiveHealthRedone/Game/Env"

local log = Env.logger("RealRoomTemperature")

local RealRoomTemperature = {}

RealRoomTemperature.MOD_ID = "RealRoomHeat"
RealRoomTemperature.REWORK_OPTION = "RRH2.BodyTempRework"
RealRoomTemperature.COLD_ROUTE = "lua_cold_trajectory"
RealRoomTemperature.SERVER_OWNER = "server_mp_body_temperature"

local cached      -- nil until asked, then true or false for the session
local failed = false

-- A save has its own mod list, so this is asked at play time, once.
function RealRoomTemperature.loaded()
    if cached == nil then
        local mods = getActivatedMods()
        cached = mods:contains(RealRoomTemperature.MOD_ID) or mods:contains("\\" .. RealRoomTemperature.MOD_ID)
    end
    return cached
end

-- Forgets what was learned about the mod list (tests, and a new game in the same session).
function RealRoomTemperature.reset()
    cached = nil
    failed = false
end

-- The mod is on and its Body Temperature Rework too (off by default). Read every time: an admin may change it.
function RealRoomTemperature.active()
    return RealRoomTemperature.loaded() and Env.sandbox(RealRoomTemperature.REWORK_OPTION, false) == true
end

-- RRT's global table, or nil.
function RealRoomTemperature.api()
    ---@diagnostic disable-next-line: undefined-global
    local rrh = RealRoomHeat2
    return type(rrh) == "table" and rrh or nil
end

local function warn(what, err)
    if not failed then
        failed = true
        log:warn("Real Room Temperature's", what, "failed; its cold model is taken to own the body:", tostring(err))
    end
end

local function singlePlayerOwns(rrh, player)
    local cold = rrh.BodyCold
    if type(cold) ~= "table" then
        return false          -- its client body model isn't loaded: nothing of it writes in SP
    end
    local check = type(cold.blocks) == "function" and cold.blocks or cold.ownsActor
    if type(check) ~= "function" then
        warn("BodyCold.blocks", "missing")
        return true
    end
    local ok, owns = pcall(check, player)
    if not ok then
        warn("BodyCold.blocks", owns)
        return true
    end
    return owns == true
end

local function serverOwns(rrh, player)
    local input, body = rrh.BodyServerInput, rrh.BodyServer
    if type(input) ~= "table" and type(body) ~= "table" then
        return false          -- its server body model isn't loaded
    end
    if type(input) ~= "table" or type(input.resolve) ~= "function"
        or type(body) ~= "table" or type(body.snapshot) ~= "function" then
        warn("server body API", "missing")
        return true
    end
    local ok, envelope = pcall(input.resolve, player, getTimestampMs())
    if not ok then
        warn("BodyServerInput.resolve", envelope)
        return true
    end
    if type(envelope) == "table" and envelope.route == RealRoomTemperature.COLD_ROUTE then
        return true
    end
    local snapOk, snap = pcall(body.snapshot, player)
    if not snapOk or type(snap) ~= "table" then
        warn("BodyServer.snapshot", snap)
        return true
    end
    return snap.owner == RealRoomTemperature.SERVER_OWNER or snap.cleanupPending == true
end

-- Whether RRT's cold model owns (or is about to own) the player's body temperature, so TEMPERATURE must not be
-- written. False without RRT or with its rework off. Authority side only (SP, the dedicated server).
function RealRoomTemperature.owns(player)
    if not player or not RealRoomTemperature.active() then
        return false
    end
    local rrh = RealRoomTemperature.api()
    if not rrh then
        return false
    end
    if isServer() then
        return serverOwns(rrh, player)
    end
    return singlePlayerOwns(rrh, player)
end

-- RRT's cold retention registry (registerColdRetentionProvider), or nil.
function RealRoomTemperature.retention()
    local rrh = RealRoomTemperature.api()
    local registry = rrh and rrh.ColdRetention
    if type(registry) == "table" and type(registry.registerColdRetentionProvider) == "function" then
        return registry
    end
    return nil
end

return RealRoomTemperature
