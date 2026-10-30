-- What using a Knox item does, decided and applied on the authority (Server/Knox runs these in Runtime.applyNow and
-- consumes the item as told). Every function returns { consume = 0 | 1, outcome = string, ... }; refusals consume
-- nothing. The rules:
--   * gene therapy costs 10% health, Phalanx brings nausea, fever and a 48 h immune debuff, the immunobooster tremors;
--   * Phalanx resets to a share of the stat's real range, rewinds the infection timers too, and a too-early dose costs
--     one dose, not two;
--   * PatientZeroTraitDisabled only stops gene therapy granting immunity and the trait; it voids nothing.

local Data = require "ExtensiveHealthRedone/Diseases/Knox/Data"
local Knox = require "ExtensiveHealthRedone/Diseases/Knox/Knox"

local Items = {}

-- The infection fully cleared now (stats here, flags and timers through the body writer).
function Items.clearInfection(p, source)
    p.body:cureKnox(source)
    p.stats:ceilingF("ZOMBIE_INFECTION", source, 0)
    p.stats:ceilingF("ZOMBIE_FEVER", source, 0)
end

function Items.geneTherapy(p)
    local state = p.state
    local k = p.facts.knox
    if Knox.permanentlyImmune(state) then
        p.say("UI_EHR_Knox_GeneTherapyImmune")
        return { consume = 0, outcome = "immune" }
    end
    if not Knox.infected(k) then
        p.say("UI_EHR_Knox_GeneTherapyNotInfected")
        return { consume = 0, outcome = "notInfected" }
    end
    local chance = Knox.geneTherapyChance(state.identity.bloodType)
    if p.rng.int(0, 99) >= chance then
        p.say("UI_EHR_Knox_GeneTherapyRejected")
        p.body:kill("geneTherapy", "Gene therapy rejection")
        return { consume = 1, outcome = "died", chance = chance }
    end
    Items.clearInfection(p, "geneTherapy")
    p.body:damage("geneTherapy", Data.GENE_THERAPY_HEALTH_COST, 1)
    local knox = state.knox
    knox.survivor = true
    local grant = p.sandbox("PatientZeroTraitDisabled", false) ~= true
    if grant then
        knox.geneTherapyImmune = true
    end
    p.dirty("knox")
    p.say("UI_EHR_Knox_GeneTherapyWorked")
    return { consume = 1, outcome = "cured", chance = chance, grantTrait = grant }
end

function Items.antibodyTest(p)
    local bloodType = p.state.identity.bloodType
    local chance = Knox.geneTherapyChance(bloodType)
    local rating = Knox.rating(chance)
    p.state.knox.lastTest = { bloodType = bloodType or "?", chance = chance, rating = rating }
    p.dirty("knox")
    p.client("knoxSay", { key = "UI_EHR_KnoxCure_TestResult", args = { bloodType or "?", rating, chance .. "%" } })
    return { consume = 1, outcome = "tested", chance = chance, rating = rating }
end

-- Why the immunobooster can't be used now, as { outcome, line key, hours } or nil.
function Items.boosterRefusal(state, k)
    local knox = state.knox
    if Knox.permanentlyImmune(state) then
        return { outcome = "immune", key = "UI_EHR_Knox_BoosterImmune" }
    elseif (knox.boosterLeft or 0) > 0 then
        return { outcome = "active", key = "UI_EHR_Knox_BoosterActive", hours = math.ceil(knox.boosterLeft / 60) }
    elseif (knox.boosterCooldown or 0) > 0 then
        return { outcome = "cooldown", key = "UI_EHR_Knox_BoosterCooldown" }
    elseif Knox.infected(k) then
        return { outcome = "infected", key = "UI_EHR_Knox_BoosterInfected" }
    elseif k and k.bitten then
        return { outcome = "bitten", key = "UI_EHR_Knox_BoosterBitten" }
    end
    return nil
end

function Items.immunobooster(p)
    local refusal = Items.boosterRefusal(p.state, p.facts.knox)
    if refusal then
        if refusal.hours then
            p.client("knoxSay", { key = refusal.key, args = { tostring(refusal.hours) } })
        else
            p.say(refusal.key)
        end
        return { consume = 0, outcome = refusal.outcome }
    end
    local knox = p.state.knox
    knox.boosterLeft = Data.BOOSTER_MINUTES
    knox.boosterCooldown = Data.BOOSTER_COOLDOWN_MINUTES
    knox.effects.tremorIn = p.rng.int(Data.TREMOR_EVERY[1], Data.TREMOR_EVERY[2])
    p.dirty("knox")
    p.say("UI_EHR_Knox_BoosterInjected")
    return { consume = 1, outcome = "protected" }
end

local PHALANX_LINES = {
    "UI_EHR_Knox_Phalanx1", "UI_EHR_Knox_Phalanx2", "UI_EHR_Knox_Phalanx3", "UI_EHR_Knox_Phalanx4",
}

function Items.phalanx(p)
    local state = p.state
    local k = p.facts.knox
    if Knox.permanentlyImmune(state) then
        p.say("UI_EHR_Knox_PhalanxImmune")
        return { consume = 0, outcome = "immune" }
    end
    if not Knox.infected(k) then
        p.say("UI_EHR_Knox_PhalanxNotInfected")
        return { consume = 0, outcome = "notInfected" }
    end
    local knox = state.knox
    local resetTo = Knox.phalanxResetFor(knox.phalanxUses)
    if not resetTo then
        p.say("UI_EHR_Knox_PhalanxAdapted")
        return { consume = 1, outcome = "adapted" }
    end
    if resetTo >= Knox.progress(k) then
        p.say("UI_EHR_Knox_PhalanxTooEarly")
        return { consume = 1, outcome = "tooEarly", resetTo = resetTo }
    end
    knox.phalanxUses = (knox.phalanxUses or 0) + 1
    p.stats:ceilingF("ZOMBIE_INFECTION", "phalanx", resetTo)
    p.stats:ceilingF("ZOMBIE_FEVER", "phalanx", resetTo)
    p.body:cureKnox("phalanx", resetTo)
    knox.effects.phalanxNausea = Data.PHALANX_NAUSEA_MINUTES
    knox.effects.phalanxFever = Data.PHALANX_FEVER_MINUTES
    knox.effects.phalanxDebuff = Data.PHALANX_DEBUFF_MINUTES
    p.dirty("knox")
    p.say(PHALANX_LINES[knox.phalanxUses])
    return { consume = 1, outcome = "reset", resetTo = resetTo }
end

return Items
