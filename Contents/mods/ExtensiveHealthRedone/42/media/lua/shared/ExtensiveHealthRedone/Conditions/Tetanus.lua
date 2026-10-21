-- Tetanus: from contaminated deep wounds (Wounds/Tetanus). Stage 1, the incubation, is hidden. Stage 2: lockjaw (no
-- eating), neck stiffness and pain, endurance drain and health loss down to 30. Stage 3: full-body spasms, fever,
-- falls and lethal health loss. Stage 4: recovery. Muscle relaxants allow eating and cut spasms and falls; a curative
-- course stops the damage and holds the stage.
-- Effects from v0.9 (docs/porting/phase3/wound-infection-sepsis-tetanus.md, part 4); timings follow the guide (W11).
-- Not ported: v0.9's general PAIN stat writes (B42 derives pain from the body parts) and muscle stiffness; spasm pain
-- goes on the body parts instead. "Breathing difficulty" was never implemented in v0.9.

local Data = require "ExtensiveHealthRedone/Data/BodyParts"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Chance = require "ExtensiveHealthRedone/Core/Chance"

local Tetanus = {}

local LINES = {
    [2] = "UI_EHR_Text_MyJawFeelsStiffLockjawStarting",
    [3] = "UI_EHR_Text_MuscleSpasmsTheTetanusIsSevereICantOpenMyMouth",
    [4] = "UI_EHR_Text_TheSpasmsAreReducing",
}

local FALL_LINES = {
    "UI_EHR_Text_MyWholeBodyJustSeized", "UI_EHR_Text_TheSpasmsThrewMeOffBalance",
    "UI_EHR_Text_ICantControlTheseCramps", "UI_EHR_Text_EverythingLockedUpAtOnce",
}

Tetanus.FALL_EVERY = 30         -- game minutes between fall rolls
Tetanus.FALL_CHANCE = 0.42
Tetanus.FALL_BLOCK_RELIEF = 0.65

function Tetanus.onStage(p, c, stage)
    Speech.stage(p, LINES[stage])
end

-- Lockjaw blocks eating in stages 2 and 3 unless muscle relaxants are working. The client reads it from the mirror;
-- the server checks it again when food is eaten.
function Tetanus.lockjaw(c, muscleRelief)
    return (c.stage == 2 or c.stage == 3) and muscleRelief <= 0
end

local function setLockjaw(p, c, value)
    if c.data.lockjaw ~= value then
        c.data.lockjaw = value
        p.dirty("conditions")
    end
end

local function falls(p, c, dt, curing, muscle)
    if curing or muscle >= Tetanus.FALL_BLOCK_RELIEF then
        return
    end
    if c.data.fallIn == nil then
        c.data.fallIn = p.rng.int(4, 10)
    end
    c.data.fallIn = c.data.fallIn - dt
    if c.data.fallIn > 0 then
        return
    end
    c.data.fallIn = Tetanus.FALL_EVERY
    local chance = math.floor(42 * math.max(0.20, 1 - 1.4 * muscle)) / 100
    if Chance.roll(p.rng, chance) then
        p.client("fall", { reason = "tetanus" })
        Speech.stage(p, Speech.pick(p, FALL_LINES))
    end
end

function Tetanus.effects(p, c, dt, curing)
    local t = p.treatment
    local sev = c.severity
    local muscle = t:relief("tetanus", "muscleSpasms")
    local painRelief = math.max(t:relief("tetanus", "pain"), 0.6 * t:relief("tetanus", "inflammation"))
    local relieved = muscle > 0 or painRelief > 0
    local spasm = math.max(relieved and 0.04 or 0.10, 1 - 2.4 * muscle)
    local painMult = math.max(relieved and 0.04 or 0.18, (1 - 1.5 * painRelief) * (1 - 1.2 * muscle))
    if curing then
        spasm = spasm * 0.55
        painMult = painMult * 0.55
    end
    local k = Symptoms.TICK * dt
    setLockjaw(p, c, Tetanus.lockjaw(c, muscle))

    if c.stage == 2 then
        p.body:pain("Neck", "tetanus", math.max(relieved and 1 or 8, 24 * sev * painMult))
        p.stats:lowerF("ENDURANCE", "tetanus", 0.70, 0.0035 * sev * spasm * k)
        p.stats:raiseF("FATIGUE", "tetanus", 0.22 * sev * spasm, 0.0018 * sev * k)
        if not curing then
            -- v0.9: 0.25 + 0.45 x severity every 0.7 game hours, never below 30 health.
            p.body:damage("tetanus", (0.25 + 0.45 * sev) / 42 * dt, 30)
            p.body:healFactorAll(Symptoms.ALL_PARTS, "tetanus", 0)
        end
    elseif c.stage == 3 then
        local pain = math.max(relieved and 3 or 18, 46 * sev * painMult)
        p.body:pain("Neck", "tetanus", pain)
        for _, part in ipairs(Data.muscles) do
            p.body:pain(part, "tetanus", pain)
        end
        p.stats:lowerF("ENDURANCE", "tetanus", 0.50, 0.012 * sev * spasm * k)
        p.stats:raiseF("FATIGUE", "tetanus", 0.58 * sev * spasm, 0.0032 * sev * k)
        local target, step = 39.0, 0.050 * sev * k
        if curing then
            target, step = 37.7, step * 1.5
        end
        target, step = Symptoms.fever(target, step, t:relief("tetanus", "fever"))
        Symptoms.applyFever(p, "tetanus", target, step)
        if not curing then
            -- v0.9: 1.0 + 1.8 x severity every 0.35 game hours, no floor.
            p.body:damage("tetanus", (1.0 + 1.8 * sev) / 21 * dt, 0)
            p.body:healFactorAll(Symptoms.ALL_PARTS, "tetanus", 0)
        end
        falls(p, c, dt, curing, muscle)
    elseif c.stage == 4 then
        p.body:pain("Neck", "tetanus", 4)
        p.stats:lowerF("ENDURANCE", "tetanus", 0.86, 0.0015 * sev * k)
    end
end

return Tetanus
