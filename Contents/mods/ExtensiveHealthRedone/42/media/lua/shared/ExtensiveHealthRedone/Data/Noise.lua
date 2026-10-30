-- Sounds a character makes because of an illness: the voice sound played on the character and the world noise that
-- draws zombies. Server/Noise plays them; systems ask with p.noise(kind) (Core/Simulation).
--   male, female   sound script names (media/scripts/EHR_Sounds.txt or vanilla)
--   radius, volume world noise (IsoGameCharacter:addWorldSoundUnlessInvisible)
--   audioOption    sandbox option that mutes only the voice sound, never the world noise
--   muffled        { male, female, radius, volume } when the character holds a tissue (ItemTag.MUFFLE_SNEEZE); one
--                  use of the tissue is consumed

return {
    cough = {
        male = "EHRCoughMale", female = "EHRCoughFemale", radius = 12, volume = 8,
        audioOption = "CoughSoundsEnabled",
        muffled = { male = "VoiceMaleMuffledCough", female = "VoiceFemaleMuffledCough", radius = 2, volume = 2 },
    },
    coughSevere = {
        male = "EHRCoughSevereMale", female = "EHRCoughSevereFemale", radius = 25, volume = 15,
        audioOption = "CoughSoundsEnabled",
        muffled = { male = "VoiceMaleMuffledCough", female = "VoiceFemaleMuffledCough", radius = 4, volume = 3 },
    },
    -- Sneezes follow CoughSoundsEnabled (its tooltip covers "cough voice sounds"), and a held tissue muffles them, as
    -- vanilla's own MuffleSneeze tag intends.
    sneeze = {
        male = "EHRSneezeMale", female = "EHRSneezeFemale", radius = 8, volume = 5,
        audioOption = "CoughSoundsEnabled",
        muffled = { male = "VoiceMaleMuffledCough", female = "VoiceFemaleMuffledCough", radius = 2, volume = 1 },
    },
    -- Pain cries (Diseases/Mind/PainSounds): vanilla pain voices. The radius and volume come from
    -- ZombieAttractionRadius and the pain level (args.radius, args.volume); the numbers here are the defaults.
    pain = { male = "VoiceMalePainMoodle", female = "VoiceFemalePainMoodle", radius = 30, volume = 18 },
    painSevere = { male = "VoiceMalePainFromLacerate", female = "VoiceFemalePainFromLacerate", radius = 40, volume = 24 },
    -- Vomiting (Diseases/Food): a 15/10 world noise, with vanilla's vomit voices.
    vomit = { male = "VoiceMaleVomit", female = "VoiceFemaleVomit", radius = 15, volume = 10 },
    -- Delirium's shout impulse: a 45/45 world sound.
    deliriumShout = { male = "VoiceMaleShoutHey", female = "VoiceFemaleShoutHey", radius = 45, volume = 45 },
}
