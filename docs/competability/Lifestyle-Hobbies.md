# Lifestyle: Hobbies

- **Mod id:** `LifestyleHobbies`
- **Workshop id:** `3403870858` (v0.4.0.3, author Angry; optional)
- **Status:** supported since 2026-10-21. Checked in its code and in offline tests (`tests/lifestyle_spec.lua`), a dedicated server started with it enabled and no Lua error. **Not yet in a game client.**

## How we are compatible

**Optional, read from its player modData.** Lifestyle keeps its state client side. We read `hygieneNeed`, `IsDoingShower`, `IsSittingOnSeat` with `ComfortVal`, `LSHiddenSkills.Yoga`, and (for the toilet system) `bathroomNeed`, `IsDoingToilet` and `LSMoodles.BladderNeed`, only while its hygiene module is on (`SandboxVars.Text.DividerHygiene`). The only thing we write into its data is its bathroom need and, after our cold bath, `lastBath` and its cold-bath moodle. v0.9 guessed about 25 key names; ours are the real ones. Nothing of ours is wrapped by it: its wraps of `ISEatFoodAction.complete`, `ISToolTipInv.render` and `setSandboxVars` call the original and pass `self` through.

**Ties** (`Game/Lifestyle.lua`, `Lifestyle/Pace.lua`, `Server/Lifestyle.lua`, `Client/Lifestyle.lua`):

| Tie | What happens |
|---|---|
| Recovery pace | Hygiene, a shower or tub (fading over 2 game hours), sitting comfort and Yoga change how fast stage 2-4 of an illness passes: at most +50 % faster, dirty -10 %, filthy -25 %, never below 50 %. Knox infection is untouched; cellulitis and the lungs have small extra rules. Applied in `Conditions/Engine`. |
| Shower counts as bathing | A Lifestyle shower or tub counts as bathing for the heat and cold meters. |
| Bladder pressure | Dysentery (2/14/26/2 points an hour by stage, eased by anti-diarrheals, which also drain the need) and furosemide (18 an hour) add to Lifestyle's bathroom need through the `bladder` client effect. Not while on the toilet; nothing without its toilet system. |
| Cold bath | The heat-stroke cold bath uses its tub animations (`Bob_Tub_Enter`, then `Bob_Tub_Base` after 8 %) and positions, puts the character back afterwards and marks the bath as Lifestyle's cold bath. |
| Multiplayer | The server never has Lifestyle's data, so the client reports it (`lifestyle.report`, every 5 s checked, on change, every 30 s). The server uses it for 90 s, clamps every field and believes a shower only for a character standing still outside a vehicle. Residual risk, accepted: a modified client can claim the best readings (at most +50 % recovery). |

**Design choices:** the dirty and filthy penalties apply (v0.9 never applied them); no Lifestyle display in the Monitor; bed rest is not "sitting".