-- Debug: a kit of items for testing the Phase 7 UI (tooltips, the Medical Monitor Watch, the Monitor's medication
-- rows), given by the debug window's "Test items" button. Like every debug command it needs sandbox DebugMode and the
-- medicalAdmin permission, checked here again.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Watch = require "ExtensiveHealthRedone/Game/Watch"
local WatchBattery = require "ExtensiveHealthRedone/Items/WatchBattery"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"
local ServerWatch = require "ExtensiveHealthRedone/Server/Watch"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"

local log = Env.logger("DebugItems")

-- A watch whose battery runs out after about 20 minutes of wear (drained every 10 game minutes).
local NEARLY_EMPTY = 20 / 60 / WatchBattery.LIFETIME_HOURS

local PLAIN = {
    "Base.Battery",
    "Base.Pills", "Base.PillsBeta", "Base.Antibiotics",
    "ExtensiveHealth.ColdFluTablets", "ExtensiveHealth.AntibioticOintment",
    "ExtensiveHealth.BroadSpectrumAntibiotics", "ExtensiveHealth.ImmunoboosterShot",
    "ExtensiveHealth.Syringe", "ExtensiveHealth.IVKit", "ExtensiveHealth.SalineBag",
    "ExtensiveHealth.EmptyBloodBag",
}

-- Filled bags, fresh: one O- (fits everyone) and one AB+ (fits only AB+).
local BAGS = { "O-", "AB+" }

Runtime.registry:register("debug.testItems", {
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx)
        local player = ctx.actor.player
        for _, fullType in ipairs(PLAIN) do
            Items.add(player, fullType)
        end
        for _, bloodType in ipairs(BAGS) do
            local bag = Items.add(player, Supplies.bagFor[bloodType])
            if bag then
                Items.markDrawn(player, bag, bloodType)
            end
        end
        -- A watch without battery data is full; the weak one's state goes to the client in MP.
        Items.add(player, "ExtensiveHealth.EHRMedicalWatch_Left")
        local weak = Items.add(player, "ExtensiveHealth.EHRMedicalWatch_Right")
        if weak then
            Watch.save(weak, { installed = true, charge = NEARLY_EMPTY })
            ServerWatch.sync(ctx.actor.key, player, { weak })
        end
        log:info(ctx.actor.key, "debug: gave the test items")
    end,
})
