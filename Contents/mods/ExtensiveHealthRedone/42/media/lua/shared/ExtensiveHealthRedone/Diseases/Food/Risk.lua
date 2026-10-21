-- The food and water triggers: what a bite or a drink risks, and the per-disease risk accumulator. Pure: the server
-- adapter (Server/Food) turns the item and the water source into the plain descriptions used here.
--
-- A food description: { fullType, type (lower-case item type), name (lower-case display name), rotten, fresh, burnt,
--   cooked, cookable, dangerousUncooked, hideUncooked, poisonPower, toxinType ("mushroom", "berry", "toxin") }
-- Hands: { blood = 0-1, dirt = 0-1 } averaged over both hands (W26: visible soil only).
--
-- Accumulator (v0.9 D:846-855, :4737-4829): state.exposure.data.food[id] = risk 0-1. A risky bite adds to it; it decays
-- by DECAY_PER_HOUR; the roll uses the total (guaranteed at GUARANTEED, immunity still applies); a contraction clears
-- it, a failed roll keeps it. Before any food disease exists, a pending risk makes the character queasy.

local Data = require "ExtensiveHealthRedone/Diseases/Food/Data"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local ImmunityRisk = require "ExtensiveHealthRedone/Conditions/Risk"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Risk = {}

Risk.FOOD_DISEASES = { "food_poisoning", "gastroenteritis", "trichinosis" }

local MULTIPLIER_OPTION = {
    food_poisoning = "FoodPoisoningChanceMultiplier",
    gastroenteritis = "GastroenteritisChanceMultiplier",
    trichinosis = "TrichinosisChanceMultiplier",
    dysentery = "DysenteryChanceMultiplier",
}

function Risk.multiplier(p, id)
    local value = tonumber(p.sandbox(MULTIPLIER_OPTION[id], 1)) or 1
    return math.max(0, math.min(5, value))
end

local function hasWord(text, words)
    for _, word in ipairs(words) do
        if text:find(word, 1, true) then
            return true
        end
    end
    return false
end

-- 0.70 for raw trichinosis sources (Data.TRICHINOSIS_TYPES, or modded "<animal>...meat"), else 0.
function Risk.trichinosis(food)
    if food.cooked or food.burnt then
        return 0, nil
    end
    local listed = Data.TRICHINOSIS_TYPES[food.fullType]
    if not listed then
        local t = food.type or ""
        if not (t:find("meat", 1, true) and hasWord(t, Data.TRICHINOSIS_ANIMALS)) or hasWord(t, Data.PRESERVED_WORDS) then
            return 0, nil
        end
    end
    local pork = (food.fullType or ""):find("^Base%.Pork") or (food.fullType or ""):find("^Base%.Bacon")
    return Data.FOOD.TRICHINOSIS, pork and "uncooked pork" or "uncooked wild game"
end

local function combine(a, b)
    return 1 - (1 - a) * (1 - b)
end

-- Food poisoning chance (before portion and multiplier) and reason. trichinosisRisk > 0 skips the uncooked branch:
-- that meat's raw risk is trichinosis.
function Risk.foodPoisoning(food, trichinosisRisk)
    if food.rotten then
        return Data.FOOD.ROTTEN, "rotten"
    end
    local chance, reasons = 0, {}
    if food.burnt then
        chance, reasons[1] = Data.FOOD.BURNED, "burned"
    elseif trichinosisRisk <= 0 and not food.cooked then
        local prepared = food.cookable and not food.hideUncooked and hasWord(food.type or "", Data.PREPARED_WORDS)
        if food.dangerousUncooked or prepared then
            chance, reasons[1] = Data.FOOD.UNCOOKED, "uncooked"
        end
    end
    if not food.burnt and food.fresh == false then
        chance = combine(chance, Data.FOOD.STALE)
        reasons[#reasons + 1] = "stale"
    end
    return chance, table.concat(reasons, " + ")
end

-- Gastroenteritis chance and reason from visible hand soil.
function Risk.hands(hands)
    if not hands then
        return 0, nil
    end
    local chance = math.min(Data.HANDS.MAX, (hands.blood or 0) * Data.HANDS.BLOOD + (hands.dirt or 0) * Data.HANDS.DIRT)
    if chance <= Data.HANDS.MIN then
        return 0, nil
    end
    local bloody, dirty = (hands.blood or 0) > 0.10, (hands.dirt or 0) > 0.10
    local reason = bloody and dirty and "bloody and dirty hands" or bloody and "bloody hands" or dirty and "dirty hands"
        or "contaminated hands"
    return chance, reason
end

-- Every food-disease risk of one bite: { { id, chance, reason } } after portion (0-1) and chance multipliers.
function Risk.ofBite(p, food, hands, portion)
    portion = math.max(0, math.min(1, portion or 1))
    local list = {}
    local function add(id, chance, reason)
        chance = chance * portion * Risk.multiplier(p, id)
        if chance > 0 then
            list[#list + 1] = { id = id, chance = math.min(1, chance), reason = reason }
        end
    end
    local trich, trichReason = Risk.trichinosis(food)
    add("trichinosis", trich, trichReason)
    add("food_poisoning", Risk.foodPoisoning(food, trich))
    add("gastroenteritis", Risk.hands(hands))
    return list
end

local function store(p)
    local data = p.state.exposure.data
    data.food = data.food or {}
    return data.food
end

-- Adds the risks of one bite and rolls each disease at its accumulated risk. Returns the ids contracted.
function Risk.applyBite(p, defs, risks)
    local acc = store(p)
    local contracted = {}
    for _, r in ipairs(risks) do
        local def = defs[r.id]
        if def and Engine.enabled(p, def) and not p.state.conditions.active[r.id] then
            local total = math.min(1, (acc[r.id] or 0) + r.chance)
            acc[r.id] = total
            local chance = total >= Data.RISK.GUARANTEED and 1 or math.min(Data.RISK.MAX_CHANCE, total)
            if Chance.roll(p.rng, ImmunityRisk.chance(p, r.id, chance)) and Engine.contract(p, defs, r.id,
                { source = r.reason }) then
                acc[r.id] = nil
                contracted[#contracted + 1] = r.id
            end
        end
    end
    return contracted
end

-- Poisonous food always poisons (no roll, no immunity). A second dose while poisoned can only raise the severity.
function Risk.applyToxin(p, defs, power, toxinType, portion)
    local def = defs.toxin_poisoning
    local effective = (power or 0) * math.max(0, math.min(1, portion or 1))
    if not def or effective <= 0 or not Engine.enabled(p, def) then
        return nil
    end
    local severity = def.poisonSeverity(toxinType, effective)
    local c = p.state.conditions.active.toxin_poisoning
    if c then
        if severity > c.severity then
            c.severity = severity
            p.dirty("conditions")
        end
        return c
    end
    c = Engine.contract(p, defs, "toxin_poisoning", { source = toxinType })
    if c then
        c.severity = math.max(c.severity, severity)
        c.data.toxinType = toxinType
        Engine.enterStage(p, defs, "toxin_poisoning", c, 1)
    end
    return c
end

-- The source of a world water object (v0.9 FoodHook getWorldWaterSourceType, first match wins). w: { customName,
-- name, sprite (lower-case strings or nil), rainCatcher (bool), tainted (bool) }. Returns a Data.WATER key.
function Risk.waterSource(w)
    local custom, name, sprite = w.customName or "", w.name or "", w.sprite or ""
    if custom:find("toilet", 1, true) then
        return "toilet"
    elseif custom == "dispenser" then
        return "tap"
    elseif sprite:find("^blends_natural_02") then
        return "river"
    elseif name:find("toilet", 1, true) then
        return "toilet"
    elseif w.rainCatcher or name:find("rain collector", 1, true) or sprite:find("^carpentry_02_5[2-5]$") then
        return "rainCollector"
    elseif w.tainted then
        return "tainted"
    end
    return "tap"
end

-- Dysentery from one drink: source is a Data.WATER key. One roll per drink, no accumulation. Returns the condition.
function Risk.applyWater(p, defs, source)
    local def = defs.dysentery
    local base = Data.WATER[source]
    if not def or not base then
        return nil
    end
    local chance = math.min(1, base * Risk.multiplier(p, "dysentery"))
    if chance <= 0.01 or not Engine.enabled(p, def) or p.state.conditions.active.dysentery then
        return nil
    end
    if Chance.roll(p.rng, ImmunityRisk.chance(p, "dysentery", chance)) then
        return Engine.contract(p, defs, "dysentery", { source = source })
    end
    return nil
end

-- The accumulated risks decay, and a pending risk makes the character queasy before any food disease exists.
function Risk.update(p, dt)
    local acc = p.state.exposure.data.food
    if not acc then
        return
    end
    local highest = 0
    for _, id in ipairs(Tables.sortedKeys(acc)) do
        local value = acc[id] - Data.RISK.DECAY_PER_HOUR / 60 * dt
        if value <= 0 then
            acc[id] = nil
        else
            acc[id] = value
            highest = math.max(highest, value)
        end
    end
    if highest > 0 then
        for _, id in ipairs(Risk.FOOD_DISEASES) do
            if p.state.conditions.active[id] then
                return
            end
        end
        local target = math.min(Data.RISK.PENDING_MAX, highest * Data.RISK.PENDING_SCALE)
        p.stats:raiseF("SICKNESS", "foodRisk", target, Data.RISK.PENDING_STEP * dt)
    end
end

return Risk
