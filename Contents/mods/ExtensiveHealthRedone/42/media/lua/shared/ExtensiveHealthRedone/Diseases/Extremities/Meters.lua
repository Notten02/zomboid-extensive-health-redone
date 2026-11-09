-- The extremities group's saved meters, in the exposure section's per-trigger scratch (no schema change):
--   exposure.data.extremities = { timers = {}, parts = { [part] = { ...meters in game hours } } }
-- Each condition keeps its own named meters on a part (blisters: frictionH; trench foot: wetColdH; frostbite: frost).

local Meters = {}

function Meters.get(p)
    local data = p.state.exposure.data
    if not data.extremities then
        data.extremities = { timers = {}, parts = {} }
    end
    return data.extremities
end

-- The meters of one part, created on first use.
function Meters.part(p, part)
    local parts = Meters.get(p).parts
    if not parts[part] then
        parts[part] = {}
    end
    return parts[part]
end

-- One named meter on a part (0 when never set).
function Meters.value(p, part, name)
    local m = Meters.get(p).parts[part]
    return m and m[name] or 0
end

-- Sets a meter, clamped to [0, max].
function Meters.set(p, part, name, value, max)
    Meters.part(p, part)[name] = math.max(0, math.min(max or math.huge, value))
end

-- Clears one named meter on every part (a condition's onEnd after a cure or a full heal).
function Meters.clear(p, name)
    for _, m in pairs(Meters.get(p).parts) do
        m[name] = nil
    end
end

return Meters
