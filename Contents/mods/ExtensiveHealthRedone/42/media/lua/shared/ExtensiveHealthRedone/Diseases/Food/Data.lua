-- Numbers for the food-borne diseases and dysentery. Only visible hand soil counts, and relief never lifts the
-- dysentery caps.
--
-- Time base: per-check numbers are per check of the original mod's disease engine, which ran every 0.8 game minutes
-- (TICK = 1.25 per game minute), and for dysentery of its environmental loop, every 1.2 game minutes (DYS_TICK = 50/60
-- per game minute).

local Data = {}

Data.TICK = 1.25
Data.DYS_TICK = 50 / 60

-- Food risk accumulation: repeated risky bites stack, decaying per game hour; at GUARANTEED a bite
-- contracts for sure (immunity still applies), and a failed roll keeps the total.
Data.RISK = {
    DECAY_PER_HOUR = 0.20,
    MAX_CHANCE = 0.95,
    GUARANTEED = 0.80,
    -- Queasy before any disease exists: SICKNESS (0-1) toward min(PENDING_MAX, risk * PENDING_SCALE).
    PENDING_SCALE = 0.45,
    PENDING_MAX = 0.24,
    PENDING_STEP = 0.01,        -- per game minute
}

-- Base chances per bite, before x portion x the disease's chance multiplier.
Data.FOOD = {
    ROTTEN = 0.70,
    BURNED = 0.05,
    STALE = 0.10,
    UNCOOKED = 0.35,            -- DangerousUncooked eaten raw, or an uncooked prepared dish
    TRICHINOSIS = 0.70,         -- raw wild game or pork
}

-- Trichinosis sources (guide: rat, mouse, rabbit and other small game, boar, bear, fox, raccoon, wolf, raw pork).
-- Full types, not substring matching, which would hit "Water Ration" and miss rabbit and squirrel.
Data.TRICHINOSIS_TYPES = {
    ["Base.DeadRat"] = true, ["Base.DeadRatSkinned"] = true, ["Base.DeadRatBaby"] = true,
    ["Base.DeadRatBabySkinned"] = true, ["Base.RatKing"] = true,
    ["Base.DeadMouse"] = true, ["Base.DeadMouseSkinned"] = true, ["Base.DeadMousePups"] = true,
    ["Base.DeadMousePupsSkinned"] = true,
    ["Base.Smallanimalmeat"] = true, ["Base.Rabbitmeat"] = true, ["Base.DeadRabbit"] = true,
    ["Base.DeadSquirrel"] = true,
    ["Base.Pork"] = true, ["Base.PorkChop"] = true, ["Base.Bacon"] = true, ["Base.BaconRashers"] = true,
    ["Base.BaconBits"] = true,
}
-- Modded meat: an item type containing one of these words and "meat" (BoarMeat, BearMeat, ...), unless preserved.
Data.TRICHINOSIS_ANIMALS = { "boar", "bear", "fox", "raccoon", "wolf" }
Data.PRESERVED_WORDS = { "jerky", "dried", "dehydrated", "smoked", "salted", "cured", "corned", "canned", "tinned",
    "pepperoni", "salami", "rinds", "spam" }

-- Cookable dishes that are risky when eaten before cooking.
Data.PREPARED_WORDS = { "recipe", "waterpot", "waterpan", "potof", "potforged", "fryingpan", "saucepan", "pizza",
    "fries", "tatodots", "tvdinner", "soup", "stew", "pasta", "rice", "omelette", "pie", "dumpling" }

-- Hand soil (visible blood and dirt on the hands, HumanVisual 0-1 averaged over both hands).
Data.HANDS = {
    BLOOD = 0.15,
    DIRT = 0.08,
    MIN = 0.05,                 -- below this, clean enough
    MAX = 0.33,                 -- the highest chance hand soil gives
}

-- Dysentery risk per drink, by water source. Boiled and tap water are safe.
Data.WATER = {
    toilet = 0.50,
    tainted = 0.25,
    river = 0.15,
    rainCollector = 0.05,
    tap = 0,
}

Data.VOMIT_LINES = { "UI_EHR_Text_Vomits", "UI_EHR_Food_RetchesViolently", "UI_EHR_Food_ThrowsUp" }
Data.DIZZY_LINES = { "UI_EHR_Text_DizzyWorldsSpinning", "UI_EHR_Food_Stumbles", "UI_EHR_Food_SwaysCantFocus" }
Data.CRAMP_LINES = { "UI_EHR_Text_CrampsOwMyLeg", "UI_EHR_Food_MusclesSeizeUp", "UI_EHR_Food_WincesCramp" }
Data.BLUR_LINES = { "UI_EHR_Text_MyVisionIsBlurring", "UI_EHR_Text_EverythingIsSwimming",
    "UI_EHR_Text_ICantFocusMyEyes", "UI_EHR_Text_TheRoomWontStayStill", "UI_EHR_Text_MyEyesFeelClouded" }
Data.RECOVERED_LINE = "UI_EHR_Disease_RecoveredLine"

-- Mean game minutes between random lines at DialogueFrequency Normal: a 1 in 7 chance every 24 game minutes
-- (stages 2-4).
Data.LINE_EVERY = 168

return Data
