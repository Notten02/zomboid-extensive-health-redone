-- The Last Prescription, Amelie Crowe's station on 47.0 MHz. Constants and the rotation tables; Radio/Station has the
-- rules, Server/Radio airs it.
--
-- 21 morning tips, 22 story episodes and 20 disease files. Every line is a UI_EHR_Radio_* key, so it can be
-- translated; the profanity in tip 5 stays.
--   UI_EHR_Radio_Intro_{Morning,Afternoon,Evening}
--   UI_EHR_Radio_Tip_<n>_<line>, UI_EHR_Radio_Story_<n>_<line>
--   UI_EHR_Radio_File_{Title,Cause,Symptoms,Treatment,WriteDown} (each takes %1)
--   UI_EHR_Radio_File_<id>_{Cause,Symptoms,Treatment}; the file's name is UI_EHR_Disease_<id>, so corpse sickness is
--   "Corpse Exposure Illness" on air
--
-- On 47.0 MHz only HAM radios, the ManPack and walkie-talkies 3-5 can tune it. The story
-- advances only when an episode airs and the last episode (the loop recording) repeats after 22.

local Radio = {}

Radio.NAME = "The Last Prescription"
Radio.UUID = "EHR-LAST-PRESCRIPTION-470"       -- the original mod's, kept
Radio.FREQUENCY = 47000                        -- vanilla units: kHz
Radio.CATEGORY = "Emergency"                   -- a ChannelCategory field name
Radio.AIR_COUNTER_MULTIPLIER = 1.35            -- how long each line stays up

-- Slot hours (game clock) -> slot name.
Radio.SLOTS = { [9] = "morning", [15] = "afternoon", [21] = "evening" }
Radio.HOURS = { morning = 9, afternoon = 15, evening = 21 }

-- Line colours, r g b.
Radio.COLORS = {
    static = { 0.65, 0.65, 0.65 },     -- the intro line
    tip = { 0.50, 0.90, 0.62 },        -- morning text, Treatment
    host = { 0.95, 0.85, 0.72 },       -- story text, Cause
    medical = { 0.45, 0.78, 1.00 },    -- the file's title and last line
    warning = { 1.00, 0.35, 0.25 },    -- Symptoms
}

-- Lines per 09:00 tip (21 tips; tip n is UI_EHR_Radio_Tip_<n>_1 .. _<count>).
Radio.TIP_LINES = { 6, 7, 6, 6, 7, 6, 6, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6 }

-- Lines per 15:00 story episode (22 episodes, in order).
Radio.STORY_LINES = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 }

-- 21:00 disease files in airing order (day d airs file ((d - 1) mod 20) + 1). The ids are our knowledge ids. The Knox
-- file never teaches Knox: only the Kentucky Herald does.
Radio.FILES = {
    "food_poisoning", "gastroenteritis", "trichinosis", "dysentery", "toxin_poisoning", "corpse_sickness",
    "cadaveric_aspergillosis", "common_cold", "pneumonia", "hypothermia", "heat_exhaustion", "heat_stroke",
    "wound_infection", "sepsis", "tetanus", "ahtr", "concussion", "hyperkeratotic_scabies", "delirium",
    "knox_infection",
}

-- Who hears it: a listener within RANGE tiles (x and y) of a world device, on its floor and on the same side of
-- inside/outside (vanilla ISRadioInteractions.playerInRange / checkPlayer).
Radio.RANGE = 5

-- Rewards are judged when the broadcast's final line airs (Radio/Station.check). If the server can't show line
-- progress, everyone listening at any check from FALLBACK_FROM to FALLBACK_UNTIL minutes after the start counts.
-- A broadcast is never watched longer than WATCH_LIMIT game minutes.
Radio.FALLBACK_FROM = 5
Radio.FALLBACK_UNTIL = 15
Radio.WATCH_LIMIT = 120

-- radioHeard keys older than this many days are pruned when a new key is written.
Radio.HEARD_KEEP_DAYS = 2

-- The world's station state in global ModData (Server/Radio).
Radio.WORLD_KEY = "EHRRedone_Radio"

return Radio
