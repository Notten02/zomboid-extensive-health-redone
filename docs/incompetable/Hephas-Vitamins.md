# Hephas Vitamins

- **Mod id:** `HephasVitamines` (the mod folder name; read from the copy installed on 2026-10-21, which has since been uninstalled, so the id was not re-checked)
- **Workshop id:** `3494803855`
- **Status:** **overlap, not supported.** Found by reading its code in the compatibility scan (2026-10-21); never run together with ours. We did nothing about it on purpose.

## Why it clashes

Both mods rework the same vanilla item, `Base.PillsVitamins`.

- **Ours** (`Data/ItemTweaks.lua`, applied at game boot): vitamins become Caffeine Pills, `UseDelta` 0.0417 (24 doses) and the tooltip `Tooltip_CaffeinePills`; the caffeine effect comes from our medication rules.
- **Theirs** (`HV_AdjustPillProperties.lua`, at `OnInitGlobalModData`, later than our tweak): `DoParam` on the same item for `UseDelta`, `Tooltip`, `StressChange` and `FatigueChange`. It overwrites our dose count and tooltip.
- It also replaces `ISTakePillAction.perform` at `OnGameStart` (`HV_Override_IsTakePillAction.lua`) to add healing when a vitamin is taken. That is not our hook (we use `ISTakePillAction.complete`), so nothing is wrapped twice, but a vitamin then both heals through Hephas and acts as caffeine through us.

## What to tell players

Use one or the other. Nothing breaks with an error as far as the code shows, but the pill's doses, tooltip and effect become a mix of two designs.

## Not done / open

- Not tested together. If players want both, the fix is to apply our item tweaks after theirs (we apply them too early) and to decide which design owns the pill; that is a design question, not a bug.
