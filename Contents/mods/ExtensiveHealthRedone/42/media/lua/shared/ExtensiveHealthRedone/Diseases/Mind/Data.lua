-- Numbers for the mental conditions (delirium, insomnia, painkiller addiction) and pain sounds. From v0.9
-- (docs/porting/phase4/mental-knox-sounds.md) unless marked "ours". Stat targets are fractions of each stat's range
-- (the original's 0-1 numbers; its UNHAPPINESS x100 matches the 0-100 range). Time is game minutes; v0.9 per-tick
-- steps (every 60 ticks, about 2 real s) are multiplied by Symptoms.TICK per game minute.

local Data = {}

Data.delirium = {
    STRESS_THRESHOLD = 0.98,        -- share of the stress range
    TRIGGER_MINUTES = 12 * 60,      -- continuous minutes at the threshold, asleep or awake
    FIRST_EPISODE = { 4, 8 },       -- minutes after contracting
    EPISODE_EVERY = { 30, 60 },     -- minutes between episodes
    ANTIPSYCHOTIC_STRETCH = 2.5,    -- both delays x 2.5 while an antipsychotic dose is active
    TINT_MINUTES = { 4, 8 },
    TINT_ALPHA = { 0.08, 0.16 },
    IMPULSE_CHANCE = 1.0,
    ANTIPSYCHOTIC_IMPULSE_CHANCE = 0.40,
    -- id, weight, cooldown minutes; the order is the pick order.
    IMPULSES = {
        { id = "firearm", weight = 25, cooldown = 60 },
        { id = "dropBackpack", weight = 20, cooldown = 120 },
        { id = "window", weight = 30, cooldown = 60 },
        { id = "shout", weight = 35, cooldown = 45 },
    },
    WINDOW_RADIUS = 2,              -- tiles around the player, same floor
    -- Local hallucination sounds (media/scripts/EHR_Sounds.txt).
    SOUNDS = {
        "EHRDeliriumAliensSound", "EHRDeliriumBigBell", "EHRDeliriumCantSleepVoices", "EHRDeliriumChicken",
        "EHRDeliriumClownBackground", "EHRDeliriumClownJingle", "EHRDeliriumClownLaugh", "EHRDeliriumComicLaugh",
        "EHRDeliriumCreepyLaugh", "EHRDeliriumCreepyVoicesWhisper", "EHRDeliriumDevilishVoice",
        "EHRDeliriumHideClownSound", "EHRDeliriumSchoolBell", "EHRDeliriumStrangeWhispers",
        "EHRDeliriumTheyKnowNothingVoices", "EHRDeliriumWhisperVoicesA", "EHRDeliriumWhisperVoicesB",
    },
    LINES = {
        "UI_EHR_Text_AhahahaWhyMyLeftSockTellingMeToGrowACar",
        "UI_EHR_Text_NoNoNoYouPinkElephantIWontEatThatMushrooomHeHeHe",
        "UI_EHR_Text_PuPiPiTapiPuPipipiTapiPuPiPiTapiPuPipipiTapi",
        "UI_EHR_Text_WaitWhatIfImTheZombieOhNoThatsNotGoodRightIWanna",
        "UI_EHR_Text_HmYeaIThinkTheSameThatStewTheOtherDayWasTopNotch",
        "UI_EHR_Text_IIForgotHowToBreathINeedABowlOfNailsRightNow",
        "UI_EHR_Text_ShishICantConcentrateYouIdiotWhaitWhaWasIDoing",
        "UI_EHR_Text_HahaHaaaaWhatACuteSquirelButItsKindaBigIsThisA",
        "UI_EHR_Text_IWonderWhyAllOfMyCarsAlwaysComplainingCantYou",
        "UI_EHR_Text_IWannaFlyOhOhRightINeedToFindAGarbageBagAndUseIt",
        "UI_EHR_Text_TheFloorWasItAlwaysMadeFromNoodles",
    },
    -- Tint colours (r, g, b): red, green, blue, purple, amber, cyan.
    COLOURS = {
        { 0.90, 0.05, 0.04 }, { 0.12, 0.80, 0.26 }, { 0.18, 0.42, 1.00 },
        { 0.72, 0.20, 0.95 }, { 1.00, 0.72, 0.08 }, { 0.12, 0.82, 0.85 },
    },
}

Data.insomnia = {
    FATIGUE_THRESHOLD = 0.80,       -- share of the fatigue range, awake
    TRIGGER_MINUTES = 12 * 60,
    STIMULANT_CHANCE = 0.10,        -- on a stimulant crash
    STIMULANT_COOLDOWN = 12 * 60,
    -- Stage effects: targets (fractions) and steps per v0.9 tick; head pain on the Head part.
    STAGES = {
        [1] = { fatigue = 0.82, stress = 0.22, unhappiness = 0.10, headPain = 8 },
        [2] = { fatigue = 0.90, stress = 0.34, unhappiness = 0.18, headPain = 18 },
        [3] = { fatigue = 0.96, stress = 0.48, unhappiness = 0.28, headPain = 28 },
    },
    FATIGUE_STEP = 0.00075,
    STRESS_STEP = 0.00055,
    UNHAPPINESS_STEP = 0.00035,
    SLEEP_AID = { stress = 0.10, unhappiness = 0.08, headPain = 8 },
    -- Recovery (maintainer decision, Phase 4; ours): a good night is 6+ h asleep (at stage 2 only with a sleep aid);
    -- with tea before sleeping it counts double. GOOD_NIGHTS in a row drop one stage (2 -> 1, 1 -> cured). More than
    -- STREAK_GAP minutes without a good night breaks the streak.
    GOOD_SLEEP = 6 * 60,
    GOOD_NIGHTS = 3,
    TEA_NIGHTS = 2,
    STREAK_GAP = 30 * 60,
    -- Random lines: v0.9 rolled 1 in 24/12/8 about every 24 game minutes.
    LINE_EVERY = { [1] = 576, [2] = 288, [3] = 192 },
}

Data.addiction = {
    -- Items whose doses count toward dependency. W18 (decided): homemade painkillers are herbal (black sage,
    -- chamomile, lemongrass) and don't count; v0.9 counted them. Phase 5 adds the EHR pharmacy painkillers.
    PAINKILLERS = { ["Base.Pills"] = true },
    WINDOW = 24 * 60,               -- rolling window of counted doses
    DUPLICATE = 1.2,                -- minutes: a second report within this is the same dose (v0.9: 0.02 h)
    -- Risk per dose by doses in the window, this one included: 1-4 -> 1, 5 -> 8, 6 -> 12, 7+ -> 20.
    DOSE_RISK = { 1, 1, 1, 1, 8, 12 },
    EXCESS_RISK = 20,
    EARLY_MINUTES = 3 * 60,         -- a dose within 3 h of the last adds EARLY_RISK
    EARLY_RISK = 4,
    THRESHOLD = 100,
    DECAY_AFTER = 24 * 60,          -- decay only after a full day without a dose
    DECAY_PER_MINUTE = 50 / (24 * 60),
    ACTIVE_MINUTES = 3 * 60,        -- a painkiller dose suppresses withdrawal (and pain sounds) for 3 h
    BASE_SEVERITY = 0.8,            -- ours: v0.9's definition had none recorded in the spec
    STAGES = {
        [1] = { stress = 0.25, unhappiness = 0.25, thirst = 0.18 },
        [2] = { stress = 0.60, unhappiness = 0.60, thirst = 0.28 },
        [3] = { stress = 0.80, unhappiness = 1.00, thirst = 0.40 },
    },
    STRESS_STEP = 0.002,
    UNHAPPINESS_STEP = 0.002,
    THIRST_STEP = 0.00008,
    SUPPRESSED = { stress = 0.06, unhappiness = 0.05, step = 0.003 },
    LINE_EVERY = { [1] = 672, [2] = 384, [3] = 240 },
}

-- Pain sounds (W5: implemented; v0.9's module was never called). Ours: thresholds on the real pain scale, the chance
-- per game minute, and the "sudden pain" trigger.
Data.pain = {
    LEVELS = { 0.15, 0.40, 0.70 },  -- share of the pain range for levels 1, 2, 3
    RADIUS_SCALE = { 0.5, 0.75, 1.0 },
    VOLUME_SHARE = 0.6,             -- world noise volume = radius x this (v0.9 used 1, which barely registers)
    CHANCE = { 1 / 120, 1 / 40, 1 / 15 },   -- per game minute, off cooldown
    JUMP = 0.15,                    -- pain rising by this share in one step: a new injury, cried out 2 times in 3
    JUMP_CHANCE = 2 / 3,
    GAME_MINUTES_PER_REAL_SECOND = 0.4,     -- Phase 3 time base (default 1-hour day)
}

return Data
