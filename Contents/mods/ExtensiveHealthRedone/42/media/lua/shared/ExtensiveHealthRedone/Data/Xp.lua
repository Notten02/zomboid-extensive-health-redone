-- First Aid XP for medical actions, times FirstAidXPMultiplier, none with FirstAidXPEnabled off. Server/Xp awards it.
--
-- A medication cure gives the cure XP as natural recovery does, and a dose gives the "take" XP at most once per
-- medication interval (at least 30 minutes, Medication/Doses), so cheap doses can't be farmed.
--
-- A flyer gives XP only when it teaches something new, the Wild Plants guide on its first read, the 09:00 radio tip
-- once per broadcast heard, a herb once per herb found. The two wild searches also give Foraging XP: one per finished
-- herb search, one per hive or web item.

local Xp = {}

Xp.AMOUNTS = {
    take = 5,           -- a dose taken or given
    treat = 3,          -- the dose acted on an active condition
    cure = 20,          -- a condition ended, cured or recovered (sepsis: + 25)
    transfusion = 10,   -- a blood bag given (to yourself or another player)
    saline = 5,         -- a saline bag given
    flyer = 50,         -- a disease flyer read that taught something new
    wildPlants = 50,    -- the Wild Medicinal Plants guide, first read
    radioTip = 4,       -- the 09:00 medical tip on 47.0 MHz, heard to the end
    herb = 2,           -- a herb found in the medicinal plant search
    forage = 1,         -- Foraging: a finished herb search, a honeycomb or spiderweb found
}

-- The skill each kind trains: a Perks field name. First Aid (Perks.Doctor) unless listed.
Xp.PERKS = { forage = "PlantScavenging" }

function Xp.perk(kind)
    return Xp.PERKS[kind] or "Doctor"
end

Xp.CURE_BONUS = { sepsis = 25 }

-- XP for one award. sandbox(name, default) reads the options. Returns a whole number (0 = nothing).
-- FirstAidXPEnabled and FirstAidXPMultiplier apply to First Aid only; the wild searches' Foraging XP is vanilla's
-- usual small amount and has no option of its own.
function Xp.amount(kind, id, sandbox)
    local base = Xp.AMOUNTS[kind] or 0
    if Xp.perk(kind) ~= "Doctor" then
        return base
    end
    if sandbox("FirstAidXPEnabled", true) == false then
        return 0
    end
    if kind == "cure" and id then
        base = base + (Xp.CURE_BONUS[id] or 0)
    end
    local mult = tonumber(sandbox("FirstAidXPMultiplier", 1)) or 1
    return math.max(0, math.floor(base * mult))
end

return Xp
