---@diagnostic disable: undefined-global
-- E2E (dev only, issue #12), client side: the doctor opens an exam and records when examModels arrive and when its
-- copy of the patient's vanilla body changes; the patient answers the consent ask.
require "PZE2E/PZE2E"

local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Exam = require "ExtensiveHealthRedone/Client/Exam"

local MODULE = "ExtensiveHealthRedone"
local PART = "ForeArm_L"

-- { t = ms, bandaged = bool } per examModel, and per change of the remote body's bandage.
local models, remotes = {}, {}

local function shownBandaged(model)
    local part = model and model.parts and model.parts[PART]
    for _, status in ipairs(part and part.statuses or {}) do
        if status.id == "bandage" then return true end
    end
    return false
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == MODULE and command == "examModel" then
        models[#models + 1] = { t = getTimestampMs(), bandaged = shownBandaged(args.model) }
    end
end)

local function patient()
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getUsername() == "player2" and not p:isLocalPlayer() then return p end
    end
    return nil
end

local lastRemote
Events.OnTick.Add(function()
    local p = patient()
    if not p then return end
    local bandaged = p:getBodyDamageRemote():getBodyPart(BodyPartType.ForeArm_L):bandaged()
    if bandaged ~= lastRemote then
        lastRemote = bandaged
        remotes[#remotes + 1] = { t = getTimestampMs(), bandaged = bandaged }
    end
end)

local function first(list, since, bandaged)
    for _, e in ipairs(list) do
        if e.t >= since and e.bandaged == bandaged then return e.t end
    end
    return nil
end

local function current()
    return Exam.window(PlayerKey.of(getPlayer()), "mp:player2")
end

PZE2E.answer("openExam", function(args)
    local p = getPlayerByOnlineID(args.patient)
    if not p then return { asked = false, error = "patient not on this client" } end
    Exam.onExamine(getPlayer(), p)
    return { asked = true }
end)

PZE2E.answer("consentYes", function(args)
    Client.send(getPlayer(), "consent.answer", { from = args.from, purpose = "exam", accepted = true })
    return { sent = true }
end)

PZE2E.answer("examOpen", function()
    return { open = current() ~= nil }
end)

PZE2E.answer("seen", function(args)
    return {
        model = first(models, args.since, args.bandaged),
        remote = first(remotes, args.since, args.bandaged),
        models = #models,
    }
end)

PZE2E.answer("closeExam", function()
    local w = current()
    if w then w:close() end
    return { closed = current() == nil }
end)
