-- The admin chat commands (decision W36 and Q6): which typed lines are ours and what they send. Pure; the chat hook
-- is Client/AdminChat.
--
--   ChatCommands.parse("/ehrfullheal Bob Smith")  -> { command = "admin.fullHeal", word = "/ehrfullheal",
--                                                    usage = "UI_EHR_Admin_UsageFullHeal", name = "Bob Smith" }
--   ChatCommands.parse("/ehrfullheal")            -> the same without name (the hook prints the usage line)
--   ChatCommands.parse("/ehrfullhealx Bob")       -> nil: not ours, vanilla handles the line
--
-- The command word is matched without case and must be followed by whitespace or the end of the line (v0.9). The
-- rest of the line, trimmed and with line breaks turned into spaces, is the name in its original case.

local ChatCommands = {}

-- The longest name the server accepts (Server/Admin's string argument).
ChatCommands.MAX_NAME = 64

ChatCommands.COMMANDS = {
    ["/ehrfullheal"] = { command = "admin.fullHeal", usage = "UI_EHR_Admin_UsageFullHeal" },
    ["/ehrreset"] = { command = "admin.reset", usage = "UI_EHR_Admin_UsageReset" },
    ["/ehrinspect"] = { command = "admin.inspect", usage = "UI_EHR_Admin_UsageInspect" },
}

function ChatCommands.parse(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("[\r\n]", " "):gsub("^%s+", "")
    local word, rest = text:match("^(%S+)(.*)$")
    local spec = word and ChatCommands.COMMANDS[word:lower()]
    if not spec then
        return nil
    end
    local name = rest:gsub("^%s+", ""):gsub("%s+$", "")
    return {
        command = spec.command,
        usage = spec.usage,
        word = word:lower(),
        name = name ~= "" and name or nil,
    }
end

return ChatCommands
