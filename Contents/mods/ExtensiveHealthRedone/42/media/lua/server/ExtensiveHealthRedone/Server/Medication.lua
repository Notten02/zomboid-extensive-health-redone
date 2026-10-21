-- Wires medication (Phase 5) to the authority: the medication.take command for our own inventory option (on
-- yourself, or on another player with consent), medication.give for the vanilla pills and antibiotics given to
-- another player (Phase 9), the vanilla pill, eat and drink hooks, and debug commands. Every way of taking a dose
-- ends in the same rules (Medication/Doses); this file only finds items and supplies, uses them up as the outcome
-- says, and awards First Aid XP to whoever gave the dose.
-- Both commands are the authority half of Actions/Medication's EHRMedicationAction (`action = true`, SA-6), and a
-- dose for another player needs their consent for that one item (Server/Consent), used up by the attempt.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"
local Xp = require "ExtensiveHealthRedone/Server/Xp"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"
local StitchData = require("ExtensiveHealthRedone/Data/Wounds").stitch
local Data = require "ExtensiveHealthRedone/Medication/Data"
local Doses = require "ExtensiveHealthRedone/Medication/Doses"
local Schema = require "ExtensiveHealthRedone/Core/Schema"

local log = Env.logger("Medication")

local function notice(player, key)
    Transport.toClient(player, "notice", { key = key, owner = PlayerKey.of(player) })
end

local function anyWound(p)
    for _, fact in pairs(p.facts.parts or {}) do
        if fact.wound then
            return true
        end
    end
    return false
end

-- Takes one dose for the patient's key. supplies: { kind = bool } or nil (a vanilla action needs none).
local function take(key, med, opts)
    return Runtime.applyNow(key, function(p)
        opts.ctx = opts.ctx or {}
        opts.ctx.wound = anyWound(p)
        opts.ctx.sandbox = p.sandbox
        return Doses.take(p, defs, med, opts)
    end)
end

local function award(player, outcome)
    for _, kind in ipairs(outcome.xp or {}) do
        Xp.award(player, kind)
    end
end

-- Our own inventory option -----------------------------------------------------------------------------------------

Runtime.registry:register("medication.take", {
    args = {
        item = { type = "item", types = Data.ownRoute },
        target = { type = "player", optional = true },
    },
    proximity = { arg = "target", tiles = StitchData.RANGE },
    consent = { arg = "target", purpose = "medicate", detail = "item", once = true },
    action = true,
    rate = { count = 3, seconds = 5 },
    handler = function(ctx, args)
        local giver = ctx.actor.player
        local patient = ctx.actor
        if args.target then
            Runtime.attach(args.target.player)
            patient = args.target
        end
        local med = Data.byType[args.item.fullType]
        if patient.key ~= ctx.actor.key and med.remote == false then
            return notice(giver, "UI_EHR_Med_NotRemote")
        end
        local kit = med.supply and Items.findFirst(giver, Supplies[med.supply]) or nil
        local supplies = {}
        if med.supply then
            supplies[med.supply] = kit ~= nil
        end
        local outcome = take(patient.key, med, { ctx = { supplies = supplies } })
        if not outcome then
            return
        end
        if outcome.result == "refused" then
            return notice(giver, outcome.reason)
        end
        if outcome.consume then
            Items.useOne(args.item.item)
        end
        if outcome.supply and kit then
            Items.useOne(kit)
        end
        award(giver, outcome)
        log:info(ctx.actor.key, "gave", med.id, "to", patient.key, "->", outcome.result, outcome.reason or "")
    end,
})

-- Vanilla pills and antibiotics given to another player ------------------------------------------------------------
-- On yourself vanilla's own action takes them (the hooks below). Given to someone else, our action ends here: the
-- patient's dose goes through the same rules, but nothing is used up for a refused dose, and for a dose that counts
-- (or is wasted, as it would be after vanilla's action) the patient also gets vanilla's own effect, the way vanilla's
-- action gives it: ISTakePillAction:complete's BodyDamage:JustTookPill for the pills, the infection-fighting power
-- ISEatFoodAction gives through IsoGameCharacter:Eat for the antibiotics.

-- Vanilla's pill effect on the patient from the doctor's item. JustTookPill uses one pill itself (vanilla's action
-- consumes nothing else; inferred, Java); if a build ever stops doing that, one is used here instead.
local function vanillaPill(patient, item)
    local before = item:getCurrentUses()
    patient:getBodyDamage():JustTookPill(item)
    if isServer() then
        sendPlayerEffects(patient)
    end
    if item:getContainer() ~= nil and item:getCurrentUses() >= before then
        Items.useOne(item)
    end
end

local function vanillaAntibiotics(patient, item)
    local power = item:getReduceInfectionPower()
    if power > patient:getReduceInfectionPower() then
        patient:setReduceInfectionPower(power)
    end
    Items.useOne(item)
end

Runtime.registry:register("medication.give", {
    args = {
        item = { type = "item", types = Data.giveVanilla },
        target = { type = "player" },
    },
    proximity = { arg = "target", tiles = StitchData.RANGE },
    consent = { arg = "target", purpose = "medicate", detail = "item", once = true },
    action = true,
    handler = function(ctx, args)
        local giver = ctx.actor.player
        local patient = args.target
        if patient.key == ctx.actor.key then
            return
        end
        Runtime.attach(patient.player)
        local item = args.item.item
        local med = Data.byType[args.item.fullType]
        local outcome = take(patient.key, med, { ctx = {} })
        if not outcome then
            return
        end
        if outcome.result == "refused" then
            return notice(giver, outcome.reason)
        end
        if med.vanilla == "pill" then
            vanillaPill(patient.player, item)
        else
            vanillaAntibiotics(patient.player, item)
        end
        award(giver, outcome)
        log:info(ctx.actor.key, "gave", med.id, "to", patient.key, "->", outcome.result, outcome.reason or "")
    end,
})

-- Vanilla actions ----------------------------------------------------------------------------------------------------
-- A vanilla action has already used the item up, so a dose that would be refused is wasted instead.

local function vanillaDose(character, med, how)
    local key = Runtime.attach(character)
    if not key then
        return
    end
    local outcome = take(key, med, { consumed = true })
    if outcome then
        award(character, outcome)
        log:debug(key, how, med.id, "->", outcome.result, outcome.reason or "")
    end
end

Patches.on("takePillComplete", {
    name = "medication",
    after = function(results, action)
        local med = results[1] ~= false and action.item and Data.byType[action.item:getFullType()]
        if med then
            vanillaDose(action.character, med, "took pill")
        end
    end,
})

Patches.on("eatComplete", {
    name = "medication",
    after = function(results, action)
        local med = results[1] ~= false and action.item and Data.byType[action.item:getFullType()]
        if med and med.vanilla == "eat" then
            vanillaDose(action.character, med, "ate")
        end
    end,
})

-- Drinks: vanilla's Tea fluid counts as tea before sleeping, and water (clean or tainted, from a container or a world
-- source) helps heat exhaustion a little. The container is read when the action is made, before it is drunk.
local TEA = Data.byType["Base.HotDrinkTea"]
local WATER = Data.byType["Fluid.Water"]

local function holds(container, fluid)
    return container ~= nil and fluid ~= nil and container:contains(fluid)
end

Patches.on("drinkFluidNew", {
    name = "medicationDrinks",
    after = function(results)
        local action = results[1]
        if type(action) == "table" then
            local container = action.fluidContainer
            action.ehrTea = holds(container, Fluid.Tea)
            action.ehrWater = holds(container, Fluid.Water) or holds(container, Fluid.TaintedWater)
        end
    end,
})

Patches.on("drinkFluidComplete", {
    name = "medicationDrinks",
    after = function(results, action)
        if results[1] == false then
            return
        end
        if action.ehrTea then
            vanillaDose(action.character, TEA, "drank tea")
        end
        if action.ehrWater then
            vanillaDose(action.character, WATER, "drank water")
        end
    end,
})

-- Drinking straight from a world source (a sink, a river); with an item it fills the item instead.
Patches.on("takeWaterComplete", {
    name = "medicationWater",
    after = function(results, action)
        if results[1] ~= false and action.item == nil then
            vanillaDose(action.character, WATER, "drank water")
        end
    end,
})

-- Debug ----------------------------------------------------------------------------------------------------------------

local MED_IDS = {}
for id in pairs(Data.byId) do
    MED_IDS[id] = true
end

Runtime.registry:register("debug.medication", {
    args = {
        id = { type = "string", oneOf = MED_IDS, optional = true },
        action = { type = "string", oneOf = { dose = true, finish = true, clear = true } },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        local med = args.id and Data.byId[args.id]
        local result = Runtime.applyNow(ctx.actor.key, function(p)
            local meds = p.state.meds
            if args.action == "dose" and med then
                return Doses.take(p, defs, med, { consumed = true }).result
            elseif args.action == "finish" and med and meds.courses[med.id] then
                local c = meds.courses[med.id]
                c.count = med.doses
                for _, hours in pairs(med.cures) do
                    c.elapsed = math.max(c.elapsed, hours * 60)
                end
                p.dirty("meds")
                return "finishing"
            elseif args.action == "clear" then
                p.state.meds = Schema.defaults().meds
                p.dirty("meds")
                return "cleared"
            end
            return "nothing"
        end)
        log:info(ctx.actor.key, "debug: medication", args.action, args.id or "", "->", result)
    end,
})

log:info("medication loaded")
