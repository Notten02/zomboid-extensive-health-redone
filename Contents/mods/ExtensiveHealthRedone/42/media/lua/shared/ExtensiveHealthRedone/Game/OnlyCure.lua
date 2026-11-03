-- The Only Cure (amputations, Workshop 3580276809, by Pao): whether it is enabled, and what it knows about a player,
-- as the plain snapshot Wounds/Amputation works with. The only code that touches the mod. Never errors.
--
-- We only read the mod: its DataController (one instance per username, on the server and on the owning client) and
-- the prosthesis the player wears. Its data loads after the game starts: until then read() returns nil, which callers
-- treat as "no mod this step", never as "nothing cut". A read that fails (the mod changed shape) switches this off
-- for the session, with one error in the log.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Amputation = require "ExtensiveHealthRedone/Wounds/Amputation"

local log = Env.logger("OnlyCure")

local OnlyCure = {}

OnlyCure.MOD_ID = "TheOnlyCure"

local cached      -- nil until asked, then true or false for the session
local broken      -- a read failed: off for the session

-- A save has its own mod list, so this is asked at play time, once.
function OnlyCure.active()
    if broken then
        return false
    end
    if cached == nil then
        local mods = getActivatedMods()
        cached = mods:contains(OnlyCure.MOD_ID) or mods:contains("\\" .. OnlyCure.MOD_ID)
    end
    return cached
end

-- Forgets what was learned (tests, and a new game in the same session).
function OnlyCure.reset()
    cached, broken = nil, nil
end

local function clamp01(v)
    v = tonumber(v) or 0
    return math.max(0, math.min(1, v))
end

-- A DataController method of the mod (checked against TOC 2.4.3). Called by name: tools/check-api.lua knows the
-- game's API, not the mod's.
local function ask(dc, method, ...)
    return dc[method](dc, ...)
end

local function snapshot(player)
    local DataController = require("TOC/Controllers/DataController")
    local dc = DataController.GetInstance(player:getUsername())
    if not dc or not ask(dc, "getIsDataReady") then
        return nil
    end
    local toc = { limbs = {}, prosthesis = {} }
    for _, limb in ipairs(Amputation.LIMBS) do
        local cut = ask(dc, "getIsCut", limb) == true
        toc.limbs[limb] = {
            cut = cut,
            healed = cut and ask(dc, "getIsCicatrized", limb) == true,
            cauterized = cut and ask(dc, "getIsCauterized", limb) == true,
            dirt = cut and clamp01(ask(dc, "getWoundDirtyness", limb)) or 0,
        }
    end
    for _, side in ipairs(Amputation.SIDES) do
        local hand = "Hand_" .. side
        toc.prosthesis[side] = toc.limbs[hand].cut and ask(dc, "getIsProstEquipped", hand) == true
    end
    return toc
end

-- The snapshot (Wounds/Amputation), or nil without the mod or before its data is ready.
function OnlyCure.read(player)
    if not player or not OnlyCure.active() then
        return nil
    end
    local ok, toc = pcall(snapshot, player)
    if not ok then
        broken = true
        log:error("reading The Only Cure failed, the compatibility is off for this session:", tostring(toc))
        return nil
    end
    return toc
end

-- The prosthesis worn on one side ("L" or "R"), a Clothing item, or nil. The mod's arm prostheses are TOC.Prost_*_L
-- and TOC.Prost_*_R.
function OnlyCure.prosthesis(player, side)
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        local fullType = item and item:getFullType() or ""
        if fullType:find("^TOC%.Prost_.+_" .. side .. "$") and instanceof(item, "Clothing") then
            return item
        end
    end
    return nil
end

return OnlyCure
