-- The only code that changes body parts: health (damage, rescue and an admin's full restore), healing caps, extra
-- pain, wound and fracture healing speed, new and reopened wounds, the vanilla wound-infection flag, vanilla's cold,
-- vanilla's Knox infection, and death. tests/layout_spec.lua checks that no other file does.
--
-- After the systems have run (or a command has applied an effect), apply() resolves the BodyAggregator against the
-- body once: a full restore first, then damage, then healing caps (so damage lowers them), then pain, then infection
-- flags. On a dedicated server every changed part is synced to clients.

local Env = require "ExtensiveHealthRedone/Game/Env"
local BodyAggregator = require "ExtensiveHealthRedone/Core/BodyAggregator"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local log = Env.logger("Body")

local BodyWriter = {}

-- Vanilla's own "sync everything on this part" value (server/ClientCommands.lua, the health cheat).
local SYNC_ALL = 0xFFFFFFFFFFF

local function kill(player, cause)
    log:info(player:getUsername(), "dies:", cause)
    -- Kill's overloads make the call shape uncertain across B42 updates; a failure is logged and health set to 0.
    local ok, err = pcall(function() player:Kill(player) end)
    if not ok then
        log:error("Kill failed, setting health to 0:", err)
        player:getBodyDamage():setOverallBodyHealth(0)
    end
end

local function addPain(part, extra)
    if extra == 0 then
        return false
    end
    part:setAdditionalPain(math.max(0, math.min(100, part:getAdditionalPain() + extra)))
    return true
end

-- Wound and fracture healing slowed (simulation steps only): each timer may only fall by factor x what vanilla took
-- off since the last step (BodyAggregator.resolveTimer). The timers we last wrote are kept in state.body.woundLock.
-- The opaque per-part speed modifiers vanilla also has are left alone.
local TIMERS = {
    { key = "scratch", get = "getScratchTime", set = "setScratchTime", speed = "woundSpeeds" },
    { key = "cut", get = "getCutTime", set = "setCutTime", speed = "woundSpeeds" },
    { key = "deep", get = "getDeepWoundTime", set = "setDeepWoundTime", speed = "woundSpeeds" },
    { key = "burn", get = "getBurnTime", set = "setBurnTime", speed = "woundSpeeds" },
    { key = "fracture", get = "getFractureTime", set = "setFractureTime", speed = "fractureSpeeds" },
}

local function slowTimers(part, name, body, bodyState)
    bodyState.woundLock = bodyState.woundLock or {}
    local locks = bodyState.woundLock[name]
    if not locks and not (body.woundSpeeds and body.woundSpeeds[name])
        and not (body.fractureSpeeds and body.fractureSpeeds[name]) then
        return false
    end
    local touched = false
    locks = locks or {}
    for _, t in ipairs(TIMERS) do
        local speeds = body[t.speed]
        local value, lock = BodyAggregator.resolveTimer(speeds and speeds[name], part[t.get](part), locks[t.key])
        locks[t.key] = lock
        if value then
            part[t.set](part, value)
            touched = true
        end
    end
    bodyState.woundLock[name] = not Tables.isEmpty(locks) and locks or nil
    return touched
end

-- Healing cap and tracked pain for one part (simulation steps only).
local function capAndPain(part, name, body, bodyState, target, extra)
    local touched = false
    local hp, lock = BodyAggregator.resolveHeal(body.heal[name], part:getHealth(), bodyState.healLock[name])
    bodyState.healLock[name] = lock
    if hp then
        part:SetHealth(hp)
        touched = true
    end
    local applied = bodyState.painApplied[name]
    if target or applied or extra ~= 0 then
        local current = part:getAdditionalPain()
        local value, nowApplied = BodyAggregator.resolvePain(target, current, applied)
        value = math.max(0, math.min(100, value + extra))
        bodyState.painApplied[name] = nowApplied > 0 and nowApplied or nil
        if value ~= current then
            part:setAdditionalPain(value)
            touched = true
        end
    end
    return touched
end

-- true: infect, false: clear vanilla's infection, nil: leave it.
local function setInfection(part, infection)
    if infection == true and not part:isInfectedWound() then
        part:setInfectedWound(true)
        return true
    elseif infection == false and (part:isInfectedWound() or part:getWoundInfectionLevel() > 0) then
        part:setWoundInfectionLevel(-1)
        part:setInfectedWound(false)
        return true
    end
    return false
end

-- Scratches (scabies) and reopened wounds (BodyAggregator:reopen): a normal vanilla wound with Knox forced off where
-- vanilla lets us, plus a check afterwards that nothing made the player Knox-infected (forceNoInfection's Java
-- behaviour isn't visible to us). A deep wound is vanilla's own generateDeepWound (the health cheat's call).
local SCRATCH_TIME = 16     -- scratchTime raised to 16-21
local SCRATCH_PAIN = 8      -- and additional pain to at least 8

local function scratch(part)
    part:setScratched(true, true)
    if part:getScratchTime() < SCRATCH_TIME then
        part:setScratchTime(SCRATCH_TIME + ZombRand(6))
    end
    if part:getAdditionalPain() < SCRATCH_PAIN then
        part:setAdditionalPain(SCRATCH_PAIN)
    end
end

local OPEN = {
    scratch = scratch,
    cut = function(part) part:setCut(true, true) end,
    deep = function(part) part:generateDeepWound() end,
}

local function newWounds(damage, list, scratches, reopened, changed)
    local wanted = {}
    for name in pairs(scratches or {}) do
        wanted[name] = "scratch"
    end
    for name, wish in pairs(reopened or {}) do
        wanted[name] = wish.kind
    end
    if Tables.isEmpty(wanted) then
        return
    end
    local wasInfected = damage:IsInfected()
    for _, name in ipairs(Tables.sortedKeys(wanted)) do
        for i, n in ipairs(BodyParts.names) do
            if n == name then
                OPEN[wanted[name]](list:get(i - 1))
                changed[i] = true
            end
        end
    end
    if not wasInfected and damage:IsInfected() then
        log:warn("a new or reopened wound Knox-infected the player; clearing it")
        damage:setInfected(false)
        damage:setInfectionTime(-1)
        damage:setInfectionMortalityDuration(-1)
        for i = 1, #BodyParts.names do
            local part = list:get(i - 1)
            if part:IsInfected() then
                part:SetInfected(false)
                part:SetFakeInfected(false)
                changed[i] = true
            end
        end
    end
end

-- Overall health raised to at least restore.target: every part below the target is healed to it, then the overall
-- value is set. The healing caps accept the new values,
-- so conditional healing doesn't undo the rescue.
local function restore(damage, list, wanted, bodyState, changed)
    if not wanted or damage:getOverallBodyHealth() >= wanted.target then
        return
    end
    for i, name in ipairs(BodyParts.names) do
        local part = list:get(i - 1)
        if part:getHealth() < wanted.target then
            part:SetHealth(wanted.target)
            changed[i] = true
        end
        if bodyState.healLock[name] then
            bodyState.healLock[name] = part:getHealth()
        end
    end
    damage:setOverallBodyHealth(math.max(damage:getOverallBodyHealth(), wanted.target))
    log:info("health restored to", wanted.target, "by", wanted.source)
end

-- An admin's full heal (BodyAggregator:fullRestore): vanilla's own health cheat per part ("healthFullBody" in
-- ISHealthPanel and server/ClientCommands.lua: RestoreToFullHealth, then stiffness 0 and the fitness record removed),
-- after BodyDamage:RestoreToFullHealth for the body-wide values. Vanilla's cold is switched off and our part
-- bookkeeping dropped, since the values it tracked are gone. Every part counts as changed, so a dedicated server
-- syncs all of them.
local function fullRestore(player, damage, list, wanted, bodyState, changed)
    if not wanted then
        return
    end
    damage:RestoreToFullHealth()
    local fitness = player:getFitness()
    for i = 1, #BodyParts.names do
        local part = list:get(i - 1)
        part:RestoreToFullHealth()
        if part:getStiffness() > 0 then
            part:setStiffness(0)
            fitness:removeStiffnessValue(BodyPartType.ToString(part:getType()))
        end
        changed[i] = true
    end
    damage:setCatchACold(0)
    damage:setColdStrength(0)
    damage:setHasACold(false)
    bodyState.healLock = {}
    bodyState.woundLock = {}

    bodyState.painApplied = {}
    bodyState.coldApplied = nil
    log:info(player:getUsername(), "body fully restored by", wanted.source)
end

-- Vanilla's Knox infection (Diseases/Knox): cured (flags and timers cleared, bite wounds kept) or rewound so its
-- progress reads rewindTo. Progress = (hours survived - infectionTime) / mortalityDuration: the hours the character
-- has survived, not the world's age (Antibodies and Zombie Virus Vaccine both stamp and read it that way). The
-- ZOMBIE_INFECTION stat itself is set through the stat writer in the same step.
local function applyKnox(player, damage, list, knox, changed)
    if not knox then
        return
    end
    if knox.rewindTo then
        local duration = damage:getInfectionMortalityDuration()
        if damage:IsInfected() and duration > 0 then
            damage:setInfectionTime(player:getHoursSurvived() - knox.rewindTo * duration)
        end
        return
    end
    damage:setInfected(false)
    damage:setInfectionTime(-1)
    damage:setInfectionMortalityDuration(-1)
    for i = 1, #BodyParts.names do
        local part = list:get(i - 1)
        if part:IsInfected() or part:IsFakeInfected() then
            part:SetInfected(false)
            part:SetFakeInfected(false)
            changed[i] = true
        end
    end
end

-- Vanilla's cold (simulation steps only): its moodle and strength follow the common cold's stage.
local function applyCold(damage, body, bodyState)
    local write, applied = BodyAggregator.resolveCold(body.coldStrength, bodyState.coldApplied,
        damage:getColdStrength())
    bodyState.coldApplied = applied
    if write then
        damage:setCatchACold(0)
        damage:setColdStrength(write)
        damage:setHasACold(write > 0)
    end
end

-- bodyState: the player's state.body section (healLock, painApplied, coldApplied). oneOff: true for a command applying a single
-- effect between simulation steps; healing caps and tracked pain belong to the step and are left alone then.
-- Returns the number of parts changed.
function BodyWriter.apply(player, body, bodyState, oneOff)
    local damage = player:getBodyDamage()
    local list = damage:getBodyParts()
    local changed = {}

    fullRestore(player, damage, list, body.full, bodyState, changed)

    local total = body:resolveDamage(damage:getOverallBodyHealth())
    if total > 0 then
        damage:ReduceGeneralHealth(total)
        for i = 1, #BodyParts.names do
            changed[i] = true
        end
    end
    for _, name in ipairs(Tables.sortedKeys(body.partDamages)) do
        for i, n in ipairs(BodyParts.names) do
            if n == name then
                list:get(i - 1):ReduceHealth(body.partDamages[name])
                changed[i] = true
            end
        end
    end

    restore(damage, list, body.restore, bodyState, changed)
    newWounds(damage, list, body.scratches, body.reopened, changed)
    applyKnox(player, damage, list, body.knox, changed)

    local targets = body:painTargets()
    for i, name in ipairs(BodyParts.names) do
        local part = list:get(i - 1)
        local extra = body.oneOff[name] or 0
        local touched
        if oneOff then
            touched = addPain(part, extra)
        else
            touched = capAndPain(part, name, body, bodyState, targets[name], extra)
            touched = slowTimers(part, name, body, bodyState) or touched
        end

        if setInfection(part, body.infection[name]) or touched then
            changed[i] = true
        end
    end

    if not oneOff then
        applyCold(damage, body, bodyState)
    end

    local count = 0
    for i = 1, #BodyParts.names do
        if changed[i] then
            count = count + 1
            if isServer() then
                syncBodyPart(list:get(i - 1), SYNC_ALL)
            end
        end
    end

    if body.killed then
        kill(player, body.killed.cause)
    end
    return count
end

return BodyWriter
