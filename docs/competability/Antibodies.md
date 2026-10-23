# Antibodies

- **Mod id:** `lgd_antibodies`
- **Workshop id:** `2392676812` (v1.98 by lonegamedev; the 42.13 folder loads on 42.21)
- **Status:** supported since 2026-10-21. Its code was read, our API check over its Lua is clean, and a dedicated server started with it enabled showed no Lua error. **Not yet in a game client.**

## How we are compatible

**No conflicts found.** It keeps its own medical file per player (its own ModData namespace and `antibodies` network module) and adds its UI to vanilla panels, which we keep.

**Its Health tab button replaces our "AB" button.** v0.9 had an "AB" button in its own panel. Antibodies adds its own "Knox infection" button to vanilla's `ISHealthPanel` (the Health tab) and a Hygiene tab to the character window, and we keep both, so we build nothing for it. Its Hygiene view sizes the window to its own width (about 400), narrower than the tabs once ours are added, so the character window is kept at least as wide as all its tabs (`Client/CharacterWindow`).

**Knox:** it delays and cures the vanilla Knox infection by writing vanilla's infection time and flags (`setInfectionTime`, `setInfected(false)`, part flags). We leave vanilla as the owner of Knox and our `knox_infection` display only mirrors it, so a delay lowers the shown stage and a cure shows as recovered. Both it and we read the infection time as the character's **hours survived**.

**Immunity:** gene-therapy survivors, Patient Zero and immunobooster users have any Knox infection cleared every step, so Antibodies' delay or cure does nothing visible for them.

**Shared vanilla methods:** it wraps `ISApplyBandage` and `ISDisinfect` (`perform` and `complete`) and `ISCharacterInfoWindow.createChildren`, as do we (`Data/PatchPoints`). Our wrap is applied last (at game boot), so it is the outermost, and observers do not change arguments or results.
