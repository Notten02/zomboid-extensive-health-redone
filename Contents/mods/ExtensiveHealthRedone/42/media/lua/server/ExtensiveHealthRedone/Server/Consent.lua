-- Asking another player for consent. A doctor asks; the patient's client shows a prompt; a yes grants a permit
-- (Core/Permits) that commands with a `consent` check accept, or starts what the purpose stands for (an exam).
--   consent.ask    { target, purpose, item? }            doctor -> server -> "consentAsk" to the patient
--   consent.answer { from, purpose, item?, accepted }    patient -> server -> "consentResult" to the doctor
--
-- Purposes (Phase 9 decisions):
--   medicate, transfuse  per dose: the ask names the item in the doctor's inventory, the prompt shows it, and the
--                        permit ("medicate:<item id>") covers that one item, used up by the command that applies it.
--   stitch               stitching another player: one permit for PERMIT_SECONDS, any wound.
--   exam                 no permit: a yes starts an exam session (Server/Exam registers the starter).

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local CommandRegistry = require "ExtensiveHealthRedone/Core/CommandRegistry"
local Tables = require "ExtensiveHealthRedone/Core/Tables"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"

local log = Env.logger("Consent")

local Consent = {}

-- purpose -> { item = the ask must name an item, seconds = how long a yes lasts }
Consent.PURPOSES = {
    medicate = { item = true },
    transfuse = { item = true },
    stitch = {},
    exam = {},
}
local PURPOSE_NAMES = {}
for name in pairs(Consent.PURPOSES) do
    PURPOSE_NAMES[name] = true
end

Consent.ASK_SECONDS = 45        -- an unanswered request expires (v0.9)
Consent.PERMIT_SECONDS = 180    -- how long a yes lasts (v0.9 action permit)
Consent.RANGE = 3
Consent.REFUSED_COOLDOWN = 30   -- after a "no", the same doctor can't ask that patient again for this long

-- purpose -> function(patient, doctor) run on a yes instead of granting a permit (records: { key, player }).
local starters = {}

function Consent.onAccepted(purpose, fn)
    starters[purpose] = fn
end

-- asked[patient][doctor][permit purpose] = expiry (real seconds)
local asked = {}
-- refused[patient][doctor] = until when that doctor's asks are dropped
local refused = {}

-- One open prompt per doctor and patient, and none during the cooldown after a refusal, so a nearby player can't
-- bury someone in dialogs (review finding, Phase 9).
local function mayAsk(patientKey, doctorKey, now)
    local untilWhen = refused[patientKey] and refused[patientKey][doctorKey]
    if untilWhen and now < untilWhen then
        return false
    end
    for _, expires in pairs(asked[patientKey] and asked[patientKey][doctorKey] or {}) do
        if now <= expires then
            return false
        end
    end
    return true
end

local function askedBy(patientKey, doctorKey)
    asked[patientKey] = asked[patientKey] or {}
    asked[patientKey][doctorKey] = asked[patientKey][doctorKey] or {}
    return asked[patientKey][doctorKey]
end

Runtime.registry:register("consent.ask", {
    args = {
        target = { type = "player" },
        purpose = { type = "string", oneOf = PURPOSE_NAMES },
        item = { type = "item", optional = true },
    },
    proximity = { arg = "target", tiles = Consent.RANGE },
    rate = { count = 3, seconds = 10 },
    handler = function(ctx, args)
        local patient = args.target
        if patient.key == ctx.actor.key then
            return
        end
        local needsItem = Consent.PURPOSES[args.purpose].item == true
        if needsItem ~= (args.item ~= nil) then
            return
        end
        local now = Env.realSeconds()
        if not mayAsk(patient.key, ctx.actor.key, now) then
            log:info(ctx.actor.key, "consent ask to", patient.key, "dropped: one is open or was just refused")
            return
        end
        local purpose = CommandRegistry.permitPurpose(args.purpose, args.item and args.item.id)
        askedBy(patient.key, ctx.actor.key)[purpose] = now + Consent.ASK_SECONDS
        Transport.toClient(patient.player, "consentAsk", {
            from = PlayerKey.ref(ctx.actor.player),
            name = ctx.actor.player:getUsername(),
            purpose = args.purpose,
            item = args.item and args.item.id or nil,
            itemType = args.item and args.item.fullType or nil,
            seconds = Consent.ASK_SECONDS,
            owner = patient.key,
        })
    end,
})

Runtime.registry:register("consent.answer", {
    args = {
        from = { type = "player" },
        purpose = { type = "string", oneOf = PURPOSE_NAMES },
        item = { type = "number", integer = true, optional = true },
        accepted = { type = "boolean" },
    },
    rate = { count = 5, seconds = 10 },
    handler = function(ctx, args)
        local doctor = args.from
        local purpose = CommandRegistry.permitPurpose(args.purpose, args.item)
        local byPurpose = asked[ctx.actor.key] and asked[ctx.actor.key][doctor.key]
        local expires = byPurpose and byPurpose[purpose]
        if not expires then
            return
        end
        byPurpose[purpose] = nil
        if Env.realSeconds() > expires then
            return
        end
        if not args.accepted then
            refused[ctx.actor.key] = refused[ctx.actor.key] or {}
            refused[ctx.actor.key][doctor.key] = Env.realSeconds() + Consent.REFUSED_COOLDOWN
        end
        local accepted, failed = args.accepted, nil
        if accepted then
            local starter = starters[args.purpose]
            if starter then
                -- A starter that can't start (the patient walked off) has already told the doctor why.
                accepted = starter(ctx.actor, doctor) ~= false
                failed = not accepted or nil
            else
                Runtime.permits:grant(ctx.actor.key, doctor.key, purpose, Env.realSeconds(), Consent.PERMIT_SECONDS)
            end
        end
        log:info(ctx.actor.key, args.accepted and "allowed" or "refused", doctor.key, purpose)
        Transport.toClient(doctor.player, "consentResult", {
            target = PlayerKey.ref(ctx.actor.player),
            name = ctx.actor.player:getUsername(),
            purpose = args.purpose,
            item = args.item,
            accepted = accepted,
            failed = failed,
            owner = doctor.key,
        })
    end,
})

-- Forget requests that expired or involve players who left.
Runtime.scheduler:every("consentRequests", 10, function()
    local now = Env.realSeconds()
    for patient, byDoctor in pairs(asked) do
        if not Runtime.store:has(patient) then
            asked[patient] = nil
        else
            local emptyDoctors = {}
            for doctor, byPurpose in pairs(byDoctor) do
                local expired = {}
                for purpose, expires in pairs(byPurpose) do
                    if now > expires then
                        expired[#expired + 1] = purpose
                    end
                end
                for _, purpose in ipairs(expired) do
                    byPurpose[purpose] = nil
                end
                if Tables.isEmpty(byPurpose) then
                    emptyDoctors[#emptyDoctors + 1] = doctor
                end
            end
            for _, doctor in ipairs(emptyDoctors) do
                byDoctor[doctor] = nil
            end
        end
    end
    for patient, byDoctor in pairs(refused) do
        local over = {}
        for doctor, untilWhen in pairs(byDoctor) do
            if now >= untilWhen then
                over[#over + 1] = doctor
            end
        end
        for _, doctor in ipairs(over) do
            byDoctor[doctor] = nil
        end
        if Tables.isEmpty(byDoctor) then
            refused[patient] = nil
        end
    end
end, { coalesce = true })

return Consent
