-- Examining another player. A doctor asks with "Examine Health"; a yes to consent purpose "exam"
-- (Server/Consent) starts a session here. While it lasts, the server builds the patient's EHR Monitor model with the
-- DOCTOR's knowledge and First Aid (exactly what the Monitor shows, nothing else is sent) and sends it
-- to the doctor's client. The session ends when the doctor closes the panel, the two are more than RANGE tiles apart
-- (or on different floors), either dies or leaves, or nothing kept it alive for IDLE_SECONDS.
-- An MP client loads this file too and stops at the first line.
--
--   Exam.isExamining(doctorKey, patientKey)   true while a session runs (also consent to stitch, see Server/Health)
--   Exam.model(patientPlayer, patientState, doctorPlayer, doctorState)   the view model the doctor gets
--
-- Messages to the doctor's client (Client/Exam):
--   examModel   { target = patient ref, patient = key, name, model = UI/Monitor model, overall = 0-100 }
--   examEnd     { target, patient, reason }: closed | too_far | idle | gone | none (no session to keep)
-- and to the patient's: examNotice { name } once when a session starts ("X is examining you").
-- Commands from the doctor:
--   exam.keep   { target }   the window is open: renews the session and sends a model if one is due
--   exam.close  { target }   the window was closed
--
-- The model is built here, not on the doctor's client, so nothing beyond it leaves the server: not the patient's
-- knowledge, immunity, Knox cure internals, mind, effects or meta sections, and no disease name the doctor can't
-- tell. It is resent when the patient's shown sections change (Runtime.onFlush), when what the body diagram shows of
-- the patient's vanilla body changes (a bandage, a splint: checked every WATCH_SECONDS) and each game minute (vitals
-- move without a section change), at most once a real second per session.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Tables = require "ExtensiveHealthRedone/Core/Tables"
local Schema = require "ExtensiveHealthRedone/Core/Schema"

local Watch = require "ExtensiveHealthRedone/Game/Watch"
local BodyFacts = require "ExtensiveHealthRedone/Game/BodyFacts"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local BodyStatus = require "ExtensiveHealthRedone/UI/BodyStatus"
local Monitor = require "ExtensiveHealthRedone/UI/Monitor"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Consent = require "ExtensiveHealthRedone/Server/Consent"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Players = require "ExtensiveHealthRedone/Server/Players"
local IndoorClimate = require "ExtensiveHealthRedone/Server/IndoorClimate"

local log = Env.logger("Exam")

local Exam = {}

Exam.RANGE = Consent.RANGE
Exam.IDLE_SECONDS = 300     -- 5 min, renewed while the panel is open
Exam.REFRESH_SECONDS = 1    -- at most one model per session per real second
Exam.WATCH_SECONDS = 0.25   -- how often the patients' bodies are compared with what their doctors last got

-- The patient's sections the model reads. Knowledge is the doctor's (UI/Monitor gates names, stages and progress
-- with state.knowledge and the First Aid level). Add-on sections registered with exam = true come too
-- (Core/Schema.registerSection), for their Monitor row providers.
Exam.PATIENT_SECTIONS = { "identity", "blood", "body", "wounds", "conditions", "exposure", "meds", "knox" }

local function patientSections()
    local list = {}
    for _, name in ipairs(Exam.PATIENT_SECTIONS) do
        list[#list + 1] = name
    end
    for _, name in ipairs(Schema.SECTIONS) do
        local spec = Schema.ADDONS[name]
        if spec and spec.exam then
            list[#list + 1] = name
        end
    end
    return list
end

local function shown(name)
    for _, n in ipairs(Exam.PATIENT_SECTIONS) do
        if n == name then
            return true
        end
    end
    local spec = Schema.ADDONS[name]
    return spec ~= nil and spec.exam
end

-- sessions[patientKey][doctorKey] = { expires, sentAt (real seconds), due (a model waits for the throttle),
--                                     doctor, patient (the IsoPlayers it started with), ref (the patient's ref),
--                                     body (bodySignature of the last model) }
local sessions = {}
-- Sessions with a model waiting for the throttle (checked on every tick while > 0).
local dueCount = 0

local endReason

-- True while a session runs and may go on (both here, in range, not idle): checked live, not only once a minute.
function Exam.isExamining(doctorKey, patientKey)
    local byDoctor = sessions[patientKey]
    local session = byDoctor and byDoctor[doctorKey]
    return session ~= nil and endReason(patientKey, doctorKey, session, Env.realSeconds()) == nil
end

local function find(patientKey, doctorKey)
    local byDoctor = sessions[patientKey]
    return byDoctor and byDoctor[doctorKey]
end

-- The model ----------------------------------------------------------------------------------------------------------------

-- The patient's EHR Monitor as the doctor may see it. Plain data (UI/Text values are tables), so it travels as is.
function Exam.model(patient, patientState, doctor, doctorState)
    local state = { knowledge = doctorState.knowledge }
    for _, name in ipairs(patientSections()) do
        state[name] = patientState[name]
    end

    local model = Monitor.build({
        state = state,
        firstAid = doctor:getPerkLevel(Perks.Doctor),
        defs = defs,
        sandbox = Env.sandbox,
        watch = Watch.poweredWorn(patient),
        bodyC = patient:getStats():get(CharacterStat.TEMPERATURE),
        airC = IndoorClimate.air(patient),
        parts = BodyFacts.read(patient),
    })
    -- A row the doctor can't name keeps its condition id for the local Monitor's sake; the view never draws it, and
    -- it would name the disease to a modified client.
    for _, row in ipairs(model.conditions) do
        if not row.known then
            row.id = nil
        end
    end
    -- Without a powered Medical Monitor Watch on the patient the Monitor hides the blood readings; so does the
    -- payload.
    if not model.blood.visible then
        model.blood = { visible = false }
    end
    return model
end

-- What the body diagram shows of a patient's vanilla body, as one string: each part's status labels (UI/BodyStatus,
-- without our wound infection, which changes a section). Health, pain and stiffness count only where they cross a
-- band the diagram shows, so a slow bleed doesn't resend the model every second.
local function bodySignature(patient)
    local parts = BodyFacts.read(patient)
    local out = {}
    for _, name in ipairs(BodyParts.names) do
        out[#out + 1] = name
        for _, status in ipairs(BodyStatus.part(parts[name]).statuses) do
            out[#out + 1] = status.label.key
        end
    end
    return table.concat(out, ",")
end

local function send(patientKey, doctorKey, session)
    if session.due then
        session.due = false
        dueCount = dueCount - 1
    end
    local patientState = Runtime.store:get(patientKey)
    local doctorState = Runtime.store:get(doctorKey)
    if not patientState or not doctorState then
        return
    end
    session.sentAt = Env.realSeconds()
    session.body = bodySignature(session.patient)
    Transport.toClient(session.doctor, "examModel", {
        target = session.ref,
        patient = patientKey,
        name = session.patient:getUsername(),
        model = Exam.model(session.patient, patientState, session.doctor, doctorState),
        overall = session.patient:getBodyDamage():getOverallBodyHealth(),
        owner = doctorKey,
    })
end

-- Sends a model now, or marks one due when the last went out less than REFRESH_SECONDS ago.
local function refresh(patientKey, doctorKey, session)
    if Env.realSeconds() - session.sentAt >= Exam.REFRESH_SECONDS then
        send(patientKey, doctorKey, session)
    elseif not session.due then
        session.due = true
        dueCount = dueCount + 1
    end
end

-- Sessions -----------------------------------------------------------------------------------------------------------------

local function remove(patientKey, doctorKey)
    local byDoctor = sessions[patientKey]
    local session = byDoctor and byDoctor[doctorKey]
    if not session then
        return nil
    end
    if session.due then
        dueCount = dueCount - 1
    end
    byDoctor[doctorKey] = nil
    if Tables.isEmpty(byDoctor) then
        sessions[patientKey] = nil
    end
    return session
end

-- Starts (or renews) a session. patient, doctor: { key, player } records. Returns false when it can't start.
function Exam.start(patient, doctor)
    local distance = Players.distance(doctor.player, patient.player)
    if not Players.isAlive(doctor.player) or not Players.isAlive(patient.player) then
        return false
    end
    if distance == nil or distance > Exam.RANGE then
        -- The patient said yes but walked off meanwhile (consent asks are not range-checked when answered).
        Transport.toClient(doctor.player, "examEnd", {
            target = PlayerKey.ref(patient.player), patient = patient.key, reason = "too_far", owner = doctor.key,
        })
        return false
    end
    local session = find(patient.key, doctor.key)
    local fresh = session == nil
    if fresh then
        session = { sentAt = -1e9, due = false, ref = PlayerKey.ref(patient.player) }
        sessions[patient.key] = sessions[patient.key] or {}
        sessions[patient.key][doctor.key] = session
        log:debug(doctor.key, "examines", patient.key)
    end
    session.expires = Env.realSeconds() + Exam.IDLE_SECONDS
    session.doctor, session.patient = doctor.player, patient.player
    if fresh then
        Transport.toClient(patient.player, "examNotice", { name = doctor.player:getUsername(), owner = patient.key })
    end
    send(patient.key, doctor.key, session)
    return true
end

-- Ends a session without telling anyone.
function Exam.stop(doctorKey, patientKey)
    if remove(patientKey, doctorKey) then
        log:debug(doctorKey, "stopped examining", patientKey)
    end
end

-- Ends a session and tells the doctor why (when the doctor is still there to hear it).
function Exam.finish(patientKey, doctorKey, reason)
    local session = remove(patientKey, doctorKey)
    if not session then
        return
    end
    log:debug(doctorKey, "stopped examining", patientKey, reason)
    if Runtime.playerFor(doctorKey) == session.doctor and Players.isAlive(session.doctor) then
        Transport.toClient(session.doctor, "examEnd", {
            target = session.ref, patient = patientKey, reason = reason, owner = doctorKey,
        })
    end
end

-- Calls fn(patientKey, doctorKey, session) for every session (collect first if fn ends sessions).
function Exam.each(fn)
    for patientKey, byDoctor in pairs(sessions) do
        for doctorKey, session in pairs(byDoctor) do
            fn(patientKey, doctorKey, session)
        end
    end
end

-- Why a session must end now, or nil while it may go on.
function endReason(patientKey, doctorKey, session, now)
    if Runtime.playerFor(doctorKey) ~= session.doctor or not Players.isAlive(session.doctor) then
        return "gone"
    end
    if Runtime.playerFor(patientKey) ~= session.patient or not Players.isAlive(session.patient) then
        return "gone"
    end
    if now >= session.expires then
        return "idle"
    end
    local distance = Players.distance(session.doctor, session.patient)
    if distance == nil or distance > Exam.RANGE then
        return "too_far"
    end
    return nil
end

-- Ends what must end; refreshes the rest when refresh is true.
function Exam.check(refreshAll)
    local now = Env.realSeconds()
    local ending, going = {}, {}
    Exam.each(function(patientKey, doctorKey, session)
        local reason = endReason(patientKey, doctorKey, session, now)
        if reason then
            ending[#ending + 1] = { patientKey, doctorKey, reason }
        elseif refreshAll then
            going[#going + 1] = { patientKey, doctorKey, session }
        end
    end)
    for _, e in ipairs(ending) do
        Exam.finish(e[1], e[2], e[3])
    end
    for _, g in ipairs(going) do
        refresh(g[1], g[2], g[3])
    end
end

Consent.onAccepted("exam", Exam.start)

-- Commands -----------------------------------------------------------------------------------------------------------------

Runtime.registry:register("exam.keep", {
    args = { target = { type = "player" } },
    rate = { count = 20, seconds = 10 },
    handler = function(ctx, args)
        local session = find(args.target.key, ctx.actor.key)
        if not session or endReason(args.target.key, ctx.actor.key, session, Env.realSeconds()) then
            if session then
                Exam.check(false)
            else
                Transport.toClient(ctx.actor.player, "examEnd", {
                    target = PlayerKey.ref(args.target.player), patient = args.target.key, reason = "none",
                    owner = ctx.actor.key,
                })
            end
            return
        end
        session.expires = Env.realSeconds() + Exam.IDLE_SECONDS
        refresh(args.target.key, ctx.actor.key, session)
    end,
})

Runtime.registry:register("exam.close", {
    args = { target = { type = "player" } },
    rate = { count = 20, seconds = 10 },
    handler = function(ctx, args)
        Exam.stop(ctx.actor.key, args.target.key)
    end,
})

-- Refresh ------------------------------------------------------------------------------------------------------------------

-- A patient's shown sections changed: their doctors get a new model. A doctor's knowledge changed (a flyer read
-- during the exam): that doctor's views change too.
Runtime.onFlush(function(key, changed)
    local patientChanged, knowledgeChanged = false, false
    -- changed: the sync message's sections, by name (a list of names works too). Only flags are set, so the order
    -- doesn't matter.
    for k, v in pairs(changed or {}) do
        local name = type(k) == "string" and k or v
        if shown(name) then
            patientChanged = true
        elseif name == "knowledge" then
            knowledgeChanged = true
        end
    end
    if patientChanged and sessions[key] then
        for doctorKey, session in pairs(sessions[key]) do
            refresh(key, doctorKey, session)
        end
    end
    if knowledgeChanged then
        Exam.each(function(patientKey, doctorKey, session)
            if doctorKey == key then
                refresh(patientKey, doctorKey, session)
            end
        end)
    end
end)

-- Each game minute: the close rules, and a fresh model (body parts, temperature and First Aid change without a
-- section change).
Runtime.scheduler:every("exam", 1, function()
    Exam.check(true)
end, { coalesce = true })

-- Vanilla treatment changes the patient's body without a section change, so it would wait for the next game minute
-- (seconds of real time): a session whose patient's diagram no longer matches its last model gets a new one.
local function watchBodies(now)
    for patientKey, byDoctor in pairs(sessions) do
        local signature
        for doctorKey, session in pairs(byDoctor) do
            if not session.due and endReason(patientKey, doctorKey, session, now) == nil then
                signature = signature or bodySignature(session.patient)
                if signature ~= session.body then
                    refresh(patientKey, doctorKey, session)
                end
            end
        end
    end
end

local watchedAt = -1e9

-- Models held back by the throttle go out as soon as it allows.
Events.OnTick.Add(function()
    local now = Env.realSeconds()
    if now - watchedAt >= Exam.WATCH_SECONDS then
        watchedAt = now
        watchBodies(now)
    end
    if dueCount <= 0 then
        return
    end
    local ready = {}
    Exam.each(function(patientKey, doctorKey, session)
        if session.due and now - session.sentAt >= Exam.REFRESH_SECONDS then
            ready[#ready + 1] = { patientKey, doctorKey, session }
        end
    end)
    for _, r in ipairs(ready) do
        send(r[1], r[2], r[3])
    end
end)

Exam.sessions = sessions
Runtime.exam = Exam

return Exam
