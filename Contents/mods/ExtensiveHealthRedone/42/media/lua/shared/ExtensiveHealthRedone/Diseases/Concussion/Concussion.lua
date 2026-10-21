-- Concussion: from a bad fall or a vehicle crash that really hurt. It starts at stage 3 and improves to 2, then 1,
-- then clears (16 h each, scaled by DiseaseSpeed). Symptoms: nausea, headache, dizzy spells with blurred vision, and a
-- temporary health cap that eases with each stage (health is pulled down to 50, then may recover to 75 and 90).
-- No medicine cures it; relief medication softens it.
--
-- Detection: a short window in which the server compares the body with how it was just before (head pain or head
-- damage, new wounds, health lost) and only then rolls. Two things open it:
--   - the server's own facts (Phase 9, SA-4): a drop of at least FALL_Z_DROP floors since the last step outside a
--     vehicle (a fall), or a loss of at least CRASH_SPEED_LOSS km/h since the last step in a vehicle (a crash);
--   - the owning client's report (OnPlayerGetDamage fires for local players only; Client/Concussion ->
--     concussion.trauma), which only speeds things up. The kind is the server's: in a vehicle now or at the last step
--     means a crash, otherwise a fall; the client's word is ignored.
-- A report can at worst ask for a roll the body already justifies, and withholding it no longer avoids the roll.
-- From v0.9 EHR_Concussion.lua and EHR_Disease.lua:3811-3906 (docs/porting/phase4/corpse-scabies-concussion.md,
-- section 4). Changes: honours DiseaseSpeed and DiseaseEnabled; detection from vanilla's damage events instead of
-- polling the character's height and vehicle speed.
--
-- Treatment (Phase 5): no cure. Relief read: "nausea", "sickness", "pain", "inflammation", "dizziness".

local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Episodes = require "ExtensiveHealthRedone/Diseases/Corpse/Episodes"

local ID = "concussion"

local Concussion = {}

Concussion.CHANCE = { fall = 0.65, crash = 0.45 }
Concussion.MULTIPLIER = { fall = "ConcussionFallChanceMultiplier", crash = "ConcussionVehicleChanceMultiplier" }
Concussion.WINDOW = { fall = 2, crash = 4 }     -- game minutes to see the trauma (ours; v0.9 0.02 h and 0.06 h)
Concussion.HISTORY = 3                          -- body snapshots kept (one per step) to compare against
Concussion.COOLDOWN_FAILED = 1.2                -- game minutes after a failed roll (v0.9 0.02 h)
Concussion.COOLDOWN_STARTED = 15                -- game minutes after a concussion started (v0.9 0.25 h)
-- Server-side causes (ours, Phase 9). Stairs or a slow stop also match, but open only a window: the roll still
-- needs the trauma pattern on the body.
Concussion.FALL_Z_DROP = 0.9                    -- floors lost between two steps
Concussion.CRASH_SPEED_LOSS = 20                -- km/h lost between two steps while in a vehicle

-- Wound score per part flag (v0.9 getBodySnapshot); severe ones also count separately.
local WOUNDS = { bleeding = 2, scratch = 1, cut = 2, burn = 2, bite = 4, deep = 4, glass = 3, bullet = 4 }
local SEVERE = { bite = true, deep = true, glass = true, bullet = true }

-- Trauma thresholds (v0.9 isTraumaticInjury).
local TRAUMA = {
    fall = { headPain = 5, partLoss = nil },
    crash = { headPain = 2.5, partLoss = 6 },
}

local ROWS = {
    [3] = { nausea = 0.68, head = 54, dizzy = 0.0110, dizzyCooldown = 0.28, floor = 50, hp = { 0.55, 0.70 },
            every = 0.15 },
    [2] = { nausea = 0.38, head = 32, dizzy = 0.0050, dizzyCooldown = 0.55, floor = 75, hp = { 0.30, 0.35 },
            every = 0.25 },
    [1] = { nausea = 0.12, head = 14, dizzy = 0.0012, dizzyCooldown = 1.15, floor = 90, hp = { 0.18, 0.20 },
            every = 0.42 },
}

Concussion.def = {
    enabledOption = "ConcussionEnabled", speedOption = "DiseaseSpeed",
    stages = { [3] = { 16, 16 }, [2] = { 16, 16 }, [1] = { 16, 16 } },
    startStage = 3, reverse = true,
    baseSeverity = 0.65,
    knowledge = "concussion", selfEvident = true,
    name = "UI_EHR_Disease_concussion",
    lines = {
        stage = {
            [3] = "UI_EHR_Text_MyHeadSomethingIsWrong",
            [2] = "UI_EHR_Text_TheWorstOfItIsFadingButMyHeadStillHurts",
            [1] = "UI_EHR_Text_TheFogIsLiftingStillNeedToTakeItEasy",
        },
        random = {
            [3] = { "UI_EHR_Text_MyHeadIsPounding", "UI_EHR_Text_EverythingKeepsSpinning",
                    "UI_EHR_Text_IFeelLikeImGoingToThrowUp", "UI_EHR_Text_CantFocusNeedToRest" },
            [2] = { "UI_EHR_Text_StillDizzy", "UI_EHR_Text_MyHeadHurtsButNotAsBad", "UI_EHR_Text_NeedToMoveCarefully" },
            [1] = { "UI_EHR_Text_JustALittleHeadacheNow", "UI_EHR_Text_AlmostSteadyAgain",
                    "UI_EHR_Text_TheNauseaIsMostlyGone" },
        },
        every = 384,        -- v0.9: 1 in 10/16/28 every 1800 frames; the middle one
    },
}

-- An improving stage lets health recover to the new, higher floor.
function Concussion.def.onStage(p, c, stage)
    local row = ROWS[stage]
    if row then
        c.data.raise = row.floor
    end
end

function Concussion.def.effects(p, c, dt)
    Episodes.tick(c, dt)
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local t = p.treatment
    local sev = c.severity
    local sevF = math.max(0.70, sev)
    local k = Symptoms.TICK * dt
    local nausea = math.max(0.32, 1 - 0.90 * math.max(t:relief(ID, "nausea"), t:relief(ID, "sickness")))
    local pain = math.max(0.30, 1 - 1.10 * math.max(t:relief(ID, "pain"), 0.65 * t:relief(ID, "inflammation")))
    local dizziness = math.max(0.22, 1 - 1.25 * t:relief(ID, "dizziness"))

    p.stats:raiseF("SICKNESS", ID, math.min(0.65, row.nausea * nausea * sevF), 0.004 * k)
    p.body:pain("Head", ID, row.head * pain * sevF)
    if Episodes.try(p, c, "dizzy", row.dizzy * sev * dizziness, row.dizzyCooldown, dt) then
        Episodes.dizzy(p, c)
    end
    Episodes.blur(p, c, ID, dt)
    local hp = (row.hp[1] + row.hp[2] * sev) * 0.65
    Episodes.healthCap(p, c, ID, row.floor, hp / (row.every * 60), dt, c.data.raise)
    c.data.raise = nil
end

-- Detection ----------------------------------------------------------------------------------------------------------

-- What the trauma check compares: head pain and health, total part health, and wound scores; plus where the
-- player was (height z, in a vehicle, vehicle speed in km/h) for the server-side causes. z and speed are nil when
-- the facts don't have them.
function Concussion.snapshot(facts)
    local s = { headPain = 0, headHealth = 100, partHealth = 0, wounds = 0, severe = 0 }
    local trauma = facts.trauma or {}
    s.headPain = trauma.headPain or 0
    s.z, s.speed, s.inVehicle = trauma.z, trauma.speed, facts.inVehicle == true
    for name, f in pairs(facts.parts) do
        s.partHealth = s.partHealth + (f.health or 100)
        if name == "Head" then
            s.headHealth = f.health or 100
        end
        for flag, score in pairs(WOUNDS) do
            if f[flag] then
                s.wounds = s.wounds + score
                if SEVERE[flag] then
                    s.severe = s.severe + 1
                end
            end
        end
        if trauma.fractures and trauma.fractures[name] then
            s.wounds = s.wounds + 4
            s.severe = s.severe + 1
        end
    end
    return s
end

local function data(p)
    local d = p.state.exposure.data
    d.concussion = d.concussion or { history = {} }
    return d.concussion
end

-- Whether the body shows real trauma since `before` (v0.9 isTraumaticInjury).
function Concussion.traumatic(kind, before, now)
    local rule = TRAUMA[kind]
    local headPainGain = now.headPain - before.headPain
    local headLoss = before.headHealth - now.headHealth
    local partLoss = before.partHealth - now.partHealth
    local woundGain = now.wounds - before.wounds
    local severeGain = now.severe - before.severe
    return headPainGain >= rule.headPain or headLoss >= 1 or severeGain > 0
        or (rule.partLoss ~= nil and partLoss >= rule.partLoss)
        or (woundGain > 0 and partLoss >= 1)
end

-- The kind of trauma by the server's facts: in a vehicle now or at the last step -> "crash", else "fall".
function Concussion.kind(p)
    local history = data(p).history
    local last = history[#history]
    if p.facts.inVehicle or (last ~= nil and last.inVehicle) then
        return "crash"
    end
    return "fall"
end

-- A cause the server sees itself, from the kept snapshots (oldest first) and now: "crash" for a speed loss since the
-- last step in a vehicle, "fall" for a drop from the highest kept height outside one (a fall can span two steps), or
-- nil.
function Concussion.cause(history, now)
    local last = history[#history]
    if not last then
        return nil
    end
    if (now.inVehicle or last.inVehicle) and last.speed and now.speed
        and last.speed - now.speed >= Concussion.CRASH_SPEED_LOSS then
        return "crash"
    end
    if now.inVehicle or last.inVehicle or not now.z then
        return nil
    end
    for _, s in ipairs(history) do
        if s.z and not s.inVehicle and s.z - now.z >= Concussion.FALL_Z_DROP then
            return "fall"
        end
    end
    return nil
end

local function open(p, defs, kind)
    local d = data(p)
    if p.state.conditions.active[ID] or (d.cooldown or 0) > 0 or d.pending then
        return false
    end
    d.pending = { kind = kind, before = d.history[1] or Concussion.snapshot(p.facts), left = Concussion.WINDOW[kind] }
    Concussion.check(p, defs, 0)
    return true
end

-- The client reported fall or crash damage: open a window to look for trauma. The kind is the server's
-- (Concussion.kind), not the client's. Returns whether a window opened, and the kind used.
function Concussion.report(p, defs)
    local kind = Concussion.kind(p)
    return open(p, defs, kind), kind
end

-- Looks at an open window: trauma found -> roll; window over -> forget it.
function Concussion.check(p, defs, dt)
    local d = data(p)
    local pending = d.pending
    if not pending then
        return
    end
    if Concussion.traumatic(pending.kind, pending.before, Concussion.snapshot(p.facts)) then
        d.pending = nil
        local mult = math.max(0, math.min(5, tonumber(p.sandbox(Concussion.MULTIPLIER[pending.kind], 1)) or 1))
        local chance = math.min(1, Concussion.CHANCE[pending.kind] * mult)
        if Chance.roll(p.rng, chance) and Engine.contract(p, defs, ID, { source = pending.kind }) then
            d.cooldown = Concussion.COOLDOWN_STARTED
            Speech.stage(p, Concussion.def.lines.stage[3])
        else
            d.cooldown = Concussion.COOLDOWN_FAILED
        end
        return
    end
    pending.left = pending.left - dt
    if pending.left <= 0 then
        d.pending = nil
    end
end

function Concussion.update(p, dt, defs)
    local d = data(p)
    if d.cooldown then
        d.cooldown = d.cooldown - dt
        if d.cooldown <= 0 then
            d.cooldown = nil
        end
    end
    Concussion.check(p, defs, dt)
    local now = Concussion.snapshot(p.facts)
    -- No report needed: a fall or crash the server sees itself opens the window too.
    local cause = Concussion.cause(d.history, now)
    if cause then
        open(p, defs, cause)
    end
    -- Remember the body as it was this step; a window compares against the oldest kept snapshot.
    table.insert(d.history, now)
    while #d.history > Concussion.HISTORY do
        table.remove(d.history, 1)
    end
end

Concussion.system = { name = "concussionTrauma", order = 320, update = Concussion.update }

return Concussion
