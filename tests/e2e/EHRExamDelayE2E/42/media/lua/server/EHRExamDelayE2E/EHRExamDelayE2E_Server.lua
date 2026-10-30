---@diagnostic disable: undefined-global
-- E2E (dev only, issue #12): how long a vanilla bandage on the patient takes to show in the doctor's EHR exam window.
-- The doctor (admin) examines the patient (player2); the server then bandages and unbandages the patient's ForeArm_L
-- CYCLES times the way ISApplyBandage:complete() does, each at a random moment inside a game minute, and the doctor's
-- client reports when the first examModel showing the change arrived (and, for comparison, when its copy of the
-- patient's vanilla body changed). Server and clients share the machine's clock (getTimestampMs).
-- Before the steps can pass, the patient must stand by the doctor: `pz-e2e.sh server-cmd 'teleport "player2" "admin"'`.
if not isServer() then return end
require "PZE2E/PZE2E"

local CYCLES = 8
local BANDAGE_SYNC = 0xc001966b8e   -- ISApplyBandage:complete()'s syncBodyPart flags

local function byName(players, name)
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getUsername() == name then return p end
    end
    return nil
end

local function arm(player)
    return player:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
end

-- A change waiting for its moment: { at = ms, on = bool, done = callback }.
local pending

local function apply(patient, on)
    local bp = arm(patient)
    if on then
        patient:getBodyDamage():SetBandaged(bp:getIndex(), true, 3, false, "Base.Bandage")
    else
        patient:getBodyDamage():SetBandaged(bp:getIndex(), false, 0, false, nil)
    end
    syncBodyPart(bp, BANDAGE_SYNC)
end

Events.OnTick.Add(function()
    if pending and getTimestampMs() >= pending.at then
        local p = pending
        pending = nil
        apply(p.patient, p.on)
        p.done(getTimestampMs())
    end
end)

local steps = {
    -- Both players online and standing together.
    function(ctx)
        local players = getOnlinePlayers()
        local doctor, patient = byName(players, "admin"), byName(players, "player2")
        if not doctor or not patient then return "wait" end
        if math.abs(doctor:getX() - patient:getX()) > 1 or math.abs(doctor:getY() - patient:getY()) > 1 then
            return "wait"
        end
        ctx.state.doctor, ctx.state.patient = doctor, patient
        ctx.state.delays, ctx.state.vanilla = {}, {}
        if arm(patient):bandaged() then apply(patient, false) end
        PZE2E.ask(doctor, "openExam", { patient = patient:getOnlineID() }, "open")
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        if not ctx.answers.open then return "wait" end
        PZE2E.check(ctx.answers.open.asked == true, "doctor asked: %s", PZE2E.describe(ctx.answers.open))
        PZE2E.ask(ctx.state.patient, "consentYes", { from = ctx.state.doctor:getOnlineID() }, "yes")
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        if not ctx.answers.yes then return "wait" end
        PZE2E.ask(ctx.state.doctor, "examOpen", {}, "window")
    end,
    function(ctx)
        if not ctx.state.doctor then return end
        if not ctx.answers.window then return "wait" end
        PZE2E.check(ctx.answers.window.open == true, "doctor's exam window is open")
    end,
}

for cycle = 1, CYCLES do
    local on = cycle % 2 == 1
    local key = "seen" .. cycle
    -- Change the arm at a random moment within the next game minute (~2.5 s).
    steps[#steps + 1] = function(ctx)
        if not ctx.state.doctor then return end
        ctx.state.t0 = nil
        pending = {
            at = getTimestampMs() + ZombRand(0, 2500), on = on, patient = ctx.state.patient,
            done = function(t) ctx.state.t0 = t end,
        }
    end
    -- Ask the doctor's client when it saw the change.
    steps[#steps + 1] = function(ctx)
        if not ctx.state.doctor then return end
        if not ctx.state.t0 then return "wait" end
        PZE2E.ask(ctx.state.doctor, "seen", { since = ctx.state.t0, bandaged = on }, key)
    end
    steps[#steps + 1] = function(ctx)
        if not ctx.state.doctor then return end
        local a = ctx.answers[key]
        if not a then return "wait" end
        if not a.model then
            -- Not there yet: ask again.
            ctx.answers[key] = nil
            ctx.state.tries = (ctx.state.tries or 0) + 1
            if ctx.state.tries < 5 then
                PZE2E.ask(ctx.state.doctor, "seen", { since = ctx.state.t0, bandaged = on }, key)
                return "wait"
            end
        end
        ctx.state.tries = 0
        local delay = a.model and (a.model - ctx.state.t0) or -1
        local vanilla = a.remote and (a.remote - ctx.state.t0) or -1
        ctx.state.delays[#ctx.state.delays + 1] = delay
        ctx.state.vanilla[#ctx.state.vanilla + 1] = vanilla
        PZE2E.log("DELAY cycle %d bandaged=%s exam=%d ms vanilla body=%d ms", cycle, tostring(on), delay, vanilla)
        PZE2E.check(a.model ~= nil, "cycle %d: the exam window showed the change", cycle)
    end
end

steps[#steps + 1] = function(ctx)
    if not ctx.state.doctor then return end
    local function stats(list)
        local sorted, sum = {}, 0
        for i, v in ipairs(list) do sorted[i] = v; sum = sum + v end
        table.sort(sorted)
        return string.format("min %d, median %d, max %d, mean %d ms", sorted[1] or -1,
            sorted[math.floor((#sorted + 1) / 2)] or -1, sorted[#sorted] or -1, #sorted > 0 and sum / #sorted or -1)
    end
    PZE2E.log("SUMMARY exam window: %s", stats(ctx.state.delays))
    PZE2E.log("SUMMARY vanilla body copy: %s", stats(ctx.state.vanilla))
    PZE2E.ask(ctx.state.doctor, "closeExam", {}, "close")
end

PZE2E.test("exam window refresh delay after a bandage", steps, { startAfter = 2, every = 2, maxWaits = 120 })
