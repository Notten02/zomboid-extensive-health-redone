# Zombie Virus Vaccine

- **Mod id:** `ZVirusVaccine42BETA`
- **Workshop id:** `3615135168` (B42.20+ port by rEXX, v3.1; the optional Research Lab Intern profession is a separate mod that only needs it)
- **Status:** supported since 2026-10-21. Checked in its code and in offline tests (`tests/zvirusvaccine_spec.lua`), **not yet in a game client**.

## How we are compatible

**No conflicts.** Its cure, delay and accidental infection write vanilla's Knox state directly. We leave vanilla as the owner of Knox and our `knox_infection` display only mirrors it, so a cure shows as recovered. Items (`LabItems`, `LabBooks`), server commands (`ZVirusVaccine42BETA`) and sandbox namespace are separate from ours, we define no fluids, and the only vanilla method it wraps (`ISFluidContainerMenu.createMenu`) is not one of ours.

**Immunity:** gene-therapy survivors, Patient Zero and immunobooster users have any Knox infection cleared every step, so the vaccine's accidental infection does nothing to them.

**Ties we added** (`Server/ZVirusVaccine.lua`, server side, only while the mod is enabled):

| Tie | What happens |
|---|---|
| Blood draw costs blood | We wrap its `LabCollectBloodLogic.ProcessCollection`. Each sample takes 50 mL and gets `EHR_DonorBloodType` in its modData. Under half blood the draw is refused and the syringe is kept. |
| Knox blood test teaches Knox | We wrap its `BloodTestLogic.ProcessTest`. A positive or negative result unlocks Knox knowledge (like the Kentucky Herald). An unusable sample does not. |
| Delay shows in the Knox stage | `facts.knox.followTimer` makes our progress follow the infection timers, so its vaccine and albumin delays lower the shown stage. |
