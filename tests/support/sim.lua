-- A player context for testing simulation systems without the game (the shape Server/Runtime builds).
--
--   local p = Sim.context({ sandbox = { BloodLossMultiplier = 1 }, floats = { 0.1 } })
--   p.facts.parts.Neck.bleeding = true
--   Blood.update(p, 1)
--   Sim.step(p)        -- fresh aggregators for the next step; state, facts and records stay
--
-- Records: p.said (keys), p.sent ({ command, args }), p.noises ({ kind, args }), p.xps ({ kind, id }),
-- p.dirtied ([section] = count).
-- Random: rng.float() returns the queued floats in order, then opts.float (default 0.99, i.e. "nothing happens");
-- rng.int(lo, hi) returns lo unless ints are queued.
-- Immunity: a fresh state starts at the neutral score (no effect on any roll), so tests of base chances don't depend
-- on the new-character score; immunity tests set their own.

local Schema = require("ExtensiveHealthRedone/Core/Schema")
local StatAggregator = require("ExtensiveHealthRedone/Core/StatAggregator")
local BodyAggregator = require("ExtensiveHealthRedone/Core/BodyAggregator")
local ClientEffects = require("ExtensiveHealthRedone/Core/ClientEffects")
local Modifiers = require("ExtensiveHealthRedone/Core/Modifiers")
local PerkAggregator = require("ExtensiveHealthRedone/Core/PerkAggregator")
local Treatments = require("ExtensiveHealthRedone/Core/Treatments")
local BodyParts = require("ExtensiveHealthRedone/Data/BodyParts")
local ImmunityData = require("ExtensiveHealthRedone/Data/Immunity")

local Sim = {}

Sim.RANGES = {
    SICKNESS = { min = 0, max = 1 }, FATIGUE = { min = 0, max = 1 }, ENDURANCE = { min = 0, max = 1 },
    THIRST = { min = 0, max = 1 }, HUNGER = { min = 0, max = 1 }, STRESS = { min = 0, max = 1 },
    PAIN = { min = 0, max = 100 }, PANIC = { min = 0, max = 100 }, FOOD_SICKNESS = { min = 0, max = 100 },
    TEMPERATURE = { min = 20, max = 45 },
    UNHAPPINESS = { min = 0, max = 100 },
    DISCOMFORT = { min = 0, max = 100 },
}

function Sim.rng(opts)
    opts = opts or {}
    local floats, ints = opts.floats or {}, opts.ints or {}
    return {
        float = function()
            if #floats > 0 then
                return table.remove(floats, 1)
            end
            return opts.float or 0.99
        end,
        int = function(lo, hi)
            if #ints > 0 then
                return table.remove(ints, 1)
            end
            return lo
        end,
    }
end

-- A treatment provider for tests: { curing = { id = true }, relief = { ["id.symptom"] = n }, active = { e = true } }
function Sim.treatment(t)
    t = t or {}
    return {
        curing = function(_, id) return (t.curing or {})[id] == true end,
        relief = function(_, id, symptom) return (t.relief or {})[id .. "." .. symptom] or 0 end,
        active = function(_, effect) return (t.active or {})[effect] == true end,
    }
end

function Sim.facts()
    local parts = {}
    for _, name in ipairs(BodyParts.names) do
        parts[name] = { health = 100 }
    end
    return { health = 100, asleep = false, inVehicle = false, firstAid = 0, stats = {}, norm = {}, parts = parts,
        env = { airC = 20, vehicleC = nil, indoors = false, shade = false, wetness = 0, raining = false,
            snowing = false, groundSnow = false, hour = 12, month = 7, sitOnGround = false, moving = false,
            running = false, sprinting = false, exerting = false, naturalFloor = false, female = false } }
end

function Sim.neutralState()
    local state = Schema.new({ int = function(lo) return lo end })
    state.immunity.score = ImmunityData.NEUTRAL
    return state
end

function Sim.context(opts)
    opts = opts or {}
    local rng = Sim.rng(opts)
    local sandbox = opts.sandbox or {}
    local p = {
        key = "sp:0",
        state = opts.state or Sim.neutralState(),
        stats = StatAggregator.new(Sim.RANGES),
        body = BodyAggregator.new(),
        fx = ClientEffects.new(),
        mods = Modifiers.new(),
        perks = PerkAggregator.new(),
        facts = Sim.facts(),
        rng = rng,
        treatment = opts.treatment and Sim.treatment(opts.treatment) or Treatments.none,
        fresh = false,
        said = {},
        sent = {},
        dirtied = {},
    }
    p.sandbox = function(name, default)
        local value = sandbox[name]
        if value == nil then
            return default
        end
        return value
    end
    p.dirty = function(section) p.dirtied[section] = (p.dirtied[section] or 0) + 1 end
    p.say = function(key) p.said[#p.said + 1] = key end
    p.client = function(command, args) p.sent[#p.sent + 1] = { command, args } end
    p.xps = {}
    p.xp = function(kind, id) p.xps[#p.xps + 1] = { kind, id } end
    p.noises = {}
    p.noise = function(kind, args) p.noises[#p.noises + 1] = { kind, args or {} } end
    return p
end

-- Starts a new step: fresh aggregators. Returns p.
function Sim.step(p)
    p.stats = StatAggregator.new(Sim.RANGES)
    p.body = BodyAggregator.new()
    p.fx = ClientEffects.new()
    p.mods = Modifiers.new()
    p.perks = PerkAggregator.new()
    return p

end

-- Whether key was said.
function Sim.said(p, key)
    for _, k in ipairs(p.said) do
        if k == key then
            return true
        end
    end
    return false
end

-- The value a stat would get from current.
function Sim.resolve(p, stat, current)
    return (p.stats:resolve(stat, current))
end

return Sim
