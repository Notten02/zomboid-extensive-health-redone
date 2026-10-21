-- The per-player simulation pipeline. Features add systems; the server runs them in a fixed order for each online
-- player on every simulation step of the scheduler.
--
--   sim:add({ name = "blood", order = 200, update = function(p, dt) ... end })
--
-- p is the player context the server builds for one step (Server/Runtime):
--   p.key, p.state      the player's key and state (plain tables)
--   p.stats             a StatAggregator; the only way to change vanilla stats
--   p.body              a BodyAggregator; the only way to change body parts (health, healing, pain, infection)
--   p.fx                a ClientEffects; continuous effects the owning client applies (speed, sprint, blur, sleep)
--   p.facts             plain facts read from the game this step (Server/Facts: stats, sleep, body part wounds)
--   p.treatment         what medication does now: curing(id), relief(id, symptom), active(effect) (Core/Treatments)
--   p.dirty(section)    mark a state section changed so it is synced
--   p.say(key)          the character says a translated line (sent to the owning client)
--   p.client(cmd, args) a message to the owning client (blackout, fall)
--   p.noise(kind, args) a sound the character makes (Data/Noise: cough, sneeze, ...), heard by players and zombies
--   p.xp(kind, id)      First Aid XP for this player (Data/Xp: "cure" when a condition ends, ...)
--   p.rng               { float(), int(lo, hi) }
--   p.sandbox(name, default)
--   p.fresh             true on the first step after the player was attached (record baselines, don't react)
-- dt is in game minutes. Systems never see game objects.
--
-- Order: lower first, ties by name. Registration order and file load order never matter.

local Perf = require "ExtensiveHealthRedone/Core/Perf"

local Simulation = {}
Simulation.__index = Simulation

-- opts.perf: a Core/Perf that times each system while it is on.
function Simulation.new(opts)
    return setmetatable({ systems = {}, byName = {}, perf = opts and opts.perf or Perf.new() }, Simulation)
end

function Simulation:add(system)
    if type(system.name) ~= "string" or self.byName[system.name] then
        error("simulation systems need a unique name: " .. tostring(system.name), 2)
    end
    if type(system.update) ~= "function" then
        error("simulation system " .. system.name .. " needs update(p, dt)", 2)
    end
    local entry = { name = system.name, order = system.order or 100, update = system.update }
    self.byName[system.name] = entry
    self.systems[#self.systems + 1] = entry
    table.sort(self.systems, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.name < b.name
    end)
end

-- Sorted list of system names, in run order.
function Simulation:names()
    local names = {}
    for i, s in ipairs(self.systems) do
        names[i] = s.name
    end
    return names
end

function Simulation:run(p, dt)
    local perf = self.perf
    if perf.on then
        for _, system in ipairs(self.systems) do
            local t0 = perf.clock()
            system.update(p, dt)
            perf:stop("system", system.name, t0)
        end
        return
    end
    for _, system in ipairs(self.systems) do
        system.update(p, dt)
    end
end

return Simulation
