-- Turns the loot data (Data/Loot, Data/LootFill) and the sandbox options into exactly what gets written: per target
-- list one entry per item, overlapping pools summed, scaled and gated. Pure: no game objects.
--
-- Options (Build.options reads them through a getter such as Env.sandbox):
--   medication  MedicationLootMultiplier, 0-2: scales every "med" pool; at 0 those add nothing and no rolls are raised
--   watch       MedicalWatchLootMultiplier, 0-1: scales the medical watch mirror
--   gates       { [option] = boolean }: pool contributions behind an option (HouseholdPrescriptionLoot)

local Build = {}

local function clamp(value, lo, hi, default)
    value = tonumber(value)
    if not value then
        return default
    end
    if value < lo then
        return lo
    end
    if value > hi then
        return hi
    end
    return value
end

-- A full item type: names without a module belong to ours.
function Build.fullType(module, name)
    if name:find(".", 1, true) then
        return name
    end
    return module .. "." .. name
end

function Build.options(get)
    return {
        medication = clamp(get("MedicationLootMultiplier", 1.0), 0, 2, 1.0),
        watch = clamp(get("MedicalWatchLootMultiplier", 1.0), 0, 1, 1.0),
        gates = { HouseholdPrescriptionLoot = get("HouseholdPrescriptionLoot", true) ~= false },
    }
end

function Build.sameOptions(a, b)
    return a.medication == b.medication and a.watch == b.watch
        and a.gates.HouseholdPrescriptionLoot == b.gates.HouseholdPrescriptionLoot
end

local function scaleOf(pool, options)
    if pool.scale == "med" then
        return options.medication
    end
    return 1
end

local function byName(a, b)
    return a.item < b.item
end

-- Heaviest first, so the most important trauma gear wins a bag's limited capacity.
local function byWeight(a, b)
    if a.chance ~= b.chance then
        return a.chance > b.chance
    end
    return a.item < b.item
end

-- One built target: { kind, list, minRolls?, front = { {item, chance} }, back = { {item, chance} } }.
function Build.target(data, target, options)
    local sums, isFront = {}, {}
    for _, add in ipairs(target.add) do
        local pool = data.pools[add.pool]
        assert(pool, "loot target " .. target.list .. " names an unknown pool " .. tostring(add.pool))
        local open = add.gate == nil or options.gates[add.gate] == true
        local mult = (add.mult or 1) * scaleOf(pool, options)
        if open and mult > 0 then
            for name, weight in pairs(pool.items) do
                local item = Build.fullType(data.MODULE, name)
                sums[item] = (sums[item] or 0) + weight * mult
                if add.front then
                    isFront[item] = true
                end
            end
        end
    end
    local built = { kind = target.kind, list = target.list, front = {}, back = {} }
    for item, chance in pairs(sums) do
        if chance > 0 then
            local side = isFront[item] and built.front or built.back
            side[#side + 1] = { item = item, chance = chance }
        end
    end
    table.sort(built.front, byWeight)
    table.sort(built.back, byName)
    if target.minRolls and options.medication > 0 and #built.front + #built.back > 0 then
        built.minRolls = target.minRolls
    end
    return built
end

-- Every target, in data order.
function Build.targets(data, options)
    local out = {}
    for i, target in ipairs(data.targets) do
        out[i] = Build.target(data, target, options)
    end
    return out
end

local function flatScaled(module, weights, mult)
    local list = {}
    for name, weight in pairs(weights) do
        if weight * mult > 0 then
            list[#list + 1] = { item = Build.fullType(module, name), chance = weight * mult }
        end
    end
    table.sort(list, byName)
    local flat = {}
    for _, entry in ipairs(list) do
        flat[#flat + 1] = entry.item
        flat[#flat + 1] = entry.chance
    end
    return flat
end

-- The Medicine Storage Box's own distribution table, scaled by the medication multiplier.
function Build.box(data, options)
    local box = data.box
    return {
        rolls = box.rolls,
        items = flatScaled(data.MODULE, box.items, options.medication),
        junk = { rolls = box.junkRolls, items = flatScaled(data.MODULE, box.junk, options.medication) },
    }
end

-- The zombie loot pool as a sorted list of { item, weight } (Data/LootFill zombie tiers plus blood bags).
function Build.zombiePool(zombie, lootData)
    local weights = {}
    for _, tier in ipairs(zombie.tiers) do
        for _, item in ipairs(tier.items) do
            weights[item] = (weights[item] or 0) + tier.weight
        end
    end
    for name, rarity in pairs(lootData.bloodRarity) do
        local item = Build.fullType(lootData.MODULE, name)
        weights[item] = (weights[item] or 0) + rarity * zombie.bloodMult
    end
    local pool = {}
    for item, weight in pairs(weights) do
        pool[#pool + 1] = { item = item, weight = weight }
    end
    table.sort(pool, function(a, b)
        return a.item < b.item
    end)
    return pool
end

return Build
