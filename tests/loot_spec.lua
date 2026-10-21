-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- World loot (Data/Loot, Data/LootFill, Loot/Build, Loot/Apply, Loot/Fill): every item exists in our scripts, every
-- list exists in vanilla 42.21, one entry per item per list, scaling and gates, the guide's placement rules, the
-- table writer and its undo, the package fill, Knox facility rolls and the zombie pool.

local Data = require("ExtensiveHealthRedone/Data/Loot")
local FillData = require("ExtensiveHealthRedone/Data/LootFill")
local Build = require("ExtensiveHealthRedone/Loot/Build")
local Apply = require("ExtensiveHealthRedone/Loot/Apply")
local Fill = require("ExtensiveHealthRedone/Loot/Fill")

local SCRIPTS = "Contents/mods/ExtensiveHealthRedone/42/media/scripts"
local VANILLA = "/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid/media/lua/server/"

local function read(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local s = f:read("*a")
    f:close()
    return s
end

-- Our script items: { [name] = { useDelta = n? } } (module ExtensiveHealth).
local function scriptItems()
    local items = {}
    local p = assert(io.popen('find "' .. SCRIPTS .. '" -name "*.txt" | sort'))
    for path in p:lines() do
        local current
        for line in assert(read(path)):gmatch("[^\n]+") do
            local name = line:match("^%s*item%s+([%w_]+)")
            if name then
                current = { }
                items[name] = current
            elseif current then
                local delta = line:match("^%s*UseDelta%s*=%s*([%d.]+)")
                if delta then
                    current.useDelta = tonumber(delta)
                end
            end
        end
    end
    p:close()
    return items
end

local SCRIPT_ITEMS = scriptItems()

local function exists(fullType)
    local module, name = fullType:match("^([^.]+)%.(.+)$")
    return module == "ExtensiveHealth" and SCRIPT_ITEMS[name] ~= nil
end

-- Vanilla 42.21 names this module writes into, checked by hand against the game's Lua (and re-checked below when the
-- game is installed). proc: ProceduralDistributions.list; bag: Distributions.lua (bags alias BagsAndContainers);
-- vehicle: VehicleDistributions; room: SuburbsDistributions rooms.
local VANILLA_LISTS = {
    proc = {
        "StoreShelfMedical", "GigamartToiletries", "MedicalCabinet", "MedicalClinicDrugs", "MedicalClinicTools",
        "MedicalStorageDrugs", "MedicalStorageOutfit", "MedicalStorageTools", "MedicalOfficeCounter",
        "MedicalOfficeDesk", "MedicalOfficeBooks", "HospitalRoomCounter", "HospitalRoomShelves",
        "HospitalMagazineRack", "ArmyStorageMedical", "ArmyStorageOutfit", "ArmyStorageGuns",
        "ArmyStorageAmmunition", "ArmyBunkerMedical", "SafehouseMedical", "SafehouseMedical_Mid",
        "SafehouseMedical_Late", "GunStoreAccessories", "GunStoreCases", "GunStoreBodyArmor", "GunStoreAmmunition",
        "GunStoreKnives", "PoliceStorageGuns", "PoliceEvidence", "PoliceCaptainCabinet", "PoliceDesk", "GarageTools",
        "GarageCarpentry", "GarageMechanics", "GarageMetalwork", "CrateCamping", "CrateHumanitarian", "CrateTools",
        "CrateRandomJunk", "ClosetShelfGeneric", "LaundryCleaning", "MagazineRackMixed", "BookstoreMedical",
        "LibraryMedical", "UniversityLibraryMedical", "UniversityDesk_Medical", "BedroomSidetable",
        "BedroomSidetableClassy", "BedroomSidetableRedneck", "BedroomDresser", "BedroomDresserClassy",
        "BedroomDresserRedneck", "LivingRoomShelf", "LivingRoomShelfClassy", "LivingRoomShelfRedneck", "DeskGeneric",
        "BathroomCabinet", "BathroomCounter", "BathroomShelf",
    },
    bag = {
        "FirstAidKit", "FirstAidKit_New", "FirstAidKit_Camping", "FirstAidKit_Camping_New", "FirstAidKit_Military",
        "FirstAidKit_Pro", "FirstAidKit_NewPro", "Bag_MedicalBag", "Bag_Satchel_Medical", "Bag_Police",
    },
    vehicle = {
        "AmbulanceGloveBox", "AmbulanceSeatFront", "AmbulanceTruckBed", "PoliceGloveBox", "PoliceSeatFront",
        "PoliceTruckBed", "PoliceSWATGloveBox", "PoliceSWATSeatFront", "PoliceSWATTruckBed",
    },
    postbox = { "postbox" },
    room = { "medical", "medicalstorage", "oldmedical" },
}

local function setOf(list)
    local s = {}
    for _, v in ipairs(list) do
        s[v] = true
    end
    return s
end

local DELETED = setOf({ "ExtensiveHealth.TBAntibiotics", "ExtensiveHealth.RifampicinComboPack",
    "ExtensiveHealth.DiseaseFlyer_Tuberculosis", "ExtensiveHealth.DiseaseFlyer_Flu",
    "ExtensiveHealth.DiseaseFlyer_KnoxInfection" })
local KNOX = setOf({ "ExtensiveHealth.PhalanxPills", "ExtensiveHealth.AntibodyTestKit",
    "ExtensiveHealth.ImmunoboosterShot", "ExtensiveHealth.GeneTherapyKit" })

local function isCrafted(fullType)
    local name = fullType:match("%.(.+)$")
    return name:find("^Home[Mm]ade") ~= nil or name:find("Tea$") ~= nil or name:find("Tallow") ~= nil
        or setOf({ "PlantBasedAntibiotics", "SpiderwebBandage", "PreparedHomemadeBloodBag", "Spiderweb", "Honeycomb",
            "PlasticStrips" })[name] == true
end

local DEFAULTS = { medication = 1, watch = 1, gates = { HouseholdPrescriptionLoot = true } }

local function options(medication, rx)
    return { medication = medication, watch = 1, gates = { HouseholdPrescriptionLoot = rx ~= false } }
end

-- built target by list name -> { [item] = chance }
local function byList(built)
    local out = {}
    for _, t in ipairs(built) do
        local items = {}
        for _, e in ipairs(t.front) do
            items[e.item] = e.chance
        end
        for _, e in ipairs(t.back) do
            items[e.item] = e.chance
        end
        out[t.list] = items
    end
    return out
end

local function every(fn)
    for name, pool in pairs(Data.pools) do
        for item in pairs(pool.items) do
            fn(Build.fullType(Data.MODULE, item), "pool " .. name)
        end
    end
    for item in pairs(Data.box.items) do
        fn(Build.fullType(Data.MODULE, item), "box")
    end
    for item in pairs(Data.box.junk) do
        fn(Build.fullType(Data.MODULE, item), "box junk")
    end
    fn(Build.fullType(Data.MODULE, Data.watch.target), "watch")
    for _, entry in ipairs(Build.zombiePool(FillData.zombie, Data)) do
        fn(entry.item, "zombie")
    end
    for item in pairs(FillData.fillItems) do
        fn(item, "package fill")
    end
end

local function near(a, b)
    return math.abs(a - b) < 1e-9
end

describe("loot data", function()
    it("names only items that exist in our scripts", function()
        every(function(item, where)
            assert.is_true(exists(item), item .. " (" .. where .. ") is not in our scripts")
        end)
        for _, level in ipairs(FillData.knox.levels) do
            for _, entry in ipairs(level.items) do
                assert.is_true(exists(entry.item), entry.item)
            end
        end
    end)

    it("never spawns deleted, crafted-only or Knox items outside the facility", function()
        every(function(item, where)
            assert.is_nil(DELETED[item], item .. " is deleted (" .. where .. ")")
            assert.is_false(isCrafted(item), item .. " is crafted-only (" .. where .. ")")
            assert.is_nil(KNOX[item], item .. " is a Knox item (" .. where .. ")")
        end)
    end)

    it("writes only into vanilla 42.21 lists on the checked list", function()
        for _, t in ipairs(Data.targets) do
            assert.is_true(setOf(VANILLA_LISTS[t.kind])[t.list], t.kind .. ":" .. t.list .. " is not a checked list")
            for _, add in ipairs(t.add) do
                assert.is_table(Data.pools[add.pool], t.list .. " uses unknown pool " .. add.pool)
            end
        end
        for _, rp in ipairs(Data.roomProcs) do
            assert.is_true(setOf(VANILLA_LISTS.room)[rp.room], rp.room)
            assert.is_true(setOf(VANILLA_LISTS.proc)[rp.proc], rp.proc)
        end
    end)

    local vp = read(VANILLA .. "Items/ProceduralDistributions.lua")
    local vd = read(VANILLA .. "Items/Distributions.lua")
    local vv = read(VANILLA .. "Vehicles/VehicleDistributions.lua")
    local present = vp and vd and vv and it or pending

    present("checked list matches the installed game's Lua", function()
        local function defined(text, name)
            return text:find("\n%s*" .. name .. "%s*=%s*{") ~= nil
                or text:find("\n%s*" .. name .. "%s*=%s*BagsAndContainers%." .. name .. "%f[^%w_]") ~= nil
                or text:find("\nVehicleDistributions%." .. name .. "%s*=%s*{") ~= nil
        end
        for _, name in ipairs(VANILLA_LISTS.proc) do
            assert.is_true(defined(vp, name), "proc " .. name)
        end
        for _, name in ipairs(VANILLA_LISTS.bag) do
            assert.is_true(defined(vd, name), "bag " .. name)
        end
        for _, name in ipairs(VANILLA_LISTS.vehicle) do
            assert.is_true(defined(vv, name), "vehicle " .. name)
        end
        for _, name in ipairs(VANILLA_LISTS.room) do
            assert.is_true(defined(vd, name), "room " .. name)
        end
        assert.is_true(defined(vd, "postbox"))
        -- v0.9's other targets really are gone (their blocks are folded or dropped here).
        for _, name in ipairs({ "MedicalStorageBlood", "AmbulanceMedical", "ArmySurplusMedical" }) do
            assert.is_false(defined(vp, name), name .. " exists again; revisit the fold")
        end
        assert(vp, "vanilla distributions not read")
        assert.truthy(vp:find('"WristWatch_Left_DigitalRed"', 1, true))
    end)

    it("lists the multi-dose items the package fill touches as drainables in our scripts", function()
        for item in pairs(FillData.fillItems) do
            local delta = SCRIPT_ITEMS[item:match("%.(.+)$")].useDelta
            assert.is_number(delta, item)
            assert.is_true(delta < 1, item .. " has one use")
        end
    end)
end)

describe("loot builder", function()
    local built = Build.targets(Data, DEFAULTS)
    local lists = byList(built)

    it("has one target per list and one entry per item", function()
        local seen = {}
        for _, t in ipairs(built) do
            assert.is_nil(seen[t.list], "two targets for " .. t.list)
            seen[t.list] = true
            local items = {}
            for _, side in ipairs({ t.front, t.back }) do
                for _, e in ipairs(side) do
                    assert.is_nil(items[e.item], e.item .. " twice in " .. t.list)
                    items[e.item] = true
                    assert.is_true(e.chance > 0)
                end
            end
        end
    end)

    it("sums v0.9's doubled entries and overlapping pools into one entry", function()
        local m = "ExtensiveHealth."
        assert.is_true(near(6, lists.StoreShelfMedical[m .. "SterilizedBandages"]))
        assert.is_true(near(8 + 4 * 0.8, lists.MedicalClinicDrugs[m .. "Syringe"]))
        assert.is_true(near(7 + 3 * 0.8, lists.MedicalClinicDrugs[m .. "SalineBag"]))
        assert.is_true(near(10 + 4 * 1.5, lists.MedicalStorageDrugs[m .. "Syringe"]))
        assert.is_true(near(1 + 0.7, lists.MedicalCabinet[m .. "TopicalPermethrin"]))
        assert.is_true(near(12, lists.ArmyStorageMedical[m .. "SalineBag"]))
        -- Hospital blood folded into large hospital storage: rarity x 1 plus saline 6, IV fluids 5, empty bags 8.
        assert.is_true(near(7 + 6, lists.MedicalStorageOutfit[m .. "SalineBag"]))
        assert.is_true(near(8, lists.MedicalStorageOutfit[m .. "BloodBagOPos"]))
        assert.is_true(near(0.5, lists.MedicalStorageOutfit[m .. "BloodBagABNeg"]))
        -- Bedroom Permethrin: common pool x 1.5 (none) + bathroom medicine 1 x 0.2 + prescription 0.06 x 1.5.
        assert.is_true(near(0.2 + 0.09, lists.BedroomSidetable[m .. "TopicalPermethrin"]))
    end)

    it("scales every medical spawn by MedicationLootMultiplier and leaves literature alone", function()
        local double = byList(Build.targets(Data, options(2)))
        for list, items in pairs(lists) do
            for item, chance in pairs(items) do
                local literature = item:find("DiseaseFlyer_") or item:find("EhrRecipe") or item:find("MedicalWildPlants")
                local want = literature and chance or chance * 2
                assert.is_true(near(want, double[list][item]), list .. " " .. item)
            end
        end
    end)

    it("adds nothing medical and raises no rolls at multiplier 0", function()
        for _, t in ipairs(Build.targets(Data, options(0))) do
            assert.is_nil(t.minRolls, t.list)
            for _, side in ipairs({ t.front, t.back }) do
                for _, e in ipairs(side) do
                    local literature = e.item:find("DiseaseFlyer_") or e.item:find("EhrRecipe")
                        or e.item:find("MedicalWildPlants")
                    assert.truthy(literature, e.item .. " in " .. t.list .. " at multiplier 0")
                end
            end
        end
        local box = Build.box(Data, options(0))
        assert.equal(0, #box.items)
        assert.equal(0, #box.junk.items)
    end)

    it("raises rolls only for ambulances and medical bags", function()
        local raised = {}
        for _, t in ipairs(built) do
            if t.minRolls then
                raised[t.list] = t.minRolls
            end
        end
        assert.same({ AmbulanceGloveBox = 2, AmbulanceSeatFront = 2, AmbulanceTruckBed = 6, Bag_MedicalBag = 4,
            Bag_Satchel_Medical = 3 }, raised)
    end)

    it("puts trauma gear first in medical bags, heaviest first", function()
        local bag
        for _, t in ipairs(built) do
            if t.list == "Bag_MedicalBag" then
                bag = t
            end
        end
        assert.equal("ExtensiveHealth.Syringe", bag.front[1].item)
        for i = 2, #bag.front do
            assert.is_true(bag.front[i - 1].chance >= bag.front[i].chance)
        end
        for _, e in ipairs(bag.back) do
            assert.is_nil(Data.pools.trauma.items[e.item:match("%.(.+)$")], e.item)
        end
    end)

    it("gates household prescription leftovers and the bathroom box on HouseholdPrescriptionLoot", function()
        local off = byList(Build.targets(Data, options(1, false)))
        local rx = { "PrescriptionAntibiotics", "BroadSpectrumAntibiotics", "Antipsychotics", "DualOrexinReceptor",
            "Buprenorphine", "AntiviralCapsules", "Furosemide", "MedicineStorageBox" }
        for _, list in ipairs({ "BedroomSidetable", "BedroomDresserClassy", "LivingRoomShelf", "DeskGeneric",
            "BathroomCabinet", "BathroomShelf" }) do
            for _, name in ipairs(rx) do
                assert.is_nil(off[list]["ExtensiveHealth." .. name], list .. " " .. name)
            end
            assert.is_not_nil(off[list]["ExtensiveHealth.AntipyreticTablets"], list)
        end
        assert.is_not_nil(lists.BathroomCabinet["ExtensiveHealth.MedicineStorageBox"])
        assert.is_not_nil(lists.BathroomCabinet["ExtensiveHealth.Antipsychotics"])
    end)
end)

describe("loot placement follows the guide", function()
    local lists = byList(Build.targets(Data, DEFAULTS))

    local function where(name)
        local out = {}
        for list, items in pairs(lists) do
            if items["ExtensiveHealth." .. name] then
                out[list] = true
            end
        end
        return out
    end

    it("keeps prescription psych drugs off general-store shelves", function()
        for _, name in ipairs({ "Antipsychotics", "DualOrexinReceptor", "Buprenorphine" }) do
            assert.is_nil(lists.StoreShelfMedical["ExtensiveHealth." .. name], name)
            assert.is_nil(lists.GigamartToiletries["ExtensiveHealth." .. name], name)
            assert.is_not_nil(lists.MedicalClinicDrugs["ExtensiveHealth." .. name], name)
        end
    end)

    it("spawns combat stimulants only in gun stores, military and police places", function()
        for list in pairs(where("CombatStimulants")) do
            assert.truthy(list:find("^GunStore") or list:find("^Army") or list:find("^Police")
                or list == "Bag_Police", list)
        end
    end)

    it("keeps clinical drugs out of houses, stores, first-aid kits and fridges", function()
        for _, name in ipairs({ "IVAntibiotics", "IVVancomycin", "EmergencySepsisKit", "ChelationKit",
            "TetanusImmunoglobulin", "LastChanceEpinephrine" }) do
            for list in pairs(where(name)) do
                assert.is_falsy(list:find("^Bedroom") or list:find("^Bathroom") or list:find("^LivingRoom")
                    or list == "DeskGeneric" or list == "StoreShelfMedical" or list == "GigamartToiletries"
                    or list:find("^FirstAidKit") or list == "FridgeMedical", name .. " in " .. list)
            end
        end
    end)

    it("puts plain Epinephrine only in hospitals, ambulances and medical bags (W6)", function()
        assert.same({ MedicalStorageOutfit = true, MedicalStorageDrugs = true, HospitalRoomShelves = true,
            AmbulanceTruckBed = true, AmbulanceSeatFront = true, AmbulanceGloveBox = true, Bag_MedicalBag = true,
            Bag_Satchel_Medical = true }, where("Epinephrine"))
        assert.equal(2.4, lists.MedicalStorageOutfit["ExtensiveHealth.Epinephrine"])
        assert.equal(4, lists.AmbulanceTruckBed["ExtensiveHealth.Epinephrine"])
    end)

    it("gives police storage, evidence and SWAT trucks the military pool, not desks or patrol cars", function()
        for _, list in ipairs({ "PoliceStorageGuns", "PoliceEvidence", "PoliceSWATTruckBed" }) do
            assert.is_true(near(12 * 0.3, lists[list]["ExtensiveHealth.SalineBag"]), list)
            assert.is_true(near(5 * 0.3, lists[list]["ExtensiveHealth.IVAntibiotics"]), list)
        end
        for _, list in ipairs({ "PoliceDesk", "PoliceSeatFront", "PoliceGloveBox", "PoliceTruckBed",
            "PoliceCaptainCabinet" }) do
            assert.is_nil(lists[list]["ExtensiveHealth.SalineBag"], list)
        end
    end)

    it("keeps blood bags rarest for AB- and commonest for O+, rare in clinics", function()
        for _, list in ipairs({ "MedicalStorageOutfit", "ArmyStorageMedical", "AmbulanceTruckBed",
            "MedicalClinicDrugs", "Bag_MedicalBag" }) do
            local items = lists[list]
            for _, name in ipairs({ "BloodBagAPos", "BloodBagBPos", "BloodBagONeg", "BloodBagANeg", "BloodBagBNeg",
                "BloodBagABPos", "BloodBagABNeg" }) do
                assert.is_true(items["ExtensiveHealth.BloodBagOPos"] > items["ExtensiveHealth." .. name], list)
                assert.is_true(items["ExtensiveHealth.BloodBagABNeg"] <= items["ExtensiveHealth." .. name], list)
            end
        end
        assert.is_true(lists.MedicalClinicDrugs["ExtensiveHealth.BloodBagOPos"]
            < lists.MedicalStorageOutfit["ExtensiveHealth.BloodBagOPos"])
    end)

    it("spreads all 19 disease flyers, the wild plants guide and both recipe guides", function()
        local flyers = 0
        for name in pairs(Data.pools.flyers.items) do
            if name:find("^DiseaseFlyer_") then
                flyers = flyers + 1
            end
        end
        assert.equal(19, flyers)
        for _, list in ipairs({ "MedicalStorageDrugs", "MedicalClinicDrugs", "MedicalCabinet", "StoreShelfMedical" }) do
            assert.is_not_nil(lists[list]["ExtensiveHealth.DiseaseFlyer_CommonCold"], list)
            assert.is_not_nil(lists[list]["ExtensiveHealth.MedicalWildPlants"], list)
            assert.is_not_nil(lists[list]["ExtensiveHealth.EhrRecipePlantBasedAntibiotics"], list)
            assert.is_not_nil(lists[list]["ExtensiveHealth.EhrRecipeUltimateCraftGuide"], list)
        end
        assert.is_true(near(4 * 0.04, lists.postbox["ExtensiveHealth.DiseaseFlyer_CommonCold"]))
        assert.is_nil(lists.postbox["ExtensiveHealth.EhrRecipeUltimateCraftGuide"])
    end)

    it("spawns Warming Packs mostly in garages and crates", function()
        local w = "ExtensiveHealth.WarmingPack"
        assert.is_true(lists.CrateCamping[w] > lists.MedicalStorageDrugs[w])
        assert.is_true(lists.GarageTools[w] > lists.MedicalClinicDrugs[w])
    end)
end)

describe("loot writer", function()
    local function fakeTables()
        local procedural, vehicles = {}, {}
        for _, name in ipairs(VANILLA_LISTS.proc) do
            procedural[name] = { rolls = 4, items = { "Base.Pills", 10 } }
        end
        procedural.JewelryWrist = { rolls = 2, items = { "WristWatch_Left_DigitalRed", 10 } }
        procedural.StoreDisplayWatches = { rolls = 2, items = {
            "Base.WristWatch_Left_DigitalRed", 10, "Base.Bracelet", 5, "Base.WristWatch_Left_DigitalRed", 10 } }
        for _, name in ipairs(VANILLA_LISTS.vehicle) do
            vehicles[name] = { rolls = 1, items = { "Base.Bandage", 5 } }
        end
        local suburbs = { all = { postbox = { rolls = 2, items = { "Base.Letter", 20 } } } }
        for _, name in ipairs(VANILLA_LISTS.bag) do
            suburbs[name] = { rolls = 2, items = { "Base.Bandage", 50 } }
        end
        suburbs.medical = { sidetable = { procedural = true, procList = {
            { name = "MedicalStorageOutfit", min = 0, max = 99 } } } }
        suburbs.medicalstorage = { sidetable = { rolls = 1, items = {} } }
        suburbs.oldmedical = { medicine = { rolls = 1, items = { "Base.Pills", 5 } } }
        return { procedural = procedural, vehicles = vehicles, suburbs = suburbs }
    end

    local function copy(v)
        if type(v) ~= "table" then
            return v
        end
        local out = {}
        for k, x in pairs(v) do
            out[k] = copy(x)
        end
        return out
    end

    local function count(items, name)
        local n = 0
        for i = 1, #items, 2 do
            if items[i] == name then
                n = n + 1
            end
        end
        return n
    end

    it("writes every target once, front entries first, and raises rolls", function()
        local t = fakeTables()
        local record = Apply.newRecord()
        local report = Apply.write(Build.targets(Data, DEFAULTS), t, record)
        assert.same({}, report.missing)
        assert.same({}, report.shared)
        assert.equal(#Data.targets, report.lists)
        local bag = t.suburbs.Bag_MedicalBag
        assert.equal("ExtensiveHealth.Syringe", bag.items[1])
        assert.equal(4, bag.rolls)
        assert.equal(6, t.vehicles.AmbulanceTruckBed.rolls)
        assert.equal(2, t.suburbs.FirstAidKit.rolls)
        assert.equal(1, count(t.procedural.StoreShelfMedical.items, "ExtensiveHealth.SterilizedBandages"))
        assert.equal(1, count(t.suburbs.all.postbox.items, "ExtensiveHealth.DiseaseFlyer_CommonCold"))
        -- Vanilla entries stay where they were.
        assert.equal(1, count(t.procedural.StoreShelfMedical.items, "Base.Pills"))
    end)

    it("reports missing lists and never aliases them", function()
        local t = fakeTables()
        t.procedural.MedicalCabinet = nil
        local report = Apply.write(Build.targets(Data, DEFAULTS), t, Apply.newRecord())
        assert.same({ "proc:MedicalCabinet" }, report.missing)
        assert.equal(0, count(t.procedural.MedicalClinicDrugs.items, "ExtensiveHealth.ColdFluTablets"))
    end)

    it("skips a second target that resolves to the same table", function()
        local t = fakeTables()
        t.procedural.BedroomSidetableClassy = t.procedural.BedroomSidetable
        local report = Apply.write(Build.targets(Data, DEFAULTS), t, Apply.newRecord())
        assert.same({ "proc:BedroomSidetableClassy" }, report.shared)
        assert.equal(1, count(t.procedural.BedroomSidetable.items, "ExtensiveHealth.ColdFluTablets"))
    end)

    it("mirrors the red digital watch once per list at the summed weight x multiplier", function()
        local t = fakeTables()
        local record = Apply.newRecord()
        local target = "ExtensiveHealth.EHRMedicalWatch_Left"
        assert.equal(2, Apply.mirror(t.procedural, Data.watch.source, target, 0.5, record))
        local items = t.procedural.StoreDisplayWatches.items
        assert.equal(1, count(items, target))
        assert.equal(10, items[#items])
        assert.equal(5, t.procedural.JewelryWrist.items[4])
        assert.equal(0, Apply.mirror(t.procedural, Data.watch.source, target, 0, record))
    end)

    it("undoes everything it wrote, so a re-apply cannot stack", function()
        local t = fakeTables()
        local before = copy(t)
        local record = Apply.newRecord()
        Apply.write(Build.targets(Data, DEFAULTS), t, record)
        Apply.mirror(t.procedural, Data.watch.source, "ExtensiveHealth.EHRMedicalWatch_Left", 1, record)
        Apply.undo(record)
        assert.same(before, t)
        Apply.write(Build.targets(Data, options(2)), t, record)
        assert.equal(1, count(t.procedural.MedicalClinicDrugs.items, "ExtensiveHealth.Syringe"))
    end)

    it("adds the medical room procs once, converting only empty containers", function()
        local t = fakeTables()
        local added, skipped = Apply.roomProcs(t.suburbs, Data.roomProcs)
        assert.equal(7, added)
        assert.same({ "oldmedical.medicine", "oldmedical.medicine" }, skipped)
        assert.equal(2, #t.suburbs.medical["medicine"].procList)
        assert.equal(2, #t.suburbs.medical.sidetable.procList)
        assert.is_true(t.suburbs.medicalstorage.sidetable.procedural)
        assert.is_nil(t.suburbs.medicalstorage.sidetable.items)
        local again = Apply.roomProcs(t.suburbs, Data.roomProcs)
        assert.equal(0, again)
    end)

    it("defines the box contents with three prescription rolls and one clinical roll", function()
        local suburbs = {}
        Apply.defineBox(suburbs, Data.box.type, Build.box(Data, DEFAULTS))
        local box = suburbs.MedicineStorageBox
        assert.equal(3, box.rolls)
        assert.equal(1, box.junk.rolls)
        assert.equal("ExtensiveHealth.ActivatedCharcoal", box.items[1])
        assert.equal(1, count(box.junk.items, "ExtensiveHealth.LastChanceEpinephrine"))
        local half = Build.box(Data, options(0.5))
        assert.equal(Data.box.items.ActivatedCharcoal * 0.5, half.items[2])
    end)
end)

describe("spawn-time loot rules", function()
    local function rng(float, pickInt)
        return {
            float = function() return float end,
            int = function(lo, hi) return pickInt == "high" and hi or lo end,
        }
    end

    it("classifies locations by exact room and container names", function()
        assert.equal("pharmacy", Fill.location(FillData, "pharmacystorage", "counter"))
        assert.equal("ambulance", Fill.location(FillData, "Base.VanAmbulance", "TruckBed"))
        assert.equal("medical", Fill.location(FillData, "hospitalroom", "counter"))
        assert.equal("military", Fill.location(FillData, "armystorage", "metal_shelves"))
        -- v0.9's substring bugs: a bathroom "medicine" cabinet is household, an office desk is not.
        assert.equal("household", Fill.location(FillData, "bathroom", "medicine"))
        assert.equal("default", Fill.location(FillData, "office", "desk"))
        assert.equal("household", Fill.location(FillData, "motelroom", "sidetable"))
        assert.equal("default", Fill.location(FillData, "gigamart", "shelves"))
        assert.equal("default", Fill.location(FillData, nil, nil))
        assert.equal("ambulance", Fill.subLocation(FillData, "Bag_MedicalBag", "default"))
        assert.equal("household", Fill.subLocation(FillData, "FirstAidKit_Pro", "medical"))
        assert.equal("medical", Fill.subLocation(FillData, "MedicineStorageBox", "medical"))
    end)

    it("leaves packages partly used within the profile's range", function()
        local normal = Fill.profile(FillData, 3)
        -- 12 doses, household .05-.45: 1 to 5 doses.
        assert.equal(1, Fill.doses(12, normal, "household", true, rng(0.9, "low")))
        assert.equal(5, Fill.doses(12, normal, "household", true, rng(0.9, "high")))
        -- Medical .35-.70 of 5: 2 to 3.
        assert.equal(3, Fill.doses(5, normal, "medical", true, rng(0.9, "high")))
        -- Pharmacy: full at 25% with AllowFullPharmacyPackages, never without.
        assert.equal(12, Fill.doses(12, normal, "pharmacy", true, rng(0.1, "low")))
        assert.equal(6, Fill.doses(12, normal, "pharmacy", false, rng(0.1, "low")))
        -- One-use items stay full; an unknown profile is Normal; an unknown location uses default.
        assert.equal(1, Fill.doses(1, normal, "household", true, rng(0.1, "low")))
        assert.equal(normal, Fill.profile(FillData, 9))
        assert.equal(2, Fill.doses(12, normal, "nowhere", true, rng(0.9, "low")))
    end)

    it("rolls Knox items only in facility basement containers, Gene Therapy only on the lab levels", function()
        local knox = FillData.knox
        assert.is_nil(Fill.knoxItems(knox, 5550, 12450, -1, "crate"))
        assert.is_nil(Fill.knoxItems(knox, 5550, 12450, 0, "crate"))
        assert.is_nil(Fill.knoxItems(knox, 6000, 12450, -14, "crate"))
        assert.is_nil(Fill.knoxItems(knox, 5550, 12450, -14, "fridge"))
        assert.is_nil(Fill.knoxItems(knox, 5550, 12450, -14, "medicinecabinet"))
        local upper = assert(Fill.knoxItems(knox, 5550, 12450, -13, "Crate"))
        assert.equal(3, #upper)
        for _, entry in ipairs(upper) do
            assert.is_true(entry.item ~= "ExtensiveHealth.GeneTherapyKit")
        end
        local lab = assert(Fill.knoxItems(knox, 5550, 12450, -16, "metal_shelves"))
        assert.equal("ExtensiveHealth.GeneTherapyKit", lab[1].item)
        assert.equal(lab, Fill.knoxItems(knox, 5550, 12450, -17, "desk"))
        assert.same({}, Fill.knoxRoll(lab, rng(0, "high")))
        assert.equal(4, #Fill.knoxRoll(lab, rng(0, "low")))
    end)

    it("picks zombie loot by weight from a pool without excluded items", function()
        local pool = Build.zombiePool(FillData.zombie, Data)
        local weights = {}
        for _, e in ipairs(pool) do
            weights[e.item] = e.weight
        end
        for _, name in ipairs({ "MedicineStorageBox", "WarmingPack", "CombatStimulants", "EHRMedicalWatch_Right",
            "Epinephrine", "PhalanxPills" }) do
            assert.is_nil(weights["ExtensiveHealth." .. name], name)
        end
        assert.equal(4, weights["ExtensiveHealth.SterilizedBandages"])
        assert.equal(2, weights["ExtensiveHealth.PrescriptionAntibiotics"])
        assert.equal(0.5, weights["ExtensiveHealth.IVVancomycin"])
        assert.equal(0.25, weights["ExtensiveHealth.EHRMedicalWatch_Left"])
        assert.equal(2, weights["ExtensiveHealth.BloodBagOPos"])
        assert.equal(0.125, weights["ExtensiveHealth.BloodBagABNeg"])
        assert.equal(pool[1].item, Fill.pick(pool, rng(0)))
        assert.equal(pool[#pool].item, Fill.pick(pool, rng(0.999999)))
        assert.is_true(Fill.percent(5, rng(0.04)))
        assert.is_false(Fill.percent(5, rng(0.06)))
        assert.is_false(Fill.percent(0, rng(0)))
    end)

    it("reads options with clamping and defaults", function()
        local values = { MedicationLootMultiplier = 5, MedicalWatchLootMultiplier = -1 }
        local o = Build.options(function(name, default)
            if values[name] == nil then
                return default
            end
            return values[name]
        end)
        assert.equal(2, o.medication)
        assert.equal(0, o.watch)
        assert.is_true(o.gates.HouseholdPrescriptionLoot)
        assert.is_true(Build.sameOptions(o, { medication = 2, watch = 0, gates = { HouseholdPrescriptionLoot = true } }))
        assert.is_false(Build.sameOptions(o, DEFAULTS))
    end)
end)
