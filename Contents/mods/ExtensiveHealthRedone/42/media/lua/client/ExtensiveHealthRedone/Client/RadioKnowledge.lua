-- Speaks "Medical knowledge acquired: %1" when the server's Knowledge/Learn rules taught the player something, from a
-- flyer (Server/Flyers) or the 21:00 file on 47.0 MHz (Server/Radio). Effects' "say" has no argument slot, so this
-- line has its own message: { name = translation key of the disease's name }.
-- Text only: the knowledge itself arrives with the knowledge section of the mirror.

local Client = require "ExtensiveHealthRedone/Client/Client"

Client.on("knowledgeLearned", function(args)
    local player = Client.localPlayer(args.owner)
    if player and not player:isDead() then
        ---@diagnostic disable-next-line: redundant-parameter
        player:Say(getText("UI_EHR_FlyerLearned", getText(tostring(args.name))))
    end
end)

return {}
