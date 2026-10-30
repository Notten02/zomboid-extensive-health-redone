-- Wound infection, tetanus triggers and stitching. Hours are game hours, divided by the speed option.

return {
    infection = {
        INCUBATION_HOURS = 12,
        STAGE_HOURS = { 12, 24, 48 },       -- stage 1, 2, 3; the end of stage 3 hands off to sepsis
        PAIN = { 0, 10, 30 },               -- extra pain on the infected part per stage
        FEVER_STAGE = 3,
        FEVER_C = 38.0,
        FEVER_STEP = 0.0125,                -- deg C per game minute
        HEAL_FACTOR = { 0.75, 0.5, 0 },     -- stage 1/2/3 heal 25/50/100% slower
        VANILLA_EPSILON = 0.05,             -- vanilla infection level above this counts as infected
        -- Immune containment, rolled once per incubation: chance = (score - 20) / 80 * 0.45, at most 0.65.
        CONTAIN_FROM = 20, CONTAIN_SPAN = 80, CONTAIN_SCALE = 0.45, CONTAIN_MAX = 0.65,
        LINES = {
            "UI_EHR_Text_ThisWoundLooksInfected",
            "UI_EHR_Text_WincesTheInfectionIsGettingWorse",
            "UI_EHR_Text_GaspsThisInfectionIsCriticalINeedAntibioticsNow",
        },
        SEPSIS_LINE = "UI_EHR_Text_TheInfectionIsInMyBloodImBurningUp",
        PREVENTED_LINE = "UI_EHR_Text_GoodThingIDisinfectedThatEarly",
        STILL_INFECTED_LINE = "UI_EHR_Text_ICleanedItButTheInfectionIsStillThere",
    },

    tetanus = {
        -- Deep wound with lodged glass: roll at once, then every 12 h while it stays, 40 % rising by 15 % per
        -- 12 h up to 70 %. All chances x TetanusChanceMultiplier.
        GLASS_FIRST = 0.40, GLASS_STEP = 0.15, GLASS_MAX = 0.70, GLASS_EVERY_HOURS = 12,
        -- Other triggers:
        CRASH = 0.40,               -- a deep wound that appears while in a vehicle (a crash)
        WALK_GLASS = 0.20,          -- glass that appears in a foot while not in a vehicle (walking on glass)
        DIRTY = 0.15, DIRTY_EVERY_HOURS = 12,   -- a deep wound left unbandaged or under a dirty bandage
        LINE = "UI_EHR_Text_ThatWasANastyWoundHopeItDoesntGetInfected",
    },

    stitch = {
        POINTS = 12,
        MISS_QUALITY = 0.13,        -- quality = max(MIN_QUALITY, 1 - misses * MISS_QUALITY)
        MIN_QUALITY = 0.35,
        GREAT = 0.90, STABLE = 0.72, ROUGH = 0.55,   -- quality bands: >= GREAT excellent, >= STABLE, >= ROUGH, else poor
        CELLULITIS_CHANCE = 0.40,   -- rough or poor stitch, and a failed or cancelled attempt below STABLE
        VERY_POOR_INFECTION = 0.30, -- poor stitch: chance of a vanilla wound infection if the wound wasn't infected
        PAIN = { great = -5, rough = 5, poor = 12, failed = 10 },
        RANGE = 3,                  -- tiles to the patient
        SESSION_SECONDS = 180,      -- a minigame session must report within this real time
        RESULT_SECONDS = 120,       -- a success must be followed by the vanilla stitch within this real time
        ABORT_WINDOW_SECONDS = 180, -- a failed stitch on someone else harms a part once in this real time
        -- The fastest plausible click rate on the moving points. A success reported sooner than
        -- POINTS * MIN_SECONDS_PER_POINT real seconds (12 * 0.35 = 4.2 s) after stitch.begin counts as poor.
        MIN_SECONDS_PER_POINT = 0.35,
        -- What vanilla's stitch menu accepts (ISHealthPanel HStitch): a suture needle, or a sewing needle and thread
        -- (item type, or the vanilla ItemTag name).
        ITEMS = { suture = "SutureNeedle", needle = "Needle", thread = "Thread",
                  needleTag = "SEWING_NEEDLE", threadTag = "THREAD" },
        FAIL_LINE = "UI_EHR_StitchMinigame_FailLine",
    },
}
