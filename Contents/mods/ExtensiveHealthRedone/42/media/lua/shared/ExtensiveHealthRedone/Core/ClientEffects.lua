-- Continuous effects only the owning client can carry out (movement, vision, sleep), collected per step like the stat
-- aggregator: systems state what they want, the strongest wish wins, and the result is written to state.effects,
-- which is synced only when it changes. The client applies state.effects every frame (Client/Effects).
--
--   p.fx:speed("blood", 0.8)       -- movement speed multiplier: the lowest wins
--   p.fx:noSprint("heatStroke")    -- no sprinting while any source asks
--   p.fx:blur("toxin", 0.6)        -- vision blur 0-1: the highest wins
--   p.fx:tint("delirium", 0.3)     -- delirium screen tint 0-1: the highest wins
--   p.fx:noSleep("insomnia")       -- natural sleep is blocked (bed and sleep prompts); sleepBy names why
--   p.fx:attackSpeed("med:combat", 2)  -- held weapon attack speed multiplier: the highest wins
--   p.fx:boost("med:lastChance", 1.2)  -- movement boost above normal speed: the highest wins
--   p.fx:bladder("dysentery", 14)      -- Lifestyle: Hobbies bathroom need, points per game hour: the sum of all sources
--                                      -- (negative eases it); the client adds it to Lifestyle's own number
--   p.fx:nightVision("myaddon:vitA", 0.7)  -- vision in the dark 0-1: dims and blurs only where it is dark (Client/Vision);
--                                          -- the highest wins
--   p.fx:aim("myaddon:tremor", 0.8)    -- ranged weapon hit chance multiplier (Client/Effects): the lowest wins

local ClientEffects = {}
ClientEffects.__index = ClientEffects

function ClientEffects.new()
    return setmetatable({ values = ClientEffects.defaults(), sources = {} }, ClientEffects)
end

function ClientEffects.defaults()
    return { speed = 1, noSprint = false, blur = 0, tint = 0, noSleep = false, sleepBy = false, attackSpeed = 1,
        boost = 1, bladder = 0, night = 0, aim = 1 }
end

-- When several sources block sleep, the message names the first of these (the stimulants say so themselves). Add-on
-- sources not listed come after these (Client/Sleep.registerReason gives them their own line).
ClientEffects.SLEEP_ORDER = { caffeine = 1, betaBlocker = 2, medInsomnia = 3, insomnia = 4 }

local function note(self, field, source)
    self.sources[field] = self.sources[field] or {}
    self.sources[field][#self.sources[field] + 1] = source
end

function ClientEffects:speed(source, multiplier)
    if multiplier < self.values.speed then
        self.values.speed = multiplier
    end
    note(self, "speed", source)
end

function ClientEffects:noSprint(source)
    self.values.noSprint = true
    note(self, "noSprint", source)
end

function ClientEffects:blur(source, level)
    if level > self.values.blur then
        self.values.blur = math.min(1, level)
    end
    note(self, "blur", source)
end

function ClientEffects:tint(source, level)
    if level > self.values.tint then
        self.values.tint = math.min(1, level)
    end
    note(self, "tint", source)
end

function ClientEffects:noSleep(source)
    self.values.noSleep = true
    local current = self.values.sleepBy
    local order = ClientEffects.SLEEP_ORDER
    if not current or (order[source] or 99) < (order[current] or 99) then
        self.values.sleepBy = source
    end
    note(self, "noSleep", source)
end

function ClientEffects:attackSpeed(source, multiplier)
    if multiplier > self.values.attackSpeed then
        self.values.attackSpeed = multiplier
    end
    note(self, "attackSpeed", source)
end

function ClientEffects:boost(source, multiplier)
    if multiplier > self.values.boost then
        self.values.boost = multiplier
    end
    note(self, "boost", source)
end

function ClientEffects:nightVision(source, level)
    if level > self.values.night then
        self.values.night = math.min(1, level)
    end
    note(self, "night", source)
end

function ClientEffects:aim(source, multiplier)
    if multiplier < self.values.aim then
        self.values.aim = math.max(0, multiplier)
    end
    note(self, "aim", source)
end

function ClientEffects:bladder(source, pointsPerHour)

    self.values.bladder = self.values.bladder + pointsPerHour
    note(self, "bladder", source)
end

-- Rounded so tiny changes don't cause a sync every step.
local function rounded(v)
    if type(v) == "number" then
        return math.floor(v * 100 + 0.5) / 100
    end
    return v
end

-- Writes the resolved values into the effects section. Returns true when something changed.
function ClientEffects:writeTo(section)
    local changed = false
    for field, value in pairs(self.values) do
        value = rounded(value)
        if section[field] ~= value then
            section[field] = value
            changed = true
        end
    end
    return changed
end

return ClientEffects
