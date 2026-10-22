# Survivor Quirks

- **Mod id:** `SurvivorQuirks`
- **Workshop id:** `3759277273`
- **Status:** **no conflict found, but untested, and it wraps the same vanilla actions as we do.** Filed here until someone runs both in a game client. Read in the compatibility scan (2026-10-21) and again for this file; nothing was run.
- **Where our wraps are defined:** `Core/PatchPoints.lua` and `Data/PatchPoints.lua`

## Where there is a conflict

Survivor Quirks replaces these vanilla methods, and so do we (each wraps the one before it and calls it):

| Method | Survivor Quirks | Ours |
|---|---|---|
| `ISEatFoodAction.complete` | client `SQ_Effects.lua:942-958` and server `SQ_ServerWraps.lua:145-159` | food diseases, tetanus lockjaw (`eatComplete`) |
| `ISApplyBandage.complete` | client `SQ_Effects.lua:991-1000` and server `SQ_ServerWraps.lua:45-54` | alcoholic bandage disinfects (`bandageComplete`) |
| `ISStitch.complete` | client `SQ_Effects.lua:1003-1026` and server `SQ_ServerWraps.lua:57-78` | stitch result (`stitchComplete`) |
| `populateTraitList`, `setSandboxVars` | `SQ_TraitToggle.lua` (around :118-134) | Patient Zero trait toggle (`traitListPopulated`, `sandboxVarsSet`) |

Its wraps call the original and return its result; ours are applied at game boot, after all file-load wraps, so ours is the outermost and only observes (it never changes arguments or results, except our five listed intercepts: the stitch minigame, lockjaw refusing food, insomnia refusing sleep, the primary health panel option and the admin chat commands).

Its wrappers read fields of the stitch action (`self.doIt`, `self.otherPlayer`); our `ISStitch.new` intercept only returns our own action for the minigame, so those fields stay intact.

Its items, traits and commands use its own module and ids; no ID, ModData key, global or command clash was found.
