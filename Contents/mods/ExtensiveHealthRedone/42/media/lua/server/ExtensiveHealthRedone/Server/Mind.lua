-- Wires the Mind disease group (delirium, insomnia, painkiller addiction, pain sounds) to the authority: what the
-- delirium impulses can act on (p.facts.mind) and debug commands. Painkiller doses reach addiction through the
-- medication rules (Server/Medication, Medication/Doses).
-- The group's systems and conditions are registered through Systems.lua and Conditions/Registry. An MP client loads
-- this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Data = require("ExtensiveHealthRedone/Diseases/Mind/Data").delirium

local log = Env.logger("Mind")

-- Delirium impulses (Diseases/Mind/Delirium): only read while delirium is active, since the window search looks at
-- 25 squares. The client checks again before acting.
local function weapon(player)
    local item = player:getPrimaryHandItem()
    if item and instanceof(item, "HandWeapon") and item:isRanged() then
        return item
    end
    return nil
end

local function nearbyWindow(player)
    local square = player:getCurrentSquare()
    if not square then
        return false
    end
    local cell = getCell()
    local r = Data.WINDOW_RADIUS
    for dx = -r, r do
        for dy = -r, r do
            local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            local window = sq and sq:getWindow()
            if window and not window:isDestroyed() and not window:isSmashed() and not window:isInvincible() then
                return true
            end
        end
    end
    return false
end

Facts.extend("mind", function(player, facts)
    local state = Runtime.store:get(PlayerKey.of(player))
    if not (state and state.conditions.active.delirium) then
        facts.mind = nil
        return
    end
    local gun = weapon(player)
    facts.mind = {
        firearm = gun ~= nil and ISReloadWeaponAction.canShoot(player, gun) == true,
        dropBackpack = player:getClothingItem_Back() ~= nil,
        window = nearbyWindow(player),
    }
end)

-- Debug ----------------------------------------------------------------------------------------------------------------

Runtime.registry:register("debug.mind", {
    args = {
        action = { type = "string", oneOf = { stress = true, fatigue = true, risk = true, episode = true,
            goodNight = true } },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local mind = p.state.mind
            local active = p.state.conditions.active
            if args.action == "stress" then
                mind.stressFor = Data.TRIGGER_MINUTES - 1        -- delirium on the next step at maximum stress
            elseif args.action == "fatigue" then
                mind.tiredFor = 12 * 60 - 1                      -- insomnia on the next step at high fatigue
            elseif args.action == "risk" then
                mind.painkiller.risk = 99                        -- the next painkiller dose addicts
                p.dirty("mind")
            elseif args.action == "episode" and active.delirium then
                active.delirium.data.next = 0
            elseif args.action == "goodNight" and active.insomnia then
                local d = active.insomnia.data
                d.streak = (d.streak or 0) + 1
            end
        end)
        log:info(ctx.actor.key, "debug: mind", args.action)
    end,
})

log:info("mind loaded")
