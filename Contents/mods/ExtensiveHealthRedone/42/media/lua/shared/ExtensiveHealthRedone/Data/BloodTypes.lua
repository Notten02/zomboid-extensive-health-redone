-- Blood types and how often each is rolled for a new character (real-world distribution, weights sum to 100).
-- Taken verbatim from the original (shared/ExtensiveHealth/EHR_Main.lua:470-471). The strings are also the save
-- format, so they never change.

return {
    types = { "O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+" },
    weights = { 7, 36, 6, 34, 2, 9, 1, 5 },
}
