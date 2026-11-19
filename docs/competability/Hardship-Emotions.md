# Hardship: Emotions

- **Mod id:** `HardshipEmotions`
- **Workshop id:** `3811647387` (`Hardship: Emotions` v2.22.16, versionMin 42.20, needs MoodleFramework)
- **Status:** supported since 2026-11-19. Its code was read (`server/HardshipEmotions/HE_Hooks.lua`, `HE_Engine.lua`, `client/HardshipEmotions/HE_EHRKnox.lua`), and we are tested offline against a stand-in that wraps our functions the way it does and a stand-in for its public API (`tests/hardship_emotions_spec.lua`). **Not yet tried in a game.**

## How we are compatible

**Its integration was written for the original EHR.** Emotions has an *Integration: Extensive Health Rework* option (`IntegrateEHR`, on by default). Every hook in it waits for the original mod's global `EHR` table and reads that mod's player modData. Without help it never fires beside Redone. Nothing breaks, the integration just stays off.

**We give it what it looks for.** While Emotions is enabled, `Server/HardshipEmotions.lua` sets a global `EHR` table backed by our own systems, and keeps a copy of our state in the original's modData shape. Emotions' own code does the rest, so its rules and options stay its own. This runs on the authority only (single player, the dedicated server), where Emotions' hooks run too. Without Emotions, no global is set and nothing is written.

| What Emotions uses | What we give it |
|---|---|
| `EHR.Medication.UseConsumedMedication(player, fullType)`, which it wraps | We call it for every dose that counted (`Doses.take` result `"taken"`), for the patient: our inventory action, vanilla pills, eat and drink, and doses given to another player. Wasted and refused doses are not reported. |
| `EHR.Medication.Database[fullType].displayName` and `DrugCategories[displayName]` | Our medication id and its category under the original's name (`Game/HardshipEmotions.CATEGORIES`): stimulant, epinephrine, beta blocker, sleep aid, antipsychotic, muscle relaxant, painkiller. Add-on medications count too. |
| `EHR.CorpseSickness.GetEnvironmentMultiplier`, `GetFungalEnvironment` and `EHR.Disease.TryContract`, which it multiplies for a hungover or dizzy character | They return 1 (and the chance as given). We ask them every step while corpses are around, and Emotions' factors scale our corpse meter, spore meter and hourly contraction rolls (`facts.corpseRisk`, `Diseases/Corpse/Exposure`). Face protection still applies first. |
| `md.EHR_Blood = { currentVolume, maxVolume }` | Our blood volume, every game minute. Emotions uses the sandbox thresholds `BloodThreshold*`, which we share with the original. |
| `md.EHR_Disease.active.concussion = { stage, severity }` | Every active condition with its stage and severity, every game minute. The concussion matches the original (stage 3 to 1, base severity 0.65). While anything is active, Emotions leaves nausea to us. |
| `md.EHR_CorpseSickness` | Our corpse exposure and the corpse count, for the same nausea check. |

**What it then does** (all Emotions' own rules): our stimulants and epinephrine make you Wired, caffeine pills give the caffeine kind, beta blockers stop natural adrenaline for 2 hours, sleep aids, antipsychotics, muscle relaxants and painkillers sedate (painkillers only on the third dose within 4 hours), and a painkiller eases a hangover. A concussion sours the mood and brings mood swings, blood loss blocks Happy, and Hungover or Dizzy characters catch corpse diseases more easily.

**Generic ties through its public API.** The original EHR knew none of our newer diseases (trench foot, foot blisters, frostbite, gangrene and others), so the stand-in alone can't tell Emotions about them. Most of them already reach it through vanilla: their pain shows in the Pain moodle (which blocks Happy and Content and feeds anger), and gangrene's sickness in the Sick moodle. On top of that, `Server/HardshipEmotions.lua` registers with the API Emotions offers other mods (the `HardshipEmotions` global, also used by Hardship: Mortality). These ties work from our condition stages, so every condition counts, including add-on ones:

| Tie | Emotions function | What we report |
|---|---|---|
| Strain | `registerStrain` (read by its Sanity feature, off by default) | Our medical alert level (the Medical Alert moodle, without medication side effects): level 1 to 4 gives 0.15 / 0.4 / 0.7 / 1. Emotions takes the highest of this and its own reading. |
| Focus block | `registerBlock`, `"focus"` | No Concentrating from medical alert level 3 (a severe stage of any condition, a stage 2 sepsis, a stage 3+ Knox infection), or while dizzy. |
| Dizziness | `addDizzy` | Every game minute our vision blur is on: dizzy spells (corpse sickness, concussion, heat, hypothermia), a toxin's blurred vision and the dizziness side effect. Light below 0.6 blur, strong from it. Emotions' Dizzy brings its nausea and makes corpse diseases more likely. |

All three follow `IntegrateEHR`. A tie whose function an older Emotions lacks is skipped, with one warning in the log. We add no unhappiness of our own: specific mood effects stay Emotions' business.

**Vanilla pills reach it twice**, from its own vanilla hook and from ours, as they did with the original. Emotions ignores the repeat (its own one-minute dose window).

**No instant Knox diagnosis** (`EHRHideKnox`, on by default): Emotions does this by wrapping the original's UI, which we don't have. Instead, `Server/Knox` reads the option and our Knox display condition starts only once the infection reaches 30% (`EHRKnoxRevealAt`, which has no sandbox entry yet, so the default applies). It uses the same progress as our Knox stage: the larger of the stat and the infection timer. The monitor, the moodle, the exam and the mini panel all follow, because they read that condition. Vanilla's infection is unchanged. Once shown, the infection stays shown.

## Saves

- The modData copy uses the original's key names (`EHR_Blood`, `EHR_Disease`, `EHR_CorpseSickness`), and each table carries `EHR_RedoneMirror = true`. The one-time importer (`Core/Importer`) skips flagged tables, so they are never taken for the original mod's data.
- With `IntegrateEHR` switched off mid-game, the copy is removed on the next game minute.
- If Emotions is removed, its last copy stays in the save. Nothing reads it.

## Limits

- A global `EHR` that already exists is left alone (only the original sets one, and it can't run beside us). Emotions' integration then talks to that one.
- If a call into Emotions' wrappers fails, that tie (medication, corpses, the modData copy or dizziness) switches off for the session, with one error in the log. Emotions runs our strain and focus providers in its own pcall.
- Strain only matters with Emotions' Sanity on. Its own reading already covers pain, low health, sickness, starving and thirst.
- Emotions writes vanilla stress, panic, unhappiness and fatigue directly. Those feed our Delirium (stress at 98% or more for 12 h) and Insomnia (fatigue at 80% or more for 12 h).
- Its optional Sanity feature (off by default) also plays phantom sounds, like our Delirium. Keep it off, or expect both.
- Not seen yet: any of this in a running game, single player or dedicated server.
