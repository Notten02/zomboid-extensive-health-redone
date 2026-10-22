# MoodleFramework

- **Mod id:** `MoodleFramework`
- **Workshop id:** `3396446795` (optional; read from its `42.20/` folder)
- **Status:** supported. **Worked in single player on 42.21** (2026-10-14, MoodleFramework v2.8). Its API names were checked again against its source on 2026-10-21. Multiplayer not yet tried.

## How we are compatible

**Optional, public API only.** Build 42.21 has no Lua API for custom moodles, and MoodleFramework's licence allows use through its public API only, so our five moodles exist only when it is enabled. Without it, `Client/Moodles.lua` does nothing: vanilla's own moodles and the EHR Monitor carry the information. The Workshop page recommends it.

**No conflicts.** It is not one of our patch points and we wrap nothing of it; our moodle names (`EHR_*`) do not clash with other mods' names.

**What we do with it** (`Client/Moodles.lua`, `UI/MoodleLevels.lua`, client side, only while the mod is enabled):

| Tie | What happens |
|---|---|
| Five moodles | `require "MF_ISMoodle"`, then `MF.createMoodle` for Medical Alert (levels 1-4), Corpse Exposure, Cadaveric Exposure, Heat Exposure and Cold Exposure, at game boot so MoodleFramework makes the objects when the player is created. |
| Look | Per moodle: `setThresholds`, `setChevronCount`, and per level `setBackground`, `setPicture`, `setTitle`, `setDescription` (all "bad" kind); the level is driven with `setValue`. Our icons are complete round badges, so the background is replaced by an empty texture. |
| Levels from the mirror | Re-applied after every sync and every game minute, for each local player (split screen). A fresh Knox infection never raises the Medical Alert. |
| Hide switch | The `ShowEHRMoodles` mod option hides all five; the mechanics are untouched. |
