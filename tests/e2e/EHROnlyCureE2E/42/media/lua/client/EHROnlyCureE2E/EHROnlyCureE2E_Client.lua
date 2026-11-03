---@diagnostic disable: undefined-global
-- E2E (dev only), client side: cuts a limb with The Only Cure's own action (as its menu does), and reports the action
-- length, our mirror of state.onlyCure, the Monitor rows and what the wash menu reads.
require "PZE2E/PZE2E"

local Client = require "ExtensiveHealthRedone/Client/Client"
local OnlyCure = require "ExtensiveHealthRedone/Game/OnlyCure"
local BodySoil = require "ExtensiveHealthRedone/Game/BodySoil"
local Rows = require "ExtensiveHealthRedone/UI/Amputation"

PZE2E.answer("timing", function()
    local action = ISBaseTimedAction:new(getPlayer())
    return { t = action:adjustMaxTime(100) }
end)

PZE2E.answer("cut", function(args)
    local player = getPlayer()
    local saw = player:getInventory():getFirstTypeRecurse("Saw")
    if not saw then return { queued = false, error = "no saw on this client" } end
    local CutLimbAction = require "TOC/TimedActions/CutLimbAction"
    ISTimedActionQueue.add(CutLimbAction:new(player, player, args.limb, saw))
    return { queued = true }
end)

PZE2E.answer("mirror", function()
    local player = getPlayer()
    local s = Client.section(player, "onlyCure")
    local stump = s and s.stumps and s.stumps.Hand_L
    local toc = OnlyCure.read(player)
    local soil, mode = BodySoil.wash(player)
    return {
        stump = stump and stump.part or "none",
        rows = #Rows.build({ state = { onlyCure = s } }),
        readCut = toc ~= nil and toc.limbs.Hand_L.cut == true,
        washMode = mode,
        washHandL = soil.Hand_L ~= nil,
    }
end)
