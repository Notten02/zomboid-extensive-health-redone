-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local CommandRegistry = require("ExtensiveHealthRedone/Core/CommandRegistry")
local Permits = require("ExtensiveHealthRedone/Core/Permits")

-- A server context with two players and one item in the doctor's inventory.
local function context(overrides)
    local players = {
        doctor = { key = "doctor", x = 0 },
        patient = { key = "patient", x = 2 },
        faraway = { key = "faraway", x = 50 },
    }
    local items = { [7] = { id = 7, fullType = "ExtensiveHealth.BloodBag_APos" } }
    local ctx = {
        actor = players.doctor,
        permissions = {},
        debugMode = false,
        permits = Permits.new(),
        permitNow = 0,
        findPlayer = function(ref) return players[ref] end,
        findItem = function(id) return items[id] end,
        distance = function(target) return math.abs(target.x - players.doctor.x) end,
    }
    ctx.can = function(name) return ctx.permissions[name] == true end
    for k, v in pairs(overrides or {}) do
        ctx[k] = v
    end
    return ctx
end

local function registry()
    local now = { t = 0 }
    local reg = CommandRegistry.new(function() return now.t end)
    return reg, now
end

local function echo(_, args)
    return args
end

describe("CommandRegistry", function()
    it("rejects unknown commands", function()
        local reg = registry()
        local ok, code = reg:dispatch(context(), "nope", {})
        assert.is_false(ok)
        assert.equal("unknown_command", code)
    end)

    it("validates scalar arguments and rejects extra ones", function()
        local reg = registry()
        reg:register("set", {
            args = {
                amount = { type = "number", min = 0, max = 100, integer = true },
                label = { type = "string", maxLength = 5, optional = true },
                stage = { type = "string", oneOf = { mild = true, severe = true }, optional = true },
            },
            handler = echo,
        })
        local ctx = context()
        assert.is_true((reg:dispatch(ctx, "set", { amount = 5 })))
        local cases = {
            { amount = 101 }, { amount = 1.5 }, { amount = "5" }, { amount = 0 / 0 }, {},
            { amount = 1, label = "toolong" }, { amount = 1, stage = "deadly" }, { amount = 1, extra = true },
        }
        for i, args in ipairs(cases) do
            local ok, code = reg:dispatch(ctx, "set", args)
            assert.is_false(ok, "case " .. i)
            assert.equal("bad_args", code, "case " .. i)
        end
        assert.equal("bad_args", select(2, reg:dispatch(ctx, "set", "notatable")))
    end)

    it("resolves items from the sender's inventory only and checks their type", function()
        local reg = registry()
        reg:register("transfuse", {
            args = { bag = { type = "item", types = { ["ExtensiveHealth.BloodBag_APos"] = true } } },
            handler = echo,
        })
        reg:register("inject", {
            args = { syringe = { type = "item", types = { ["ExtensiveHealth.Syringe"] = true } } },
            handler = echo,
        })
        local ctx = context()
        local ok, args = reg:dispatch(ctx, "transfuse", { bag = 7 })
        assert.is_true(ok)
        assert.equal("ExtensiveHealth.BloodBag_APos", (assert(args) --[[@as table]]).bag.fullType)
        assert.equal("no_item", select(2, reg:dispatch(ctx, "transfuse", { bag = 8 })))
        assert.equal("bad_args", select(2, reg:dispatch(ctx, "transfuse", { bag = "7" })))
        assert.equal("wrong_item", select(2, reg:dispatch(ctx, "inject", { syringe = 7 })))
    end)

    it("checks permissions by capability name, so a role without it is refused", function()
        local reg = registry()
        reg:register("fullHeal", { access = "medicalAdmin", args = { target = { type = "player" } }, handler = echo })
        local observer = context()
        assert.equal("forbidden", select(2, reg:dispatch(observer, "fullHeal", { target = "patient" })))
        local admin = context()
        admin.permissions.medicalAdmin = true
        assert.is_true((reg:dispatch(admin, "fullHeal", { target = "patient" })))
    end)

    it("refuses debug commands without the sandbox DebugMode option, even for admins", function()
        local reg = registry()
        reg:register("debug.skip", { access = "medicalAdmin", debugOnly = true, handler = echo })
        local ctx = context()
        ctx.permissions.medicalAdmin = true
        assert.equal("debug_only", select(2, reg:dispatch(ctx, "debug.skip", {})))
        ctx.debugMode = true
        assert.is_true((reg:dispatch(ctx, "debug.skip", {})))
    end)

    it("rate-limits per sender and command over a sliding window", function()
        local reg, now = registry()
        reg:register("ping", { rate = { count = 2, seconds = 10 }, handler = echo })
        local doctor = context()
        local patient = context({ actor = { key = "patient" } })
        assert.is_true((reg:dispatch(doctor, "ping")))
        now.t = 5
        assert.is_true((reg:dispatch(doctor, "ping")))
        assert.equal("rate_limited", select(2, reg:dispatch(doctor, "ping")))
        assert.is_true((reg:dispatch(patient, "ping")))
        now.t = 10.5
        assert.is_true((reg:dispatch(doctor, "ping")))
    end)

    it("checks proximity to a target player, but not to yourself", function()
        local reg = registry()
        reg:register("exam", {
            args = { target = { type = "player" } },
            proximity = { arg = "target", tiles = 3 },
            handler = echo,
        })
        local ctx = context()
        assert.is_true((reg:dispatch(ctx, "exam", { target = "patient" })))
        assert.equal("too_far", select(2, reg:dispatch(ctx, "exam", { target = "faraway" })))
        assert.equal("no_target", select(2, reg:dispatch(ctx, "exam", { target = "ghost" })))
        ctx.distance = function() return nil end
        assert.equal("too_far", select(2, reg:dispatch(ctx, "exam", { target = "patient" })))
        assert.is_true((reg:dispatch(ctx, "exam", { target = "doctor" })))
    end)

    it("requires the target's consent permit, which expires", function()
        local reg = registry()
        reg:register("treat", {
            args = { target = { type = "player" } },
            consent = { arg = "target", purpose = "treat" },
            handler = echo,
        })
        local ctx = context()
        assert.equal("no_consent", select(2, reg:dispatch(ctx, "treat", { target = "patient" })))
        ctx.permits:grant("patient", "doctor", "exam", 0, 300)
        assert.equal("no_consent", select(2, reg:dispatch(ctx, "treat", { target = "patient" })))
        ctx.permits:grant("patient", "doctor", "treat", 0, 300)
        assert.is_true((reg:dispatch(ctx, "treat", { target = "patient" })))
        ctx.permitNow = 300
        assert.equal("no_consent", select(2, reg:dispatch(ctx, "treat", { target = "patient" })))
        assert.is_true((reg:dispatch(ctx, "treat", { target = "doctor" })))
    end)

    it("narrows a consent permit to one item and uses it up once", function()
        local reg = registry()
        reg:register("give", {
            args = { target = { type = "player" }, item = { type = "item" } },
            consent = { arg = "target", purpose = "medicate", detail = "item", once = true },
            handler = echo,
        })
        local ctx = context()
        ctx.permits:grant("patient", "doctor", "medicate", 0, 300)
        assert.equal("no_consent", select(2, reg:dispatch(ctx, "give", { target = "patient", item = 7 })))
        ctx.permits:grant("patient", "doctor", CommandRegistry.permitPurpose("medicate", 7), 0, 300)
        assert.is_true((reg:dispatch(ctx, "give", { target = "patient", item = 7 })))
        assert.equal("no_consent", select(2, reg:dispatch(ctx, "give", { target = "patient", item = 7 })))
        assert.has_error(function()
            reg:register("bad", { args = { target = { type = "player" } }, handler = echo,
                consent = { arg = "target", purpose = "x", detail = "item" } })
        end)
    end)

    it("runs action commands only from an action, without the rate limit", function()
        local reg = registry()
        reg:register("act", { action = true, rate = { count = 1, seconds = 10 }, handler = echo })
        local ctx = context()
        assert.equal("action_only", select(2, reg:dispatch(ctx, "act", {})))
        assert.is_true((reg:dispatch(ctx, "act", {}, { fromAction = true })))
        assert.is_true((reg:dispatch(ctx, "act", {}, { fromAction = true })))
    end)

    it("refuses bad registrations", function()
        local reg = registry()
        reg:register("a", { handler = echo })
        assert.has_error(function() reg:register("a", { handler = echo }) end)
        assert.has_error(function() reg:register("b", {}) end)
        assert.has_error(function() reg:register("c", { args = { x = { type = "table" } }, handler = echo }) end)
        assert.has_error(function()
            reg:register("d", { proximity = { arg = "target", tiles = 3 }, handler = echo })
        end)
    end)
end)

describe("Permits", function()
    it("grants per patient, actor and purpose, and forgets a player everywhere", function()
        local p = Permits.new()
        p:grant("patient", "doctor", "exam", 0, 10)
        p:grant("doctor", "patient", "exam", 0, 10)
        p:grant("other", "doctor", "exam", 0, 10)
        assert.is_true(p:check("patient", "doctor", "exam", 5))
        assert.is_false(p:check("patient", "nurse", "exam", 5))
        p:forget("doctor")
        assert.is_false(p:check("patient", "doctor", "exam", 5))
        assert.is_false(p:check("doctor", "patient", "exam", 5))
        assert.is_false(p:check("other", "doctor", "exam", 5))
    end)

    it("prunes expired permits", function()
        local p = Permits.new()
        p:grant("a", "b", "exam", 0, 10)
        p:grant("a", "c", "exam", 0, 30)
        p:prune(20)
        assert.is_nil(p.entries.a.b.exam)
        assert.is_true(p:check("a", "c", "exam", 20))
    end)
end)
