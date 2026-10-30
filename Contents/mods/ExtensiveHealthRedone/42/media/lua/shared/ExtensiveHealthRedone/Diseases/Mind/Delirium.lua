-- Delirium: stress held at its maximum for 12 hours breaks the mind. One permanent stage until an antipsychotic course
-- cures it. Delirium itself changes no stats; it comes in episodes every 30-60 minutes: a hallucinated sound only the
-- player hears, a strange line, a coloured screen tint, and an unsafe impulse (break a nearby window, shout and draw
-- zombies, drop the backpack, fire the held gun).
-- The server decides the trigger, the schedule and the impulse; the owning client plays the episode (Client/Delirium),
-- so the tint shows in MP too.
--
-- Treatment hooks:
--   p.treatment:active("antipsychotic")   an antipsychotic dose is active: episodes 2.5x further apart, impulses 40%
--   p.treatment:curing("delirium")        the antipsychotic course (8 doses, 12 h apart) cures it when complete

local Data = require("ExtensiveHealthRedone/Diseases/Mind/Data").delirium
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local Delirium = {}

Delirium.ENTRY_LINE = "UI_EHR_Text_TheNoiseWontStopSomethingIsTalkingBehindMyEyes"

-- Stress trigger (a system step). Continuous minutes at the threshold, asleep or awake; any lower sample resets.
function Delirium.trigger(p, defs, dt)
    local mind = p.state.mind
    if p.state.conditions.active.delirium then
        mind.stressFor = 0
        return
    end
    if (p.facts.norm.STRESS or 0) >= Data.STRESS_THRESHOLD then
        mind.stressFor = mind.stressFor + dt
    else
        mind.stressFor = 0
    end
    if mind.stressFor >= Data.TRIGGER_MINUTES and Engine.contract(p, defs, "delirium", { source = "stress" }) then
        mind.stressFor = 0
        Speech.stage(p, Delirium.ENTRY_LINE)
    end
end

-- A random index 1..n, never `last` when there is a choice.
local function pickNew(p, n, last)
    local i = p.rng.int(1, n)
    if i == last and n > 1 then
        i = i % n + 1
    end
    return i
end

-- The impulses the character can act on now, off cooldown. Server/Mind reads p.facts.mind = { firearm, dropBackpack,
-- window } (true when possible); shouting is always possible.
local function pickImpulse(p, d)
    local can = p.facts.mind or {}
    local ready = {}
    local total = 0
    for _, impulse in ipairs(Data.IMPULSES) do
        local possible = impulse.id == "shout" or can[impulse.id] == true
        if possible and not d.cool[impulse.id] then
            ready[#ready + 1] = impulse
            total = total + impulse.weight
        end
    end
    if total == 0 then
        return nil
    end
    local roll = p.rng.int(1, total)
    for _, impulse in ipairs(ready) do
        roll = roll - impulse.weight
        if roll <= 0 then
            return impulse
        end
    end
    return ready[#ready]
end

-- One episode: sound, line, tint and maybe an impulse. Returns the message sent to the owning client.
function Delirium.episode(p, c, antipsychotic)
    local d = c.data
    d.cool = d.cool or {}
    d.sound = pickNew(p, #Data.SOUNDS, d.sound)
    d.line = pickNew(p, #Data.LINES, d.line)
    d.tintLeft = p.rng.int(Data.TINT_MINUTES[1], Data.TINT_MINUTES[2])
    d.tintAlpha = Chance.between(p.rng, Data.TINT_ALPHA[1], Data.TINT_ALPHA[2])
    local colour = p.rng.int(1, #Data.COLOURS)
    local impulse
    if Chance.roll(p.rng, antipsychotic and Data.ANTIPSYCHOTIC_IMPULSE_CHANCE or Data.IMPULSE_CHANCE) then
        impulse = pickImpulse(p, d)
    end
    local message = { sound = Data.SOUNDS[d.sound], line = Data.LINES[d.line], colour = colour }
    if impulse then
        d.cool[impulse.id] = impulse.cooldown
        message.impulse = impulse.id
        if impulse.id == "shout" then
            p.noise("deliriumShout", { muffle = false })
        end
    end
    p.client("delirium", message)
    return message
end

local function delay(p, range, stretch)
    return p.rng.int(range[1], range[2]) * stretch
end

function Delirium.effects(p, c, dt)
    local d = c.data
    d.cool = d.cool or {}
    local antipsychotic = p.treatment:active("antipsychotic")
    local stretch = antipsychotic and Data.ANTIPSYCHOTIC_STRETCH or 1
    if d.next == nil then
        d.next = delay(p, Data.FIRST_EPISODE, stretch)
        d.antipsychotic = antipsychotic
    elseif d.antipsychotic ~= antipsychotic then
        -- A dose starting or lapsing stretches or shrinks the wait already running.
        d.next = antipsychotic and d.next * Data.ANTIPSYCHOTIC_STRETCH or d.next / Data.ANTIPSYCHOTIC_STRETCH
        d.antipsychotic = antipsychotic
    end
    for _, impulse in ipairs(Data.IMPULSES) do
        local left = d.cool[impulse.id]
        if left then
            d.cool[impulse.id] = left - dt > 0 and left - dt or nil
        end
    end
    if d.tintLeft and d.tintLeft > 0 then
        d.tintLeft = d.tintLeft - dt
        if d.tintLeft > 0 then
            p.fx:tint("delirium", d.tintAlpha)
        end
    end
    d.next = d.next - dt
    -- Asleep or driving: the episode waits and comes once the character is free again.
    if d.next > 0 or p.facts.asleep or p.facts.inVehicle then
        return
    end
    Delirium.episode(p, c, antipsychotic)
    d.next = delay(p, Data.EPISODE_EVERY, stretch)
end

function Delirium.onEnd(p)
    p.state.mind.stressFor = 0
end

Delirium.def = {
    enabledOption = "DeliriumEnabled",
    knowledge = "delirium",
    selfEvident = true,
    name = "UI_EHR_Disease_delirium",
    baseSeverity = 0.85,
    severityHidden = true,      -- no symptom scales with the severity, so the monitor shows no severity word
    -- One stage, for good: it ends only through a cure.
    stages = { [1] = { 1, 1 } },
    persistsAt = 1,
    effectsInStage1 = true,
    effects = Delirium.effects,
    onEnd = Delirium.onEnd,
}

return Delirium
