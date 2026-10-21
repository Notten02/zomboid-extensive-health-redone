# Player guides

Guides for **Extensive Health Redone**, reworked from Frozen_Heart's original Workshop guides
(`docs/original-author-guides/`). They describe what the mod does **today**, with numbers read from the code, not from the
original text.

| Guide | Original it replaces | What it covers |
|---|---|---|
| [mod-overview.md](mod-overview.md) | Workshop description | What the mod adds, controls, the Monitor, blood, medicine, radio, professions, multiplayer, admin commands, compatibility. |
| [disease-overview.md](disease-overview.md) | Disease Overview | Every disease: cause, timing, stages, cure and prevention, plus the medication reference. |
| [immune-system.md](immune-system.md) | Immune System Explained | How the immune score is built, which diseases it affects, antibiotic suppression, sandbox options. |
| [medicine-distribution.md](medicine-distribution.md) | Medicine Distribution | Where each kind of medicine spawns, the Knox facility items, zombie loot, crafted-only medicine, loot options. |

Each guide ends with **What changed from the original**. The full list of differences for players is in
`docs/release/changes-from-original.md`.

## Keeping them true

- The numbers come from `Data/*.lua`, `Medication/Data.lua`, `Diseases/*` and `Conditions/*`. If you tune one, update the
  guide that quotes it. Pointers are at the top of each guide.
- The mod has **not been verified in a game client yet**, so a few statements are marked *(unverified in game)*. Drop the
  mark once checked.
- Spelling follows the repo (British).
- These are Markdown for GitHub. The Steam page text is separate, in `docs/release/workshop-description.md`.
