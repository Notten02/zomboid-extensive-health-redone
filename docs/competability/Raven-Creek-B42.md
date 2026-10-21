# Raven Creek B42

- **Mod id:** `RavenCreekB42`
- **Workshop id:** `3484263516` (a map mod; versionMin 42.0.0)
- **Status:** supported by design, **checked in its code only** (2026-10-21). The original listed it as compatible ("medicine spawns fine"). Nothing was run: no spawn test in a game client, and the mod is a map, so the server smoke test did not load it.

## How we are compatible

**Nothing to set up: it uses vanilla room names.** Its medical rooms are the vanilla ones (`medical`, `medicalstorage`, `medclinic`, `pharmacy`, `pharmacystorage`, `hospitalstorage`, `medicaloffice`), and it adds no procedural distributions of its own. Vanilla aliases `medclinic` and `medicaloffice` to `medical`, so our distributions (`Loot/Apply`, `Data/Loot`) reach them like any vanilla town.

**Its one distribution file** (`RCB42_NewDistribution.lua`, at `OnPostDistributionMerge`) adds only vanilla list names (army medical storage, hospital lockers and similar) under its own rooms `armyhanger` and `armysurplustorage`. Those are lists we extend, so army medical loot there carries our items too.

**No error path found:** our loot code tolerates a missing room or list table (`Loot/Apply.roomProcs` and `write` report it as `missing` instead of failing).

## Not done / open

- Needs a game client: open clinic, pharmacy and hospital containers in Raven Creek and confirm EHR items spawn; no error at distribution merge.
- Unverified: whether our items are added after its `OnPostDistributionMerge` handler runs (the order of the two handlers).
- Not ours to fix: its custom rooms such as `grocers`, `shop` and `stroge` have no vanilla distribution, so they get loot from nobody.
