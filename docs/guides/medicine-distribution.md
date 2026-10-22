# Medicine Distribution

> Player guide for **Extensive Health Redone**. Based on Frozen_Heart's original "Medicine Distribution"
> (`docs/original-author-guides/medicine-distribution.md`), reworked to match the loot tables Redone actually writes
> (`Data/Loot.lua`, `Data/LootFill.lua`, `Loot/*`, `Server/Loot.lua`).
>
> Loot is random. Everything below is "where it can appear and how likely compared with its neighbours", never a
> promise. The *Loot* sandbox page and the multiplayer server's other loot mods change the real results.

## How loot works

- Medicine is added to Project Zomboid's normal container lists, so it appears in the same kinds of places as vanilla
  medical loot. Each item has one entry per list.
- Most medicine comes in **packages with several doses**. When a package is generated, it is partly used up. Pharmacies
  and medical rooms give the fullest packages, ambulances and military crates give less, and houses give the emptiest
  (sometimes a single dose). Vanilla pills are never touched.
- A **small chance of a full package** exists in pharmacies (see the sandbox options below).
- Weights in this guide are **relative within a list**. A weight 10 item is about ten times as likely as a weight 1
  item in that list.
- **Blood bag types** follow realistic rarity: O+ is by far the most common, then A+, then B+, with O- and A- next,
  then B- and AB+, and AB- the rarest. They are not weighted like character blood types.

## Where to look

### Pharmacies, drugstores, supermarkets

**Pharmacy and store medical shelves** (also used by general stores and some gas stations) hold over-the-counter stock:
- Sterilized Bandages (the most common), then Cold & Flu Tablets, Antipyretic Tablets, Anti-Inflammatory Pills, Antiseptic Cream
- Cough Syrup, Cough Suppressant, Anti-Nausea Tablets, Anti-Diarrheal Tablets, Electrolyte Powder
- Muscle Relaxants, Bronchodilator Inhaler (less common)
- Instant Ice Packs, Topical Permethrin
- Alcoholic Bandages
- Saline Bags (rare)

**Pharmacy counters and storage** share the **clinic** list (below), so they are where you find the prescription drugs
a pharmacy should have, including Antipsychotics, Dual Orexin Receptor, Buprenorphine and Furosemide.

**Supermarket toiletry aisles** carry the same OTC items, at roughly 40% of the pharmacy shelf's weight.

### Houses

Houses are the worst source, but they are everywhere.
- **Always:** a small chance of basic OTC medicine in bedroom sidetables and dressers, living room shelves and desks.
- **Bathrooms** (cabinets best, counters and shelves less): OTC medicine, Topical Permethrin and Nitric Oxide Boosters.
- **Prescription leftovers** (only if *Household Prescription Loot* is on, which is the default): Prescription
  Antibiotics most often, then Broad Spectrum Antibiotics, Antibiotic Ointment, and now and then Antipsychotics, Dual
  Orexin Receptor, Buprenorphine, Furosemide and others. Rare, and usually nearly empty.
- **Medicine Storage Box** (with the same option): a rare find in bathrooms.
- Clinical drugs (IV, injections) never spawn in ordinary houses.

### Clinics, medical offices, waiting rooms, hospital rooms

Better odds for **prescription** medicine and supplies.

**Clinic list** (medical rooms' medicine cabinets, pharmacy counters):
- Prescription Antibiotics (best), Broad Spectrum Antibiotics, Antibiotic Ointment
- Antiviral Capsules, Antifungal Tablets, Oral Rehydration Kit
- Antipsychotics, Dual Orexin Receptor, Buprenorphine, Furosemide, Nitric Oxide Boosters
- Topical Permethrin, Instant Ice Packs
- Syringes, Saline Bags, a few IV Fluids, Empty Blood Bags, rarely filled Blood Bags
- Sterilized and Alcoholic Bandages
- Plus a share of the **clinical** list (below), the Medicine Storage Box, and flyers

**Medical cabinets, offices, hospital room counters and shelves** get the OTC cabinet list, prescription leftovers, a
smaller helping of the clinical list, and the Medicine Storage Box. Hospital room shelves also hold plain Epinephrine.

### Medical storage and hospitals

**Medical storage** is the best ordinary source of stronger medicine:
- Everything in the clinic list, plus Activated Charcoal, Antiparasitic Pills, Tetanus Antitoxin
- IV Kits (frequent), IV Fluids, Saline Bags, Syringes
- A solid share of the clinical list
- A few filled Blood Bags (O+, A+ most likely)
- Warming Packs and plain Epinephrine (rare)

**Large hospital storage** is the best civilian source of **clinical-grade** medicine:
- IV Antibiotics (most common), IV Metronidazole, IV Amphotericin B, IV Ciprofloxacin, IV Vancomycin
- IV Fluids (most common clinical item), Emergency Sepsis Kit, Corticosteroid Injection, Respiratory Support Kit
- Chelation Kit, Albendazole Injection, Tetanus Immunoglobulin
- Last Chance Epinephrine and plain Epinephrine
- IV Kits, Syringes, Saline Bags, and a good supply of blood bags and Empty Blood Bags

### Emergency sources

**First aid kits** hold basic field medicine: Antiseptic Cream, Anti-Inflammatory Pills, Antipyretic Tablets,
Electrolyte Powder, bandages, Instant Ice Packs, Topical Permethrin, a Syringe, and rarely a Nitric Oxide Booster.
The newer, professional and military kits also roll an advanced set: Antibiotic Ointment, Oral Rehydration Kit,
Bronchodilator Inhaler, Prescription Antibiotics, and rarely an IV Kit, Corticosteroid Injection or Respiratory Support
Kit.

**Ambulances.** The glove box and front seats hold basic supplies (the seats also Prescription and Broad Spectrum
Antibiotics). The **trunk** is much better and rolls more items: bandages and disinfectants, OTC medicine, Electrolyte
Powder, inhalers, Activated Charcoal, Antibiotic Ointment, Oral Rehydration Kit, Prescription and Broad Spectrum
Antibiotics, plenty of IV Kits, Syringes, Saline Bags, IV Fluids and Empty Blood Bags, Respiratory Support Kit,
Corticosteroid Injection, Emergency Sepsis Kit, Epinephrine, and rare IV antibiotics and other clinical drugs. It also
holds the most Medicine Storage Boxes.

**Medical bags and medical satchels** roll more times than vanilla, and the trauma gear is placed first: IV Kits,
Syringes, Saline Bags, IV Fluids, Empty Blood Bags, Prescription and Broad Spectrum Antibiotics, plus bandages, basic
medicine, and a small chance of clinical drugs.

### Military, police and tactical

**Military medical storage and bunkers** carry the high-value list: Saline Bags, Empty Blood Bags, IV Antibiotics, IV
Ciprofloxacin, IV Fluids, Emergency Sepsis Kit, Corticosteroid Injection, Respiratory Support Kit, Tetanus
Immunoglobulin, IV Kits, Syringes, Broad Spectrum Antibiotics, blood bags, and bandages. The bunker and story
safehouses get smaller helpings of the clinical list.

**Police** storage guns, evidence rooms and SWAT truck beds get the military list at **30%** of its weight, so
medical gear there is rare.

**Combat Stimulants** are restricted tactical supplies. They appear rarely in:
- gun store shelves and cases,
- army storage (medical, outfit, guns, ammunition),
- police storage, evidence, captain's cabinet, desks, police bags,
- police vehicles (glove boxes, seats and truck beds, SWAT trucks best).

### Blood and fluids

Filled Blood Bags, Empty Blood Bags, Saline Bags and IV Fluids are most common in hospital and military storage and in
ambulances, and turn up rarely in clinics. Filled bags **spoil**: after about one warm game hour a bag is stale, after
about two it is rotten (time in a freezer does not count), so loot blood fresh or keep it frozen.

### Warming Packs

Mostly in **garages** (tool, carpentry, mechanics, metalwork), camping and tool **crates**, rarely in closets, laundries
and medical storage.

### Medical Monitor Watch

The Medical Monitor Watch spawns wherever the vanilla red digital watch does, scaled by the sandbox *Medical Watch Loot
Multiplier*. It also drops from zombies, rarely.

## Knox facility items

Experimental Knox items only appear in the **Military Research Facility** basement (if *Knox Cure
Items* is on in the sandbox). Each container rolls once, and does not roll again when loot respawns.

| Level | Items, chance per container |
|---|---|
| Upper basement levels (barracks, storage, offices) | Phalanx Pills 3%, Antibody Test Kit 4%, Immunobooster Shot 2% |
| Lower laboratory levels | **Gene Therapy Kit 1%**, Phalanx Pills 5%, Antibody Test Kit 6%, Immunobooster Shot 4% |

Knox items spawn full.

## Flyers, books and recipes

- **Disease flyers** (one per disease, plus the Blood Types flyer) and the **Wild Medicinal Plants** guide spawn in
  medical storage, clinics, medical cabinets, pharmacies, magazine racks, medical books at offices, hospitals, book
  stores and libraries. In mailboxes they are very rare, about one in 35 to 40. Flyers are unscaled by the medicine
  loot multiplier.
- **Recipe guides:** the Plant-Based Antibiotics recipe and the Ultimate Craft Guide appear on the same shelves, at
  lower odds, and in magazine racks.
- There is no Tuberculosis flyer, Flu flyer or Knox Infection flyer. The Knox infection is learned from the Kentucky
  Herald, July 16, 1993.
- **Zombies** drop loot too (see below).

## Zombies

By default each dead zombie has a **5%** chance (*Zombie Loot Chance*) to carry one medical item. It is a weighted pick:
over-the-counter medicine and bandages are often, prescription drugs and supplies a bit less, clinical drugs rarely,
flyers less often than OTC medicine, blood bags at a quarter of their normal rarity, and the watch very rarely. Zombies never carry the
Medicine Storage Box, Warming Packs, Combat Stimulants, Knox items or crafted-only items.

## Medicine Storage Box

A small container that medical places and ambulances sometimes hold. It is a loot container of its own: three rolls
from the prescription list (Prescription Antibiotics, Broad Spectrum Antibiotics, Antibiotic Ointment and so on) and a
roll from the clinical list (IV Fluids, IV Antibiotics, Corticosteroid Injection and so on). Its contents scale with
the medicine loot multiplier.

## Crafted-only medicine

These are made, not found. None of them spawns as loot.
- Homemade Activated Charcoal, Plant-Based Antibiotics, Homemade Antiseptic Cream, Homemade Antibiotic Ointment,
  Homemade Topical Permethrin
- Homemade Cough Syrup, Homemade Muscle Relaxant, Homemade Painkillers (these do not count toward painkiller
  addiction), Homemade Sleeping Pills
- Herbal teas: Common Cold Tea, Antipyretic Tea, Relaxant Tea
- Spiderweb Bandage, Homemade Syringes, Homemade IV Kit, Homemade Blood Bag
- Honey from honeycomb, and a suture needle from spiderweb

Herbs come from the **medicinal plant search**, and honeycomb and spiderweb from the **hive and spiderweb search**
(see the Mod Overview). Plant-Based Antibiotics need their recipe guide first.

## Sandbox options (Loot page)

- *Medication Loot Multiplier*: scales every medicine, blood bag, saline bag, medical supply and the Medicine Storage Box.
- *Medical Watch Loot Multiplier*.
- *Medication Package Fill* (1 to 4, default 3): how full packages are. At 3, a pharmacy package has 45 to 90% of its
  doses, a medical room 35 to 70%, an ambulance 25 to 70%, a house 5 to 45%.
- *Allow Full Pharmacy Packages*: a chance of a full package in pharmacies (25% at fill 3).
- *Household Prescription Loot*: prescription leftovers and the Medicine Storage Box in houses.
- *Knox Cure Items*: the research facility items.
- *Zombie Loot* and *Zombie Loot Chance*.
