# Disease Overview

> Player guide for **Extensive Health Redone**. Based on Frozen_Heart's original "Disease Overview"
> (`docs/original-author-guides/disease-overview.md`), reworked to match the code as it is today
> (`Diseases/*`, `Conditions/*`, `Wounds/*`, `Medication/Data.lua`). Where Redone differs from the original guide, the
> difference is listed in the last section.
>
> Times are **game time**. They are divided by the sandbox *Disease Speed* option (default 1.0), except where noted.
> Medicine timings (course lengths, dose intervals) are never scaled by it.

## How diseases work

**Stages.** Most conditions run in four stages:

| Stage | Meaning |
|---|---|
| 1 | Incubation. Usually no symptoms (a few conditions have mild ones). |
| 2 | Active illness. |
| 3 | Peak danger. |
| 4 | Recovery, or a late and dangerous stage, depending on the disease. |

The total length of stages 2 to 4 is split 40% / 30% / 30%. Every disease rolls a random severity (the disease's base plus
or minus 0.15), and most symptom strengths scale with it, so two cases of the same disease are not identical.

Exceptions:
- **Concussion** has 3 stages and starts at stage 3.
- **Delirium** has one permanent stage.
- **Insomnia** and **painkiller addiction** have 3 stages. Stage 3 never recovers on its own.
- **Sepsis** never ends on its own: stage 4 stays deadly.
- **Hypothermia, heat exhaustion** follow your body temperature and heat meter, not a timer.
- **Knox infection** is vanilla's mechanic, which the mod only mirrors.
- **Wound infection** is tracked per body part, with its own stage clock.

**What you can see.** A disease shows by name only once your character can identify it: read its flyer, hear it on the
radio, be an EHR Doctor or Surgeon, or have **First Aid 8**. Hypothermia, heat exhaustion, heat stroke and food poisoning
are self-evident. Once the name is known, **First Aid 4** shows the stage and **First Aid 6** shows the time left and the
treatment. The Knox infection needs the **Kentucky Herald, July 16, 1993** and nothing else.

**How medicine works.**
- **Relief** medicine lowers symptoms for as long as a dose is active. It scales with the drug's tier: over the counter
  40%, prescription 60%, clinical 80% (basic vanilla pills 15%). It never cures.
- **Cure** medicine ends the disease. Many cures are a **course**: several doses at fixed intervals. A dose only counts
  once 90% of the interval has passed; **taking one earlier wastes it**, and for most prescription drugs it also causes an
  **overdose** (three early doses inside one overdose kill). When every dose is in, the disease ends after the drug's
  cure time, counted from the **first** dose.
- **The first dose of a curing course freezes the disease at its current stage** and stops the health drain of most
  lethal conditions. A cure can take days, but it stops the dying right away. Do not wait for symptoms to peak.
- A dose taken before you actually have the disease still starts the course, so do not take courses "just in case".
- Injections need a **syringe**. IV drugs need an **IV kit**.
- Systemic antibiotics lower your immune score while active (see the immune system guide).

## Quick finder: what cures what

| Disease | Cure (relief-only drugs are listed in each section) |
|---|---|
| Food Poisoning | Activated Charcoal (homemade too) |
| Gastroenteritis | Antiviral Capsules, IV Ciprofloxacin |
| Trichinosis | Antiparasitic Pills, Albendazole Injection |
| Toxin Poisoning | Activated Charcoal (homemade too), Chelation Kit |
| Dysentery | Oral Rehydration Kit, Broad Spectrum or Plant-Based Antibiotics, IV Antibiotics, IV Metronidazole, IV Ciprofloxacin |
| Common Cold | Cold & Flu Tablets, Herbal Cold Tea, Antiviral Capsules |
| Pneumonia | Prescription, Broad Spectrum or Plant-Based Antibiotics, IV Ciprofloxacin |
| Hypothermia | Nothing: warm up |
| Heat Exhaustion | Nothing: cool down (water and rehydration help) |
| Heat Stroke | Instant Ice Pack, cold bath, three hours at 10 C or colder |
| Corpse Exposure Illness | Respiratory Support Kit, Corticosteroid Injection, fresh air |
| Cadaveric Aspergillosis | Antifungal Tablets, IV Amphotericin B |
| Wound Infection | Prescription, Broad Spectrum or Plant-Based Antibiotics, Antibiotic Ointment, IV Antibiotics; disinfect early |
| Cellulitis | Prescription, Broad Spectrum or Plant-Based Antibiotics, Antibiotic Ointment, IV Antibiotics, IV Vancomycin |
| Sepsis | Broad Spectrum or Plant-Based Antibiotics, IV Antibiotics, IV Vancomycin, IV Metronidazole, Emergency Sepsis Kit |
| Tetanus | Tetanus Antitoxin, Tetanus Immunoglobulin |
| Hyperkeratotic Scabies | Topical Permethrin (homemade too), Antiparasitic Pills |
| Concussion | Nothing: time (48 hours) |
| AHTR | Furosemide, IV Fluids |
| Delirium | Antipsychotics |
| Insomnia | Dual Orexin Receptor, Antidepressants (good sleep helps in stages 1 and 2) |
| Painkiller Addiction | Buprenorphine |
| Knox Infection | No medicine: Gene Therapy Kit (risky), Immunobooster, Phalanx Pills |

---

# Food and water

Food diseases are rolled **per bite or drink**. The chance scales with how much of the item you eat, and each risky bite
adds to a running total that fades by 20% per game hour. When the total reaches 80%, the next bite is a guaranteed catch.
Before you fall ill you may feel queasy, which is your warning.

## Food Poisoning

**Cause** (per bite): rotten food (70%), unsafe uncooked food and cooked dishes that were never cooked properly (35%), stale
food (10%), burned food (5%). Immunity does not help.

**Timing:** incubation 2 to 12 hours, then 1 to 3 days.

**Stages:**
- 2: nausea, endurance slowly drained, occasional vomiting.
- 3 (peak): stronger nausea, endurance drained harder, more hunger and thirst, vomiting.
- 4: recovery. Symptoms fade.
- It does not damage health.

**Treatment:** **Activated Charcoal** (or homemade): one dose, cures 6 hours later. Relief: Anti-Nausea Tablets,
Electrolyte Powder.
**Prevention:** do not eat rotten, stale, burned or half-cooked food.

## Gastroenteritis

**Cause:** eating with **bloody or dirty hands**. Chance per bite is about 15% of the blood on your hands plus 8% of the
dirt, up to 33%, and nothing at all if your hands are almost clean. Immune sensitivity 0.75.

**Timing:** incubation 4 to 12 hours, then 1 to 3 days.

**Stages:**
- 2: thirst, hunger, endurance loss, nausea.
- 3 (peak): vomiting, stronger nausea, weakness.
- 4: the stomach settles.
- It does not damage health.

**Treatment:** **Antiviral Capsules** (6 doses, 8 hours apart; cures 48 hours after the first) or **IV Ciprofloxacin**
(one dose, cures after 12 hours). Relief: Anti-Nausea Tablets, Electrolyte Powder.
**Prevention:** **Wash your hands** before eating (Wash Hands at a water source; soap uses less water and is quicker).

## Trichinosis

**Cause:** eating **raw** small game or pork: rats, mice, rabbit, squirrel, pork, bacon, and modded boar, bear, fox,
raccoon or wolf meat that is not preserved. About 70% per bite. Ordinary raw beef and chicken are not trichinosis sources.

**Timing:** incubation 24 to 48 hours, then 7 to 12 days.

**Stages:**
- 2: muscle aches, a low fever, endurance loss, slower movement, occasional leg cramps.
- 3 (peak): severe muscle pain, fever about 39 C, heavy endurance loss, movement at 80%. **Drains roughly 11 health per hour
  and blocks healing. Lethal untreated.**
- 4: pain fades, weakness remains.

**Treatment:** **Antiparasitic Pills** (14 doses, 12 hours apart; cure after 7 days) or **Albendazole Injection** (one
dose, cures after 72 hours, needs a syringe). The first dose of either stops the health drain.
Relief: Muscle Relaxants (homemade too), Anti-Inflammatory Pills, Antipyretic Tablets or Tea.
**Prevention:** cook all wild game and pork fully.

## Toxin Poisoning

**Cause:** eating anything with a poison value, usually unidentified mushrooms and berries. There is **no roll**. If the
food is poisonous you get it, and mushrooms are the worst (severity up to 1.0, versus roughly 0.5 to 0.8 for berries).

**Timing:** incubation 1 to 4 hours, then 1 to 4 days.

**Stages:**
- 2: nausea, vomiting, dizzy spells.
- 3 (peak): stronger symptoms, abdominal pain, recurring blurred vision. **Mushrooms only: about 4 health per hour,
  healing blocked. Lethal untreated.** Berries and other toxins do not drain health.
- 4: recovery.

**Treatment:** **Activated Charcoal** (cures 12 hours later), or the **Chelation Kit** (one IV dose, cures after
24 hours). Relief: Anti-Nausea Tablets, Electrolyte Powder.
**Prevention:** do not eat berries and mushrooms you cannot identify.

## Dysentery

**Cause:** drinking contaminated water. One roll per drink: **toilet 50%**, tainted water 25%, river 15%, rain collector
5%. Tap water and boiled water are safe. Immune sensitivity 0.65.

**Timing:** incubation 6 to 12 hours, then 3 to 5 days.

**Main danger:** dehydration. It does not damage health directly, but thirst and hunger rise fast.

**Stages:**
- 1: mild gut symptoms, thirst and hunger raised slightly.
- 2: thirst and hunger rising (capped near half), abdominal pain, a little blood loss, rare vomiting.
- 3 (peak): thirst and hunger rise with no cap, frequent vomiting, stronger pain, **movement at 70%**.
- 4: back to mild levels.
- With Lifestyle: Hobbies, it raises your bladder need.

**Treatment:**
- Cures: **Oral Rehydration Kit** (8 doses, 6 hours apart; cures 48 hours after the first), **Broad Spectrum** or
  **Plant-Based Antibiotics** (6 doses, cure after 72 hours), **IV Antibiotics** (36 hours), **IV Metronidazole**
  (24 hours), **IV Ciprofloxacin** (12 hours).
- **Prescription Antibiotics and vanilla antibiotics do not cure dysentery.**
- Relief: Anti-Diarrheal Tablets (strongest), Electrolyte Powder, Anti-Nausea Tablets (vomiting). Relief slows the rise
  of thirst but never lifts the caps.

**Prevention:** boil or purify water, never drink from toilets, avoid river and tainted water.

---

# Weather and temperature

## Common Cold

**Cause:** cold-and-wet exposure, or being soaked.
- **Freezing route:** outdoors, air at **5 C or colder**, and wetness above 30%, away from a fire. After 2 hours of
  that exposure you start rolling every game hour (10% rising to a 35% cap).
- **Soaked route:** wetness at **90% or more**, any air temperature, even indoors. After 1 hour you roll hourly (8% rising
  to a 25% cap).
- The meter drains faster near a lit fire, wearing a Warming Pack, indoors and warm, or bathing. Immune sensitivity 0.85.
- You cannot catch a cold while you have a cold, pneumonia, hypothermia or heat stroke.

**Timing:** incubation 12 to 24 hours, then 2 to 4 days.

**Stages:**
- 1: occasional sneezing.
- 2: the vanilla cold moodle, fatigue, sneezing every hour, a mild fever (about 37.6 C).
- 3 (peak): a stronger cold, a fever of about 38 C, a sneeze every half hour, heavy fatigue.
- 4: recovery. **Untreated, there is a 35% chance as it begins that it becomes Pneumonia.** A running cure course skips
  that roll.

**Treatment:** **Cold & Flu Tablets** (8 doses, 4 hours apart; cure after 28 hours), **Herbal Cold Tea** (the same
course), or **Antiviral Capsules** (cure after 48 hours). Relief: Cough Syrup (homemade too), Cough Suppressant,
Antipyretic Tablets or Tea.
**Prevention:** stay dry, stay warm, get near a fire, and do not stay soaked.

## Pneumonia

**Cause:** only an **untreated common cold** (35%, modified by immunity at sensitivity 0.80).

**Timing:** incubation 12 to 24 hours, then 5 to 9 days.

**Stages:**

| Stage | Cough | Notes |
|---|---|---|
| 1 | every 2 hours | Mild chest pain, fever about 38 C. |
| 2 | every hour (severe) | Fever 40 C, endurance capped at 70%, chest pain. |
| 3 | every 45 minutes | **Drains 2.5 health per hour down to 30.** Healing blocked. |
| 4 | every 45 minutes | **Drains 4 health per hour with no floor. Lethal untreated.** |

Coughs make noise that **attracts zombies**.

**Treatment:** **Prescription**, **Broad Spectrum** or **Plant-Based Antibiotics** (cure after 72 hours) or **IV
Ciprofloxacin** (12 hours). The first dose stops the drain. Vanilla antibiotics give only minor relief.
Relief: Bronchodilator Inhaler (lifts the endurance cap), Cough Syrup and Suppressant, Antipyretic Tablets or Tea.
**Prevention:** cure the cold before it reaches stage 4.

## Hypothermia

**Cause:** your **body temperature** falling. It has no timer and no roll. Cold air, wet clothes, wind and poor insulation
all push it down, and vanilla decides how fast.

**Stages** (the default thresholds are sandbox options):

| Stage | Body temperature | Effects |
|---|---|---|
| 1 | 35.0 C or lower | Movement at 90%, endurance ceiling 86%. |
| 2 | 34.0 C | No sprinting, **2 health per hour**, some confusion. |
| 3 | 32.0 C | Movement at 52%, blur and dizziness, **8 health per hour**. |
| 4 | 31.0 C | Movement at 42%, **18 health per hour**, **blackouts** (forced one-hour sleep). |

Stages move back as you warm up (a stage holds until 0.25 C above its threshold, and stage 1 until 35.5 C). Natural
healing is not blocked.

**Treatment:** **no medicine helps.** Get indoors, dry off, change wet clothes, light a fire or stove, and eat or drink
something hot. A **Warming Pack** pulls you toward 37 C for 2 hours.
**Prevention:** stay dry, wear insulated clothing, do not linger in the cold. Disabled by the sandbox option *Body
Temperature*.

## Heat Exhaustion

**Cause:** a **heat meter**. Between 9 AM and 8 PM, with air above **30 C** (the threshold is a sandbox option), it fills
over about 4 hours, faster if you are thirsty or exerting yourself. **A hat cuts the build-up by 70%**, and shade
by 65%. It drains indoors, in the shade, at night, or in cooler air.

**Stages** (by meter fill: 35%, 60%, 85%):
- 1: hot and thirsty.
- 2: leg cramps, more thirst, movement at 90%.
- 3: dizziness, nausea, movement at 80%, **no sprinting**.
- 4: cooling down.
- It does not damage health, but **Heat Stroke rolls begin as it nears full**.

**Treatment:** **cooling down** is the cure. Get indoors or into shade, drink water, take off heavy clothing. Electrolyte
Powder and the Oral Rehydration Kit ease the thirst.
**Prevention:** hat, shade, water, and avoid exertion in a heat wave.

## Heat Stroke

**Cause:** the same heat meter. At 85% fill you roll every 5 minutes, higher with thirst or exertion. At 100% it is
guaranteed.

**Timing:** instant, lasting about 4 to 8 hours. **Stage 3 does not end until you are cooled.**

**Stages:** all stages give a 40.5 C fever, no sprinting, blurred vision, dehydration and confusion, and **collapses**
(a fall and a forced hour of sleep).

| Stage | Movement | Health drain per hour |
|---|---|---|
| 2 | 50% | 15 |
| 3 | 35% | 36 |
| 4 | 50% | 24 |

It is almost always lethal if you are not cooled.

**Treatment:**
- **Instant Ice Pack:** 4 doses, one hour apart.
- **Cold bath:** a bathtub within 3 tiles, 8 units of water, 180 minutes of continuous bathing.
- **Cold air:** three hours in air at **10 C or colder**. A car with the air conditioning on counts.
- Electrolyte Powder gives 40% relief on every symptom for half an hour, but does not replace cooling.

**Prevention:** treat heat exhaustion early.

---

# Corpses

Corpses within **10 tiles** on your floor count. Fresh corpses (under a day) are weak, decomposing ones (1 to 2 days) count
double and rotten ones (2 days or more) five times. Being **indoors** multiplies exposure by 1.5, and a **small room**
by 2. Only corpses in your own room count when you are inside. A sealed vehicle blocks everything.

**Protection:** a **gas mask or respirator with a working filter blocks exposure fully**. Dust masks, surgical masks,
bandanas and other cloth face covers **halve** it.

## Corpse Exposure Illness

**Cause:** the corpse meter. It rises per hour with every corpse (fresh 1, decomposing 2, rotten 5, times the room
multiplier) and decays 30 per hour in fresh air. From 85 you roll hourly (after an hour in the area), and 100 is
certain. Bands: low 30, medium 60, high 100.

**Timing:** incubation 6 to 18 hours, then 1 to 3 days. **Fresh air doubles the pace** once the meter is back to zero.

**Stages:**
- 2: nausea, weakness, headache, occasional dizziness.
- 3 (peak): headache, dizzy spells, severe coughs, movement at 85%, and occasional **collapses**.
- 4: recovery.
- **It never kills.**

**Treatment:** leave the area. **Respiratory Support Kit** (3 doses, 3 hours apart; cures 6 hours after the first) or
**Corticosteroid Injection** (cures after 12 hours, but suppresses immunity and causes insomnia). Relief: Anti-Nausea
Tablets, Bronchodilator Inhaler.
**Prevention:** do not sleep or work near corpse piles, remove corpses from buildings, wear a filtered mask.

## Cadaveric Aspergillosis

**Cause:** a separate **spore meter**. Only **decomposing and rotten** corpses carry spores, and only in **damp or cold**
conditions (wet 30% or more, raining outdoors, or air at 10 C or colder). Cold, rain and indoors multiply it. Immune
sensitivity **1.00**, the strongest of any disease.

**Timing:** incubation 24 to 72 hours, then 7 to 14 days.

**Stages:**
- 2: cough, fever of about 38 C, endurance loss.
- 3: severe cough, fever about 39.4 C, heavy fatigue, **no sprinting**, movement at 75%, **about 3 health per hour
  drained. Lethal untreated.**
- 4: recovery.

**Treatment:** **Antifungal Tablets** (10 doses, 12 hours apart; cure after 5 days) or **IV Amphotericin B** (cures after
24 hours). The first dose stops the drain. Relief: Bronchodilator Inhaler, Cough Syrup, Antipyretic Tablets.
**Prevention:** avoid damp corpse-filled rooms, wear a mask, and leave in the rain.

---

# Wounds and infection

## Wound Infection

**Cause:** vanilla's wound infection. Redone watches for it and tracks each infected body part. A poor stitch also has a
30% chance of infecting a wound.

**Timing:** a **12 hour incubation**, then stage 1 (12 hours), stage 2 (24 hours) and stage 3 (48 hours). Untreated, the
end of stage 3 starts **Sepsis** (96 hours in all).

**During the incubation you can still stop it:**
- **Disinfect** the wound (vanilla disinfect, or an alcoholic bandage).
- **Antiseptic Cream** on the wound prevents it from starting while active.
- A good immune score gives the incubation a chance of being **contained** (see the immune guide).

Once it has become active, disinfecting does nothing.

**Stages:** the infected part heals **25% slower** (stage 1), **50% slower** (stage 2), or not at all (stage 3), and has
extra pain (0, +10, +30). In stage 3 a fever of about 38 C starts.

**Treatment:** **Prescription**, **Broad Spectrum** or **Plant-Based Antibiotics** or **Antibiotic Ointment** (cure after
72 hours; ointment does not weaken immunity), **IV Antibiotics** (36 hours). **Vanilla antibiotics** drop every infected
part by one stage per dose. Relief: Anti-Inflammatory Pills, Antipyretic Tablets.
**Prevention:** disinfect, bandage cleanly, replace dirty bandages, do not close dirty wounds.

## Cellulitis

**Cause:** a **rough or poor stitch** from the stitching minigame, or a failed or cancelled stitch below the stable
quality. **40%**, modified by immunity (sensitivity 0.90). Excellent and stable stitches never trigger it.

**Timing:** incubation 12 to 36 hours, then 3 to 6 days. **Untreated, it turns into Sepsis** as it reaches stage 4.

**Stages:**
- 2: local pain, fever about 37.8 C, fatigue.
- 3: more pain, fever about 38.6 C.
- 4: systemic spread. This hands off to Sepsis straight away unless a cure course is running.
- It does not drain health itself.

**Treatment:** **Prescription**, **Broad Spectrum** or **Plant-Based Antibiotics** or **Antibiotic Ointment** (72 hours),
**IV Antibiotics** (36 hours), **IV Vancomycin** (48 hours). Relief: Anti-Inflammatory Pills, Antipyretic Tablets.
**Prevention:** clean the wound before stitching, and stitch carefully. At most two misses is a "stable" stitch.

## Sepsis

**Cause:** an untreated Wound Infection reaching the end of stage 3, or an untreated Cellulitis reaching stage 4.
Immunity does not help. After a cure it cannot restart for 2 hours.

**Timing:** incubation 6 to 24 hours (already symptomatic), then stages 2 and 3 over about 2 to 4 days. **Stage 4 never
ends on its own.**

| Stage | Fever | Health drain per hour |
|---|---|---|
| 1 | 38.0 C | 0.25 (stops at 85 health) |
| 2 | 38.6 C | 1 (stops at 65) |
| 3 | 39.4 C | 4 (stops at 30) |
| 4 | 40.0 C | **10, no floor** |

Confusion rises with the stage. Healing is blocked.

**Treatment:** **Broad Spectrum** or **Plant-Based Antibiotics** (72 hours), **IV Antibiotics** (36), **IV Vancomycin**
(48), **IV Metronidazole** (24) or the **Emergency Sepsis Kit** (24). Prescription Antibiotics are **not** listed for
sepsis. Antipyretics reduce the fever but do not solve the infection; vanilla antibiotics only give minor relief.
**Careful:** Vancomycin, Metronidazole and the Sepsis Kit cure the sepsis but **not the infected wound** behind it, which
can start it again within 48 hours. Also treat the wound with IV Antibiotics, Broad Spectrum or Plant-Based
Antibiotics, or Antibiotic Ointment.
**Prevention:** treat wound infection and cellulitis early.

## Tetanus

**Cause** (all multiplied by the sandbox chance multiplier; no immunity effect):
- **Glass lodged in a deep wound:** 40% at once, then every 12 hours, rising by 15% to a 70% cap.
- **Crash:** a deep wound that appears while in a vehicle, 40%.
- **Walking on glass:** glass in a foot, 20%.
- **Dirty deep wound** (no bandage or a dirty one): 15% per 12 hours.

**Timing:** incubation **3 to 7 days**, hidden. Then 7 to 14 days. It ends on its own if you survive.

**Stages:**
- 2 (lockjaw): you **cannot eat** (drinks are fine) unless a muscle-relief drug is active, neck pain, endurance loss, slow
  health damage down to 30.
- 3 (spasms): full-body pain, fever about 39 C, **about 7.7 health per hour with no floor**, regular falls.
- 4: recovery.

**Treatment:** **Tetanus Antitoxin** (one dose, cures after 5 days, needs a syringe) or **Tetanus Immunoglobulin** (cures
after 48 hours, needs a syringe). Nothing else cures it. Relief: Muscle Relaxants (homemade too), Anti-Inflammatory Pills
and Antipyretic Tablets ease pain, lockjaw and falls but **do not stop the health drain**. Only a cure does.
**Prevention:** clean deep wounds, remove glass, replace dirty bandages.

## Concussion

**Cause:** a serious **fall from height** (65%) or a **vehicle crash** (45%), but only if the body shows real trauma
afterwards (head pain, head damage or a severe new wound).

**How it works:** it starts at stage 3 and improves every 16 hours (48 hours in all). **No medicine treats it.**

| Stage | Symptoms |
|---|---|
| 3 | Strong headache, blur, nausea, frequent dizzy spells. Health pulled down to 50. |
| 2 | Moderate. Health floor 75. |
| 1 | Lingering. Health floor 90. |

**Prevention:** avoid high falls and fast crashes.

## Hyperkeratotic Scabies

**Cause:** **sitting on bare natural ground** (dirt or grass). Every 15 continuous minutes you roll 3%, modified by immunity
(sensitivity 0.85), about 12% per hour. Winter (December to February) and snow block it by default.

**Timing:** incubation 1 to 2 hours, then 4 to 7 days.

**Stages:**
- 1: an itchy bite wound.
- 2: fever 38 C, scratches every 3 hours, **health capped at 60%**.
- 3: fever 40 C, scratches every hour, health cap 30%.
- 4: fever 40 C, **about 12 health per hour with no floor. Lethal untreated.**

**Treatment:** **Topical Permethrin** (homemade too: 6 doses, 12 hours apart; cures after 72 hours) or **Antiparasitic
Pills** (14 doses; cure after 7 days). Relief: Antipyretic Tablets.
**Prevention:** do not sit on bare ground for long.

---

# Blood

## Acute Hemolytic Transfusion Reaction (AHTR)

**Cause:** a transfusion of **incompatible blood**. You get an immediate reaction (nausea, panic, pain, 150 mL of
blood lost) and then AHTR with a severity of at least 0.95. A second incompatible bag makes it worse.
Compatibility: **O-** is the universal donor, **AB+** takes everything.

**Timing:** incubation 1 to 6 hours (symptoms already active), then 2 to 4 days.

**Stages:**
- 1: lower back pain, weakness, endurance loss.
- 2: fever 40 C, nausea, **about 3.5 health per hour** (stops at 50).
- 3: **about 10 health per hour, no floor.**
- 4: about 7 health per hour, no floor.

**Treatment:** **Furosemide** (6 doses, 8 hours apart; cures 48 hours after the first; dehydrates you) or **IV Fluids**
(one dose, 24 hours, needs an IV kit). Relief: Anti-Nausea, Anti-Inflammatory, Antipyretic.
**Prevention:** use compatible, **fresh** blood. Learn your type from the **Blood Types flyer** or at **First Aid 8**.
A stale bag (over about an hour) gives a separate reaction, and a rotten bag (over two hours) is refused.

---

# Mind

## Painkiller Addiction

**Cause:** repeated use of **vanilla Painkillers**. Homemade Painkillers do not count. A hidden **risk meter** (0 to 100)
goes up with each dose in a rolling 24 hours:

| Doses in 24 hours | Risk added by that dose |
|---|---|
| 1st to 4th | 1 each |
| 5th | 8 |
| 6th | 12 |
| 7th or more | 20 |

A dose less than **3 hours** after the last adds 4 more. At 100 you are addicted. The meter only starts falling after a
**full 24 hours without a dose** (about 50 points per day).

**Timing:** no incubation. Stage 2 after 24 hours, stage 3 after 48 hours. **It is permanent until cured.**

**Symptoms (withdrawal):** cravings (as speech), rising stress, unhappiness and thirst.

| Stage | Stress and unhappiness raised toward | Thirst |
|---|---|---|
| 1 | 25% | 18% |
| 2 | 60% | 28% |
| 3 | 80% stress, **100% unhappiness** | 40% |

A **Painkiller** dose (3 hours) or a **Buprenorphine** dose (12 hours) suppresses withdrawal and calms you. Painkillers do
not cure it.

**Treatment:** **Buprenorphine**: 10 doses, one every 12 hours (120 hours). A dose taken early is refused.
**Prevention:** never take 5 or more doses in 24 hours, never doses less than 3 hours apart, and give yourself a full day
without.

## Delirium

**Cause:** **stress at 98% or more for 12 hours** in a row.

**Duration:** a single stage that is permanent until treated.

**Symptoms:** a hallucinated sound only you hear, nonsense speech, a screen tint, and an **unsafe impulse**, one episode
every 30 to 60 minutes. The impulse can be to **fire a held firearm**, **drop your backpack**, **smash a nearby window**
or **shout** (which attracts zombies).

**Treatment:** **Antipsychotics**: 8 doses, 12 hours apart (96 hours). While a dose is active, episodes are 2.5 times
rarer and impulses much less likely.
**Prevention:** do not let stress stay at maximum. Relaxant Tea lowers it.

## Insomnia

**Cause:** being awake with **fatigue at 80% or more for 12 hours**. There is also a 10% chance after the **crash** of
Caffeine Pills, Nitric Oxide Boosters or Combat Stimulants.

**Progression:** stage 1 (24 hours), stage 2 (24 hours), then stage 3, which **never recovers on its own**.

| Stage | Effect |
|---|---|
| 1 | Sleep does not restore you. Fatigue is pushed up while you sleep. |
| 2 | You **cannot fall asleep naturally** without a sleep aid. |
| 3 | Same, with higher stress and headaches. |

**Recovery without drugs (stages 1 and 2):** six hours of continuous sleep is a "good night". Three in a row (a tea
before bed counts a night double) drops a stage, and a stage 1 case ends. In stage 2 the sleep only counts with a sleep aid.
More than 30 hours without a good night breaks the streak. Stage 3 needs a cure.

**Treatment:** **Sleeping Pills** (homemade too) let you sleep for 8 hours but do not cure. **Dual Orexin Receptor**
cures in 96 hours (8 doses) and lets you sleep. **Antidepressants** cure in 168 hours (14 doses), also ease stress, and
act as a sleep aid.
**Prevention:** sleep before fatigue stays extreme, and avoid stimulant abuse.

---

# Knox Infection

**Cause:** vanilla's zombie infection, usually from bites. The mod adds no infection rules of its own. Its Knox entry only
**mirrors** vanilla's infection (stage 1 to 4 at 0%, 20%, 50% and 80% progress).

**Knowledge:** it stays "Unknown" even for doctors until you read the **Kentucky Herald, July 16, 1993**. (With Zombie
Virus Vaccine, a finished Knox blood test also teaches it.)

**There is no normal medical cure.** The Knox items are found only in the **Military Research Facility** basements, and
each is used on yourself:

| Item | What it does | Risks |
|---|---|---|
| **Gene Therapy Kit** | **Cures** the infection and makes you permanently immune, and gives you the Patient Zero trait. | The success chance depends on your **blood type**: O- 95%, O+ 85%, A- and B- 75%, A+ and B+ 65%, AB- 50%, AB+ 40%. **On a failure the character dies.** On success it costs 10 health. Occasional migraines afterwards. Refused if you are not infected. |
| **Antibody Test Kit** | Shows your blood type and your gene therapy odds (High 75%+, Moderate 50%+, Low 25%+). | None. Use it **before** the Gene Therapy Kit. |
| **Immunobooster Shot** | 24 hours during which any infection is cleared again and again. | 7-day cooldown. Nausea, slower endurance regeneration and tremors while active. Refused if you are already bitten or infected. |
| **Phalanx Suppressant Pills** | Rewinds the infection progress. 1st dose: to 0%, 2nd: 25%, 3rd: 50%, 4th: 75%, 5th and later: nothing. A dose taken when it would not help is wasted. | 6 hours of nausea, 12 hours of fever, and 48 hours of lowered immunity. A kit holds 3 uses. |

**Patient Zero** is a character trait (chosen at character creation) that gives permanent immunity to the Knox infection.
Server admins can disable it. Bites still wound you.

---

# Medication quick reference

**Tiers:** basic (vanilla pills, 15% relief), over the counter (40%), prescription (60%), clinical (80%).

## Symptom relief

| Medicine | Helps with |
|---|---|
| Anti-Nausea Tablets | Nausea and vomiting: food poisoning, gastroenteritis, toxin poisoning, dysentery, corpse illness, AHTR |
| Electrolyte Powder | Dehydration and weakness: food diseases, dysentery, heat exhaustion, heat stroke |
| Anti-Diarrheal Tablets | Dysentery's diarrhea and bathroom urgency |
| Antipyretic Tablets or Tea | Fever in any feverish disease |
| Anti-Inflammatory Pills | Pain and inflammation: wound infection, cellulitis, trichinosis, tetanus, AHTR |
| Muscle Relaxants (homemade too) | Tetanus spasms and lockjaw, trichinosis muscle pain |
| Bronchodilator Inhaler | Breathing and endurance: pneumonia, corpse illness, aspergillosis |
| Cough Syrup (homemade too), Cough Suppressant | Coughing: cold, pneumonia, aspergillosis |
| Painkillers | Vanilla pain relief only. **Addictive.** |
| Antiseptic Cream (homemade too) | Prevents wound infection for 8 hours while on a wound |

## Cures

| Medicine | Course | Cures |
|---|---|---|
| Activated Charcoal (homemade too) | 1 dose | Food Poisoning (6 h), Toxin Poisoning (12 h) |
| Cold & Flu Tablets, Herbal Cold Tea | 8 doses, 4 h apart | Common Cold (28 h) |
| Antiviral Capsules | 6 doses, 8 h | Common Cold, Gastroenteritis (48 h) |
| Prescription Antibiotics | 9 doses, 8 h | Wound Infection, Cellulitis, Pneumonia (72 h) |
| Broad Spectrum, Plant-Based Antibiotics | 6 doses, 8 h | Wound Infection, Sepsis, Pneumonia, Cellulitis, Dysentery (72 h) |
| Antibiotic Ointment (homemade too) | 6 doses, 8 h | Wound Infection, Cellulitis (72 h) |
| Antifungal Tablets | 10 doses, 12 h | Cadaveric Aspergillosis (120 h) |
| Antiparasitic Pills | 14 doses, 12 h | Trichinosis, Scabies (168 h) |
| Topical Permethrin (homemade too) | 6 doses, 12 h | Scabies (72 h) |
| Oral Rehydration Kit | 8 doses, 6 h | Dysentery (48 h); helps heat exhaustion |
| Furosemide | 6 doses, 8 h | AHTR (48 h) |
| Antipsychotics | 8 doses, 12 h | Delirium (96 h) |
| Dual Orexin Receptor | 8 doses, 12 h | Insomnia (96 h) |
| Antidepressants | 14 doses, 12 h | Insomnia (168 h) |
| Buprenorphine | 10 doses, 12 h | Painkiller Addiction (120 h) |
| Instant Ice Pack | 4 doses, 1 h | Heat Stroke (4 h) |
| Respiratory Support Kit | 3 doses, 3 h | Corpse Exposure Illness (6 h) |
| Tetanus Antitoxin (syringe) | 1 dose | Tetanus (120 h) |

## Clinical treatments (one dose; IV drugs need an IV kit, injections a syringe)

| Medicine | Cures | Side effects |
|---|---|---|
| IV Antibiotics | Sepsis, Wound Infection, Cellulitis, Dysentery (36 h) | Nausea, fatigue |
| IV Metronidazole | Dysentery, Sepsis (24 h) | Metallic taste, nausea |
| IV Ciprofloxacin | Gastroenteritis, Dysentery, Pneumonia (12 h) | Tendon weakness, dizziness |
| IV Amphotericin B | Cadaveric Aspergillosis (24 h) | Fever, kidney stress, fatigue |
| IV Vancomycin | Sepsis, Cellulitis (48 h) | Red man syndrome, kidney stress |
| Emergency Sepsis Kit | Sepsis (24 h) | Severe fatigue, nausea, fever |
| IV Fluids | AHTR (24 h) | |
| Albendazole Injection (syringe) | Trichinosis (72 h) | Abdominal pain, dizziness |
| Chelation Kit | Toxin Poisoning (24 h) | Headache, fatigue, nausea |
| Tetanus Immunoglobulin (syringe) | Tetanus (48 h) | Injection-site pain, fever |
| Corticosteroid Injection (syringe) | Corpse Exposure Illness (12 h) | Immunosuppression, insomnia |

## Utility and performance drugs

- **Caffeine Pills** (the vanilla vitamin pills, retuned): remove fatigue and block its build-up for 12 hours, then a hard
  fatigue crash. A second dose is refused while active. Can lead to insomnia.
- **Nitric Oxide Boosters:** strong stamina boost for 3 hours, then whole-body muscle pain. Can lead to insomnia.
- **Combat Stimulants:** doubled attack speed, stress and panic suppression, endurance support for 3 hours, then a harsh
  crash. Can lead to insomnia.
- **Epinephrine Auto-Injector:** wakes the character, even from a blackout (so usually another player gives it).
  **Last Chance Epinephrine** is the emergency version. Both have headache and insomnia side effects.
- **Warming Pack:** pulls body temperature toward 37 C for 2 hours.
- **Beta Blockers** (vanilla): steady the heart. They do not help hypothermia.
- **Saline and IV fluids** boost hydration. Too much saline dilutes blood and becomes lethal.

## Drug interactions

A pair fires once when both are active, and the character warns you:
antibiotics + corticosteroid (immunosuppression), Chelation Kit + IV Amphotericin (kidney stress), Muscle Relaxant + Beta
Blocker (drowsy), anti-inflammatory + corticosteroid (stomach pain), anti-inflammatory + antibiotic (stomach upset),
painkiller + muscle relaxant (drowsy), Activated Charcoal + antibiotic (antibiotic relief halved), Epinephrine + Beta
Blocker (weaker), Cough Suppressant + Cold & Flu Tablets (drowsy), Anti-Nausea + Anti-Diarrheal (constipation),
antibiotic + antifungal (stomach upset), Electrolyte Powder + Oral Rehydration Kit (too much).

## Disease knowledge

- Reading **disease flyers** teaches that disease (once per disease) and gives First Aid XP.
- The daily **radio broadcast on 47.0 MHz at 9 PM** teaches one disease a day, in a 20-day rotation.
- A higher **First Aid** level reveals more automatically (see "What you can see").
- **Knox Infection** is the exception: only the Kentucky Herald, July 16, 1993.

---

# What changed from the original guide

**Removed**
- **Tuberculosis** (it was unfinished in the original) with its drugs, flyer and radio file. Also removed: the Flu and
  Knox flyers.

**New or changed on purpose**
- **Heat Exhaustion** is a real four-stage condition driven by the heat meter. The original only showed a meter.
- **Tetanus** has four triggers, not one, and lasts 7 to 14 days.
- **Common Cold** from the cold needs air at 5 C or colder, and stage 4 is a real recovery stage.
- **Pneumonia** comes only from an untreated cold ("severe respiratory stress" is dropped).
- **Corpse Exposure Illness:** fresh air shortens it. The corpse and spore meters build separately.
- **Insomnia** stages 1 and 2 can recover from good sleep alone. Only stage 3 never recovers by itself.
- **Hypothermia** has no medicine at all (Beta Blockers no longer count).
- **Wound infection** now slows healing of the infected part, and has an incubation you can stop.
- **Toxin Poisoning** is also cured by the **Chelation Kit**.
- **Homemade Painkillers** do not cause addiction. **Painkiller Addiction** can be switched off in the sandbox.
- **Side effects** of drugs now have their intended strength. A headache hurts, a drug fever raises your temperature.
  Some hit much harder than in the original.
- **Pain and cough sounds** work: strong pain makes the character cry out, which attracts zombies nearby.

**Clarified here**
- The first dose of a curing course freezes a disease and stops its lethal drain.
- Which diseases are fatal untreated (trichinosis, mushroom toxin, pneumonia, aspergillosis, heat stroke, hypothermia,
  sepsis, tetanus, AHTR, scabies, and wound infection through sepsis), and which never kill (corpse illness, food
  poisoning, gastroenteritis, cellulitis, concussion on its own).
- Dysentery is not cured by Prescription Antibiotics.
- **A failed Gene Therapy roll kills the character.**
