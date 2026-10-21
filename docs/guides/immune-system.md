# Immune System Explained

> Player guide for **Extensive Health Redone**. Based on Frozen_Heart's original "Immune System Explained"
> (`docs/original-author-guides/immune-system.md`), reworked to match what Redone does today. Every number below is
> read from the code (`Data/Immunity.lua`, `Immunity/Immunity.lua`, `Conditions/Risk.lua`, `Wounds/Infection.lua`).

Your character has an **immune score** from 0 to 100. It does not give immunity and it does not cure anything. It
nudges the **chance of catching** some diseases, and it gives an incubating wound infection a chance to be stopped before
it starts. Once you are ill, the score changes nothing: symptoms, stages and timings stay the same.

You read it on the **Immune System** tab of the character window (open the EHR Monitor with **H**, then pick the tab).
The tab is one click away in both compact and full Monitor mode, and it only exists while the immune system is enabled
in the sandbox.

## How the score moves

- A new character starts at **75**, then drifts toward a target.
- The score is recalculated **every 15 game minutes**. It rises about **1.5 points per game hour** and falls about
  **3 points per game hour**, so it is quicker to lose than to build back. The sandbox options *Immunity Recovery Rate*
  and *Immunity Decline Rate* scale those speeds.
- The tab shows the **current score**, the **target**, the **trend** (recovering, declining, stable), and the
  **Current Pressures** that hold the target down.

## What sets the target

The target is a weighted sum of six factors, minus a hygiene penalty.

| Factor | Weight | How it is measured |
|---|---|---|
| Nutrition | 22% | The opposite of hunger. |
| Rest | 22% | Full marks while fatigue is under 50%. Above that it falls, reaching 0 at total exhaustion. |
| Hydration | 18% | The opposite of thirst. |
| Health reserve | 15% | Your overall health, minus *disease pressure* (below). |
| Blood | 13% | 0 at 40% blood or less, 100% at full blood. |
| Stress control | 10% | The opposite of stress. |

**Disease pressure** is subtracted from the health reserve factor, to a maximum of 70 points:
- every active illness: 8 points plus 2 per stage,
- every infected wound: 6 points plus 2 per stage (incubating wounds do not count),
- sepsis: a flat 25 points,
- delirium, insomnia and painkiller addiction count for half,
- the Knox infection is ignored (it is vanilla's mechanic).

**Hygiene penalty** (dirt and blood on your skin and worn clothing, whichever is worse for each body part, averaged):

| Dirtiness | Penalty | Bloodiness | Penalty |
|---|---|---|---|
| under 5% | 0 | under 2% | 0 |
| 20% | 12 | 20% | 16 |
| 50% | 25 | 50% | 30 |
| 100% | 35 | 100% | 40 |

The two penalties together never take more than **55** points off the target. Dirt and blood are the biggest single
levers you have: a character who is fed and rested but covered in blood can sit well below one who is merely hungry.

## Status bands

| Score | Status |
|---|---|
| 80 to 100 | **Strong** |
| 60 to 79 | **Stable** |
| 40 to 59 | **Strained** |
| 20 to 39 | **Compromised** |
| 0 to 19 | **Suppressed** |

A score of **50 is neutral**: it changes no chances. Above 50 it lowers them, below 50 it raises them. At a score of 100
the chance of the most sensitive diseases drops by up to **35%**; at 0 it rises by up to **50%**. How much of that applies
depends on the disease.

## Which diseases it affects

The number is how fully the disease follows the immune curve (1.00 = fully).

| Disease | Sensitivity | Chance at score 100 | Chance at score 0 |
|---|---|---|---|
| Cadaveric Aspergillosis | 1.00 | -35% | +50% |
| Cellulitis (from a rough stitch) | 0.90 | -31.5% | +45% |
| Common Cold | 0.85 | -29.8% | +42.5% |
| Hyperkeratotic Scabies | 0.85 | -29.8% | +42.5% |
| Pneumonia (from an untreated cold) | 0.80 | -28% | +40% |
| Gastroenteritis | 0.75 | -26.3% | +37.5% |
| Dysentery | 0.65 | -22.8% | +32.5% |

Anything not listed is unaffected: food poisoning, toxin poisoning, trichinosis, tetanus, sepsis, corpse exposure,
heat and cold illness, concussion, the mental conditions, AHTR and the Knox infection.

The Immune System tab shows one summary line, **Infection risk**, for a sensitivity of 1.00 at your current score.

### Wound infection: a second chance

A wound that has been detected as infected starts with a 12 hour **incubation**. Once per infection, the immune system
gets one roll to **contain it** before it develops:

- chance = (score - 20) / 80 x 45%, capped at 65%. At a score of 100 that is 45%; at 20 or below it is 0%.
- The score used is the average of your score when the infection was detected and your score when the roll happens.
- If it succeeds, you are told you disinfected it in time and the infection never starts.

A strong immune system **cannot remove an infection that has already become active**. After the incubation, only
treatment or time will end it.

## Antibiotic suppression

**Systemic antibiotics** weaken your immune system while a dose is active. The target is capped at **35%**, and your
score falls **4 points every 15 game minutes** until it gets there. When the dose wears off, normal recovery resumes.

Systemic antibiotics are: vanilla antibiotics, Prescription Antibiotics, Broad Spectrum and Plant-Based Antibiotics, IV
Antibiotics, IV Metronidazole, IV Ciprofloxacin, IV Vancomycin and the Emergency Sepsis Kit.

Not suppressing: Antibiotic Ointment (shop-bought or homemade), Antiseptic Cream, antivirals, antifungals,
antiparasitics.

The tab lists the penalty under **Current Pressures** as *Antibiotic Suppression*. Two other things push the score down
the same way:
- **Immunosuppression**, a side effect of the Corticosteroid Injection (48 hours, also caps the target at 35%), and of
  mixing antibiotics with a corticosteroid.
- The **Phalanx debuff**: after taking Phalanx pills, the target is 20 points lower for 48 hours.

Taking antibiotics when you do not need them is therefore a trade-off. A course of Prescription Antibiotics for a wound
infection is worth it. Antibiotics "just in case" make the next cold more likely.

## Practical advice

- Keep hunger, thirst and fatigue low. Nutrition, rest and hydration together are 62% of the target.
- Wash. Take off blood-soaked clothes and bathe. Hygiene can cost up to 55 points.
- Treat wounds early. Disinfect and bandage before the infection is detected, because the containment roll only exists
  during the incubation.
- Do not stack antibiotics. Use ointments for a mild wound infection; save systemic antibiotics for when you need them.
- Rest while you are ill. A sick character also loses score through disease pressure, so illnesses feed each other.
- With **Lifestyle: Hobbies**, hygiene, a comfortable seat, a recent shower and yoga make you recover faster from
  illnesses already underway. That is a separate system from the immune score.

## What it does not do

- It does not stop exposure from building up (cold, heat, corpses).
- It does not change symptoms, stage timing or progression.
- It does not replace medicine, wound care, hygiene or protective equipment.
- It does not affect a Knox infection.

## For server owners

Sandbox page **Immunity**:
- *Immune System Enabled*: turns the score and the tab off.
- *Enable Immune Gameplay Effects*: off means **monitoring only**. The score still moves and shows, but every roll is
  neutral and no wound infection is ever contained.
- *Immune Effect Strength*: scales the effect (0 = monitoring only, 1 = default, 2 = double, within safety caps. The
  multiplier on a disease chance never goes below 0.35 or above 2.0).
- *Immunity Recovery Rate* and *Immunity Decline Rate*: scale how quickly the score rises and falls.

## What changed from the original guide

- **Tuberculosis** is gone from the supported list (the disease was removed).
- Pneumonia and cellulitis are supported through their only real sources: the cold-to-pneumonia roll and the
  rough-stitch cellulitis roll.
- The guide never gave the weights. They are listed above, along with the hygiene curve and the disease pressure rules.
- New characters start at 75 rather than at the neutral score.
- Suppression also comes from the Corticosteroid Injection and the Phalanx debuff, and the Monitor lists them.
- Effects can be switched to monitoring only, and scaled, in the sandbox.
