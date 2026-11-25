-- Concussion: from a bad fall or a vehicle crash that really hurt. It starts at stage 3 and improves to 2, then 1,
-- then clears (16 h each, scaled by DiseaseSpeed). Symptoms: nausea, headache, dizzy spells with blurred vision, and a
-- temporary health cap that eases with each stage (health is pulled down to 50, then may recover to 75 and 90).
-- No medicine cures it; relief medication softens it.
--
-- Detection starts from vanilla's own damage event (OnPlayerGetDamage, "FALLDOWN" or "CARCRASHDAMAGE") and nothing
-- else: stairs, a teleport or braking never look like a fall. The event opens a short window in which the server
-- compares the body with how it was just before, and only then rolls.
--   - The authority hears the event itself (Server/Corpse): in single player, and on a dedicated server, where
--     B42 raises a fall's event on the server and never on the client (tests/e2e/EHRConcussionE2E). It knows
--     the kind and the damage; a fall under MIN_DAMAGE is a stumble and opens nothing.
--   - An MP client that gets the event itself reports it (Client/Concussion -> concussion.trauma). Its word only
--     opens the window: the kind is the server's (in a vehicle now or at the last step means a crash, otherwise a
--     fall), and the body has to show the trauma.
-- Trauma: a new fracture, health lost on BROAD_PARTS body parts at once (vanilla's fall damage is spread over the
-- whole body and takes least from the head: 0.6 there for a two-floor fall), head pain or head damage, a severe
-- new wound, or a new wound with health lost.
-- What the mod itself did to the body is never trauma: Concussion.rebase moves the kept body samples along with
-- every write of the body writer (disease drains, tracked pain, an overdose).
-- The samples are for this session only: the first step after a player is attached (a login, a new character, a
-- loaded save) drops what was saved and only records.
-- Honours DiseaseSpeed and DiseaseEnabled.
--
-- Treatment: no cure. Relief read: "nausea", "sickness", "pain", "inflammation", "dizziness".

local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Episodes = require "ExtensiveHealthRedone/Diseases/Corpse/Episodes"

local ID = "concussion"

local Concussion = {}

Concussion.CHANCE = { fall = 0.65, crash = 0.45 }
Concussion.MULTIPLIER = { fall = "ConcussionFallChanceMultiplier", crash = "ConcussionVehicleChanceMultiplier" }
Concussion.WINDOW = { fall = 2, crash = 4 }     -- game minutes to see the trauma
Concussion.HISTORY = 2                          -- body samples kept (one per step) to compare against
Concussion.COOLDOWN_FAILED = 1.2                -- game minutes after a failed roll
Concussion.COOLDOWN_STARTED = 15                -- game minutes after a concussion started
-- The least damage vanilla's event must carry to open a window, where the authority hears it. Measured on 42.21:
-- a one-floor drop deals 0 to 3, two floors 7, three floors 13.
Concussion.MIN_DAMAGE = { fall = 5 }
-- Broad trauma: this many parts lost at least PART_LOSS health each. A two-floor fall does that to 13 parts, a
-- one-floor fall to the hands at most; a zombie hits one part at a time.
Concussion.BROAD_PARTS = 4
Concussion.PART_LOSS = 1

-- Wound score per part flag; severe ones also count separately.
local WOUNDS = { bleeding = 2, scratch = 1, cut = 2, burn = 2, bite = 4, deep = 4, glass = 3, bullet = 4 }
local SEVERE = { bite = true, deep = true, glass = true, bullet = true }

-- Trauma thresholds.
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
        every = 384,        -- about 1 in 16 every 1800 frames
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

-- A body sample for the trauma check: head pain, each part's health, wound scores and the number of fractures, and
-- whether the player was in a vehicle (for the kind of a client's report).
function Concussion.snapshot(facts)
    local s = { headPain = 0, health = {}, wounds = 0, severe = 0, fractures = 0, inVehicle = facts.inVehicle == true }
    local trauma = facts.trauma or {}
    s.headPain = trauma.headPain or 0
    for name, f in pairs(facts.parts) do
        s.health[name] = f.health or 100
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
            s.fractures = s.fractures + 1
        end
    end
    return s
end

local function data(p)
    local d = p.state.exposure.data
    d.concussion = d.concussion or { history = {} }
    return d.concussion
end

-- Samples and an open window from before the player was attached say nothing about now (another session, another
-- place, a body the server had not loaded yet): dropped. The cooldown stays.
local function forget(d)
    d.history = {}
    d.pending = nil
end

-- Whether the body shows real trauma since `before`.
function Concussion.traumatic(kind, before, now)
    local partLoss, broad = 0, 0
    for name, health in pairs(now.health) do
        local loss = (before.health[name] or health) - health
        partLoss = partLoss + loss
        if loss >= Concussion.PART_LOSS then
            broad = broad + 1
        end
    end
    local rule = TRAUMA[kind]
    local headPainGain = now.headPain - before.headPain
    local headLoss = (before.health.Head or 100) - (now.health.Head or 100)
    local woundGain = now.wounds - before.wounds
    local severeGain = now.severe - before.severe
    return broad >= Concussion.BROAD_PARTS or headPainGain >= rule.headPain or headLoss >= 1 or severeGain > 0
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

-- Vanilla dealt fall or crash damage: open a window to look for trauma, against the oldest kept sample (the damage
-- may already be in the newest).
--   seen: { kind = "fall" | "crash", damage = n } when the authority heard the event itself; a fall under
--         MIN_DAMAGE opens nothing. nil for a client's report: the kind is then the server's (Concussion.kind).
-- Before the first step after attaching there is nothing to compare with: the event is dropped.
-- Returns whether a window opened, and the kind used.
function Concussion.report(p, defs, seen)
    local d = data(p)
    if p.fresh then
        forget(d)
    end
    local kind = seen and seen.kind or Concussion.kind(p)
    local least = seen and Concussion.MIN_DAMAGE[kind]
    if p.fresh or (least and (seen.damage or 0) < least) then
        return false, kind
    end
    if p.state.conditions.active[ID] or (d.cooldown or 0) > 0 or d.pending then
        return false, kind
    end
    d.pending = { kind = kind, before = d.history[1] or Concussion.snapshot(p.facts), left = Concussion.WINDOW[kind] }
    Concussion.check(p, defs, 0)
    return true, kind
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

-- The body writer changed the body for us (Server/Runtime.onBodyWrite, steps and one-off effects alike):
-- wrote = { health = { [part] = change }, pain = { [part] = change } }. The kept samples move along, so our own
-- drains, healing caps and pain never read as trauma, and never hide it either.
function Concussion.rebase(p, wrote)
    local d = data(p)
    local samples = { d.pending and d.pending.before }
    for _, s in ipairs(d.history) do
        samples[#samples + 1] = s
    end
    local seen = {}
    for _, s in pairs(samples) do
        -- A sample saved by an older version has no part table; the first step drops it. The window's sample is
        -- one of the history's until that one is pushed out: moved once.
        if s.health and not seen[s] then
            seen[s] = true
            for name, change in pairs(wrote.health or {}) do
                if s.health[name] then
                    s.health[name] = s.health[name] + change
                end
            end
            s.headPain = s.headPain + ((wrote.pain or {}).Head or 0)
        end
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
    if p.fresh then
        forget(d)
    else
        Concussion.check(p, defs, dt)
    end
    -- Remember the body as it was this step; a window compares against the oldest kept sample.
    table.insert(d.history, Concussion.snapshot(p.facts))
    while #d.history > Concussion.HISTORY do
        table.remove(d.history, 1)
    end
end

Concussion.system = { name = "concussionTrauma", order = 320, update = Concussion.update }

return Concussion
