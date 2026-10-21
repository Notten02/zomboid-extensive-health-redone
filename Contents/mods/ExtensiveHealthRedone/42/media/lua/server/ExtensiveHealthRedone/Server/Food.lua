-- Wires the food-borne diseases to the game on the authority: what is eaten (ISEatFoodAction complete, and the partial
-- bite of a cancelled meal), what is drunk (ISDrinkFluidAction from a container, ISTakeWaterAction from a world
-- source), the wash-hands command, the hand-soil facts, and debug commands. The rules live in Diseases/Food.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"
local Risk = require "ExtensiveHealthRedone/Diseases/Food/Risk"
local Washing = require "ExtensiveHealthRedone/Diseases/Food/Washing"

local log = Env.logger("Food")

local Food = {}

-- Hands -------------------------------------------------------------------------------------------------------------

-- Visible blood and dirt, averaged over both hands (W26).
function Food.hands(player)
    local visual = player:getHumanVisual()
    local blood = (visual:getBlood(BloodBodyPartType.Hand_L) + visual:getBlood(BloodBodyPartType.Hand_R)) / 2
    local dirt = (visual:getDirt(BloodBodyPartType.Hand_L) + visual:getDirt(BloodBodyPartType.Hand_R)) / 2
    return { blood = blood, dirt = dirt }
end

Facts.extend("hands", function(player, facts)
    facts.hands = Food.hands(player)
end)

-- Blood and dirt on the hands and arms, by BloodBodyPartType name.
function Food.soil(player)
    local visual = player:getHumanVisual()
    local soil = {}
    for _, name in ipairs(Washing.PARTS) do
        local part = BloodBodyPartType[name]
        soil[name] = { blood = visual:getBlood(part), dirt = visual:getDirt(part) }
    end
    return soil
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
    }
end

-- One bite: toxins, then the food-borne risks. portion: the share of the item eaten (0-1).
function Food.bite(player, food, portion)
    local key = Runtime.attach(player)
    if not key or not food or portion <= 0 then
        return
    end
    local hands = Food.hands(player)
    local result = Runtime.applyNow(key, function(p)
        Risk.applyToxin(p, defs, food.poisonPower, food.toxinType, portion)
        return Risk.applyBite(p, defs, Risk.ofBite(p, food, hands, portion))
    end)
    if result and #result > 0 then
        log:info(key, "ate", food.fullType, "x", portion, "->", table.concat(result, ", "))
    end
end

Patches.on("eatComplete", {
    name = "foodDisease",
    before = function(action)
        action.ehrFood = Food.describe(action.item)
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

-- A usable water source on a square: not a puddle, with water in it.
function Food.waterSourceAt(square)
    if not square then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object:getFluidAmount() > 0 and not instanceof(object, "IsoWorldInventoryObject") then
            return object
        end
    end
    return nil
end

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

-- Only Actions/WashHands' EHRWashHandsAction runs it, when its time is up (`action = true`, SA-6).
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
            log:info(ctx.actor.key, "wash hands refused: no water source in reach")
            return
        end
        local soap = soapOf(player)
        local plan = Washing.plan(Food.soil(player), soap ~= nil)
        if not plan then
            return notice(player, "UI_EHR_Context_WashHandsClean")
        end
        if sink:getFluidAmount() < plan.water then
            return notice(player, "UI_EHR_Context_WashHandsNoWater")
        end
        local visual = player:getHumanVisual()
        for _, name in ipairs(plan.parts) do
            visual:setBlood(BloodBodyPartType[name], 0)
            visual:setDirt(BloodBodyPartType[name], 0)
        end
        if soap and plan.bloody then
            soap:UseAndSync()
        end
        sendHumanVisual(player)
        player:resetModelNextFrame()
        if sink:useFluid(plan.water) > 0 and not instanceof(sink, "IsoWorldInventoryObject") then
            sink:transmitModData()
        end
        Runtime.applyNow(ctx.actor.key, function(p)
            if soap then
                p.stats:add("UNHAPPINESS", "washHands", -Washing.UNHAPPINESS_WITH_SOAP)
            end
            p.say("UI_EHR_Text_WashesHandsMuchBetter")
        end)
        log:debug(ctx.actor.key, "washed", #plan.parts, "parts with", plan.water, "water", soap and "and soap" or "")
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
