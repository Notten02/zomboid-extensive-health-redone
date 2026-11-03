-- Amputations by The Only Cure (Game/OnlyCure reads the mod; Server/OnlyCure puts it in the facts). Without the mod
-- there are no facts.toc and this system does nothing.
--
-- The mod cuts hands, forearms and upper arms; cutting a limb also takes everything below it. Its plain snapshot:
--   toc = { limbs = { [limb] = { cut, healed, cauterized, dirt = 0-1 } }, prosthesis = { L = bool, R = bool } }
--
-- Every step, for the cut parts:
--   * our state on them goes: wound infection, tetanus bookkeeping, slowed healing timers. Nothing can return it: the
--     parts are missing (facts.missing), and the body aggregator ignores wishes for them.
--   * a part cut since the last step while it had a wound infection: the amputation cured it, at any stage (a line
--     and the cure XP). Sepsis already in the blood is not touched. An amputation from before we first saw the mod
--     (a save that had it already) is cleanup only: no line, no XP.
-- The stump of each arm (its highest cut limb) is a wound on the part above it (Hand_L -> ForeArm_L, ForeArm_L ->
-- UpperArm_L, UpperArm_L -> Torso_Upper). While it is neither healed nor cauterized it rolls every 12 h for a wound
-- infection incubation there, by the mod's wound dirtiness (Data/Wounds stump); from then on Wounds/Infection's rules
-- run it. The mod's wound cleaning (its dirtiness falls) counts as disinfecting that part.
--
-- state.onlyCure (its own section, so the core schema version never moves for it):
--   { v, known = bool (the mod's data was seen), cut = { [part] = true }, prosthesis = { L, R },
--     stumps = { [limb] = { part, healed, cauterized, dirt, shown, elapsed } } }
--   dirt is the last dirtiness seen, shown the one the client has (a tenth), elapsed the minutes since the last roll.

local Data = require("ExtensiveHealthRedone/Data/Wounds").stump
local Infection = require "ExtensiveHealthRedone/Wounds/Infection"
local Schema = require "ExtensiveHealthRedone/Core/Schema"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local Amputation = {}

Amputation.SECTION = "onlyCure"

-- The limbs the mod can cut, from the hand up, per side.
Amputation.SIDES = { "L", "R" }
Amputation.LIMBS = { "Hand_L", "ForeArm_L", "UpperArm_L", "Hand_R", "ForeArm_R", "UpperArm_R" }
local CHAIN = {
    L = { "Hand_L", "ForeArm_L", "UpperArm_L" },
    R = { "Hand_R", "ForeArm_R", "UpperArm_R" },
}
-- The part a stump sits on.
Amputation.ABOVE = {
    Hand_L = "ForeArm_L", ForeArm_L = "UpperArm_L", UpperArm_L = "Torso_Upper",
    Hand_R = "ForeArm_R", ForeArm_R = "UpperArm_R", UpperArm_R = "Torso_Upper",
}

function Amputation.defaults()
    return { known = false, cut = {}, prosthesis = {}, stumps = {} }
end

-- Registered once, even when a test loads this module again.
if not Schema.ADDONS[Amputation.SECTION] then
    Schema.registerSection(Amputation.SECTION, { defaults = Amputation.defaults, exam = true })
end

-- The cut parts: { [part] = true }.
function Amputation.missing(toc)
    local out = {}
    for _, limb in ipairs(Amputation.LIMBS) do
        local l = toc.limbs[limb]
        if l and l.cut then
            out[limb] = true
        end
    end
    return out
end

-- Each arm's stump, its highest cut limb: { limb, side, part (the part it sits on), healed, cauterized, dirt }.
function Amputation.stumps(toc)
    local out = {}
    for _, side in ipairs(Amputation.SIDES) do
        local top
        for _, limb in ipairs(CHAIN[side]) do
            local l = toc.limbs[limb]
            if l and l.cut then
                top = limb
            end
        end
        if top then
            local l = toc.limbs[top]
            out[#out + 1] = { limb = top, side = side, part = Amputation.ABOVE[top], healed = l.healed == true,
                cauterized = l.cauterized == true, dirt = l.dirt or 0 }
        end
    end
    return out
end

-- What the character holds things with on one side: "hand", "prosthesis" or "none".
function Amputation.hand(toc, side)
    local l = toc.limbs["Hand_" .. side]
    if not (l and l.cut) then
        return "hand"
    end
    return toc.prosthesis[side] and "prosthesis" or "none"
end

-- True when neither side has a hand or a prosthesis: the character eats face first and washes the face.
function Amputation.noHands(toc)
    return Amputation.hand(toc, "L") == "none" and Amputation.hand(toc, "R") == "none"
end

-- The roll's chance for a stump of this dirtiness.
function Amputation.stumpChance(dirt, multiplier)
    return math.max(0, math.min(1, Data.CHANCE * math.max(0, math.min(1, dirt or 0)) * (multiplier or 1)))
end

local function multiplier(p)
    local m = tonumber(p.sandbox("StumpInfectionChanceMultiplier", 1.0)) or 1
    return math.max(0, math.min(5, m))
end

local function tenth(dirt)
    return math.floor((dirt or 0) * 10 + 0.5) / 10
end

-- Our state on a cut part goes. Returns whether a wound infection (not an incubation) was there.
local function dropPart(p, name)
    local wounds, infected = p.state.wounds, false
    local e = wounds.parts[name]
    if e then
        infected = e.phase == "infected"
        wounds.parts[name] = nil
        p.dirty("wounds")
    end
    local t = wounds.tetanus
    if t and (t.glass[name] or t.dirty[name] or t.seen[name]) then
        t.glass[name], t.dirty[name], t.seen[name] = nil, nil, nil
        p.dirty("wounds")
    end
    local locks = p.state.body and p.state.body.woundLock
    if locks and locks[name] then
        locks[name] = nil
        p.dirty("body")
    end
    return infected
end

local function rollStump(p, stump, st)
    if p.sandbox("WoundInfectionEnabled", true) == false or p.state.wounds.parts[stump.part]
        or p.treatment:active("antiseptic") then
        return
    end
    if Chance.roll(p.rng, Amputation.stumpChance(stump.dirt, multiplier(p))) then
        Infection.start(p, stump.part)
        p.state.wounds.parts[stump.part].stump = stump.limb
    end
    st.elapsed = st.elapsed - Data.EVERY_HOURS * 60
end

local function stumps(p, s, toc, dt)
    local seen = {}
    for _, stump in ipairs(Amputation.stumps(toc)) do
        seen[stump.limb] = true
        local st = s.stumps[stump.limb]
        if not st or st.part ~= stump.part then
            st = { part = stump.part, elapsed = 0, dirt = stump.dirt }
            s.stumps[stump.limb] = st
            p.dirty(Amputation.SECTION)
        end
        if st.healed ~= stump.healed or st.cauterized ~= stump.cauterized then
            st.healed, st.cauterized = stump.healed, stump.cauterized
            p.dirty(Amputation.SECTION)
        end
        if not (stump.healed or stump.cauterized) then
            -- The mod's cleaning: its dirtiness fell.
            if stump.dirt <= (st.dirt or 0) - Data.CLEANED and p.state.wounds.parts[stump.part] then
                Infection.disinfected(p, stump.part)
            end
            st.elapsed = (st.elapsed or 0) + dt
            if st.elapsed >= Data.EVERY_HOURS * 60 then
                rollStump(p, stump, st)
            end
        end
        st.dirt = stump.dirt
        if st.shown ~= tenth(stump.dirt) then
            st.shown = tenth(stump.dirt)
            p.dirty(Amputation.SECTION)
        end
    end
    for _, limb in ipairs(Amputation.LIMBS) do
        if s.stumps[limb] and not seen[limb] then
            s.stumps[limb] = nil
            p.dirty(Amputation.SECTION)
        end
    end
end

function Amputation.update(p, dt)
    local toc = p.facts and p.facts.toc
    if not toc then
        return
    end
    local s = p.state[Amputation.SECTION]
    local missing = Amputation.missing(toc)
    local cured = false
    for _, name in ipairs(Amputation.LIMBS) do
        if missing[name] then
            local infected = dropPart(p, name)
            if not s.cut[name] then
                s.cut[name] = true
                p.dirty(Amputation.SECTION)
                cured = cured or (infected and s.known)
            end
        elseif s.cut[name] then
            s.cut[name] = nil
            p.dirty(Amputation.SECTION)
        end
    end
    if cured then
        Speech.stage(p, Data.CURED_LINE)
        p.xp("cure", "woundInfection")
    end
    for _, side in ipairs(Amputation.SIDES) do
        local worn = toc.prosthesis[side] == true
        if (s.prosthesis[side] == true) ~= worn then
            s.prosthesis[side] = worn
            p.dirty(Amputation.SECTION)
        end
    end
    stumps(p, s, toc, dt)
    if not s.known then
        s.known = true
        p.dirty(Amputation.SECTION)
    end
end

-- Before the wound systems (300), so they never see the state of a cut part.
Amputation.system = { name = "amputation", order = 290, update = Amputation.update }

return Amputation
