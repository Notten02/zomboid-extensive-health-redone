-- Crafting data: the fresh-herb rule, recipe learning and the clean bandage pack. The recipe scripts
-- (scripts/EHR_Recipes.txt, EHR_SupplyRecipes.txt) hold the recipes themselves; tests/recipes_spec.lua checks that
-- these lists match them.

local function set(list)
    local s = {}
    for _, v in ipairs(list) do
        s[v] = true
    end
    return s
end

-- The 17 medicine and material recipes. They are auto-learned at First Aid 6 plus Foraging 4 (AutoLearnAll in the
-- scripts; Server/Recipes adds a safety net for characters who already have the levels).
local medicine = {
    "MakePlantBasedAntibiotics", "MakeHomemadeActivatedCharcoal", "MakeHomemadeAntisepticCream",
    "MakeHomemadeAntibioticOintment", "MakeHomemadeTopicalPermethrin", "MakeHomemadeCoughSyrup",
    "MakeHomemadeMuscleRelaxant", "MakeHomemadePainkillers", "MakeHomemadeSleepingPills", "MakeCommonColdTea",
    "MakeAntipyreticTea", "MakeRelaxantTea", "MakeSpiderwebBandage", "MakeHoneyFromHoneycomb",
    "MakeSutureNeedleFromSpiderweb", "PrepareTallowMixture", "StrainRenderedTallow",
}

-- The 7 supply recipes: only the Ultimate guide and the two EHR professions teach them.
local supply = {
    "MakeHomemadeSyringes", "CutPlasticStripsSmall", "CutPlasticStripsBottle", "CutPlasticStripsLarge",
    "CutPlasticStripsHeavy", "PrepareHomemadeBloodBag", "MakeHomemadeIVKit",
}

local all = {}
for _, name in ipairs(medicine) do
    all[#all + 1] = name
end
for _, name in ipairs(supply) do
    all[#all + 1] = name
end

return {
    -- Medicinal ingredients that must be fresh (not stale, not rotten). v0.9's list; 42.21's dried herbs are not
    -- accepted by the recipes at all (maintainer decision 2026-10-14).
    freshOnly = set({
        "Base.Garlic", "Base.WildGarlic2", "Base.Oregano", "Base.Thyme", "Base.Lavender", "Base.GingerRoot",
        "Base.Plantain", "Base.Comfrey", "Base.Marigold", "Base.CommonMallow", "Base.Chamomile", "Base.BlackSage",
        "Base.LemonGrass", "Base.BerryBlack", "Base.BerryBlue", "Base.BerryGeneric1", "Base.BerryGeneric2",
        "Base.BerryGeneric3", "Base.BerryGeneric4", "Base.BerryGeneric5",
    }),

    -- Skill levels for the auto-learned recipes, all of them needed (the scripts' AutoLearnAll, in its order).
    autoLearnLevels = { { perk = "Doctor", level = 6 }, { perk = "PlantScavenging", level = 4 } },
    autoLearned = medicine,
    supply = supply,
    all = all,                                  -- what the Ultimate guide and the EHR professions teach

    -- Clean bandage pack: a drainable whose uses are bandages. The pack recipes are not learned.
    pack = {
        item = "ExtensiveHealth.SterilizedBandages",
        bandage = "Base.Bandage",
        size = 5,                               -- 1 / UseDelta of the pack item
        recipes = { "EHRTakeBandageFromPack", "EHRUnpackBandagePack", "EHRPackBandages", "EHRAddBandageToPack",
            "EHRStartBandagePack" },
    },
}
