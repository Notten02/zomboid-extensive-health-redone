-- Medicinal plant search rules: the hidden board, picks, quality, and what a finished search finds. Pure: the random
-- source (rng.int(lo, hi), rng.float()) and item existence are passed in. Server/WildSearch keeps the board, so a
-- client only learns a cell's kind when it picks it.
-- From v0.9 c/EHR_HerbalSearch.lua:328-407 and sv/EHR_HerbalSearchServer.lua:272-555 (docs/porting/phase8/
-- herbal-and-hive-minigames.md sections 2-3). Changes: quality comes from the server's own counts and is not latched
-- to the best value seen (H2, H8); an Excellent run finds two herbs; the pools are weighted (H20).

local Data = require("ExtensiveHealthRedone/Data/WildSearch").herb

local HerbalBoard = {}

-- Access (checked on the server; the client only hides the menu option): the guide, or both skills high enough.
function HerbalBoard.canSearch(knowsGuide, firstAid, foraging)
    return knowsGuide == true or ((firstAid or 0) >= Data.ACCESS_FIRST_AID and (foraging or 0) >= Data.ACCESS_FORAGING)
end

-- 16 kinds ("target", "hazard", "decoy"), Fisher-Yates shuffled.
function HerbalBoard.newBoard(rng)
    local kinds = {}
    for i = 1, Data.CELLS do
        if i <= Data.TARGETS then
            kinds[i] = "target"
        elseif i <= Data.TARGETS + Data.HAZARDS then
            kinds[i] = "hazard"
        else
            kinds[i] = "decoy"
        end
    end
    for i = #kinds, 2, -1 do
        local j = rng.int(1, i)
        kinds[i], kinds[j] = kinds[j], kinds[i]
    end
    return kinds
end

-- 8 at Foraging 0-3, 9 at 4-7, 10 at 8-10.
function HerbalBoard.maxPicks(foraging)
    return math.min(Data.MAX_PICKS, Data.BASE_PICKS + math.floor((foraging or 0) / 4))
end

-- What picking a cell counts as: "hit", "hazard" or "miss" (a decoy, or cell 0 = empty space).
function HerbalBoard.outcome(kind)
    if kind == "target" then
        return "hit"
    elseif kind == "hazard" then
        return "hazard"
    end
    return "miss"
end

function HerbalBoard.quality(hits, misses, hazards, firstAid, foraging)
    local Q = Data.QUALITY
    local skill = math.min(1, ((firstAid or 0) + (foraging or 0)) / Q.SKILL_DIVISOR)
    local q = Q.BASE + (hits / Data.REQUIRED_HITS) * Q.HIT + skill * Q.SKILL - misses * Q.MISS - hazards * Q.HAZARD
    return math.max(Q.MIN, math.min(Q.MAX, q))
end

-- "excellent", "good", "rough" or "poor".
function HerbalBoard.band(quality)
    if quality >= Data.BANDS.EXCELLENT then
        return "excellent"
    elseif quality >= Data.BANDS.GOOD then
        return "good"
    elseif quality >= Data.BANDS.ROUGH then
        return "rough"
    end
    return "poor"
end

-- Find chance in percent. zoneClass: Wild/Vegetation.zoneClass; month 1-12.
function HerbalBoard.findChance(zoneClass, month, quality, firstAid, foraging)
    local base = Data.ZONE_BASE[zoneClass] or Data.ZONE_BASE.other
    local season = Data.SEASON[month] or 1
    local bonus = math.min(Data.SKILL_BONUS_MAX, ((firstAid or 0) + (foraging or 0)) * Data.SKILL_BONUS)
    local chance = base * season * (Data.CHANCE_Q0 + quality * Data.CHANCE_Q) + bonus
    return math.max(Data.CHANCE_MIN, math.min(Data.CHANCE_MAX, chance))
end

-- Chance in percent that a find comes from the rare pool.
function HerbalBoard.rareChance(quality, foraging)
    return Data.RARE_BASE + math.floor(quality * Data.RARE_Q) + math.floor((foraging or 0) * Data.RARE_FORAGING)
end

-- A weighted pick from a pool of { fullType, weight }, keeping only types for which exists(fullType) is true
-- (nil = all). Returns the full type, or nil when nothing in the pool exists.
function HerbalBoard.choose(pool, rng, exists)
    local total = 0
    for _, entry in ipairs(pool) do
        if not exists or exists(entry[1]) then
            total = total + entry[2]
        end
    end
    if total <= 0 then
        return nil
    end
    local roll = rng.int(1, total)
    for _, entry in ipairs(pool) do
        if not exists or exists(entry[1]) then
            roll = roll - entry[2]
            if roll <= 0 then
                return entry[1]
            end
        end
    end
    return nil
end

-- The roll at the end of a search. s: { hits, misses, hazards, firstAid, foraging, zoneClass, month }.
-- Returns { quality, band, found = bool, item = fullType|nil, count, rare = bool }.
function HerbalBoard.roll(s, rng, exists)
    local q = HerbalBoard.quality(s.hits, s.misses, s.hazards, s.firstAid, s.foraging)
    local result = { quality = q, band = HerbalBoard.band(q), found = false, count = 0, rare = false }
    local chance = HerbalBoard.findChance(s.zoneClass, s.month, q, s.firstAid, s.foraging)
    if rng.float() * 100 >= chance then
        return result
    end
    local item
    if rng.int(0, 99) < HerbalBoard.rareChance(q, s.foraging) then
        item = HerbalBoard.choose(Data.RARE, rng, exists)
        result.rare = item ~= nil
    end
    item = item or HerbalBoard.choose(Data.COMMON, rng, exists)
    if not item then
        return result
    end
    result.found, result.item = true, item
    result.count = 1 + (result.band == "excellent" and Data.EXCELLENT_BONUS or 0)
    return result
end

return HerbalBoard
