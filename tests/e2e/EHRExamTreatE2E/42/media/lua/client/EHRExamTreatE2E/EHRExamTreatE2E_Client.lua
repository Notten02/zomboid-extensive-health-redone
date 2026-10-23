---@diagnostic disable: undefined-global, duplicate-set-field
-- E2E (dev only, issue #3), client side: the doctor opens an exam and treats through the exam window's diagram the way
-- a click would (MonitorView treat / treatWith with what the Diagram passes); the patient answers the consent ask.
require "PZE2E/PZE2E"

local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Exam = require "ExtensiveHealthRedone/Client/Exam"

-- The context menus opened since the last reset (ISContextMenu.get is how vanilla's treatment menu starts).
local menus = {}
local get = ISContextMenu.get
ISContextMenu.get = function(...)
    local menu = get(...)
    menus[#menus + 1] = menu
    return menu
end

local function window(args)
    local doctor = getPlayer()
    local patient = getPlayerByOnlineID(args.patient)
    return patient and Exam.window(PlayerKey.of(doctor), PlayerKey.of(patient)), patient
end

local function current()
    return Exam.window(PlayerKey.of(getPlayer()), "mp:player2")
end

PZE2E.answer("openExam", function(args)
    local patient = getPlayerByOnlineID(args.patient)
    if not patient then return { asked = false, error = "patient not on this client" } end
    Exam.onExamine(getPlayer(), patient)
    return { asked = true }
end)

PZE2E.answer("consentYes", function(args)
    Client.send(getPlayer(), "consent.answer", { from = args.from, purpose = "exam", accepted = true })
    return { sent = true }
end)

-- How many parts of a body report an injury.
local function injuredParts(body)
    local parts, n = body:getBodyParts(), 0
    for i = 0, parts:size() - 1 do
        if parts:get(i):HasInjury() then n = n + 1 end
    end
    return n
end

PZE2E.answer("examState", function(args)
    local w, patient = window(args)
    if not w then return { window = false } end
    local _, bodyPart = w:healthPart(BodyPartType.Hand_L)
    local remoteBody = patient:getBodyDamageRemote()
    return {
        window = true,
        remote = isClient() and not patient:isLocalPlayer(),
        injured = bodyPart ~= nil and bodyPart:HasInjury(),
        remoteInjured = injuredParts(remoteBody),
        remoteScratched = remoteBody:getBodyPart(BodyPartType.Hand_L):scratched(),
        localInjured = injuredParts(patient:getBodyDamage()),
    }
end)

-- The patient's own client: what it sees of its Hand_L.
PZE2E.answer("ownHand", function()
    local hand = getPlayer():getBodyDamage():getBodyPart(BodyPartType.Hand_L)
    return { scratched = hand:scratched(), injured = hand:HasInjury(), bandaged = hand:bandaged() }
end)

PZE2E.answer("treatMenu", function(args)
    local w = current()
    if not w then return { menu = false, error = "no window" } end
    menus = {}
    local diagram = w.view.diagram
    w.view:treat(BodyPartType.FromString(args.part), diagram:getAbsoluteX() + 30, diagram:getAbsoluteY() + 30)
    local context = menus[#menus]
    if not context or not context:getIsVisible() then return { menu = false, count = #menus } end
    local names, chose = {}, nil
    for _, option in ipairs(context.options) do
        names[#names + 1] = option.name
        if option.name == getText("ContextMenu_Bandage") and option.subOption then
            local sub = context:getSubMenu(option.subOption)
            local pick = sub and sub.options[1]
            if pick then
                pick.onSelect(pick.target, pick.param1, pick.param2)
                chose = pick.name
            end
        end
    end
    context:setVisible(false)
    return { menu = true, options = table.concat(names, ","), chose = chose }
end)

PZE2E.answer("treatDrop", function(args)
    local w = current()
    if not w then return { dropped = false, error = "no window" } end
    local item = getPlayer():getInventory():getFirstTypeRecurse("Bandage")
    if not item then return { dropped = false, error = "no bandage left" } end
    w.view:treatWith(BodyPartType.FromString(args.part), { item })
    return { dropped = true, item = item:getFullType() }
end)

PZE2E.answer("closeExam", function(args)
    local w = window(args)
    if not w then return { closed = false, error = "no window" } end
    local ok, err = pcall(function() w:close() end)
    return { closed = ok and window(args) == nil, error = err and tostring(err) or nil }
end)
