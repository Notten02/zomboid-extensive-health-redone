-- Wires Phase 3 (blood and wounds) to the authority: the simulation systems, the client commands for transfusion,
-- blood draw and the stitch minigame, the vanilla treatment hooks, the blood bag spoilage scan, and debug commands.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"
local Xp = require "ExtensiveHealthRedone/Server/Xp"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local systems = require "ExtensiveHealthRedone/Systems"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local StitchData = require("ExtensiveHealthRedone/Data/Wounds").stitch
local Blood = require "ExtensiveHealthRedone/Blood/Blood"
local Transfusion = require "ExtensiveHealthRedone/Blood/Transfusion"
local Infection = require "ExtensiveHealthRedone/Wounds/Infection"
local Stitch = require "ExtensiveHealthRedone/Wounds/Stitch"
local Players = require "ExtensiveHealthRedone/Server/Players"
local Exam = require "ExtensiveHealthRedone/Server/Exam"

local log = Env.logger("Health")

for _, system in ipairs(systems) do
    Runtime.sim:add(system)
end

local function notice(player, key)
    Transport.toClient(player, "notice", { key = key, owner = PlayerKey.of(player) })
end

-- A patient named in a command, attached so their state is loaded.
local function patientOf(ctx, target)
    if not target then
        return ctx.actor
    end
    Runtime.attach(target.player)
    return target
end

-- Blood ----------------------------------------------------------------------------------------------------------

Runtime.registry:register("blood.transfuse", {
    args = {
        bag = { type = "item", types = Supplies.transfusable },
        target = { type = "player", optional = true },
    },
    proximity = { arg = "target", tiles = StitchData.RANGE },
    -- Per bag: the patient said yes to this one bag (Server/Consent), used up by this attempt.
    consent = { arg = "target", purpose = "transfuse", detail = "bag", once = true },
    -- Only Actions/Blood's EHRTransfusionAction runs it, when its time is up (SA-6).
    action = true,
    rate = { count = 2, seconds = 5 },
    handler = function(ctx, args)
        local doctor = ctx.actor.player
        local patient = patientOf(ctx, args.target)
        local bag = args.bag.item
        local fullType = args.bag.fullType
        local kit = Items.findFirst(doctor, Supplies.ivKit)
        if not kit then
            return notice(doctor, "UI_EHR_MedAction_RequiresIVKit")
        end
        local patientState = Runtime.store:get(patient.key)
        if not patientState then
            return
        end
        local spoilage = fullType == Supplies.saline and "fresh" or Items.spoilage(doctor, bag)
        local refusal = Transfusion.refusal(patientState, fullType, spoilage)
        if refusal then
            return notice(doctor, refusal)
        end
        Items.useOne(kit)
        Items.remove(bag)
        local outcome = Runtime.applyNow(patient.key, function(p)
            return Transfusion.apply(p, defs, fullType, spoilage)
        end)
        Xp.award(doctor, fullType == Supplies.saline and "saline" or "transfusion")
        log:info(ctx.actor.key, "gave", fullType, "(" .. spoilage .. ") to", patient.key, "->", outcome)
    end,
})

Runtime.registry:register("blood.draw", {
    args = { bag = { type = "item", types = Supplies.emptyBag } },
    action = true,     -- Actions/Blood's EHRDrawBloodAction
    rate = { count = 2, seconds = 5 },
    handler = function(ctx, args)
        local player = ctx.actor.player
        local state = Runtime.store:get(ctx.actor.key)
        local refusal = Transfusion.drawRefusal(state)
        if refusal then
            return notice(player, refusal)
        end
        local filled = Runtime.applyNow(ctx.actor.key, Transfusion.draw)
        Items.remove(args.bag.item)
        local item = Items.add(player, filled)
        if item then
            Items.markDrawn(player, item, state.identity.bloodType)
        end
        log:info(ctx.actor.key, "drew blood into", filled)
    end,
})

-- Carried blood bags spoil on time: look at them every 10 game minutes.
Runtime.scheduler:every("bloodBags", 10, function()
    for _, key in ipairs(Runtime.store:keys()) do
        local player = Runtime.playerFor(key)
        if player then
            for _, bag in ipairs(Items.findAll(player, Supplies.bloodTypeOf)) do
                Items.spoilage(player, bag)
            end
        end
    end
end, { coalesce = true })

-- Wounds: vanilla treatment hooks -----------------------------------------------------------------------------------

local function disinfected(patient, bodyPart, how)
    local key = Runtime.attach(patient)
    if key then
        local name = Facts.partName(bodyPart)
        local outcome = Runtime.applyNow(key, function(p)
            return Infection.disinfected(p, name)
        end)
        log:debug(key, name, how, "->", outcome)
    end
end

Patches.on("disinfectComplete", {
    name = "woundInfection",
    after = function(results, action)
        if results[1] ~= false then
            disinfected(action.otherPlayer, action.bodyPart, "disinfected")
        end
    end,
})

-- An alcoholic bandage (ours, vanilla's or another mod's) disinfects as it is applied.
Patches.on("bandageComplete", {
    name = "woundInfection",
    after = function(results, action)
        if results[1] ~= false and action.doIt and action.item and action.item:isAlcoholic() then
            disinfected(action.otherPlayer, action.bodyPart, "alcoholic bandage")
        end
    end,
})

-- Tetanus lockjaw: the server refuses food too, so a modified client can't eat through it. Drinks (no hunger
-- change) are allowed, as in v0.9. This is one of the two intercepts allowed by Core/PatchPoints.
Patches.on("eatComplete", {
    name = "tetanusLockjaw",
    intercept = function(action)
        local state = Runtime.store:get(PlayerKey.of(action.character))
        local tetanus = state and state.conditions.active.tetanus
        if tetanus and tetanus.data.lockjaw and action.item and action.item:getHungChange() ~= 0 then
            return true, false
        end
        return false
    end,
})

-- Stitch minigame --------------------------------------------------------------------------------------------------
-- The client plays the minigame, then the vanilla stitch runs. The server keeps one session per doctor (so one
-- minigame gives at most one roll), then a pending result that the vanilla ISStitch:complete picks up.
-- Phase 9 authority (SA-1 to SA-3):
--   stitch.begin   another patient needs a "stitch" permit (Server/Consent) or an exam session by this doctor
--                  (Server/Exam); the doctor must carry what vanilla's stitch menu needs. Refusals go back to the doctor
--                  as "stitchDenied" { part, reason = no_consent | no_needle | nothing }, so the client can ask.
--   stitch.result  only while the two are still within RANGE; a success sooner than Stitch.MIN_SECONDS after the
--                  begin counts as poor; every "excellent" claim is logged with its duration.
--   stitchComplete with StitchMinigameEnabled on, a vanilla stitch the minigame would have run for, without a valid
--                  result for this doctor, patient and part, counts as a poor stitch (logged). Off: nothing is rolled.

local sessions = {}      -- [doctorKey] = { id, patient, part, began, expires }
local pending = {}       -- [doctorKey .. "|" .. patientKey .. "|" .. part] = { band, expires }
local aborted = {}       -- [doctorKey .. "|" .. patientKey .. "|" .. part] = until when another abort does no harm
local nextSession = 0

local function partByIndex(index)
    return BodyParts.names[index + 1]
end

local function minigameOn()
    return Env.sandbox("StitchMinigameEnabled", true) ~= false
end

-- The item's type without its module ("Base.SutureNeedle" -> "SutureNeedle"), as vanilla's getType().
local function itemType(item)
    return item:getFullType():match("([^%.]+)$")
end

local function hasTag(item, name)
    ---@diagnostic disable-next-line: undefined-global
    local tags = ItemTag
    return tags ~= nil and tags[name] ~= nil and item:hasTag(tags[name])
end

-- A suture needle, or a sewing needle and thread, anywhere in the doctor's inventory (vanilla ISHealthPanel HStitch).
local function hasStitchingItem(player)
    local kinds = StitchData.ITEMS
    local inventory = player:getInventory()
    local function has(test)
        return inventory:getFirstEvalRecurse(test) ~= nil
    end
    if has(function(item) return itemType(item) == kinds.suture end) then
        return true
    end
    return has(function(item) return itemType(item) == kinds.needle or hasTag(item, kinds.needleTag) end)
        and has(function(item) return itemType(item) == kinds.thread or hasTag(item, kinds.threadTag) end)
end

-- Consent to stitch: yourself, a "stitch" permit from the patient, or an exam session the patient agreed to.
local function mayStitch(doctorKey, patientKey)
    return doctorKey == patientKey
        or Runtime.permits:check(patientKey, doctorKey, "stitch", Env.realSeconds())
        or Exam.isExamining(doctorKey, patientKey)
end

local function denied(ctx, part, reason)
    Transport.toClient(ctx.actor.player, "stitchDenied", { part = part, reason = reason, owner = ctx.actor.key })
end

-- Doctor and patient still close enough (always true for yourself).
local function inRange(doctorKey, doctor, patientKey)
    if doctorKey == patientKey then
        return true
    end
    local patient = Runtime.playerFor(patientKey)
    local distance = patient and Players.distance(doctor, patient)
    return distance ~= nil and distance <= StitchData.RANGE
end

local function tenths(seconds)
    return math.floor(seconds * 10 + 0.5) / 10
end

Runtime.registry:register("stitch.begin", {
    args = {
        target = { type = "player", optional = true },
        part = { type = "number", integer = true, min = 0, max = #BodyParts.names - 1 },
    },
    proximity = { arg = "target", tiles = StitchData.RANGE },
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local patient = patientOf(ctx, args.target)
        local name = partByIndex(args.part)
        if not mayStitch(ctx.actor.key, patient.key) then
            log:info(ctx.actor.key, "stitch session refused: no consent from", patient.key)
            return denied(ctx, args.part, "no_consent")
        end
        if not hasStitchingItem(ctx.actor.player) then
            log:info(ctx.actor.key, "stitch session refused: no needle")
            return denied(ctx, args.part, "no_needle")
        end
        local part = Facts.bodyPart(patient.player, name)
        if not (part and part:deepWounded() and not part:haveGlass() and not part:stitched()) then
            log:info(ctx.actor.key, "stitch session refused: nothing to stitch on", patient.key, name)
            return denied(ctx, args.part, "nothing")
        end
        nextSession = nextSession + 1
        local now = Env.realSeconds()
        sessions[ctx.actor.key] = { id = nextSession, patient = patient.key, part = name, began = now,
            expires = now + StitchData.SESSION_SECONDS }
        Transport.toClient(ctx.actor.player, "stitchSession",
            { id = nextSession, part = args.part, owner = ctx.actor.key })
    end,
})

Runtime.registry:register("stitch.result", {
    args = {
        session = { type = "number", integer = true, min = 1 },
        misses = { type = "number", integer = true, min = 0, max = 20 },
        outcome = { type = "string", oneOf = { success = true, failed = true, cancelled = true } },
        started = { type = "boolean" },
    },
    rate = { count = 4, seconds = 10 },
    handler = function(ctx, args)
        local s = sessions[ctx.actor.key]
        sessions[ctx.actor.key] = nil
        local now = Env.realSeconds()
        if not s or s.id ~= args.session or now > s.expires then
            log:info(ctx.actor.key, "stitch result without a valid session ignored")
            return
        end
        if not inRange(ctx.actor.key, ctx.actor.player, s.patient) then
            log:info(ctx.actor.key, "stitch result ignored: out of range of", s.patient)
            return
        end
        local seconds = now - s.began
        if args.outcome == "success" then
            local band = Stitch.band(Stitch.quality(args.misses))
            if seconds < Stitch.MIN_SECONDS then
                log:info(ctx.actor.key, "stitch on", s.patient, s.part, "reported", band, "after", tenths(seconds),
                    "s, faster than", Stitch.MIN_SECONDS, "s: counted as poor")
                band = "poor"
            elseif band == "excellent" then
                log:info(ctx.actor.key, "claims an excellent stitch on", s.patient, s.part, "after", tenths(seconds), "s")
            end
            pending[ctx.actor.key .. "|" .. s.patient .. "|" .. s.part] = {
                band = band, expires = now + StitchData.RESULT_SECONDS,
            }
            return
        end
        -- A failed or cancelled stitch on someone else harms them once per part per consent window; repeating the
        -- begin/fail loop can't stack pain or reroll cellulitis (review finding, Phase 9).
        local abortId = ctx.actor.key .. "|" .. s.patient .. "|" .. s.part
        if ctx.actor.key ~= s.patient and aborted[abortId] and now <= aborted[abortId] then
            log:info(ctx.actor.key, "repeated stitch", args.outcome, "on", s.patient, s.part, "ignored")
            return
        end
        if ctx.actor.key ~= s.patient then
            aborted[abortId] = now + StitchData.ABORT_WINDOW_SECONDS
        end
        local result = Runtime.applyNow(s.patient, function(p)
            return Stitch.applyAbort(p, defs, s.part, args.misses, args.started, args.outcome == "failed")
        end)
        log:info(ctx.actor.key, "stitch", args.outcome, "on", s.patient, s.part, "cellulitis:",
            result and result.cellulitis)
    end,
})

Patches.on("stitchComplete", {
    name = "stitchMinigame",
    before = function(action)
        local part = action.bodyPart
        action.ehrWasInfected = part:isInfectedWound()
        -- Would the client have run the minigame for this stitch? (Client/StitchMinigame's intercept)
        action.ehrMinigame = action.doIt and part:deepWounded() and not part:haveGlass() and not part:stitched()
    end,
    after = function(results, action)
        if results[1] == false or not action.doIt then
            return
        end
        local doctorKey = PlayerKey.of(action.character)
        local patientKey = Runtime.attach(action.otherPlayer)
        local name = Facts.partName(action.bodyPart)
        local id = doctorKey .. "|" .. tostring(patientKey) .. "|" .. name
        local result = pending[id]
        pending[id] = nil
        if not patientKey then
            return
        end
        local band = result and Env.realSeconds() <= result.expires and result.band or nil
        if not band then
            if not (action.ehrMinigame and minigameOn()) then
                return
            end
            if not mayStitch(doctorKey, patientKey) then
                -- Only a modified client stitches someone without our consent flow; vanilla closes the wound, we add
                -- no harm to a player who never agreed.
                log:info(doctorKey, "stitched", patientKey, name, "without consent or minigame result: no roll")
                return
            end
            band = "poor"
            log:info(doctorKey, "stitch without minigame result on", patientKey, name, ": counted as poor")
        end
        local outcome = Runtime.applyNow(patientKey, function(p)
            return Stitch.applyBand(p, defs, name, band, action.ehrWasInfected)
        end)
        if outcome then
            log:info(doctorKey, "stitched", patientKey, name, outcome.band, "cellulitis:", outcome.cellulitis,
                "infected:", outcome.infected)
        end
    end,
})

Runtime.scheduler:every("stitchSessions", 10, function()
    local now = Env.realSeconds()
    local stale = {}
    for key, session in pairs(sessions) do
        if now > session.expires then
            stale[#stale + 1] = key
        end
    end
    for _, key in ipairs(stale) do
        sessions[key] = nil
    end
    stale = {}
    for id, entry in pairs(pending) do
        if now > entry.expires then
            stale[#stale + 1] = id
        end
    end
    for _, id in ipairs(stale) do
        pending[id] = nil
    end
    stale = {}
    for id, expires in pairs(aborted) do
        if now > expires then
            stale[#stale + 1] = id
        end
    end
    for _, id in ipairs(stale) do
        aborted[id] = nil
    end
end, { coalesce = true })

-- Debug ----------------------------------------------------------------------------------------------------------------

local CONDITION_IDS = {}
for id in pairs(defs) do
    CONDITION_IDS[id] = true
end

Runtime.registry:register("debug.setBlood", {
    args = { percent = { type = "number", min = 0, max = 100 }, saline = { type = "number", min = 0, max = 5000,
        optional = true } },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local b = p.state.blood
            b.volume = b.max * args.percent / 100
            if args.saline then
                b.saline = args.saline
            end
            p.dirty("blood")
        end)
        log:info(ctx.actor.key, "debug: blood set to", args.percent, "%")
    end,
})

Runtime.registry:register("debug.condition", {
    args = {
        id = { type = "string", oneOf = CONDITION_IDS },
        action = { type = "string", oneOf = { start = true, next = true, stage = true, cure = true } },
        stage = { type = "number", integer = true, min = 1, max = 4, optional = true },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local c = p.state.conditions.active[args.id]
            if args.action == "start" then
                p.state.conditions.timers[args.id .. "Block"] = nil
                Engine.contract(p, defs, args.id, { source = args.id == "cellulitis" and "ForeArm_L" or "debug" })
            elseif args.action == "next" and c then
                c.left = 0.001
            elseif args.action == "stage" and c and args.stage then
                Engine.setStage(p, defs, args.id, args.stage)
            elseif args.action == "cure" then
                Engine.finish(p, defs, args.id, "debug")
            end
        end)
        log:info(ctx.actor.key, "debug: condition", args.id, args.action)
    end,
})

Runtime.registry:register("debug.woundInfection", {
    args = {
        part = { type = "number", integer = true, min = 0, max = #BodyParts.names - 1 },
        stage = { type = "number", integer = true, min = 0, max = 3 },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            Infection.start(p, partByIndex(args.part), args.stage)
        end)
    end,
})

-- debug.healAll (the debug menu's Full heal) is in Server/Admin: the same routine as an admin's /ehrfullheal.

log:info("blood and wounds loaded")
