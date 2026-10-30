-- Taking a dose, and dose courses: the one set of rules for every medication, whichever way it is taken (our
-- inventory action, a vanilla pill or eat action, or given by another player). Pure: the server adapter
-- (Server/Medication) looks up items and supplies, then consumes what the outcome says.
--
-- State, state.meds (Core/Schema):
--   doses[medId]   = { since = minutes since the last dose }
--   courses[medId] = { count = doses that counted, elapsed = minutes since the first dose, cured = { [id] = true } }
--   effects, side, overdose, pairs   (Medication/Effects, SideEffects, Overdose, Interactions)
--   xpCooldown[medId] = minutes until taking it gives First Aid XP again
--
-- Rules:
--   * A course (doses > 1) counts a dose once 90 % of its interval has passed since the last one (Data.DUE_SHARE).
--     An earlier dose is wasted (consumed, no effect); on the overdose list it also overdoses. Some drugs refuse a
--     dose while the last one is active instead (med.early = "refuse"); a dose a vanilla action already consumed
--     can't be refused, so it is wasted.
--   * A course cures once every dose is taken and its cure time has passed since the first dose; a single-dose cure
--     cures that long after the dose. Meanwhile the condition holds its stage (p.treatment:curing, Conditions/Engine).
--   * A course whose next dose is more than max(24, min(72, 3 x interval)) hours overdue is abandoned.
--   * While a cure is running with every dose taken, more doses of that drug are refused ("already working").
--   * A drug registered with course = true (add-on supplements) runs as a course without curing anything: the course
--     ends once every dose is in. Doses.onDose listeners hear every dose that counted.

local Data = require "ExtensiveHealthRedone/Medication/Data"
local Effects = require "ExtensiveHealthRedone/Medication/Effects"
local SideEffects = require "ExtensiveHealthRedone/Medication/SideEffects"
local Overdose = require "ExtensiveHealthRedone/Medication/Overdose"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Infection = require "ExtensiveHealthRedone/Wounds/Infection"
local Addiction = require "ExtensiveHealthRedone/Diseases/Mind/Addiction"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Doses = {}

local doseListeners = {}

-- fn(p, med, outcome) after a dose was taken (outcome.result == "taken"), inside the same step: an add-on reacts to
-- its own medications here (a supplement refilling a reserve). Listeners run in registration order.
function Doses.onDose(fn)
    doseListeners[#doseListeners + 1] = fn
end

local function taken(p, med, outcome)
    for _, fn in ipairs(doseListeners) do
        fn(p, med, outcome)
    end
    return outcome
end

Doses.XP_COOLDOWN = 30          -- minutes; at least the medication's interval

local function minutes(hours)
    return (hours or 0) * 60
end

-- Is this condition active? woundInfection is per body part (state.wounds).
function Doses.conditionActive(state, id)
    if id == "woundInfection" then
        for _, e in pairs(state.wounds.parts) do
            if e.phase == "infected" then
                return true
            end
        end
        return false
    end
    return state.conditions.active[id] ~= nil
end

function Doses.dose(state, med)
    return state.meds.doses[med.id]
end

function Doses.course(state, med)
    return state.meds.courses[med.id]
end

-- The last dose is still working.
function Doses.isActive(state, med)
    local d = state.meds.doses[med.id]
    return d ~= nil and d.since < minutes(med.active)
end

-- A course is running and has every dose it needs (only its cure time is left).
local function fullyDosed(state, med)
    local c = state.meds.courses[med.id]
    return c ~= nil and c.count >= med.doses
end

-- Minutes until the next course dose counts (0 = it counts now); nil when the drug isn't on a course.
function Doses.nextDoseIn(state, med)
    if not Data.isCourse(med) then
        return nil
    end
    local c = state.meds.courses[med.id]
    local d = state.meds.doses[med.id]
    if not c or not d or c.count >= med.doses then
        return nil
    end
    return math.max(0, minutes(med.interval) * Data.DUE_SHARE - d.since)
end

-- A course dose now would be early (before 90 % of the interval).
local function earlyCourseDose(state, med)
    local wait = Doses.nextDoseIn(state, med)
    return wait ~= nil and wait > 0
end

-- Why a dose would be refused now, or nil. ctx: { supplies = { syringe = bool, ivKit = bool }, wound = bool,
-- sandbox = function(name, default) }. A missing ctx field counts as present (the server checks supplies itself).
function Doses.refusal(state, med, ctx)
    ctx = ctx or {}
    if med.option and ctx.sandbox and ctx.sandbox(med.option, true) == false then
        return "UI_EHR_MedReason_TemperatureDisabled"
    end
    if med.needs and not Doses.conditionActive(state, med.needs) then
        return "UI_EHR_Med_NothingToTreat"
    end
    if med.needsWound and ctx.wound == false then
        return "UI_EHR_MedReason_RequiresActiveWound"
    end
    if Data.curesAnything(med) and fullyDosed(state, med) then
        return "UI_EHR_Med_AlreadyWorking"
    end
    if med.early == "refuse" and Doses.isActive(state, med) and (not Data.isCourse(med) or earlyCourseDose(state, med)) then
        return med.earlyLine or "UI_EHR_MedReason_DoseActive"
    end
    local supplies = ctx.supplies or {}
    if med.supply == "ivKit" and supplies.ivKit == false then
        return "UI_EHR_MedReason_RequiresIVKit"
    elseif med.supply == "syringe" and supplies.syringe == false then
        return "UI_EHR_MedReason_RequiresSyringe"
    end
    return nil
end

-- A dose taken now would be wasted (consumed for nothing), or nil.
function Doses.wasteReason(state, med)
    if earlyCourseDose(state, med) then
        return med.earlyLine or "UI_EHR_Med_DoseWasted"
    end
    -- Course drugs follow the course rule above only; this is for teas taken again while the last one works.
    if med.early == "waste" and not Data.isCourse(med) and Doses.isActive(state, med) then
        return med.earlyLine or "UI_EHR_Med_DoseWasted"
    end
    return nil
end

local function wasted(p, med, line)
    p.say(line)
    local share
    if med.overdose and earlyCourseDose(p.state, med) then
        -- How early, as a share of the whole interval.
        local since = p.state.meds.doses[med.id].since
        share = math.max(0, minutes(med.interval) - since) / math.max(1, minutes(med.interval))
    end
    if share then
        Overdose.apply(p, share)
    end
    return { result = "wasted", consume = true, supply = false, reason = line, xp = {} }
end

local function anyTargetActive(state, med)
    for _, id in ipairs(med.targets) do
        if Doses.conditionActive(state, id) then
            return true
        end
    end
    return false
end

-- Takes one dose of med. opts: { consumed = true (a vanilla action already used the item), ctx = refusal ctx }.
-- Returns { result = "refused" | "wasted" | "taken", reason = key, consume = bool (use one of the item),
-- supply = bool (use one syringe or IV kit), xp = { kinds } (First Aid XP for whoever gave it) }.
function Doses.take(p, defs, med, opts)
    opts = opts or {}
    local state = p.state
    local meds = state.meds
    local refusal = Doses.refusal(state, med, opts.ctx)
    if refusal then
        if not opts.consumed then
            return { result = "refused", consume = false, supply = false, reason = refusal, xp = {} }
        end
        return wasted(p, med, refusal)
    end
    local waste = Doses.wasteReason(state, med)
    if waste then
        return wasted(p, med, waste)
    end

    if med.line and not med.silent then
        p.say(med.line)
    end
    local treated = anyTargetActive(state, med)
    meds.doses[med.id] = { since = 0 }
    if Data.tracksCourse(med) then
        local c = meds.courses[med.id]
        if c then
            c.count = c.count + 1
        else
            meds.courses[med.id] = { count = 1, elapsed = 0, cured = {} }
        end
    end
    for stat, amount in pairs(med.now or {}) do
        p.stats:addF(stat, "med:" .. med.id, amount)
    end
    for _, spec in ipairs(med.effects or {}) do
        Effects.start(p, defs, spec)
    end
    for _, id in ipairs(med.side or {}) do
        SideEffects.start(p, id)
    end
    if med.woundStep and Infection.antibiotics(p) > 0 then
        treated = true
    end
    if med.addiction then
        Addiction.recordDose(p, defs, med.fullType)
    end
    p.dirty("meds")

    local xp = {}
    if med.silent then
        return taken(p, med, { result = "taken", consume = true, supply = false, xp = xp })
    end
    if (meds.xpCooldown[med.id] or 0) <= 0 then
        xp[#xp + 1] = "take"
        meds.xpCooldown[med.id] = math.max(Doses.XP_COOLDOWN, minutes(med.interval))
    end
    if treated then
        xp[#xp + 1] = "treat"
    end
    return taken(p, med, { result = "taken", consume = true, supply = med.supply ~= nil, xp = xp })
end

local function cure(p, defs, id)
    if id == "woundInfection" then
        if Doses.conditionActive(p.state, id) then
            Infection.cureAll(p)
            if p.xp then
                p.xp("cure", id)
            end
            return true
        end
        return false
    end
    return Engine.cure(p, defs, id, "cured")
end

-- Advances doses and courses by dt minutes: cures what is due, abandons courses that went too long without a dose,
-- forgets old doses.
function Doses.update(p, defs, dt)
    local meds = p.state.meds
    for _, id in ipairs(Tables.sortedKeys(meds.xpCooldown)) do
        local left = meds.xpCooldown[id] - dt
        meds.xpCooldown[id] = left > 0 and left or nil
    end
    for _, id in ipairs(Tables.sortedKeys(meds.doses)) do
        meds.doses[id].since = meds.doses[id].since + dt
    end
    for _, id in ipairs(Tables.sortedKeys(meds.courses)) do
        local c = meds.courses[id]
        local med = Data.byId[id]
        local d = meds.doses[id]
        if not med then
            meds.courses[id] = nil
        else
            c.elapsed = c.elapsed + dt
            local finished = true
            local curedAny = false
            if c.count >= med.doses then
                for _, cond in ipairs(Tables.sortedKeys(med.cures or {})) do
                    if not c.cured[cond] then
                        if c.elapsed >= minutes(med.cures[cond]) then
                            c.cured[cond] = true
                            p.dirty("meds")
                            if cure(p, defs, cond) then
                                curedAny = true
                            end
                        else
                            finished = false
                        end
                    end
                end
            else
                finished = false
                if d and d.since > minutes(med.interval + Data.abandonHours(med.interval)) then
                    finished = true
                end
            end
            if curedAny then
                p.say("UI_EHR_Med_CourseCured")
            end
            if finished then
                meds.courses[id] = nil
            end
            if curedAny or finished then
                p.dirty("meds")
            end
        end
    end
    for _, id in ipairs(Tables.sortedKeys(meds.doses)) do
        local med = Data.byId[id]
        local d = meds.doses[id]
        if not med or (not meds.courses[id] and d.since > math.max(minutes(med.active), minutes(med.interval))) then
            meds.doses[id] = nil
            p.dirty("meds")
        end
    end
end

-- Conditions a running course or single-dose cure is curing: { [conditionId] = true }.
function Doses.curing(state)
    local set = {}
    for id, c in pairs(state.meds.courses) do
        local med = Data.byId[id]
        if med then
            for cond in pairs(med.cures or {}) do

                if not c.cured[cond] then
                    set[cond] = true
                end
            end
        end
    end
    return set
end

return Doses
