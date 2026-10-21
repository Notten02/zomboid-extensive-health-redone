-- Both sides of consent (Server/Consent) on the client.
--   patient: a yes/no prompt when another player asks to treat or examine them ("consentAsk"). It names the item for
--            a per-dose ask and closes itself when the request expires.
--   doctor:  Consent.ask(player, target, purpose, onAllowed, item) asks; the answer ("consentResult") calls
--            onAllowed(player, targetRef) once if the patient said yes. item: the InventoryItem a medicate or
--            transfuse ask is for (the permit covers that one item). One handler serves every menu, so each menu
--            passes its own callback instead of listening to "consentResult" itself.

require "ISUI/ISModalDialog"

local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"

local Consent = {}

-- [doctorKey .. "|" .. targetRef .. "|" .. purpose .. "|" .. item id] = onAllowed
local waiting = {}

local function waitKey(player, targetRef, purpose, itemId)
    return PlayerKey.of(player) .. "|" .. tostring(targetRef) .. "|" .. tostring(purpose) .. "|" .. tostring(itemId)
end

-- Asks target for consent to purpose. A newer ask for the same patient, purpose and item replaces the callback.
function Consent.ask(player, target, purpose, onAllowed, item)
    local ref = PlayerKey.ref(target)
    local itemId = item and item:getID() or nil
    waiting[waitKey(player, ref, purpose, itemId)] = onAllowed
    Client.send(player, "consent.ask", { target = ref, purpose = purpose, item = itemId })
    HaloTextHelper.addText(player, getText("UI_EHR_Consent_Waiting"))
end

Client.on("consentResult", function(args)
    local player = Client.localPlayer(args.owner)
    if not player then
        return
    end
    local id = waitKey(player, args.target, args.purpose, args.item)
    local onAllowed = waiting[id]
    waiting[id] = nil
    if args.failed then
        return
    end
    if not args.accepted then
        HaloTextHelper.addBadText(player, getText("UI_EHR_Consent_Refused", tostring(args.name)))
        return
    end
    if onAllowed then
        onAllowed(player, args.target)
    end
end)

-- The prompt text: per-dose asks name the item.
function Consent.promptText(args)
    local name = tostring(args.name)
    if args.itemType then
        local itemName = getItemNameFromFullType(args.itemType) or args.itemType
        return getText("UI_EHR_Consent_AskItem_" .. tostring(args.purpose), name, itemName)
    end
    return getText("UI_EHR_Consent_Ask_" .. tostring(args.purpose), name)
end

-- Open prompts, so an expired one can close itself: { dialog, closesAt (ms) }.
local open = {}

Client.on("consentAsk", function(args)
    local player = Client.localPlayer(args.owner)
    if not player or player:isDead() then
        return
    end
    local function answer(_, button)
        Client.send(player, "consent.answer", {
            from = args.from,
            purpose = args.purpose,
            item = args.item,
            accepted = button.internal == "YES",
        })
    end
    local width, height = 380, 150
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local dialog = ISModalDialog:new(x, y, width, height, Consent.promptText(args), true, nil, answer,
        player:getIndex())
    dialog:initialise()
    dialog:addToUIManager()
    if JoypadState.players[player:getIndex() + 1] then
        setJoypadFocus(player:getIndex(), dialog)
    end
    open[#open + 1] = { dialog = dialog, closesAt = getTimestampMs() + (tonumber(args.seconds) or 45) * 1000 }
end)

-- An unanswered prompt closes when the server would no longer accept the answer.
Events.OnTick.Add(function()
    if #open == 0 then
        return
    end
    local now = getTimestampMs()
    local keep = {}
    for _, entry in ipairs(open) do
        if not entry.dialog:isReallyVisible() then
            -- answered (the dialog removed itself)
        elseif now >= entry.closesAt then
            entry.dialog:destroy()
        else
            keep[#keep + 1] = entry
        end
    end
    open = keep
end)

return Consent
