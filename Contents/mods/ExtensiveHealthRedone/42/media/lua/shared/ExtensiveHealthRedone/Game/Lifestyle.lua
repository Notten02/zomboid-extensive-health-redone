-- Reads Lifestyle: Hobbies (an optional mod, id LifestyleHobbies) from the player's modData, the way Lifestyle keeps it
-- (checked against v0.4.0.3: client/Hygiene/HygieneNeed.lua, ToiletBladderNeed.lua, LSEffects/LSPerMinute.lua,
-- TimedActions/LSUseShower and LSUseTub, Helper/HSMng.lua). Never errors; without Lifestyle every function says
-- "nothing".
--
-- Lifestyle runs on the client and keeps its state in the local player's modData:
--   hygieneNeed 0-100 (0 = spotless, default 50), only while sandbox Text.DividerHygiene is on
--   IsDoingShower true during a shower and during a tub bath
--   IsSittingOnSeat true on a Lifestyle seat or in a tub; ComfortVal 0-1 (0.7 furniture, 0.25 default, 0.75-0.95 tub)
--   LSHiddenSkills.Yoga = { level, xp, xp for the next level }
--   bathroomNeed 0-100, IsDoingToilet, LSMoodles.BladderNeed (the toilet system, with DividerHygiene)
-- A dedicated server never has this data (a client reports it: Client/Lifestyle, Server/Lifestyle); single player and
-- the client read it here. All of it is read-only except addBathroomNeed, which adds to Lifestyle's own bladder need.

local Env = require "ExtensiveHealthRedone/Game/Env"

local log = Env.logger("Lifestyle")

local Lifestyle = {}

Lifestyle.MOD_ID = "LifestyleHobbies"
-- What a sitting character with no Lifestyle seat counts as (sitting on the ground).
Lifestyle.GROUND_COMFORT = 0.2

local cached      -- nil until asked, then true or false for the session
local announced = false

-- Lifestyle is enabled in this game. A save has its own mod list, so this is asked at play time, once.
function Lifestyle.active()
    if cached == nil then
        local mods = getActivatedMods()
        cached = mods:contains(Lifestyle.MOD_ID) or mods:contains("\\" .. Lifestyle.MOD_ID)
    end
    return cached
end

-- Forgets what was learned about the mod list (tests, and a new game in the same session).
function Lifestyle.reset()
    cached = nil
    announced = false
end

-- Lifestyle's hygiene module is on (its sandbox divider), which also owns the toilet system.
function Lifestyle.hygieneOn()
    local text = SandboxVars and SandboxVars.Text
    return text ~= nil and text.DividerHygiene == true
end

local function yogaLevel(data)
    local skills = data.LSHiddenSkills
    local yoga = type(skills) == "table" and skills.Yoga or nil
    local level = type(yoga) == "table" and yoga[1] or nil
    return type(level) == "number" and level or 0
end

-- The hygiene, bathing, sitting and yoga reading of a player (see Lifestyle/Pace), or nil without Lifestyle data.
-- Client and single player only: a dedicated server has no Lifestyle data.
function Lifestyle.sample(player)
    if not Lifestyle.active() then
        return nil
    end
    local data = player:getModData()
    if type(data) ~= "table" then
        return nil
    end
    local sitting, comfort = false, 0
    if data.IsSittingOnSeat == true or player:isSittingOnFurniture() then
        sitting, comfort = true, tonumber(data.ComfortVal) or 0
    elseif player:isSitOnGround() then
        sitting, comfort = true, Lifestyle.GROUND_COMFORT
    end
    if not announced then
        announced = true
        log:info("Lifestyle: Hobbies found: hygiene, bathing, sitting and yoga change how fast illnesses pass")
    end
    return {
        hygiene = Lifestyle.hygieneOn() and tonumber(data.hygieneNeed) or nil,
        showering = data.IsDoingShower == true,
        sitting = sitting,
        comfort = comfort,
        yoga = yogaLevel(data),
    }
end

-- Lifestyle's toilet system exists for this player (client and single player only).
function Lifestyle.hasToilet(player)
    if not Lifestyle.active() or not Lifestyle.hygieneOn() then
        return false
    end
    local data = player:getModData()
    local moodles = type(data) == "table" and data.LSMoodles or nil
    return type(moodles) == "table" and type(moodles.BladderNeed) == "table"
end

-- Adds to (or, negative, takes from) Lifestyle's bathroom need, 0-100. Nothing happens on the toilet or without the
-- toilet system. Returns the new need, or nil when nothing was changed.
function Lifestyle.addBathroomNeed(player, delta)
    if delta == 0 or not Lifestyle.hasToilet(player) then
        return nil
    end
    local data = player:getModData()
    if data.IsDoingToilet == true then
        return nil
    end
    local need = math.max(0, math.min(100, (tonumber(data.bathroomNeed) or 0) + delta))
    data.bathroomNeed = need
    return need
end

-- The tub: Lifestyle's bath animation for the heat-stroke cold bath (Client/ColdBath). A tub's main sprite says which way
-- it faces; Lifestyle puts a character at ENTER while climbing in (Bob_Tub_Enter) and at SEAT while sitting in it
-- (Bob_Tub_Base), as offsets inside the tub's square (LSUseTub.lua getTubEnterXY, getXYTexture). Without Lifestyle
-- these animations don't exist.
Lifestyle.TUB_FACING = {
    fixtures_bathroom_01_25 = "S", fixtures_bathroom_01_26 = "E",
    fixtures_bathroom_01_52 = "N", fixtures_bathroom_01_55 = "W",
}
Lifestyle.TUB_ENTER = { S = { 0.2, 0.35 }, E = { 0.35, 0.2 }, N = { 0.2, 0.35 }, W = { 0.35, 0.2 } }
Lifestyle.TUB_SEAT = { S = { 0.4, 0.35 }, E = { 0.35, 0.4 }, N = { 0.35, 0.4 }, W = { 0.4, 0.35 } }
Lifestyle.TUB_ANIM_ENTER = "Bob_Tub_Enter"
Lifestyle.TUB_ANIM_SEAT = "Bob_Tub_Base"

-- Lifestyle's note of a bath, so its own moodle and "last bath" know about our cold bath: the cold-bath moodle level and
-- the hour. Only touches data Lifestyle already keeps.
function Lifestyle.markColdBath(player)
    if not Lifestyle.active() then
        return
    end
    local data = player:getModData()
    if type(data) ~= "table" then
        return
    end
    data.lastBath = player:getHoursSurvived()
    local moodle = type(data.LSMoodles) == "table" and data.LSMoodles.BathCold or nil
    if type(moodle) == "table" then
        moodle.Value = math.max(tonumber(moodle.Value) or 0, 0.2)
    end
end

return Lifestyle
