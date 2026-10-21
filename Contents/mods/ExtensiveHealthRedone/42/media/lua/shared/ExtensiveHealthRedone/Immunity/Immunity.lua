-- The immune system (order 395: after medication, so a dose taken this step counts; before the conditions). Every
-- 15 game minutes it recomputes the target from six factors and the hygiene penalty, applies suppression, and moves
-- the score. The score only matters through Conditions/Risk (catching supported diseases) and wound containment
-- (Wounds/Infection); it never changes symptoms or progression. v0.9 EHR_Immunity.lua; docs/porting/phase6/immunity.md.
--
-- state.immunity = {
--   score       0-100, the current score
--   target      0-100 after suppression; false until the first update
--   trend       "recovering" | "declining" | "stable" | "disabled"
--   factors     { nutrition, hydration, rest, stressControl, bloodCondition, healthReserve } (0-100 each)
--   hygiene     { dirtiness, bloodiness (0-100), dirtPenalty, bloodPenalty, penalty }
--   pressures   { antibiotic = true, immunosuppression = true, phalanx = points } while they apply (for the UI)
--   tick        game minutes until the next update
-- }
--
-- Reads: p.facts.norm (HUNGER, THIRST, FATIGUE, STRESS as 0-1), p.facts.health (0-100), p.facts.hygiene
-- ({ dirt, blood } as 0-1 averages, Server/Immunity), state.blood, state.conditions, state.wounds, state.meds.side,
-- state.knox.effects, and p.treatment:active("antibiotic").

local Data = require "ExtensiveHealthRedone/Data/Immunity"
local KnoxData = require "ExtensiveHealthRedone/Diseases/Knox/Data"
local Blood = require "ExtensiveHealthRedone/Blood/Blood"

local Immunity = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function round1(v)
    return math.floor(v * 10 + 0.5) / 10
end

-- Piecewise linear through { { x, y }, ... }: 0 up to the first point, flat after the last.
local function curve(points, x)
    if x <= points[1][1] then
        return 0
    end
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if x <= b[1] then
            return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
        end
    end
    return points[#points][2]
end

local function rate(p, name)
    return clamp(tonumber(p.sandbox(name, 1)) or 1, 0.25, 3)
end

function Immunity.enabled(p)
    return p.sandbox("ImmunitySystemEnabled", true) ~= false
end

-- Disease pressure (0-MAX): what active illness takes off the health reserve.
function Immunity.pressure(state)
    local P = Data.PRESSURE
    local total = 0
    for id, c in pairs(state.conditions.active) do
        if id == "sepsis" then
            total = total + P.SEPSIS
        elseif not P.IGNORE[id] then
            local pressure = P.CONDITION_BASE + P.CONDITION_PER_STAGE * clamp(tonumber(c.stage) or 1, 1, 4)
            total = total + (P.HALF[id] and pressure / 2 or pressure)
        end
    end
    for _, e in pairs(state.wounds.parts) do
        if e.phase == "infected" then
            total = total + P.WOUND_BASE + P.WOUND_PER_STAGE * (e.stage or 1)
        end
    end
    return math.min(P.MAX, total)
end

-- The six factors (0-100) from plain values: norm = { HUNGER, THIRST, FATIGUE, STRESS } (0-1), health (0-100),
-- bloodPercent (0-100), pressure (0-70).
function Immunity.factors(norm, health, bloodPercent, pressure)
    local fatigue = clamp(norm.FATIGUE or 0, 0, 1)
    local rest = 100
    if fatigue > Data.REST_FROM then
        rest = (1 - fatigue) / (1 - Data.REST_FROM) * 100
    end
    local f = {
        nutrition = (1 - clamp(norm.HUNGER or 0, 0, 1)) * 100,
        hydration = (1 - clamp(norm.THIRST or 0, 0, 1)) * 100,
        rest = rest,
        stressControl = (1 - clamp(norm.STRESS or 0, 0, 1)) * 100,
        bloodCondition = (bloodPercent - Data.BLOOD_FLOOR) / (100 - Data.BLOOD_FLOOR) * 100,
        healthReserve = health - pressure,
    }
    for k, v in pairs(f) do
        f[k] = round1(clamp(v, 0, 100))
    end
    return f
end

-- The hygiene penalty from average dirt and blood (0-1 each).
function Immunity.hygiene(dirt, blood)
    local h = { dirtiness = round1(clamp(dirt or 0, 0, 1) * 100), bloodiness = round1(clamp(blood or 0, 0, 1) * 100) }
    h.dirtPenalty = round1(curve(Data.DIRT_CURVE, h.dirtiness))
    h.bloodPenalty = round1(curve(Data.BLOOD_CURVE, h.bloodiness))
    h.penalty = round1(clamp(h.dirtPenalty + h.bloodPenalty, 0, Data.HYGIENE_MAX))
    return h
end

-- The weighted factors minus the hygiene penalty, before suppression.
function Immunity.baseTarget(factors, hygiene)
    local sum = 0
    for _, name in ipairs(Data.FACTOR_ORDER) do
        sum = sum + factors[name] * Data.WEIGHTS[name]
    end
    return round1(clamp(sum - hygiene.penalty, 0, 100))
end

-- What pushes the score down right now: { antibiotic, immunosuppression, phalanx = points }.
function Immunity.pressures(p)
    local list = {}
    if p.treatment:active("antibiotic") then
        list.antibiotic = true
    end
    local side = p.state.meds.side.immunosuppression
    if side and (side.left or 0) > 0 then
        list.immunosuppression = true
    end
    if (p.state.knox.effects.phalanxDebuff or 0) > 0 then
        list.phalanx = KnoxData.PHALANX_DEBUFF_POINTS
    end
    return list
end

-- Moves the score one update (TICK_MINUTES) toward the target. Returns the new score and the trend.
function Immunity.move(score, target, suppressed, rise, fall)
    local hours = Data.TICK_MINUTES / 60
    if suppressed and score > Data.SUPPRESSED_CAP then
        return math.max(Data.SUPPRESSED_CAP, score - Data.SUPPRESSED_STEP * fall), "declining"
    elseif target > score + Data.SETTLE then
        return math.min(target, score + Data.RISE_PER_HOUR * rise * hours), "recovering"
    elseif target < score - Data.SETTLE then
        return math.max(target, score - Data.FALL_PER_HOUR * fall * hours), "declining"
    end
    return target, "stable"
end

-- The status band id for a score: "Strong", "Stable", "Strained", "Compromised" or "Suppressed".
function Immunity.band(score)
    for _, b in ipairs(Data.BANDS) do
        if score >= b.from then
            return b.id
        end
    end
    return Data.BANDS[#Data.BANDS].id
end

-- One update: recompute everything and move the score.
function Immunity.recompute(p)
    local im = p.state.immunity
    local facts = p.facts
    local soil = facts.hygiene or {}
    local factors = Immunity.factors(facts.norm, facts.health or 100, Blood.percent(p.state.blood) * 100,
        Immunity.pressure(p.state))
    local hygiene = Immunity.hygiene(soil.dirt, soil.blood)
    local pressures = Immunity.pressures(p)
    local target = Immunity.baseTarget(factors, hygiene)
    if pressures.phalanx then
        target = math.max(0, target - pressures.phalanx)
    end
    local suppressed = pressures.antibiotic or pressures.immunosuppression
    if suppressed then
        target = math.min(target, Data.SUPPRESSED_CAP)
    end
    im.factors, im.hygiene, im.pressures, im.target = factors, hygiene, pressures, target
    if not Immunity.enabled(p) then
        im.trend = "disabled"
    else
        local score, trend = Immunity.move(im.score, target, suppressed, rate(p, "ImmunityRecoveryRate"),
            rate(p, "ImmunityDeclineRate"))
        im.score, im.trend = round1(clamp(score, 0, 100)), trend
    end
    p.dirty("immunity")
end

function Immunity.update(p, dt)
    local im = p.state.immunity
    im.tick = (im.tick or 0) - dt
    if im.tick > 0 then
        return
    end
    im.tick = Data.TICK_MINUTES
    Immunity.recompute(p)
end

Immunity.system = { name = "immunity", order = 395, update = function(p, dt) Immunity.update(p, dt) end }

return Immunity
