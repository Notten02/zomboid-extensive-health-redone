-- Hardship: Emotions (Workshop 3811647387, mod id HardshipEmotions): whether it is enabled, and the options of its
-- Extensive Health Rework integration. Server/HardshipEmotions does the work. Never errors.
--
-- Its integration was written for the original EHR: it looks for a global EHR table and that mod's player modData.
-- Its options live in its own sandbox namespace (SandboxVars.HardshipEmotions); the ones that have no sandbox entry
-- fall back to its own defaults.

local Env = require "ExtensiveHealthRedone/Game/Env"

local HardshipEmotions = {}

HardshipEmotions.MOD_ID = "HardshipEmotions"

-- Our medication categories (Medication/Data) as the original EHR named them, for the ones Emotions reacts to
-- (stimulants and epinephrine make the character Wired, beta blockers stop adrenaline, the rest sedate).
HardshipEmotions.CATEGORIES = {
    stimulant = "stimulant",
    epinephrine = "epinephrine",
    betaBlocker = "beta blocker",
    sleepAid = "sleep aid",
    antipsychotic = "antipsychotic",
    muscleRelaxant = "muscle relaxant",
    painkiller = "painkiller",
}

HardshipEmotions.KNOX_REVEAL_DEFAULT = 30     -- percent of the infection (its EHRKnoxRevealAt default)

local cached      -- nil until asked, then true or false for the session

-- A save has its own mod list, so this is asked at play time, once.
function HardshipEmotions.active()
    if cached == nil then
        local mods = getActivatedMods()
        cached = mods:contains(HardshipEmotions.MOD_ID) or mods:contains("\\" .. HardshipEmotions.MOD_ID)
    end
    return cached
end

-- Forgets what was learned about the mod list (tests, and a new game in the same session).
function HardshipEmotions.reset()
    cached = nil
end

local function option(name, default)
    return Env.sandbox(HardshipEmotions.MOD_ID .. "." .. name, default)
end

-- The mod is on and its EHR integration (IntegrateEHR, default on) too.
function HardshipEmotions.integrated()
    return HardshipEmotions.active() and option("IntegrateEHR", true) ~= false
end

-- The infection share (0-1) under which a Knox infection stays off our displays, or nil when nothing is hidden
-- (EHRHideKnox, default on; EHRKnoxRevealAt, default 30 %).
function HardshipEmotions.knoxRevealAt()
    if not HardshipEmotions.integrated() or option("EHRHideKnox", true) == false then
        return nil
    end
    local percent = tonumber(option("EHRKnoxRevealAt", HardshipEmotions.KNOX_REVEAL_DEFAULT))
        or HardshipEmotions.KNOX_REVEAL_DEFAULT
    return math.max(0, math.min(100, percent)) / 100
end

return HardshipEmotions
