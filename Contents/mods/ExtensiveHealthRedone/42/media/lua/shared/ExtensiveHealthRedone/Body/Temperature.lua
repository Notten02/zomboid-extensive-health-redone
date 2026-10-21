-- Body temperature: the one owner of vanilla's TEMPERATURE (order 790, after every system that asks for a fever,
-- before healing). It keeps a floor and a ceiling in state.temperature; Server/Temperature holds vanilla's value
-- inside them on every tick.
--
-- Why a hold: in 42.21 TEMPERATURE is the thermoregulator's own core temperature. A single write is half kept on the
-- next tick and then pulled back toward 37 deg C within minutes; writing every tick holds it (the Phase 6 fever probe,
-- phase6-result.md). Vanilla still decides how the air, clothes and wetness heat or cool the body; we only bound it.
--
-- Floor, the highest of:
--   fever        Diseases, side effects and Knox items ask through the stat aggregator (Conditions/Symptoms.applyFever:
--                p.stats:raise("TEMPERATURE", source, target, step); heat stroke cooling: p.stats:lower). This system
--                takes those contributions each step and turns them into one fever that rises by the asked step,
--                breaks by DECAY_PER_HOUR toward a lower target or toward normal (maintainer: a visible break, not
--                vanilla's half hour), and ends at NORMAL. A fever isn't started when the body is already that hot.
--   warm         the Warming Pack (Medication/Data, effect "warming"): toward 37 deg C at WARMING_PER_HOUR, never above.
--   hot food     a hot meal or drink (Temperature.eat): up to +0.4 deg C over the body at the time, never above 37.
-- Ceiling (only without a fever: a fever beats food cooling):
--   cold food    frozen food or ice: up to -0.4 deg C under the body at the time, never below 37.
-- TemperatureChangeSpeed scales the fever's rise and break and the pack's warming. BodyTemperatureEnabled=false
-- turns off the pack's warming and food temperature (fevers stay: they are part of the diseases).
--
-- state.temperature = {
--   fever, source     deg C of the fever and what asked for its highest target; false without a fever
--   warm              deg C the Warming Pack holds the body at; false when no pack is active
--   food = { hot, cold }   each false or { base = body deg C when first eaten, add = deg C (<= FOOD.MAX_TOTAL),
--                          left, total = minutes }; the effect fades linearly with left / total
--   floor, ceiling    what Server/Temperature holds TEMPERATURE between; false for none
--   shown             floor/ceiling rounded to 0.1, at the last sync
-- }

local Temperature = {}

Temperature.NORMAL = 37.0           -- deg C; at or below this a fever ends, and the pack and hot food warm to here
Temperature.DECAY_PER_HOUR = 1.0    -- deg C per game hour while a fever breaks
Temperature.WARMING_PER_HOUR = 3.2  -- the Warming Pack (v0.9)

-- Food temperature (W25, maintainer: warm and cool; v0.9 EHR_FoodTemperature.lua numbers, classified by vanilla's
-- heat value instead of a temperature 42.21 doesn't have).
Temperature.FOOD = {
    HOT_HEAT = 1.3,                 -- vanilla's "hot enough" (ISInventoryPaneContextMenu "better hot")
    MAX = 0.4,                      -- deg C from one item
    MAX_TOTAL = 0.6,                -- deg C from several, each further one x FALLOFF
    FALLOFF = 0.7,
    HOT_PER_HEAT = 0.4,             -- deg C per 1.0 of heat above room temperature (1.0), x the portion factor
    FROZEN = 0.3,                   -- deg C for frozen food or ice, x the portion factor
    LIQUID_MINUTES = { 15, 30 },    -- scaled by the size of the effect
    SOLID_MINUTES = { 30, 60 },
    LINE_FROM = 0.15,               -- deg C at which the character remarks on it
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function speed(p)
    return clamp(tonumber(p.sandbox("TemperatureChangeSpeed", 1)) or 1, 0.25, 4)
end

local function round1(v)
    return math.floor(v * 10 + 0.5) / 10
end

function Temperature.enabled(p)
    return p.sandbox("BodyTemperatureEnabled", true) ~= false
end

function Temperature.warmingActive(state)
    local e = state.meds and state.meds.effects.warming
    return e ~= nil and (e.left or 0) > 0
end

-- The body's temperature this step, as vanilla has it (including what we held last tick).
local function bodyOf(p)
    return p.facts.stats and p.facts.stats.TEMPERATURE or Temperature.NORMAL
end

-- Fever -------------------------------------------------------------------------------------------------------------

-- The next fever from the current one (false when none), the body's temperature, and this step's contribution entry
-- (StatAggregator:take; may be nil). dt in game minutes. Returns the fever (or false) and its source.
function Temperature.nextFever(fever, body, e, dt, speedFactor)
    local decay = Temperature.DECAY_PER_HOUR / 60 * dt * speedFactor
    local raise, lower = e and e.raise, e and e.lower
    local source = false
    if raise and raise.target > Temperature.NORMAL then
        source = raise.source or false
        if not fever then
            if body < raise.target then
                fever = math.min(raise.target, body + raise.step * speedFactor)
            end
        elseif fever < raise.target then
            fever = math.min(raise.target, fever + raise.step * speedFactor)
        else
            fever = math.max(raise.target, fever - decay)
        end
    elseif fever then
        fever = fever - decay
    end
    if fever and lower and fever > lower.target then
        fever = math.max(lower.target, fever - lower.step * speedFactor)
    end
    if e and (e.delta or 0) > 0 then
        fever = (fever or body) + e.delta       -- a one-off spike (Temperature.spike outside the step)
    end
    if fever and fever <= Temperature.NORMAL then
        return false, false
    end
    return fever, fever and source or false
end

-- Food --------------------------------------------------------------------------------------------------------------

-- What eating or drinking an item does: info = { heat (vanilla multiplier, 1.0 room temperature), frozen, liquid,
-- portion (0-1 of the item) }. Returns { kind = "hot" | "cold", add = deg C, minutes } or nil.
function Temperature.foodEffect(info)
    local F = Temperature.FOOD
    local factor = 0.5 + clamp(tonumber(info.portion) or 1, 0, 1)
    local kind, add
    if info.frozen then
        kind, add = "cold", F.FROZEN * factor
    elseif (tonumber(info.heat) or 1) >= F.HOT_HEAT then
        kind, add = "hot", F.HOT_PER_HEAT * clamp(info.heat - 1, 0, 1) * factor
    else
        return nil
    end
    add = math.min(F.MAX, add)
    local range = info.liquid and F.LIQUID_MINUTES or F.SOLID_MINUTES
    return { kind = kind, add = add, minutes = range[1] + (range[2] - range[1]) * add / F.MAX }
end

-- The food effect now (deg C): add fading linearly over its time.
local function foodNow(entry)
    if not entry or entry.total <= 0 then
        return 0
    end
    return entry.add * clamp(entry.left / entry.total, 0, 1)
end

-- Eating or drinking an item (Server/Temperature's eat and drink hooks). Returns the effect or nil.
function Temperature.eat(p, info)
    if not Temperature.enabled(p) then
        return nil
    end
    local effect = Temperature.foodEffect(info)
    if not effect then
        return nil
    end
    local F = Temperature.FOOD
    local food = p.state.temperature.food
    local entry = food[effect.kind]
    if entry then
        local now = foodNow(entry)
        entry.add = math.min(F.MAX_TOTAL, now + effect.add * F.FALLOFF)
        entry.left = math.max(entry.left, effect.minutes)
        entry.total = entry.left
    else
        food[effect.kind] = { base = bodyOf(p), add = effect.add, left = effect.minutes, total = effect.minutes }
    end
    if effect.add >= F.LINE_FROM then
        p.say(effect.kind == "hot" and "UI_EHR_Food_Warming" or "UI_EHR_Food_Cooling")
    end
    p.dirty("temperature")
    return effect
end

local function updateFood(food, dt)
    for _, kind in ipairs({ "hot", "cold" }) do
        local entry = food[kind]
        if entry then
            entry.left = entry.left - dt
            if entry.left <= 0 then
                food[kind] = false
            end
        end
    end
end

-- Step --------------------------------------------------------------------------------------------------------------

-- Marks the section dirty when the floor or ceiling starts, ends, or moves by a displayed 0.1 deg C.
local function publish(p, t)
    local shown = tostring(t.floor and round1(t.floor)) .. "/" .. tostring(t.ceiling and round1(t.ceiling))
    if shown ~= t.shown then
        t.shown = shown
        p.dirty("temperature")
    end
end

function Temperature.update(p, dt)
    local t = p.state.temperature
    local body = bodyOf(p)
    local k = speed(p)
    local fever, source = Temperature.nextFever(t.fever, body, p.stats:take("TEMPERATURE"), dt, k)
    t.fever, t.source = fever, source or (fever and t.source) or false

    local enabled = Temperature.enabled(p)
    if enabled and Temperature.warmingActive(p.state) then
        local from = math.max(t.warm or body, body)
        t.warm = math.min(Temperature.NORMAL, from + Temperature.WARMING_PER_HOUR / 60 * dt * k)
    else
        t.warm = false
    end

    local food = t.food
    if enabled then
        updateFood(food, dt)
    else
        food.hot, food.cold = false, false
    end

    local floor = t.fever or false
    if t.warm and (not floor or t.warm > floor) then
        floor = t.warm
    end
    local hot = food.hot
    if hot then
        local warmTo = math.min(Temperature.NORMAL, hot.base + foodNow(hot))
        if not floor or warmTo > floor then
            floor = warmTo
        end
    end
    local ceiling = false ---@type number|false
    local cold = food.cold
    if cold and not t.fever then
        ceiling = math.max(Temperature.NORMAL, cold.base - foodNow(cold))
    end
    t.floor, t.ceiling = floor, ceiling
    publish(p, t)
end

-- A sudden fever outside the simulation step (a command, e.g. the stale-blood reaction): delta deg C on top of the
-- held fever, or of the body's temperature. It then breaks like any other fever.
function Temperature.spike(p, source, delta)
    local t = p.state.temperature
    local body = bodyOf(p)
    t.fever = math.max(t.fever or body, body) + delta
    t.source = source
    if not t.floor or t.fever > t.floor then
        t.floor = t.fever
    end
    publish(p, t)
end

Temperature.system = { name = "temperature", order = 790, update = function(p, dt) Temperature.update(p, dt) end }

return Temperature
