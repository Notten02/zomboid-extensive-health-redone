-- Vanilla CharacterStat names that simulation systems may change through the StatAggregator.
-- The server's stat writer reads each one's range from the game, so a scale change in a B42 update needs no edit
-- here. A name the game no longer has is logged at start and left out.
-- ZOMBIE_INFECTION and ZOMBIE_FEVER (vanilla's Knox infection) are only ever lowered, by Knox immunity and Phalanx
-- (Diseases/Knox); the infected flag and timers go through the body writer.

return {
    "ANGER",
    "BOREDOM",
    "DISCOMFORT",
    "ENDURANCE",
    "FATIGUE",
    "FOOD_SICKNESS",
    "HUNGER",
    "IDLENESS",
    "INTOXICATION",
    "MORALE",
    "NICOTINE_WITHDRAWAL",
    "PAIN",
    "PANIC",
    "POISON",
    "SANITY",
    "SICKNESS",
    "STRESS",
    "TEMPERATURE",
    "THIRST",
    "UNHAPPINESS",
    "WETNESS",
    "ZOMBIE_FEVER",
    "ZOMBIE_INFECTION",
}
