-- Drug interactions. A pair fires once when both categories have an active dose at the same time: the character says
-- the warning and the effect applies once. It can fire again after one of the two has worn off. A pair may also weaken
-- a category for as long as both are active (weakens: Interactions.weakened, read by Medication/Provider).
--
-- Categories are by item (Medication/Data), so homemade twins and the IV antibiotics count; painkillers take part.
--
-- State: state.meds.pairs[pairId] = true while the pair is active (fired).

local Tables = require "ExtensiveHealthRedone/Core/Tables"
local SideEffects = require "ExtensiveHealthRedone/Medication/SideEffects"

local Interactions = {}

local T = "UI_EHR_Text_"
local SRC = "med:interaction"

-- Adds `amount` (share of the range) but never past `cap`, and never lowers the stat.
local function addUpTo(p, stat, amount, cap)
    local current = p.facts.norm and p.facts.norm[stat] or 0
    local add = math.min(amount, math.max(0, cap - current))
    if add > 0 then
        p.stats:addF(stat, SRC, add)
    end
end

-- id -> { a, b (categories), line, effect(p) (optional), weakens (optional) }. Effects are one-off; weakens =
-- { category, factor } scales the relief of that category's doses by factor while both are active.
Interactions.PAIRS = {
    antibioticCorticosteroid = { a = "antibiotic", b = "corticosteroid",
        line = T .. "AntibioticsCorticosteroidsRiskOf",
        effect = function(p) SideEffects.start(p, "immunosuppression") end },
    chelationAntifungal = { a = "chelation", b = "ivAntifungal",
        line = T .. "ChelationIVAntifungalStrongKidneyStress",
        effect = function(p)
            addUpTo(p, "FATIGUE", 0.18, 0.65)
            addUpTo(p, "SICKNESS", 0.12, 0.35)
            SideEffects.start(p, "kidney_stress")
        end },
    relaxantBeta = { a = "muscleRelaxant", b = "betaBlocker",
        line = T .. "MuscleRelaxantsBetaBlockersMayCauseExcessive",
        effect = function(p) addUpTo(p, "FATIGUE", 0.15, 0.8) end },
    nsaidCorticosteroid = { a = "antiInflammatory", b = "corticosteroid",
        line = T .. "AntiInflammatoryCorticosteroidsIncreasedGI",
        effect = function(p) SideEffects.start(p, "abdominal_pain") end },
    nsaidAntibiotic = { a = "antiInflammatory", b = "antibiotic",
        line = T .. "NSAIDsAntibioticsIncreasedGIUpset",
        effect = function(p) addUpTo(p, "FOOD_SICKNESS", 0.10, 0.30) end },
    painkillerRelaxant = { a = "painkiller", b = "muscleRelaxant",
        line = T .. "PainkillersMuscleRelaxantsIncreasedDrowsiness",
        effect = function(p) addUpTo(p, "FATIGUE", 0.10, 0.70) end },
    -- While both are active, antibiotic relief is halved (Medication/Provider).
    charcoalAntibiotic = { a = "charcoal", b = "antibiotic", line = T .. "ActivatedCharcoalAbsorbsAntibioticsReduced",
        weakens = { category = "antibiotic", factor = 0.5 } },
    epinephrineBeta = { a = "epinephrine", b = "betaBlocker", line = T .. "EpinephrineBetaBlockersReducedEpinephrine" },
    coughCold = { a = "coughSuppressant", b = "coldFlu", line = T .. "MultipleColdMedicationsWatchForDrowsiness" },
    nauseaDiarrheal = { a = "antiNausea", b = "antiDiarrheal", line = T .. "MultipleGIMedicationsWatchForConstipation" },
    antibioticAntifungal = { a = "antibiotic", b = "antifungal", line = T .. "AntibioticAntifungalMinorGIUpsetPossible" },
    electrolyteRehydration = { a = "electrolyte", b = "rehydration",
        line = T .. "MultipleRehydrationSolutionsExcessive" },
}

Interactions.IDS = Tables.sortedKeys(Interactions.PAIRS)

-- Adds an interaction from an add-on mod: pair = { a, b (categories, Medication/Data), line = key, effect(p),
-- weakens = { category, factor (0-1) } }. Errors on a known id.
function Interactions.register(id, pair)
    if type(id) ~= "string" or Interactions.PAIRS[id] then
        error("drug interaction " .. tostring(id) .. " is already registered", 2)
    end
    if type(pair) ~= "table" or type(pair.a) ~= "string" or type(pair.b) ~= "string" or type(pair.line) ~= "string" then
        error("drug interaction " .. id .. " needs categories a, b and a line", 2)
    end
    local w = pair.weakens
    if w ~= nil and (type(w) ~= "table" or type(w.category) ~= "string" or type(w.factor) ~= "number"
        or w.factor < 0 or w.factor > 1) then
        error("drug interaction " .. id .. " weakens needs a category and a factor from 0 to 1", 2)
    end
    Interactions.PAIRS[id] = pair
    Interactions.IDS = Tables.sortedKeys(Interactions.PAIRS)
end

-- What the active pairs weaken: { [category] = factor }, the lowest factor when several pairs weaken one category.
-- categories: { [category] = true } of the active doses (Medication/Provider.activeDoses).
function Interactions.weakened(categories)
    local out = {}
    for _, id in ipairs(Interactions.IDS) do
        local pair = Interactions.PAIRS[id]
        local w = pair.weakens
        if w and categories[pair.a] and categories[pair.b] then
            out[w.category] = math.min(out[w.category] or 1, w.factor)
        end
    end
    return out
end

-- categories: { [category] = true } of the active doses (Medication/Provider.activeDoses).
function Interactions.update(p, categories)
    local fired = p.state.meds.pairs
    for _, id in ipairs(Interactions.IDS) do
        local pair = Interactions.PAIRS[id]
        local both = categories[pair.a] and categories[pair.b]
        if both and not fired[id] then
            fired[id] = true
            p.dirty("meds")
            p.say(pair.line)
            if pair.effect then
                pair.effect(p)
            end
        elseif not both and fired[id] then
            fired[id] = nil
            p.dirty("meds")
        end
    end
end

return Interactions
