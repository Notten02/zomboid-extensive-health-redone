# The Only Cure

- **Mod id:** `TheOnlyCure`
- **Workshop id:** `3580276809` (`[B42.21] The Only Cure`, v2.4.3 by Pao, versionMin 42.20; source at `github.com/ZioPao/The-Only-Cure`, GPL-3.0)
- **Status:** supported since 2026-11-03. Its code was read, we are tested offline against a stand-in for its data (`tests/only_cure_spec.lua`), and on a dedicated server with one client (`tests/e2e/EHROnlyCureE2E`: a hand cut with the mod's own saw action, 21 checks passed). **Not yet played by hand.**

## How we are compatible

**We only read it.** It amputates hands, forearms and upper arms (cutting a limb takes everything below it), heals and cleans the stump, and fits prostheses. We read its per-player `DataController` (`TOC/Controllers/DataController`: `getIsDataReady`, `getIsCut`, `getIsCicatrized`, `getIsCauterized`, `getWoundDirtyness`, `getIsProstEquipped`, checked against v2.4.3) and the prosthesis the player wears (`TOC.Prost_*_L` / `_R`). We never write its state, call its actions or copy its code. `Game/OnlyCure.lua` is the only file that touches it.

**Without it, nothing changes.** Everything sits behind `getActivatedMods():contains("TheOnlyCure")`. Its data loads after the game starts, and until `getIsDataReady()` turns true we treat the mod as absent for that step, never as "nothing cut". If a read fails (the mod changed shape), the compatibility switches itself off for the session and logs one error.

**Knox:** it cures by clearing vanilla's Knox flags. Our `knox_infection` only mirrors vanilla, so a cure shows as recovered.

**Vanilla methods:** it rewrites vanilla's Health tab (`ISHealthPanel`), the medical check and the timed-action length (`ISBaseTimedAction.adjustMaxTime`). We keep vanilla's Health tab and wrap none of these (`Data/PatchPoints`). Its action slowdown applies to our timed actions too, on the client and on the authority, because its wrap is shared code.

## Ties we added

| Tie | What happens |
|---|---|
| Missing parts | A cut part reads as missing in the facts (`Server/OnlyCure`). Our state on it goes: wound infection, tetanus bookkeeping, slowed healing timers. The body aggregator drops every wish for a missing part, so no system can scratch, hurt, infect or slow a limb that is gone (`Core/BodyAggregator`). |
| Amputation cures | Cutting at or above a part with a wound infection ends it at any stage, with a line and the cure XP. Sepsis already in the blood is not touched. An incubation on a cut part goes without a word. |
| Stumps | Each arm's stump (its highest cut limb) is a wound on the part above it (hand: forearm, forearm: upper arm, upper arm: upper torso). While the mod has it neither healed nor cauterized, it rolls every 12 h for a wound infection incubation there: 25% x the mod's wound dirtiness (0-1) x **(The Only Cure) Stump Infection Chance** (sandbox, 0-5, default 1). Antiseptic cream blocks the roll. From then on our normal rules run it (immune roll, stages, sepsis). The mod's **Clean Wound** (its dirtiness falls) counts as disinfecting that part. The mod leaves a bleeding deep wound on that part, and vanilla flags it infected within minutes (seen on the dedicated server); while the stump is open that flag starts nothing of ours and is cleared, so the stump's roll alone decides (`Wounds/Infection`). |
| Eating surface | What touches the food at a bite: each side's hand, or the prosthesis worn there (its dirt and blood), averaged over the ones there are. With no hand and no prosthesis left the character eats face first, and the head's dirt and blood count (`Game/BodySoil`). |
| Washing | **Wash Hands** cleans the parts still there and any worn prosthesis. A character with no hand or prosthesis left gets **Wash Face** at water sources instead. |
| Monitor | One row per stump: open (with its dirt), healed or cauterized, and "Prosthesis fitted". The exam shows them too. |

## Saves

- **Our state for it** is its own section, `onlyCure` (`Schema.registerSection`). The core schema version did not move, so an older EHR still loads the save.
- **A save that already had the mod:** amputations found on the first sight of its data are cleanup only. State is dropped, with no line and no XP.
- **The mod added mid-playthrough:** nothing changes until the first amputation.
- **The mod removed again:** its limbs read as whole, and what we dropped stays dropped. A stump infection that had already started goes on as a normal wound infection on that part.

## Limits

- Only arms: the mod cuts no legs, so an infected foot or leg has no amputation.
- Seen on the dedicated server: the authority's `DataController` has the cut limb and its dirtiness, and our state, facts, the client's mirror and the Monitor row follow. The mod's action slowdown applies on both sides (100 -> about 387 after a hand); the client and the authority agreed within 0.05%, the rest being vanilla's own factors (the pain rising after the cut) between the two reads.
- Not seen yet: the dirtiness the mod relays from the owning client about once a game hour (the test set it on the authority), a prosthesis, and Wash Face at a real sink.
