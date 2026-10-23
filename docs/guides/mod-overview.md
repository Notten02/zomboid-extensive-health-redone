# Mod Overview

> Player guide for **Extensive Health Redone**. Based on the original Workshop description by Frozen_Heart for
> *Extensive Health Rework Evolved* (`docs/original-author-guides/workshop-description.md`) and on Hunter's predecessor
> page, reworked to describe what this rewrite does in this version. For the text meant for the Steam page itself, see
> `docs/release/workshop-description.md`.

Project Zomboid health is simple: patch the wound, disinfect it, take some pills, and hope the bite was not that bite.
This mod makes the body more fragile, more varied and harder to ignore. Diseases come from food, water, weather, corpses
and wounds. Blood loss matters. Medicine has courses and side effects. What your character *knows* decides how much you
are told.

It is a from-scratch rewrite for **Build 42.21+**. The gameplay follows the original; the code is new, MIT-licensed, and
the server owns all health state, so it should works in multiplayer.

Related guides:
- `disease-overview.md`: every disease, its cure and prevention
- `immune-system.md`: the immune score
- `medicine-distribution.md`: where to find medicine

## Switching from the original

**You cannot run both.** Redone has its own mod ID (`ExtensiveHealthRedone`) and cannot be enabled together with
*Extensive Health Rework Evolved* (`ExtensiveHealthReworkEvolved`) or its predecessor (`EHR`). Back up your save first.

- **Kept:** the item module and every item ID, every sandbox option name, your server config.
- **Imported once per character:** blood type, disease knowledge (flyers, radio, profession), Knox Herald knowledge,
  handbook entries, radio heard, wild-plant knowledge, immunity score, gene-therapy immunity and Patient Zero.
- **Reset:** every active illness, treatment, wound infection, blood loss and cooldown. Characters start healthy.
- **Gone:** Tuberculosis and its items, the Flu and Knox flyers, the diagnosis system that never worked in the original.
- **Check *Blackout Cooldown (hours)*:** the original ignored the option and always used 24. Redone obeys it, so an old
  save that used the original's default of 1 now allows a blackout every game hour. Set it to 24.
- **Mod Options** has a new page, so rebind your keys if you changed them.

The full list is in `docs/release/changes-from-original.md`.

## Controls

| Key | Opens |
|---|---|
| **H** | The EHR Monitor (vanilla's Health key, with the *primary health panel* mod option on, which is the default). |
| **J** | The disease handbook (also vanilla's Info key; the character window goes back as it was). |
| **G** | The debug window, only with the sandbox option *Debug Mode*. In multiplayer, only for roles that may cheat medically. |

The **Mod Options** page (not the sandbox) lets you set a separate Monitor key (unbound by default), choose whether the
Monitor opens compact or full, and hide or show the EHR moodles.

## Health monitoring

The **EHR Monitor** and **Immune System** tabs sit inside vanilla's character window. The vanilla **Health** tab
stays beside them and is still where you bandage, disinfect, stitch, splint and remove glass or bullets, so wound items
from other mods keep working. You can also treat from the Monitor's body diagram: right-click a body part for vanilla's
treatment menu, or drag an item from your inventory onto it.

The Monitor shows what your character can work out:
- active illnesses, with their stage, time left and treatment as your knowledge allows,
- medication in effect, doses taken, overdose risk and drug interactions,
- blood (see the watch below), infected wounds, temperature, and heat and cold exposure.

Not every illness is shown by name. Until your character can identify it, it appears as an **Unknown** illness with a
hint (such as "Respiratory" or "Gastrointestinal") that narrows it down.

### What your character knows

| You know... | When |
|---|---|
| The **name** of a disease | You read its **flyer**, heard it on the **radio**, have an **EHR Doctor or Surgeon** profession, or have **First Aid 8**. A few are self-evident (you know when you are freezing). |
| Its **stage** | The name is known, and First Aid 4 or more. |
| Its **progress**, time left and treatment | The name is known, and First Aid 6 or more. |

The **Knox infection** is the exception. It stays unknown, even for doctors, until you read the **Kentucky Herald of
July 16, 1993** (or a finished Zombie Virus Vaccine blood test teaches you).

The **handbook (J)** shows what you have discovered.

### Medical Monitor Watch

Your **blood level** shows only while you wear a **powered Medical Monitor Watch**. The battery lasts about seven game
days of wear; swapping it is a short timed action and a removed battery keeps its charge. The sandbox option *Medical
Watch Required* turns the requirement off.

## Blood

- Blood volume is a pool of **5000 mL**. Bleeding wounds drain it, faster on the neck, groin and torso.
- Falling blood brings growing penalties, blackouts at the lowest stage, and death.
- **Eight blood types.** Blood bags carry a type and **spoil** unless frozen (stale after about one warm hour, rotten
  after two).
- You can **draw your own blood** (it costs blood and a bit of endurance), give **saline**, use **IV kits**, and
  **transfuse** yourself or another player. **Incompatible blood** triggers an immediate reaction and then **AHTR**. You
  learn type compatibility from the **Blood Types flyer** or at **First Aid 8**.
- Healing only progresses while your character is **fed, hydrated, rested and calm**. Each requirement can be switched off.
- Homemade syringes, IV kits and blood bags can be crafted.

## Wounds and suturing

- Infected wounds are tracked **per body part**, and an infected part heals more slowly: stage 1, 2 and 3 heal 25%,
  50% and 100% slower.
- **Sepsis** follows a wound infection or cellulitis that went untreated.
- **Suturing minigame.** Vanilla stitching is very forgiving. Here you click moving points on the wound, and how good you
  are, helped by First Aid skill, decides quality. A rough or poor stitch has a **40% chance** of triggering
  **cellulitis**, and a very poor one may infect the wound. Turn it off in the sandbox with *Stitch Minigame Enabled* if
  you prefer vanilla.
- **Tetanus** can follow glass lodged in a deep wound, a vehicle crash, a dirty deep wound or walking on glass.

## Medicine

Every medicine is a **relief** (eases symptoms), a **cure** (ends the disease), or both. They come in three tiers:
**over the counter**, **prescription** and **clinical** (stronger, usually injected or IV). The higher the tier, the
stronger the relief.

- **Courses.** Many cures need several doses at fixed intervals ("Dose 3/8"). A dose counts only once **90% of the
  interval** has passed; taking one earlier **wastes** it. A course whose next dose is more than 24 to 72 hours late (three times the interval, within those limits) is abandoned.
  When the last dose is in, the disease ends after the drug's cure time.
- **Overdose.** For many prescription drugs, an early dose is an **overdose**. The earlier it is, the worse (sickness,
  thirst, an endurance and health cap). The **third early dose inside one overdose is fatal**.
- **Side effects.** Strong drugs have them: nausea, headache, fatigue, fever, tendon weakness, kidney stress and more.
- **Interactions.** Twelve pairs warn you and have an effect, such as antibiotics with corticosteroids, painkillers with
  muscle relaxants, or activated charcoal with antibiotics.
- **Supplies.** **Injections need a syringe** and **IV drugs need an IV kit**.
- **Systemic antibiotics suppress your immune system** while active (see the immune guide).
- **Painkiller addiction.** Taking vanilla painkillers too often builds a hidden dependency. See the disease guide.

Using the wrong treatment is useless, risky, or a waste of supplies.

## Disease

There are **23 conditions** (the disease guide lists them). Each has its own *Enabled* switch in the sandbox, many have
chance multipliers, and **Disease Speed** scales how fast they run.

## Immune system

A score from 0 to 100 that raises or lowers your chance of catching some diseases. It never changes an illness you
already have. Details are in the immune system guide.

## Knox

Gene Therapy Kit, Antibody Test Kit, Immunobooster Shot, Phalanx Pills and the **Patient Zero** trait. These are found
only in the Military Research Facility basements. Details are in the disease guide, under Knox Infection.

## Radio: The Last Prescription

A daily broadcast on **47.0 MHz** by **Amelie Crowe**, a radio host whose story unfolds over time. Tune it on a **HAM
radio, a ManPack radio or walkie-talkies 3 to 5**. Car radios and ordinary FM radios do not receive it. You must stand
within **5 tiles** of the device, on its floor and on the same side of a wall (indoors or outdoors).

| Time | Content |
|---|---|
| 9 AM | A **medical tip**. Gives a little First Aid XP. 21 tips. |
| 3 PM | **Story progression.** 22 episodes, then the last repeats daily. |
| 9 PM | A **disease file**. Teaches you one disease, in a 20-day rotation. |

The Knox infection is never taught by radio.

## Professions and traits

- **EHR Doctor:** First Aid 6, Short Blade 1, and the knowledge of every disease except Knox. Starts in a doctor's outfit.
- **EHR Surgeon:** First Aid **10**, Short Blade 3, the **Scalpel Master** trait (the scalpel hits much harder and lasts
  far longer in your main hand), and the same disease knowledge. Starts in scrubs and a surgical cap and mask.
- Both start knowing the homemade medicine, tea, syringe, IV kit and blood bag recipes.
- **Patient Zero:** a character trait (cost 20) that gives immunity to Knox infection. It can be turned off for a server
  with the sandbox option *Patient Zero Trait Disabled*.

## Crafting and the wild

- **Homemade medicine:** Plant-Based Antibiotics, Activated Charcoal, Antiseptic Cream, Antibiotic Ointment, Topical
  Permethrin, Cough Syrup, Muscle Relaxant, Painkillers, Sleeping Pills, three herbal teas. It does not replace
  clinical items.
- **Bandage packs and spiderweb bandages.** The bandage pack is handled by crafting recipes: Take One, Unpack All, Add
  to Pack, Create Pack and Pack 5. You cannot apply a bandage straight from the pack.
- **Medicinal plant search.** Read the **Wild Medicinal Plants** guide, or have both **First Aid 4 and Foraging 4**. Find
  a real bush outdoors and play a 4x4 search board in 42 seconds. Some spots hide thorns that scratch your hands
  unless you wear intact gloves. A bush is empty for 48 game hours afterwards. Herbs are used in medicine recipes.
- **Hive and spiderweb search.** About 40% of trees hold something: honeycomb (with bees) or spiderwebs. Reach in
  without touching the bees or spiders. A tree is empty for 48 game hours afterwards.
- **Hand washing** prevents gastroenteritis. **A cold bath** can cure heat stroke.

## Multiplayer

- **The server decides** every roll, item use and dose. Medical timers do not run while a player is offline.
- **Examine Health** (right-click a player, after vanilla's Medical Check): they must be within 3 tiles and accept. The
  doctor then sees what the patient's own Monitor would show, limited by the doctor's knowledge. The session lasts about
  5 minutes while the window is open. Treat the patient's wounds from the window's body diagram, within 2 tiles:
  right-click a body part for vanilla's treatment menu, or drag an item from your inventory onto it. Their yes to the
  exam covers this, so vanilla's separate Medical Check is not needed.
- **Giving medicine, blood or saline** asks the patient first, one dose or item at a time, with a 45 second prompt.
  **Stitching another player** asks too. Teas and drinks cannot be given.
- **Admin chat commands**, for roles with the medical-cheat capability (admin, moderator, GM; not observer):
  - `/ehrfullheal Name`: restores everything, including an active Knox infection. Keeps blood type, knowledge, immunity.
  - `/ehrreset Name`: back to a new character. Keeps blood type, knowledge and permanent Knox immunity.
  - `/ehrinspect Name`: read only.

  Single player has no chat. The debug menu (G, needs *Debug Mode*) has *Full heal* and *Reset state*.

## Compatibility

| Mod | Status |
|---|---|
| **MoodleFramework** (optional, recommended) | The five EHR moodles show only with it. Worked in single player on 42.21. |
| **Indoor Climate Redone** (optional) | Room air feeds the heat and cold meters, also on a dedicated server. The original Indoor Climate (EHR Addon) works in single player only. |
| **Lifestyle: Hobbies** (optional) | A clean, rested, bathed character recovers up to about 50% faster, a dirty one slower. |
| **Mini Health Panel** | A small "EHR Status" panel docks beside it. |
| **Antibodies** | Works beside Redone. |
| **Zombie Virus Vaccine** (B42 port) | Works beside Redone, with three ties. |
| **Raven Creek** | EHR medicine should spawn in its medical rooms. |
| **Red Days, Unseasonal Weather** | Listed as compatible by the original; not yet verified here. |
| **Hephas Vitamins** | Overlaps: both rework the vitamin pills. Use one. |
| **Realistic Temperature** | Not supported. Use Indoor Climate Redone. |
| **Other health reworks** | Not supported. |

Recommended sandbox setting: **Decaying Corpse Health Impact = None**, so only EHR's corpse illness applies.

## Known limitations

- English is complete. The other eight languages keep the original's translations, but about 30% of the interface text is
  still English.
- Controllers: designed in, but not tested on a gamepad.
- No Tuberculosis, They Knew or N&C Narcotics support.
- Many new numbers (loot, new triggers) are first guesses and will be tuned in play-testing.
- Back up your saves, and report bugs with your `console.txt`.
