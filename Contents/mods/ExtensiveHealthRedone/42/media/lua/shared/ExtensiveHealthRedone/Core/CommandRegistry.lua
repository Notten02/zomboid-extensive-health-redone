-- The one table of client-to-server commands. Every command is declared with what it accepts and what it needs, and
-- the registry checks all of it before the handler runs. A client can only send intents (an item ID, a target, a
-- number); the server looks everything up itself and decides.
--
--   registry:register("medication.take", {
--       args = { item = { type = "item", types = { ["ExtensiveHealth.Amoxicillin"] = true } } },
--       rate = { count = 4, seconds = 10 },
--       handler = function(ctx, args) ... end,      -- args.item is the server's own item record
--   })
--
-- Command spec fields (all optional except handler):
--   args       { [name] = argSpec }. Unknown argument names are rejected. argSpec.optional allows a missing value.
--              type "string"  (maxLength, oneOf = { [value] = true })
--              type "number"  (min, max, integer = true)
--              type "boolean"
--              type "player"  the raw value is a player reference; resolved with ctx.findPlayer -> target record
--              type "item"    the raw value is an item ID; resolved with ctx.findItem, which only searches the
--                             sender's own inventory -> item record. types = { [fullType] = true } narrows it.
--   access     a permission name checked with ctx.can(name), e.g. "medicalAdmin". Default: any player.
--   debugOnly  true: also needs the sandbox DebugMode option (ctx.debugMode).
--   rate       { count, seconds }: at most count calls per sender in any window of that many seconds.
--              Default DEFAULT_RATE. Real time, from the clock passed to new().
--   proximity  { arg, tiles }: the player in args[arg] must be within tiles (ctx.distance; nil = not reachable,
--              e.g. another floor). A player is always in range of themselves.
--   consent    { arg, purpose, detail, once }: the player in args[arg] must have granted the sender a permit for
--              purpose (ctx.permits). Acting on yourself needs no consent. detail names another argument whose raw
--              value narrows the permit (CommandRegistry.permitPurpose: "medicate:<item id>" is consent for that one
--              item). once = true uses the permit up when the handler has run.
--   action     true: the command is the authority half of one of our shared timed actions (Actions/Authority). A
--              client can't send it; only the action's complete() on the authority runs it, through
--              dispatch(..., { fromAction = true }), which skips the rate limit (the action's duration is the limit).
--
-- dispatch(ctx, name, rawArgs, opts) returns true, handlerResult or false, code, detail. Codes: unknown_command,
-- action_only, forbidden, debug_only, rate_limited, bad_args, no_target, no_item, wrong_item, too_far, no_consent.
--
-- ctx is built by the server adapter for each received command:
--   ctx.actor        { key = "...", ... } the sender
--   ctx.can(name)    permission check for the sender
--   ctx.debugMode    sandbox DebugMode
--   ctx.findPlayer(ref)  -> { key = ..., ... } or nil (strict lookup)
--   ctx.findItem(id)     -> { id = ..., fullType = ... } or nil, sender's inventory only
--   ctx.distance(target) -> tiles or nil
--   ctx.permits, ctx.permitNow   consent store and its current time

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local CommandRegistry = {}
CommandRegistry.__index = CommandRegistry

CommandRegistry.DEFAULT_RATE = { count = 20, seconds = 10 }

local ARG_TYPES = { string = true, number = true, boolean = true, player = true, item = true }

-- clock: function() -> real time in seconds.
function CommandRegistry.new(clock)
    return setmetatable({ commands = {}, clock = clock, calls = {} }, CommandRegistry)
end

function CommandRegistry:register(name, spec)
    if type(name) ~= "string" or self.commands[name] then
        error("command name must be a new string: " .. tostring(name), 2)
    end
    if type(spec.handler) ~= "function" then
        error("command " .. name .. " needs a handler", 2)
    end
    for argName, argSpec in pairs(spec.args or {}) do
        if not ARG_TYPES[argSpec.type] then
            error("command " .. name .. " argument " .. argName .. " has unknown type " .. tostring(argSpec.type), 2)
        end
    end
    if spec.consent and spec.consent.detail and not (spec.args and spec.args[spec.consent.detail]) then
        error("command " .. name .. " consent detail must name an argument", 2)
    end
    for _, field in ipairs({ "proximity", "consent" }) do
        local check = spec[field]
        if check and not (spec.args and spec.args[check.arg] and spec.args[check.arg].type == "player") then
            error("command " .. name .. " " .. field .. " must name a player argument", 2)
        end
    end
    self.commands[name] = spec
end

-- The permit purpose for a consent spec and the raw value of its detail argument: "medicate" or "medicate:123".
function CommandRegistry.permitPurpose(purpose, detail)
    if detail == nil then
        return purpose
    end
    return purpose .. ":" .. tostring(detail)
end

function CommandRegistry:has(name)
    return self.commands[name] ~= nil
end

-- Sorted command names.
function CommandRegistry:names()
    return Tables.sortedKeys(self.commands)
end

local function rateLimited(self, actorKey, name, rate)
    local now = self.clock()
    local byActor = self.calls[actorKey]
    if not byActor then
        byActor = {}
        self.calls[actorKey] = byActor
    end
    local recent = {}
    for _, t in ipairs(byActor[name] or {}) do
        if now - t < rate.seconds then
            recent[#recent + 1] = t
        end
    end
    if #recent >= rate.count then
        byActor[name] = recent
        return true
    end
    recent[#recent + 1] = now
    byActor[name] = recent
    return false
end

-- Forget a player's rate-limit history (on logout).
function CommandRegistry:forget(actorKey)
    self.calls[actorKey] = nil
end

local function checkScalar(argSpec, value)
    local kind = argSpec.type
    if kind == "string" then
        if type(value) ~= "string" then return false end
        if argSpec.maxLength and #value > argSpec.maxLength then return false end
        if argSpec.oneOf and not argSpec.oneOf[value] then return false end
        return true
    elseif kind == "number" then
        -- value == value rejects NaN.
        if type(value) ~= "number" or value ~= value then return false end
        if argSpec.min and value < argSpec.min then return false end
        if argSpec.max and value > argSpec.max then return false end
        if argSpec.integer and value ~= math.floor(value) then return false end
        return true
    elseif kind == "boolean" then
        return type(value) == "boolean"
    end
    return false
end

-- Validates and resolves the raw arguments. Returns resolved args, or nil, code, detail.
local function resolveArgs(ctx, spec, raw)
    local argSpecs = spec.args or {}
    raw = raw or {}
    if type(raw) ~= "table" then
        return nil, "bad_args", "arguments must be a table"
    end
    for argName in pairs(raw) do
        if not argSpecs[argName] then
            return nil, "bad_args", "unexpected argument " .. tostring(argName)
        end
    end
    local args = {}
    for _, argName in ipairs(Tables.sortedKeys(argSpecs)) do
        local argSpec = argSpecs[argName]
        local value = raw[argName]
        if value == nil then
            if not argSpec.optional then
                return nil, "bad_args", "missing " .. argName
            end
        elseif argSpec.type == "player" then
            if type(value) ~= "string" and type(value) ~= "number" then
                return nil, "bad_args", argName
            end
            local target = ctx.findPlayer(value)
            if not target then
                return nil, "no_target", argName
            end
            args[argName] = target
        elseif argSpec.type == "item" then
            if type(value) ~= "number" or value ~= math.floor(value) then
                return nil, "bad_args", argName
            end
            local item = ctx.findItem(value)
            if not item then
                return nil, "no_item", argName
            end
            if argSpec.types and not argSpec.types[item.fullType] then
                return nil, "wrong_item", argName
            end
            args[argName] = item
        elseif checkScalar(argSpec, value) then
            args[argName] = value
        else
            return nil, "bad_args", argName
        end
    end
    return args
end

function CommandRegistry:dispatch(ctx, name, rawArgs, opts)
    local spec = type(name) == "string" and self.commands[name]
    if not spec then
        return false, "unknown_command", tostring(name)
    end
    local fromAction = opts ~= nil and opts.fromAction == true
    if spec.action and not fromAction then
        return false, "action_only", name
    end
    if spec.access and not ctx.can(spec.access) then
        return false, "forbidden", spec.access
    end
    if spec.debugOnly and not ctx.debugMode then
        return false, "debug_only", name
    end
    if not fromAction and rateLimited(self, ctx.actor.key, name, spec.rate or CommandRegistry.DEFAULT_RATE) then
        return false, "rate_limited", name
    end
    local args, code, detail = resolveArgs(ctx, spec, rawArgs)
    if not args then
        return false, code, detail
    end
    if spec.proximity then
        local target = args[spec.proximity.arg]
        if target and target.key ~= ctx.actor.key then
            local distance = ctx.distance(target)
            if distance == nil or distance > spec.proximity.tiles then
                return false, "too_far", spec.proximity.arg
            end
        end
    end
    local permit
    if spec.consent then
        local target = args[spec.consent.arg]
        if target and target.key ~= ctx.actor.key then
            local purpose = CommandRegistry.permitPurpose(spec.consent.purpose,
                spec.consent.detail and rawArgs[spec.consent.detail])
            if not ctx.permits:check(target.key, ctx.actor.key, purpose, ctx.permitNow) then
                return false, "no_consent", purpose
            end
            if spec.consent.once then
                permit = { target.key, purpose }
            end
        end
    end
    local result = spec.handler(ctx, args)
    if permit then
        ctx.permits:revoke(permit[1], ctx.actor.key, permit[2])
    end
    return true, result
end

return CommandRegistry
