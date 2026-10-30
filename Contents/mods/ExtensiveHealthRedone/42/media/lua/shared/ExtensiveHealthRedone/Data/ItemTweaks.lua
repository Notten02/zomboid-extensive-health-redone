-- Changes to item scripts we don't own, applied by Core/ItemTweaks. See that module for the entry format.
--
-- The original mod redefined these vanilla items wholesale (EHR_VanillaOverrides.txt). Compared with vanilla 42.21:
--   Base.Pills, Base.PillsAntiDep, Base.PillsBeta   UseDelta 0.1 -> 0.0625 (16 doses)          (below)
--   Base.PillsSleepingTablets                       UseDelta 0.1 -> 0.0833 (12 doses)          (below)
--   Base.PillsVitamins     "Caffeine Pills": UseDelta 0.2 -> 0.0417 (24 doses) and a new tooltip (below); the name
--                          comes from translations. Vanilla's own small fatigue effect stays: the EHR effect holds
--                          fatigue at zero anyway.
--   Base.Antibiotics       food -> drainable with 10 doses: a type change DoParam can't make safely, so vanilla's
--                          single-dose item stays and the medication rules give its effect
--   Base.Scalpel           the copy removed base:nomaintenancexp on purpose ("Let scalpels train Maintenance like
--                          other melee weapons"). Not kept:
--                          vanilla tags 67 tools and improvised weapons this way, and with Scalpel Master's x100
--                          durability the scalpel would become a Maintenance trainer. Everything else in the copy
--                          equals vanilla 42.21, which is already a low-damage stabbing weapon; Scalpel Master's boost
--                          is per item, not a script change (Items/Scalpel, Game/Scalpel)

local DOSES = "the original's dose count per bottle"

return {
    { item = "Base.Pills", property = "UseDelta", value = "0.0625", reason = DOSES },
    { item = "Base.PillsAntiDep", property = "UseDelta", value = "0.0625", reason = DOSES },
    { item = "Base.PillsBeta", property = "UseDelta", value = "0.0625", reason = DOSES },
    { item = "Base.PillsSleepingTablets", property = "UseDelta", value = "0.0833", reason = DOSES },
    { item = "Base.PillsVitamins", property = "UseDelta", value = "0.0417", reason = DOSES },
    { item = "Base.PillsVitamins", property = "Tooltip", value = "Tooltip_CaffeinePills",
        reason = "vitamins are repurposed as Caffeine Pills" },
}
