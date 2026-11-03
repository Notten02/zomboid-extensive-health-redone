-- Wires the food-borne diseases to the game on the authority: what is eaten (ISEatFoodAction complete, and the partial
-- bite of a cancelled meal), what is drunk (ISDrinkFluidAction from a container, ISTakeWaterAction from a world
-- source), the wash-hands command (also Wash Face and worn prostheses with The Only Cure), the hand-soil facts, and
-- debug commands. The rules live in Diseases/Food.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local WaterSource = require "ExtensiveHealthRedone/Game/WaterSource"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Risk = require "ExtensiveHealthRedone/Diseases/Food/Risk"
local Washing = require "ExtensiveHealthRedone/Diseases/Food/Washing"
local BodySoil = require "ExtensiveHealthRedone/Game/BodySoil"
local OnlyCure = require "ExtensiveHealthRedone/Game/OnlyCure"

local log = Env.logger("Food")

local Food = {}

-- Hands -------------------------------------------------------------------------------------------------------------

-- Visible blood and dirt on what touches the food: both hands, averaged (Game/BodySoil has The Only Cure's cases).
function Food.hands(player)
    return BodySoil.hands(player)
end

Facts.extend("hands", function(player, facts)
    facts.hands = Food.hands(player)
end)

-- Blood and dirt on what washing cleans, by BloodBodyPartType name (or Prosthesis_L/R), and the mode: "hands", or
-- "face" for a character with no hand or prosthesis left (Game/BodySoil).
function Food.soil(player)
    return BodySoil.wash(player)
end

-- Cleans one part of a washing plan: the skin, or a worn prosthesis (as vanilla's ISWashClothing cleans a garment).
-- Returns the prosthesis it cleaned, if any.
local function clean(player, visual, name)
    local side = name:match("^Prosthesis_(%a)$")
    if not side then
        visual:setBlood(BloodBodyPartType[name], 0)
        visual:setDirt(BloodBodyPartType[name], 0)
        return nil
    end
    local item = OnlyCure.prosthesis(player, side)
    if item then
        local covered = item:getCoveredParts()
        for i = 0, covered:size() - 1 do
            item:setBlood(covered:get(i), 0)
            item:setDirt(covered:get(i), 0)
        end
    end
    return item
end

-- Eating -------------------------------------------------------------------------------------------------------------

local function lower(s)
    return s and string.lower(tostring(s)) or ""
end

-- The plain description Diseases/Food/Risk works with (read before the item is eaten).
function Food.describe(item)
    if not (item and instanceof(item, "Food")) then
        return nil
    end
    local herbalist = lower(item:getHerbalistType())
    local name = lower(item:getDisplayName())
    local toxinType = "toxin"
    if herbalist == "mushroom" or name:find("mushroom", 1, true) then
        toxinType = "mushroom"
    elseif herbalist == "berry" or name:find("berr", 1, true) then
        toxinType = "berry"
    end
    return {
        fullType = item:getFullType(),
        type = lower(item:getType()),
        name = name,
        rotten = item:isRotten(),
        fresh = item:isFresh(),
        burnt = item:isBurnt(),
        cooked = item:isCooked(),
        cookable = item:isCookable(),
        dangerousUncooked = item:isbDangerousUncooked(),
        hideUncooked = item:hasTag(ItemTag.HIDE_UNCOOKED),
        poisonPower = item:getPoisonPower() or 0,
        toxinType = toxinType,
        heat = tonumber(item:getHeat()) or 1,
        frozen = item:isFrozen(),
    }
end

-- Add-on bite listeners (Food.onBite), in registration order.
local biteListeners = {}

-- Lets an add-on mod react to what is eaten with EHR's own portion and in the same step as the food-borne risks.
-- listener:
--   name                       unique
--   describe(item, action)     read before vanilla eats the item; returns what bite needs (or nil to skip the item)
--   bite(p, data, portion)     inside Runtime.applyNow (a player context, Core/Simulation); portion is the share of
--                              the item's base hunger eaten (vanilla's percentage, times the progress of a cancelled
--                              meal), not of what is left of it
-- A failing listener is logged and skipped.
function Food.onBite(listener)
    if type(listener) ~= "table" or type(listener.name) ~= "string" or type(listener.describe) ~= "function"
        or type(listener.bite) ~= "function" then
        error("bite listeners need name, describe(item, action) and bite(p, data, portion)", 2)
    end
    for _, existing in ipairs(biteListeners) do
        if existing.name == listener.name then
            error("bite listener " .. listener.name .. " is already registered", 2)
        end
    end
    biteListeners[#biteListeners + 1] = listener
end

-- Each listener's description of the item, by name (read before the item is eaten).
local function describeForListeners(item, action)
    local out = {}
    for _, l in ipairs(biteListeners) do
        local ok, data = pcall(l.describe, item, action)
        if not ok then
            log:error("bite listener", l.name, "describe failed:", data)
        else
            out[l.name] = data
        end
    end
    return out
end

local function biteListenersRun(p, addons, portion)
    for _, l in ipairs(biteListeners) do
        local data = addons and addons[l.name]
        if data ~= nil then
            local ok, err = pcall(l.bite, p, data, portion)
            if not ok then
                log:error("bite listener", l.name, "failed:", err)
            end
        end
    end
end

-- One bite: toxins, then the food-borne risks, then the add-on listeners. portion: the share of the item eaten (0-1).
function Food.bite(player, food, portion)
    local key = Runtime.attach(player)
    if not key or not food or portion <= 0 then
        return
    end
    local hands = Food.hands(player)
    local result = Runtime.applyNow(key, function(p)
        Risk.applyToxin(p, defs, food.poisonPower, food.toxinType, portion)
        local caught = Risk.applyBite(p, defs, Risk.ofBite(p, food, hands, portion))
        biteListenersRun(p, food.addons, portion)
        return caught
    end)
    if result and #result > 0 then
        log:debug(key, "ate", food.fullType, "x", portion, "->", table.concat(result, ", "))
    end
end

Patches.on("eatComplete", {
    name = "foodDisease",
    before = function(action)
        action.ehrFood = Food.describe(action.item)
        if action.ehrFood then
            action.ehrFood.addons = describeForListeners(action.item, action)
        end
    end,
    after = function(results, action)
        if results[1] ~= false then
            Food.bite(action.character, action.ehrFood, tonumber(action.percentage) or 1)
        end
    end,
})

-- The share of the item a cancelled meal eats (vanilla serverStop), or nil when vanilla eats none of it: it skips
-- cigarettes and items worth at most 1 hunger. Also used by Server/Temperature.
function Food.stopPortion(action)
    local item = action.item
    if not item or item:getFullType() == "Base.Cigarettes" or math.abs(item:getHungerChange() * 100) <= 1
        or not action.character:getInventory():contains(item) then
        return nil
    end
    local progress = action.netAction and action.netAction:getProgress() or action:getJobDelta()
    if progress > 0.95 then
        progress = 1
    end
    return (tonumber(action.percentage) or 1) * progress
end

-- A cancelled meal still eats part of the item: roll for the share eaten.
Patches.on("eatServerStop", {
    name = "foodDisease",
    before = function(action)
        local portion = Food.stopPortion(action)
        if portion then
            action.ehrFood = Food.describe(action.item)
            if action.ehrFood then
                action.ehrFood.addons = describeForListeners(action.item, action)
            end
            action.ehrPortion = portion
        end

    end,
    after = function(_, action)
        if action.ehrPortion then
            Food.bite(action.character, action.ehrFood, action.ehrPortion)
            action.ehrPortion = nil
        end
    end,
})

-- Drinking -----------------------------------------------------------------------------------------------------------

local function drank(player, source)
    local key = Runtime.attach(player)
    if not key then
        return
    end
    local c = Runtime.applyNow(key, function(p)
        return Risk.applyWater(p, defs, source)
    end)
    log:debug(key, "drank", source, c and "-> dysentery" or "")
end

-- From a container: only tainted water risks dysentery (boiling turns tainted water into water). Read when the action
-- is made, before any of it is drunk; checked again at the end for actions made elsewhere.
local function tainted(container)
    return container ~= nil and container:contains(Fluid.TaintedWater)
end

Patches.on("drinkFluidNew", {
    name = "dysentery",
    after = function(results)
        local action = results[1]
        if type(action) == "table" then
            action.ehrTainted = tainted(action.fluidContainer)
        end
    end,
})

Patches.on("drinkFluidComplete", {
    name = "dysentery",
    before = function(action)
        if action.ehrTainted == nil then
            action.ehrTainted = tainted(action.fluidContainer)
        end
    end,
    after = function(results, action)
        if results[1] ~= false and action.ehrTainted then
            drank(action.character, "tainted")
        end
    end,
})

-- The world source description for Risk.waterSource.
function Food.describeSource(object)
    local props = object:getProperties()
    local sprite = object:getSprite()
    local fluid = object:getFluidContainer()
    return {
        customName = props and lower(props:get("CustomName")) or "",
        name = lower(object:getName()),
        sprite = sprite and lower(sprite:getName()) or "",
        rainCatcher = fluid ~= nil and (fluid:getRainCatcher() or 0) > 0,
        tainted = object:isTaintedWater(),
    }
end

-- From a world source (sink, toilet, river, rain collector): item == nil means drinking, not filling a container.
Patches.on("takeWaterComplete", {
    name = "dysentery",
    before = function(action)
        if action.item == nil and action.waterObject then
            action.ehrSource = Risk.waterSource(Food.describeSource(action.waterObject))
        end
    end,
    after = function(results, action)
        if results[1] ~= false and action.ehrSource then
            drank(action.character, action.ehrSource)
        end
    end,
})

-- Washing hands -----------------------------------------------------------------------------------------------------

local function notice(player, key)
    Transport.toClient(player, "notice", { key = key, owner = PlayerKey.of(player) })
end

-- A usable water source on a square: not a puddle, with water in it. Shared with the menu (Game/WaterSource).
Food.waterSourceAt = WaterSource.at

local function soapOf(player)
    local soaps = player:getInventory():getSoapList(nil, false)
    for i = 0, soaps:size() - 1 do
        local soap = soaps:get(i)
        if instanceof(soap, "DrainableComboItem") and soap:getCurrentUses() > 0 then
            return soap
        end
    end
    return nil
end

Food.WASH_RANGE = 2.5

-- Only Actions/WashHands' EHRWashHandsAction runs it, when its time is up (`action = true`).
Runtime.registry:register("food.washHands", {
    args = {
        x = { type = "number", integer = true },
        y = { type = "number", integer = true },
        z = { type = "number", integer = true },
    },
    action = true,
    rate = { count = 2, seconds = 5 },
    handler = function(ctx, args)
        local player = ctx.actor.player
        if player:getVehicle() then
            return
        end
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        local sink = Food.waterSourceAt(square)
        local dx, dy = player:getX() - (args.x + 0.5), player:getY() - (args.y + 0.5)
        if not sink or math.floor(player:getZ()) ~= args.z or math.sqrt(dx * dx + dy * dy) > Food.WASH_RANGE then
            log:debug(ctx.actor.key, "wash hands refused: no water source in reach")
            return
        end
        local soap = soapOf(player)
        local soil, mode = Food.soil(player)
        local face = mode == "face"
        local plan = Washing.plan(soil, soap ~= nil)
        if not plan then
            return notice(player, face and "UI_EHR_Context_WashFaceClean" or "UI_EHR_Context_WashHandsClean")
        end
        if sink:getFluidAmount() < plan.water then
            return notice(player, "UI_EHR_Context_WashHandsNoWater")
        end
        local visual = player:getHumanVisual()
        local garments = {}
        for _, name in ipairs(plan.parts) do
            garments[#garments + 1] = clean(player, visual, name)
        end
        if soap and plan.bloody then
            soap:UseAndSync()
        end
        sendHumanVisual(player)
        for _, item in ipairs(garments) do
            syncItemFields(player, item)
        end
        if #garments > 0 then
            syncVisuals(player)
        end
        player:resetModelNextFrame()
        if sink:useFluid(plan.water) > 0 and not instanceof(sink, "IsoWorldInventoryObject") then
            sink:transmitModData()
        end
        Runtime.applyNow(ctx.actor.key, function(p)
            if soap then
                p.stats:add("UNHAPPINESS", "washHands", -Washing.UNHAPPINESS_WITH_SOAP)
            end
            p.say(face and "UI_EHR_Text_WashesFaceMuchBetter" or "UI_EHR_Text_WashesHandsMuchBetter")
        end)
        log:debug(ctx.actor.key, "washed", #plan.parts, "parts with", plan.water, "water", soap and "and soap" or "",
            face and "(face)" or "")
    end,
})

-- Debug ----------------------------------------------------------------------------------------------------------------

local WATER_SOURCES = { toilet = true, tainted = true, river = true, rainCollector = true, tap = true }

Runtime.registry:register("debug.food", {
    args = {
        action = { type = "string", oneOf = { dirtyHands = true, clearRisk = true, water = true } },
        source = { type = "string", oneOf = WATER_SOURCES, optional = true },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        local player = ctx.actor.player
        if args.action == "dirtyHands" then
            local visual = player:getHumanVisual()
            for _, name in ipairs({ "Hand_L", "Hand_R" }) do
                visual:setBlood(BloodBodyPartType[name], 0.8)
                visual:setDirt(BloodBodyPartType[name], 0.8)
            end
            sendHumanVisual(player)
            player:resetModelNextFrame()
        elseif args.action == "clearRisk" then
            Runtime.applyNow(ctx.actor.key, function(p)
                p.state.exposure.data.food = nil
            end)
        elseif args.action == "water" and args.source then
            drank(player, args.source)
        end
        log:info(ctx.actor.key, "debug: food", args.action, args.source)
    end,
})

log:info("food-borne diseases loaded")

return Food
