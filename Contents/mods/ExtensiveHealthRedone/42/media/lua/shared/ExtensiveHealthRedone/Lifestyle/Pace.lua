-- How Lifestyle: Hobbies speeds up or slows down getting over an illness.
-- Pure: a plain reading of the player's Lifestyle data goes in, a multiplier on the elapsed time of the illness comes
-- out. The Lifestyle reader (Server/Lifestyle) builds the reading and Conditions/Engine applies the multiplier.
--
-- A reading `l`:
--   hygiene   0-100 or nil   Lifestyle's hygieneNeed: 0 = spotless, 50 = neutral, 100 = filthy
--   showering true           in a shower or tub right now
--   bathLeft  minutes        game minutes left of the "recently bathed" glow (0 when none)
--   sitting   true           seated on furniture, a bed, a tub or the ground
--   comfort   0-1            how comfortable the seat is (Lifestyle's ComfortVal; 0.5 and up is comfortable)
--   yoga      0-10           Lifestyle's hidden Yoga skill level
-- l.pace (set by Pace.read) is the total multiplier; Pace.forCondition adds the per-illness adjustments.
--
-- Bonuses and penalties add up: very clean +25 %, clean +15 %, dirty -10 %, filthy -25 %, a shower +5 % (fading over
-- the two hours after it), comfortable seat +10 %, any other sitting +5 %, +1 % per Yoga level. The pace never drops
-- below 50 %. "Comfortable" reads Lifestyle's own seat keys.
-- No hysteresis on the hygiene tiers: nothing shows the tier, so flicker at a threshold costs nothing.

local Pace = {}

Pace.HYGIENE = { EXCELLENT = 15, GOOD = 35, DIRTY = 65, FILTHY = 85 }
Pace.BONUS = {
    EXCELLENT = 0.25, GOOD = 0.15, SHOWER = 0.05, SIT_COMFORT = 0.10, SIT_BASIC = 0.05, YOGA_PER_LEVEL = 0.01,
}
Pace.PENALTY = { DIRTY = -0.10, FILTHY = -0.25 }
Pace.BATH_GLOW_MINUTES = 120
Pace.COMFORTABLE = 0.5
Pace.MIN = 0.5

-- Conditions Lifestyle never speeds up: Knox isn't about hygiene.
Pace.EXCLUDED = { knox_infection = true }

local function number(v, lo, hi, default)
    if type(v) ~= "number" or v ~= v then
        return default
    end
    return math.max(lo, math.min(hi, v))
end

-- A reading cleaned up to the ranges above. Anything missing means "nothing to say about it".
function Pace.clean(raw)
    raw = type(raw) == "table" and raw or {}
    return {
        hygiene = number(raw.hygiene, 0, 100, nil),
        showering = raw.showering == true,
        bathLeft = number(raw.bathLeft, 0, Pace.BATH_GLOW_MINUTES, 0),
        sitting = raw.sitting == true,
        comfort = number(raw.comfort, 0, 1, 0),
        yoga = math.floor(number(raw.yoga, 0, 10, 0)),
    }
end

local function hygieneBonus(hygiene)
    local H, B, P = Pace.HYGIENE, Pace.BONUS, Pace.PENALTY
    if hygiene == nil then
        return 0
    elseif hygiene < H.EXCELLENT then
        return B.EXCELLENT
    elseif hygiene < H.GOOD then
        return B.GOOD
    elseif hygiene > H.FILTHY then
        return P.FILTHY
    elseif hygiene > H.DIRTY then
        return P.DIRTY
    end
    return 0
end

-- The recent-bath share (0-1): 1 while showering, fading over the glow.
local function bathShare(l)
    if l.showering then
        return 1
    end
    return l.bathLeft / Pace.BATH_GLOW_MINUTES
end

-- The total multiplier and its parts { name, bonus } for a cleaned reading.
function Pace.compute(l)
    local B = Pace.BONUS
    local parts = {}
    local function add(name, bonus)
        if bonus ~= 0 then
            parts[#parts + 1] = { name = name, bonus = bonus }
        end
    end
    add("hygiene", hygieneBonus(l.hygiene))
    add("bath", B.SHOWER * bathShare(l))
    if l.sitting then
        add("sitting", l.comfort >= Pace.COMFORTABLE and B.SIT_COMFORT or B.SIT_BASIC)
    end
    add("yoga", l.yoga * B.YOGA_PER_LEVEL)
    local total = 1
    for _, part in ipairs(parts) do
        total = total + part.bonus
    end
    return math.max(Pace.MIN, total), parts
end

-- Cleans a raw reading and attaches its pace and parts.
function Pace.read(raw)
    local l = Pace.clean(raw)
    l.pace, l.parts = Pace.compute(l)
    return l
end

-- The multiplier on elapsed time for one condition (per-illness adjustments): a dirty wound-prone body does
-- worse with cellulitis and a recent bath helps; sitting still helps the lungs a little less. l may be nil.
function Pace.forCondition(l, id)
    if not l or Pace.EXCLUDED[id] then
        return 1
    end
    local pace = l.pace or 1
    if id == "cellulitis" then
        local H = Pace.HYGIENE
        if l.hygiene and l.hygiene > H.FILTHY then
            pace = pace - 0.10
        elseif l.hygiene and l.hygiene > H.DIRTY then
            pace = pace - 0.05
        end
        if l.showering or l.bathLeft > 0 then
            pace = pace + 0.05
        end
    elseif (id == "pneumonia" or id == "common_cold") and l.sitting then
        pace = pace - 0.05
    end
    return math.max(Pace.MIN, pace)
end

return Pace
