-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, undefined-field, duplicate-set-field
-- Server/Loot against the fake game: the distribution write at OnPreDistributionMerge (with the single-player
-- sandbox preload), the re-apply at OnInitGlobalModData when the options changed, the package fill and Knox items
-- on OnFillContainer, and zombie loot.

insulate("single-player wiring: loot", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    local function newEvent()
        local event = { handlers = {} }
        function event.Add(fn)
            event.handlers[#event.handlers + 1] = fn
        end
        function event.trigger(...)
            for _, h in ipairs(event.handlers) do
                h(...)
            end
        end
        return event
    end
    for _, name in ipairs({ "OnPreDistributionMerge", "OnInitGlobalModData", "OnFillContainer", "OnZombieDead" }) do
        _G.Events[name] = newEvent()
    end

    -- Distribution tables: just the lists this test looks at; the rest are reported missing.
    _G.ProceduralDistributions = { list = {
        MedicalClinicDrugs = { rolls = 4, items = { "Base.Pills", 4 } },
        JewelryWrist = { rolls = 2, items = { "Base.WristWatch_Left_DigitalRed", 10 } },
    } }
    _G.SuburbsDistributions = { all = { postbox = { rolls = 2, items = {} } },
        Bag_MedicalBag = { rolls = 2, items = { "Base.Bandage", 50 } } }
    _G.VehicleDistributions = { AmbulanceTruckBed = { rolls = 4, items = {} } }

    -- The save's sandbox file says multiplier 0.5; the preload brings it in.
    local saved = { MedicationLootMultiplier = 0.5 }
    local preloaded = 0
    _G.checkSaveFileExists = function(name) return name == "map_sand.bin" end
    _G.getSandboxOptions = function()
        return { loadCurrentGameBinFile = function()
            preloaded = preloaded + 1
            for k, v in pairs(saved) do
                game.sandbox[k] = v
            end
        end }
    end
    local parsed = 0
    _G.ItemPickerJava = { Parse = function() parsed = parsed + 1 end }

    local baseInstanceof = _G.instanceof
    _G.instanceof = function(obj, class)
        if class == "ItemContainer" then return obj.isItemContainer == true end
        if class == "InventoryContainer" then return obj.inner ~= nil end
        return baseInstanceof(obj, class)
    end

    local function list(items)
        return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
    end
    local function drainable(fullType, uses)
        local item = { uses = uses, max = uses }
        function item.getFullType() return fullType end
        function item.getMaxUses() return item.max end
        function item.getCurrentUses() return item.uses end
        function item.setCurrentUses(_, n) item.uses = n end
        return item
    end
    local function container(items, parent)
        local c = { isItemContainer = true, items = items, parent = parent }
        function c.getItems() return list(c.items) end
        function c.getParent() return c.parent end
        function c.AddItem(_, fullType)
            local item = drainable(fullType, 4)
            c.items[#c.items + 1] = item
            return item
        end
        return c
    end

    local ServerLoot = require("ExtensiveHealthRedone/Server/Loot")
    local Build = require("ExtensiveHealthRedone/Loot/Build")
    local Env = require("ExtensiveHealthRedone/Game/Env")
    local events = game.events
    local clinic = _G.ProceduralDistributions.list.MedicalClinicDrugs.items

    local function weight(items, name)
        local found, n = nil, 0
        for i = 1, #items, 2 do
            if items[i] == name then
                found, n = items[i + 1], n + 1
            end
        end
        return found, n
    end

    it("writes the entries at the distribution merge with the save's preloaded options", function()
        events.OnPreDistributionMerge.trigger()
        assert.equal(1, preloaded)
        local w, n = weight(clinic, "ExtensiveHealth.PrescriptionAntibiotics")
        assert.equal(5, w)
        assert.equal(1, n)
        assert.equal("ExtensiveHealth.Syringe", _G.SuburbsDistributions.Bag_MedicalBag.items[1])
        assert.equal(4, _G.SuburbsDistributions.Bag_MedicalBag.rolls)
        assert.equal(6, _G.VehicleDistributions.AmbulanceTruckBed.rolls)
        assert.equal(10, weight(_G.ProceduralDistributions.list.JewelryWrist.items,
            "ExtensiveHealth.EHRMedicalWatch_Left"))
        assert.is_table(_G.SuburbsDistributions.MedicineStorageBox)
        assert.truthy(game.logged("loot lists missing in this build"))
    end)

    it("re-applies and re-parses only when the options changed after the merge", function()
        events.OnInitGlobalModData.trigger(false)
        assert.equal(0, parsed)
        game.sandbox.MedicationLootMultiplier = 0
        events.OnInitGlobalModData.trigger(false)
        assert.equal(1, parsed)
        assert.is_nil(weight(clinic, "ExtensiveHealth.PrescriptionAntibiotics"))
        assert.equal(2, _G.SuburbsDistributions.Bag_MedicalBag.rolls)
        assert.equal(1, select(2, weight(clinic, "ExtensiveHealth.DiseaseFlyer_CommonCold")))
        game.sandbox.MedicationLootMultiplier = 1
        ServerLoot.reapply(Build.options(Env.sandbox))
        local w, n = weight(clinic, "ExtensiveHealth.PrescriptionAntibiotics")
        assert.equal(10, w)
        assert.equal(1, n)
    end)

    it("leaves spawned packages partly used, kits included, and skips other containers' kinds", function()
        local pills = drainable("ExtensiveHealth.ColdFluTablets", 12)
        local used = drainable("ExtensiveHealth.AntiDiarrheal", 12)
        used.uses = 7
        local vanilla = drainable("Base.Pills", 12)
        local kitPills = drainable("ExtensiveHealth.AntipyreticTablets", 12)
        local kit = { inner = container({ kitPills }) }
        function kit.getType() return "Bag_MedicalBag" end
        function kit.getItemContainer() return kit.inner end
        function kit.getFullType() return "Base.Bag_MedicalBag" end
        game.float = 0.5
        events.OnFillContainer.trigger("bathroom", "medicine", container({ pills, used, vanilla, kit }))
        -- Household, Normal: 1-5 of 12 (the fake ZombRand picks the middle). The medical bag uses the ambulance range.
        assert.is_true(pills.uses >= 1 and pills.uses <= 5, tostring(pills.uses))
        assert.equal(7, used.uses)
        assert.equal(12, vanilla.uses)
        assert.is_true(kitPills.uses >= 3 and kitPills.uses <= 8, tostring(kitPills.uses))
        -- A sub-container's own fill event passes an ItemPickerContainer: ignored.
        events.OnFillContainer.trigger("bathroom", "medicine", {})
    end)

    it("rolls Knox items once per basement container", function()
        local modData = {}
        local parent = {
            getSquare = function()
                return { getX = function() return 5550 end, getY = function() return 12450 end,
                    getZ = function() return -16 end }
            end,
            getModData = function() return modData end,
        }
        local crate = container({}, parent)
        game.float = 0
        _G.ZombRand = function(lo) return lo end -- every 1-100 roll is 1: all four items spawn
        events.OnFillContainer.trigger("laboratory", "crate", crate)
        assert.equal(4, #crate.items)
        for _, item in ipairs(crate.items) do
            assert.equal(4, item.uses) -- spawned after the package fill, so full
        end
        events.OnFillContainer.trigger("laboratory", "crate", crate)
        assert.equal(4, #crate.items)
        game.sandbox.KnoxCureItemsEnabled = false
        local other = container({}, { getSquare = parent.getSquare, getModData = function() return {} end })
        events.OnFillContainer.trigger("laboratory", "crate", other)
        assert.equal(0, #other.items)
    end)

    it("gives a dead zombie at most one roll", function()
        local inventory = container({})
        local zombieData = {}
        local zombie = { getModData = function() return zombieData end, getInventory = function() return inventory end }
        game.sandbox.ZombieLootChance = 100
        game.float = 0
        events.OnZombieDead.trigger(zombie)
        assert.equal(1, #inventory.items)
        events.OnZombieDead.trigger(zombie)
        assert.equal(1, #inventory.items)
        game.sandbox.ZombieLootEnabled = false
        local other = container({})
        events.OnZombieDead.trigger({ getModData = function() return {} end, getInventory = function() return other end })
        assert.equal(0, #other.items)
    end)
end)
