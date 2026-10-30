-- Numbers for the two wild searches: the medicinal plant search (herbal) and the hive and spiderweb search (hive).
-- Rules: Wild/HerbalBoard, Wild/HiveTree, Wild/SpotCooldowns, Wild/Search; the authority is Server/WildSearch.
--
-- Only real bushes outdoors (canBeCut), at a fixed hash density; one herb per find, two on an Excellent run;
-- Base.LemonGrass in the common pool, berries at half weight; a winter multiplier; cancelling with no pick is free,
-- after a pick the spot is spent; any intact HANDS item counts as gloves and loses 1 condition per hit; injuries on a
-- hand or forearm; no skill scaling in the hive game; instant retry after a sting; at least 1 s before the first hive
-- grab.

local WildSearch = {}

-- Server-only global ModData table for cooldowns and tree contents (never transmitted).
WildSearch.STORE_TAG = "ExtensiveHealthRedone_WildSearch"

-- Distances in tiles from the player to the searched square's centre, same floor only.
WildSearch.BEGIN_RANGE = 2.5        -- the walk ends next to the bush or tree
WildSearch.PLAY_RANGE = 4.5         -- while playing

WildSearch.herb = {
    -- Who may search: the Wild Medicinal Plants guide read, or First Aid and Foraging both at least this.
    ACCESS_FIRST_AID = 4,
    ACCESS_FORAGING = 4,

    CELLS = 16,                     -- a 4 x 4 board
    TARGETS = 5,
    HAZARDS = 2,                    -- the other 9 are decoys
    REQUIRED_HITS = 3,
    SECONDS = 42,                   -- real time
    GRACE = 3,                      -- extra seconds before the server closes a session itself
    TIME_TOLERANCE = 2,             -- a client's "time is up" is accepted this much early (latency)
    COOLDOWN_HOURS = 48,            -- per bush square, game hours

    -- maxPicks = min(MAX_PICKS, BASE_PICKS + floor(Foraging / 4)): 8 / 9 / 10
    BASE_PICKS = 8,
    MAX_PICKS = 10,

    -- quality = BASE + hits/3 * HIT + skill * SKILL - misses * MISS - hazards * HAZARD, clamped; skill =
    -- min(1, (First Aid + Foraging) / SKILL_DIVISOR).
    QUALITY = { BASE = 0.18, HIT = 0.58, SKILL = 0.14, SKILL_DIVISOR = 16, MISS = 0.08, HAZARD = 0.12,
        MIN = 0.05, MAX = 1.0 },
    BANDS = { EXCELLENT = 0.82, GOOD = 0.60, ROUGH = 0.38 },

    -- Find chance (%) = zoneBase * season * (CHANCE_Q0 + q * CHANCE_Q) + min(SKILL_BONUS_MAX, (FA + Fo) *
    -- SKILL_BONUS), clamped to CHANCE_MIN..CHANCE_MAX.
    CHANCE_Q0 = 0.42,
    CHANCE_Q = 0.96,
    SKILL_BONUS = 0.75,
    SKILL_BONUS_MAX = 12,
    CHANCE_MIN = 4,
    CHANCE_MAX = 78,
    -- Rare pool chance (%) = RARE_BASE + floor(q * RARE_Q) + floor(Foraging * RARE_FORAGING).
    RARE_BASE = 8,
    RARE_Q = 18,
    RARE_FORAGING = 1.2,
    -- Herbs per find: 1, plus 1 at Excellent quality.
    EXCELLENT_BONUS = 1,

    -- Zone classes (Wild/Vegetation.zoneClass): menu density (% of bush squares that are a search patch, by the
    -- square hash) and the base find chance.
    DENSITY = { deepForest = 68, forest = 56, vegitation = 46, farm = 34, other = 24 },
    ZONE_BASE = { deepForest = 46, forest = 37, vegitation = 30, farm = 24, other = 16 },
    -- By 1-based month: Dec-Feb x0.58, Apr-Aug x1.15, Mar and Sep-Nov x0.92.
    SEASON = { 0.58, 0.58, 0.92, 1.15, 1.15, 1.15, 1.15, 1.15, 0.92, 0.92, 0.92, 0.58 },

    -- { fullType, weight }. Berries at half weight; LemonGrass is needed by two medicine recipes.
    COMMON = {
        { "Base.Plantain", 2 }, { "Base.CommonMallow", 2 }, { "Base.Chamomile", 2 }, { "Base.Marigold", 2 },
        { "Base.Lavender", 2 }, { "Base.WildGarlic2", 2 }, { "Base.LemonGrass", 2 },
        { "Base.BerryBlack", 1 }, { "Base.BerryBlue", 1 }, { "Base.BerryGeneric1", 1 }, { "Base.BerryGeneric2", 1 },
        { "Base.BerryGeneric3", 1 }, { "Base.BerryGeneric4", 1 }, { "Base.BerryGeneric5", 1 },
    },
    RARE = { { "Base.BlackSage", 1 }, { "Base.Comfrey", 1 }, { "Base.Ginseng", 1 } },
}

WildSearch.hive = {
    CONTENT_CHANCE = 40,            -- % of trees with anything
    HIVE_CHANCE = 32,               -- % of those with a hive
    WEBS = { 35, 30, 22, 13 },      -- % for 0, 1, 2, 3 webs; no hive and no web becomes 1 web
    MAX_WEBS = 3,
    SECONDS = 48,
    GRACE = 3,
    MIN_REACH_S = 1.0,              -- from the session start to the first grab
    MIN_GAP_S = 0.5,                -- between two grabs
    COOLDOWN_HOURS = 48,            -- an empty or emptied tree, game hours
    FORGET_HOURS = 168,             -- a tree that still holds something, unvisited this long, is forgotten
    HONEYCOMB = "ExtensiveHealth.Honeycomb",
    SPIDERWEB = "ExtensiveHealth.Spiderweb",
}

-- Thorns, stings and bites: the part hurt when no gloves are worn (Hand 50%, ForeArm 50%, side random).
WildSearch.INJURY_PARTS = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R" }
WildSearch.GLOVE_WEAR = 1           -- condition lost per hit absorbed

return WildSearch
