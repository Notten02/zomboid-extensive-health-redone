-- Pain sounds: a character in real pain cries out now and then, louder the worse it is, and the cry draws zombies
-- within ZombieAttractionRadius. A sudden jump in pain (a fresh injury) makes a cry likely at once. Nothing while
-- asleep, while a painkiller dose works, during the PainSoundCooldown, or with PainSoundsEnabled off. The sounds are
-- vanilla's own pain voices (Data/Noise pain, painSevere).

local Data = require("ExtensiveHealthRedone/Diseases/Mind/Data").pain
local Addiction = require "ExtensiveHealthRedone/Diseases/Mind/Addiction"
local Chance = require "ExtensiveHealthRedone/Core/Chance"

local PainSounds = {}

-- 0 (no cry) to 3, from the share of the pain range.
function PainSounds.level(pain)
    local level = 0
    for i, threshold in ipairs(Data.LEVELS) do
        if pain >= threshold then
            level = i
        end
    end
    return level
end

-- PainSoundCooldown is in real seconds (60-900, default 300); the simulation runs on game minutes.
function PainSounds.cooldownMinutes(p)
    local seconds = math.max(60, math.min(900, tonumber(p.sandbox("PainSoundCooldown", 300)) or 300))
    return seconds * Data.GAME_MINUTES_PER_REAL_SECOND
end

function PainSounds.radius(p, level)
    local radius = math.max(10, math.min(100, tonumber(p.sandbox("ZombieAttractionRadius", 40)) or 40))
    return math.floor(radius * Data.RADIUS_SCALE[level] + 0.5)
end

function PainSounds.update(p, dt)
    local mind = p.state.mind
    local pain = p.facts.norm.PAIN or 0
    local last = mind.painLast or pain
    mind.painLast = pain
    if mind.painCooldown and mind.painCooldown > 0 then
        mind.painCooldown = math.max(0, mind.painCooldown - dt)
    end
    if p.fresh or p.facts.asleep or p.sandbox("PainSoundsEnabled", true) == false then
        return
    end
    local level = PainSounds.level(pain)
    if level == 0 or (mind.painCooldown or 0) > 0 or Addiction.painkillerActive(p) then
        return
    end
    local chance
    if pain - last >= Data.JUMP then
        chance = Data.JUMP_CHANCE
    else
        chance = Chance.over(Data.CHANCE[level], 1, dt)
    end
    if not Chance.roll(p.rng, chance) then
        return
    end
    local radius = PainSounds.radius(p, level)
    p.noise(level >= 3 and "painSevere" or "pain",
        { muffle = false, radius = radius, volume = math.floor(radius * Data.VOLUME_SHARE + 0.5) })
    mind.painCooldown = PainSounds.cooldownMinutes(p)
end

return PainSounds
