-- Admin commands on another player, by name (decision W36 "two commands", plus Q6's read-only inspect):
--   admin.fullHeal { name }   every health row back to normal, identity kept (Admin/FullHeal "heal")
--   admin.reset { name }      the state back to a new character's, keeping blood type, knowledge and permanent Knox
--                             immunity (Admin/FullHeal "reset")
--   admin.inspect { name }    a short summary as chat lines to the admin, the full state to the server log
-- Client/AdminChat sends them for /ehrfullheal, /ehrreset and /ehrinspect typed in chat (MP only: vanilla has no chat
-- in single player). They need the medicalAdmin permission (CanMedicalCheat), not DebugMode: they are live-server
-- tools. Replies go to the admin, and a notice to the target, as "adminReply" messages of translation keys and
-- arguments, translated on each client. Every action is logged with both player keys.
--
-- The debug menu's "Full heal" and "Reset state" (debug.healAll, debug.resetState: DebugMode too) run the same
-- routine on the sender; that is the single-player route.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Dump = require "ExtensiveHealthRedone/Core/Dump"
local Text = require "ExtensiveHealthRedone/UI/Text"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Players = require "ExtensiveHealthRedone/Server/Players"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local FullHeal = require "ExtensiveHealthRedone/Admin/FullHeal"
local Names = require "ExtensiveHealthRedone/Admin/Names"
local Inspect = require "ExtensiveHealthRedone/Admin/Inspect"
local ChatCommands = require "ExtensiveHealthRedone/Admin/ChatCommands"

local log = Env.logger("Admin")

local Admin = {}

-- The named log file (Zomboid/Logs) admin actions are written to on a dedicated server, besides console.txt.
Admin.LOG_NAME = "ExtensiveHealthRedone"

local NAME_ARG = { name = { type = "string", maxLength = ChatCommands.MAX_NAME } }

-- Text lines for one player's chat (Client/AdminChat).
function Admin.reply(player, lines)
    Transport.toClient(player, "adminReply", { owner = PlayerKey.of(player), lines = lines })
end

local function audit(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    local line = table.concat(parts, " ")
    log:info(line)
    if isServer() then
        writeLog(Admin.LOG_NAME, line)
    end
end

-- One candidate per living player the server serves (Admin/Names).
local function candidates()
    local list = {}
    for _, player in ipairs(Players.online()) do
        if Players.isAlive(player) then
            local c = { player = player, username = player:getUsername(), display = player:getDisplayName() }
            local desc = player:getDescriptor()
            if desc then
                c.fullName = tostring(desc:getForename() or "") .. " " .. tostring(desc:getSurname() or "")
            end
            list[#list + 1] = c
        end
    end
    return list
end

-- The player named, or nil after telling the admin why not.
function Admin.find(admin, name)
    local found = Names.match(name, candidates())
    if found.status == "one" then
        return found.candidate.player
    elseif found.status == "many" then
        Admin.reply(admin, { Text.key("UI_EHR_Admin_Ambiguous", name, tostring(found.count), table.concat(found.usernames, ", ")) })
    else
        Admin.reply(admin, { Text.key("UI_EHR_Admin_NotFound", name) })
    end
    return nil
end

local DONE = { heal = "UI_EHR_Admin_HealDone", reset = "UI_EHR_Admin_ResetDone" }
local NOTICE = { heal = "UI_EHR_Admin_YouWereHealed", reset = "UI_EHR_Admin_YouWereReset" }

-- Full heal or reset (mode) of a player key. Returns the summary, or nil when the player isn't attached.
function Admin.restore(key, mode)
    return Runtime.applyNow(key, function(p)
        return FullHeal.apply(p, defs, mode)
    end)
end

local function restoreNamed(ctx, name, mode)
    local admin = ctx.actor.player
    local target = Admin.find(admin, name)
    local key = target and Runtime.attach(target)
    if not target then
        return
    elseif not key then
        return Admin.reply(admin, { Text.key("UI_EHR_Admin_NotFound", name) })
    end
    local summary = Admin.restore(key, mode) or { conditions = 0, woundInfections = 0 }
    local username = target:getUsername()
    Admin.reply(admin, { Text.key(DONE[mode], username, tostring(summary.conditions),
        tostring(summary.woundInfections)) })
    if key ~= ctx.actor.key then
        Admin.reply(target, { Text.key(NOTICE[mode]) })
    end
    audit(ctx.actor.key, "admin:", mode, "of", key, "(" .. username .. "): conditions ended", summary.conditions,
        "wound infections", summary.woundInfections)
    return summary
end

Runtime.registry:register("admin.fullHeal", {
    args = NAME_ARG,
    access = "medicalAdmin",
    rate = { count = 3, seconds = 10 },
    handler = function(ctx, args)
        return restoreNamed(ctx, args.name, "heal")
    end,
})

Runtime.registry:register("admin.reset", {
    args = NAME_ARG,
    access = "medicalAdmin",
    rate = { count = 3, seconds = 10 },
    handler = function(ctx, args)
        return restoreNamed(ctx, args.name, "reset")
    end,
})

Runtime.registry:register("admin.inspect", {
    args = NAME_ARG,
    access = "medicalAdmin",
    rate = { count = 5, seconds = 10 },
    handler = function(ctx, args)
        local admin = ctx.actor.player
        local target = Admin.find(admin, args.name)
        local key = target and Runtime.attach(target)
        local state = key and Runtime.store:get(key)
        if not target then
            return
        elseif not state then
            return Admin.reply(admin, { Text.key("UI_EHR_Admin_NotFound", args.name) })
        end
        Admin.reply(admin, Inspect.lines(state, defs, target:getUsername()))
        log:info("inspect of", key, "for", ctx.actor.key .. ":\n" .. Dump.lines(state))
        audit(ctx.actor.key, "admin: inspected", key, "(" .. target:getUsername() .. ")")
    end,
})

-- Debug menu (DebugMode + medicalAdmin): the same routine on the sender.
Runtime.registry:register("debug.healAll", {
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx)
        local summary = Admin.restore(ctx.actor.key, "heal")
        log:info(ctx.actor.key, "debug: full heal, conditions ended", summary and summary.conditions)
    end,
})

Runtime.registry:register("debug.resetState", {
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx)
        local summary = Admin.restore(ctx.actor.key, "reset")
        log:info(ctx.actor.key, "debug: state reset, conditions ended", summary and summary.conditions)
    end,
})

log:info("admin commands loaded")

return Admin
