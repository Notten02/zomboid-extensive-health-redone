-- Spawn-time loot rules (Data/LootFill): where a filled container is, how many doses a spawned package keeps, which
-- Knox facility items a container rolls, and what a dead zombie carries. Pure: rng is { float(), int(lo, hi) }
-- (Env.rng in game).

local Fill = {}

-- "Base.VanAmbulance" -> "vanambulance"; nil -> "".
local function key(name)
    if name == nil then
        return ""
    end
    name = tostring(name)
    return string.lower(name:match("^[^.]+%.(.+)$") or name)
end

-- The location class of a container: the room first, then household furniture, else "default".
function Fill.location(data, roomType, containerType)
    local byRoom = data.rooms[key(roomType)]
    if byRoom then
        return byRoom
    end
    if data.householdContainers[key(containerType)] then
        return "household"
    end
    return "default"
end

-- A kit or bag filled inside a container: its own class (Data/LootFill subContainers), else the outer one.
function Fill.subLocation(data, itemType, outer)
    return data.subContainers[itemType] or outer
end

-- The MedicationPackageFill profile (1-4), defaulting to Normal.
function Fill.profile(data, setting)
    return data.profiles[tonumber(setting) or data.defaultProfile] or data.profiles[data.defaultProfile]
end

-- How many of maxUses doses a freshly spawned package keeps (v0.9 MS:214-266). A one-use item stays full. Pharmacy
-- packages are sometimes full when allowFull (AllowFullPharmacyPackages).
function Fill.doses(maxUses, profile, location, allowFull, rng)
    if maxUses <= 1 then
        return maxUses
    end
    if location == "pharmacy" and allowFull and rng.float() < profile.pharmacyFull then
        return maxUses
    end
    local range = profile.ranges[location] or profile.ranges.default
    local low = math.max(1, math.ceil(maxUses * range[1]))
    local high = math.min(maxUses, math.max(low, math.floor(maxUses * range[2])))
    if high <= low then
        return low
    end
    return rng.int(low, high)
end

-- The Knox item list for a container at x, y, z, or nil when it is not a facility basement container.
function Fill.knoxItems(knox, x, y, z, containerType)
    if x < knox.minX or x > knox.maxX or y < knox.minY or y > knox.maxY then
        return nil
    end
    if not knox.containers[key(containerType)] then
        return nil
    end
    for _, level in ipairs(knox.levels) do
        if z <= level.top and z >= level.bottom then
            return level.items
        end
    end
    return nil
end

-- Each item rolls on its own, chance in percent (v0.9 KD:105-108). Returns the item types that spawn.
function Fill.knoxRoll(items, rng)
    local out = {}
    for _, entry in ipairs(items) do
        if rng.int(1, 100) <= entry.chance then
            out[#out + 1] = entry.item
        end
    end
    return out
end

-- A percent chance (ZombieLootChance).
function Fill.percent(chance, rng)
    return chance > 0 and rng.float() * 100 < chance
end

-- A weighted pick from a Build.zombiePool list.
function Fill.pick(pool, rng)
    local total = 0
    for _, entry in ipairs(pool) do
        total = total + entry.weight
    end
    if total <= 0 then
        return nil
    end
    local roll = rng.float() * total
    for _, entry in ipairs(pool) do
        roll = roll - entry.weight
        if roll < 0 then
            return entry.item
        end
    end
    return pool[#pool].item
end

return Fill
