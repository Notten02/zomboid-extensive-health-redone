-- The disease engine: contracting, advancing, holding and ending staged conditions (diseases, sepsis, AHTR, ...).
--
-- A condition in state.conditions.active[id]:
--   { stage = 1..4, left = minutes left in this stage, len = { [stage] = minutes }, duration = minutes of stages 2-4,
--     extra = minutes added to stage 3 (AHTR worsening), severity, source, data = {} (per-condition scratch) }
-- Everything is a remaining time, so nothing moves while a player is offline.
--
-- A definition (Data/Conditions merged with the condition's behaviour module, see Conditions/Registry) may have:
--   Switches   enabledOption, speedOption (default none), master = false (DiseaseEnabled doesn't apply)
--   Timing     incubation = { minH, maxH } and duration = { minH, maxH }: stage 1 is the incubation, then the duration
--              is split 40/30/30 % over stages 2-4 (or def.split). Or stages = { [s] = { minH, maxH } } for explicit
--              stage lengths. startStage (default 1), reverse (counts down: 3 -> 2 -> 1 -> recovered),
--              persistsAt = stage that never ends untreated, hold(p, c) -> true keeps the current stage from ending
--              (heat stroke until cooled), rate(p, c) -> multiplier on elapsed time (fresh air shortens corpse illness),
--              driven = true with drive(p, c, dt) -> a stage, "recovered" or nil: no timers, the module sets the stage
--              (hypothermia follows body temperature)
--   Speech     lines = { stage = { [s] = key }, random = { [s] = { keys } }, every = mean game minutes between random
--              lines at DialogueFrequency Normal (or { [s] = minutes } by stage), quiet(p, c) -> true mutes random
--              lines }
--   Chains     complications = { { stage = s, id = other, chance = 0..1, risk = true (immunity-modified),
--              untreated = true (only without a curative course), replace = true (this condition ends) } }
--   Behaviour  onStage(p, c, stage, defs), effects(p, c, dt, curing, defs), effectsInStage1,
--              onEnd(p, c, reason, defs): the one cleanup path for every way a condition ends ("recovered", "cured",
--              "complication", "admin", "debug"), blockAfterCureHours
--   Knowledge  knowledge = knowledge id, selfEvident, strand = a registered knowledge strand (Conditions/Knowledge)
--   Elsewhere  alert = false (no Medical Alert moodle), pressure = false | "half" (immune pressure), display (how an
--              add-on condition is shown); see Conditions/Registration

--   Display    severityHidden = true: the monitor shows no severity word (its symptoms don't scale with severity)
--   XP         xp = false: ending it gives no First Aid XP (p.xp("cure", id) otherwise)
--
-- Treatment: while p.treatment:curing(id), a condition holds its stage (the course cures it when it completes).
-- Untreated, it advances; at the end of its last stage it recovers, unless it persists or is held.

local Tables = require "ExtensiveHealthRedone/Core/Tables"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Timers = require "ExtensiveHealthRedone/Core/Timers"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Risk = require "ExtensiveHealthRedone/Conditions/Risk"
local Pace = require "ExtensiveHealthRedone/Lifestyle/Pace"

local Engine = {}

Engine.SPLIT = { [2] = 0.4, [3] = 0.3, [4] = 0.3 }

local function speed(p, def)
    local value = def.speedOption and tonumber(p.sandbox(def.speedOption, 1)) or 1
    if not value or value <= 0 then
        value = 1
    end
    return value
end

function Engine.enabled(p, def)
    if def.master ~= false and p.sandbox("DiseaseEnabled", true) == false then
        return false
    end
    return not def.enabledOption or p.sandbox(def.enabledOption, true) ~= false
end

-- Minutes of a stage for a condition.
function Engine.stageMinutes(c, stage)
    local minutes
    if c.len then
        minutes = c.len[stage] or 0
    else
        minutes = c.duration * (Engine.SPLIT[stage] or 0)
    end
    if stage == 3 then
        minutes = minutes + (c.extra or 0)
    end
    return minutes
end

local function lastStage(def)
    return def.reverse and 1 or 4
end

local function nextStage(def, stage)
    return def.reverse and stage - 1 or stage + 1
end

-- Minutes until the condition ends from now (the remaining stages), for "at least N hours left" rules.
function Engine.minutesLeft(c, def)
    local total = c.left
    local stage = c.stage
    while stage ~= lastStage(def or {}) do
        stage = nextStage(def or {}, stage)
        total = total + Engine.stageMinutes(c, stage)
    end
    return total
end

function Engine.isBlocked(state, id)
    return Timers.running(state.conditions.timers, id .. "Block")
end

local function rollLengths(p, def, s)
    local len = {}
    if def.stages then
        for stage, range in pairs(def.stages) do
            len[stage] = Chance.between(p.rng, range[1], range[2]) * 60 / s
        end
        return len, 0
    end
    local split = def.split or Engine.SPLIT
    len[1] = def.incubation and Chance.between(p.rng, def.incubation[1], def.incubation[2]) * 60 / s or 0
    local duration = def.duration and Chance.between(p.rng, def.duration[1], def.duration[2]) * 60 / s or 0
    for stage = 2, 4 do
        len[stage] = duration * split[stage]
    end
    return len, duration
end

-- Starts a condition. Returns the new condition, or nil and why not: "disabled", "active", "blocked".
-- opts: { severity = n (overrides the roll), source = string, stage = n (start at another stage) }
function Engine.contract(p, defs, id, opts)
    local def = defs[id]
    if not def then
        error("unknown condition " .. tostring(id), 2)
    end
    opts = opts or {}
    local conditions = p.state.conditions
    if not Engine.enabled(p, def) then
        return nil, "disabled"
    end
    if conditions.active[id] then
        return nil, "active"
    end
    if Engine.isBlocked(p.state, id) then
        return nil, "blocked"
    end
    local len, duration = rollLengths(p, def, speed(p, def))
    local c = {
        stage = opts.stage or def.startStage or 1,
        len = len,
        duration = duration,
        extra = 0,
        severity = opts.severity or ((def.baseSeverity or 1) + Chance.between(p.rng, -0.15, 0.15)),
        source = opts.source,
        data = {},
    }
    c.left = Engine.stageMinutes(c, c.stage)
    conditions.active[id] = c
    p.dirty("conditions")
    return c
end

-- Ends a condition through the one cleanup path: onEnd, removal, and the block on catching it again.
-- reason: "recovered", "cured" (the default), "complication", "admin" (an admin's full heal, Admin/FullHeal: no XP,
-- but the normal re-catch block) or "debug" (no XP, no block). Returns true when it was active.
function Engine.finish(p, defs, id, reason)
    local conditions = p.state.conditions
    local c = conditions.active[id]
    if not c then
        return false
    end
    reason = reason or "cured"
    conditions.active[id] = nil
    local def = defs[id]
    if def and def.onEnd then
        def.onEnd(p, c, reason, defs)
    end
    -- First Aid XP for getting over it, by medicine or naturally.
    if p.xp and (reason == "cured" or reason == "recovered") and not (def and def.xp == false) then
        p.xp("cure", id)
    end
    if def and def.blockAfterCureHours and reason ~= "debug" then
        Timers.start(conditions.timers, id .. "Block", def.blockAfterCureHours * 60)
    end
    p.dirty("conditions")
    return true
end

-- A cure (medication course, cold bath, debug heal). Same cleanup as natural recovery.
function Engine.cure(p, defs, id, reason)
    return Engine.finish(p, defs, id, reason or "cured")
end

-- Moves a condition to a stage now (driven conditions, debug). Runs the stage entry like natural progression.
function Engine.setStage(p, defs, id, stage)
    local c = p.state.conditions.active[id]
    if not c or c.stage == stage then
        return
    end
    c.stage = stage
    c.left = Engine.stageMinutes(c, stage)
    p.dirty("conditions")
    Engine.enterStage(p, defs, id, c, stage)
end

local function complications(p, defs, id, c, stage)
    local def = defs[id]
    for _, rule in ipairs(def.complications or {}) do
        if rule.stage == stage and p.state.conditions.active[id] == c
            and not (rule.untreated and p.treatment:curing(id)) then
            local chance = rule.chance or 1
            if rule.risk then
                chance = Risk.chance(p, rule.id, chance)
            end
            if Chance.roll(p.rng, chance) and Engine.contract(p, defs, rule.id, { source = id }) and rule.replace then
                Engine.finish(p, defs, id, "complication")
            end
        end
    end
end

-- Stage entry: the stage line, the module's onStage, then complications.
function Engine.enterStage(p, defs, id, c, stage)
    local def = defs[id]
    if def.lines and def.lines.stage then
        Speech.stage(p, def.lines.stage[stage])
    end
    if def.onStage then
        def.onStage(p, c, stage, defs)
    end
    complications(p, defs, id, c, stage)
end

-- Lifestyle: Hobbies (facts.lifestyle, Server/Lifestyle): a clean, rested, bathed character gets over an illness
-- faster, a filthy one slower. The incubation (stage 1) never moves.
local function pace(p, c, id)
    local lifestyle = p.facts and p.facts.lifestyle
    if not lifestyle or c.stage < 2 then
        return 1
    end
    return Pace.forCondition(lifestyle, id)
end

-- Advances one condition by dt minutes. Returns "recovered" when it ended, or the last stage it entered.
local function advance(p, def, c, dt, id)
    if def.rate then
        dt = dt * def.rate(p, c)
    end
    dt = dt * pace(p, c, id)
    c.left = c.left - dt
    local entered
    while c.left <= 0 do
        if c.stage == def.persistsAt or (def.hold and def.hold(p, c)) then
            c.left = 0
            return entered
        end
        if c.stage == lastStage(def) then
            return "recovered"
        end
        c.stage = nextStage(def, c.stage)
        c.left = c.left + Engine.stageMinutes(c, c.stage)
        entered = c.stage
    end
    return entered
end

local function randomLine(p, def, c, dt)
    local lines = def.lines
    local pool = lines and lines.random and lines.random[c.stage]
    if not pool or #pool == 0 or (lines.quiet and lines.quiet(p, c)) then
        return
    end
    local every = lines.every
    if type(every) == "table" then
        every = every[c.stage]
    end
    Speech.maybePick(p, pool, every or 60, dt)
end

-- One simulation step for every active condition, in id order.
function Engine.step(p, defs, dt)
    local conditions = p.state.conditions
    Timers.advance(conditions.timers, dt)
    for _, id in ipairs(Tables.sortedKeys(conditions.active)) do
        local c = conditions.active[id]
        local def = defs[id]
        if c and def then
            local curing = p.treatment:curing(id)
            local result
            if def.driven then
                result = def.drive(p, c, dt)
                if result == c.stage then
                    result = nil
                elseif type(result) == "number" then
                    c.stage = result
                    c.left = Engine.stageMinutes(c, result)
                end
            elseif not curing then
                -- Only stage changes are synced; the client's remaining times are as of the last change.
                result = advance(p, def, c, dt, id)
            end
            if result == "recovered" then
                Engine.finish(p, defs, id, "recovered")
            elseif result then
                p.dirty("conditions")
                Engine.enterStage(p, defs, id, c, result)
            end
            -- Stage entry may hand the condition off (cellulitis -> sepsis) and remove it.
            c = conditions.active[id]
            if c and (c.stage > 1 or def.effectsInStage1 or def.reverse or def.driven) then
                if def.effects then
                    def.effects(p, c, dt, curing, defs)
                end
                randomLine(p, def, c, dt)
            end
        end
    end
end

return Engine
