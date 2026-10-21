-- The admin chat commands, client half: /ehrfullheal Name, /ehrreset Name and /ehrinspect Name typed in the MP chat
-- become our admin.* commands (Admin/ChatCommands), and the server's replies ("adminReply") come back as chat lines.
-- The server checks the permission; this file only translates typing into intents.
--
-- Interception: vanilla's ISChat.onCommandEntered sends any line starting with "/" that isn't a chat stream to the
-- server as a Java command (SendCommandToServer), so the line is caught first through the chatCommandEntered patch
-- point, an intercept (Data/PatchPoints). It is wrapped at OnGameBoot; the chat window copies the function into its
-- text box when it is built at OnGameStart, so the box gets the wrapper. v0.9 also rebound the text box; that is kept
-- as a fallback for a box that still holds vanilla's original function (rebindTextBox below).
-- A caught line gets the housekeeping vanilla gives a "/" command: unfocus (which clears the box), the up-arrow
-- history, doKeyPress(false) and the text box timer. Nothing goes to SendCommandToServer.
--
-- Output: a local chat line (ISChat.addLineInChat with a small Lua message object that has the two methods the chat
-- reads), or halo text when the chat isn't there (single player has no chat window).

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Text = require "ExtensiveHealthRedone/Client/Text"
local UiText = require "ExtensiveHealthRedone/UI/Text"
local ChatCommands = require "ExtensiveHealthRedone/Admin/ChatCommands"

local log = Env.logger("AdminChat")

local AdminChat = {}

AdminChat.PREFIX = "[EHR] "

-- Vanilla's function as this file found it, before the patch point wrapped it (ISChat loads before mod files).
local vanillaEntered = ISChat and ISChat.onCommandEntered

local function chatLine(text)
    local line = AdminChat.PREFIX .. text
    local message = {}
    function message.getTextWithPrefix() return line end
    function message.getText() return line end
    function message.getAuthor() return nil end
    function message.setText(_, value) line = tostring(value) end
    return message
end

-- The zero-based tab id of the tab the player is looking at, or of the first tab.
local function currentTab(chat)
    if chat.chatText and chat.chatText.tabID ~= nil then
        return chat.chatText.tabID
    end
    local first = chat.tabs and chat.tabs[1]
    return first and first.tabID
end

-- Shows one text value (UI/Text, or a plain string) to a local player.
function AdminChat.show(player, t)
    local text = UiText.is(t) and Text.t(t) or tostring(t)
    local chat = ISChat and ISChat.instance
    if chat and ISChat.addLineInChat then
        local tab = currentTab(chat)
        if tab ~= nil then
            local ok, err = pcall(ISChat.addLineInChat, chatLine(text), tab)
            if ok then
                return
            end
            log:warn("chat line failed, using halo text:", tostring(err))
        end
    end
    if player then
        HaloTextHelper.addText(player, text)
    end
end

-- Vanilla's housekeeping for a "/" command it handles itself (ISChat:onCommandEntered).
local function finishLine(chat, line)
    chat:unfocus()
    chat:logChatCommand(line)
    doKeyPress(false)
    chat.timerTextEntry = 20
end

-- The intercept: true when the line was ours (vanilla then does nothing more with it).
function AdminChat.entered()
    local chat = ISChat and ISChat.instance
    local entry = chat and chat.textEntry
    if not entry then
        return false
    end
    local line = entry:getText()
    local parsed = ChatCommands.parse(line)
    if not parsed then
        return false
    end
    finishLine(chat, line)
    local player = getPlayer()
    if not parsed.name then
        AdminChat.show(player, UiText.key(parsed.usage))
    elseif player then
        Client.send(player, parsed.command, { name = parsed.name })
    end
    return true
end

Patches.on("chatCommandEntered", {
    name = "adminCommands",
    intercept = function()
        if AdminChat.entered() then
            return true
        end
        return false
    end,
})

-- The text box holds a copy of the function. If it still holds vanilla's original although ISChat.onCommandEntered is
-- now the wrapper (the box was built before the wrap), point it at the wrapper.
function AdminChat.rebindTextBox()
    local chat = ISChat and ISChat.instance
    local entry = chat and chat.textEntry
    if entry and vanillaEntered and entry.onCommandEntered == vanillaEntered
        and ISChat.onCommandEntered ~= vanillaEntered then
        entry.onCommandEntered = ISChat.onCommandEntered
        log:info("chat text box rebound to the patched command handler")
    end
end

Events.OnGameStart.Add(AdminChat.rebindTextBox)
if Events.OnChatWindowInit then
    Events.OnChatWindowInit.Add(AdminChat.rebindTextBox)
end

-- Replies from Server/Admin: { owner, lines = { text values } }.
Client.on("adminReply", function(args)
    local player = Client.localPlayer(args.owner)
    if not player or type(args.lines) ~= "table" then
        return
    end
    for _, t in ipairs(args.lines) do
        AdminChat.show(player, t)
    end
end)

-- A refused admin command (no permission, too fast, a bad name) is shown to the admin instead of only logged.
local REFUSALS = {
    forbidden = "UI_EHR_Admin_Forbidden",
    rate_limited = "UI_EHR_Admin_RateLimited",
    bad_args = "UI_EHR_Admin_BadName",
}

Client.onRejected(function(args)
    local command = tostring(args.command)
    if command:sub(1, 6) ~= "admin." then
        return
    end
    AdminChat.show(getPlayer(), UiText.key(REFUSALS[args.code] or "UI_EHR_Admin_Refused", tostring(args.code)))
end)

return AdminChat
