-- The heat-stroke cold bath: a "Take Cold Bath" option on a bathtub while the character has heat stroke, and a timed
-- action that sits in the tub until the server says the 3 hours are done (or the heat stroke is gone). The server
-- checks the tub, the water and the distance, and decides the cure (Server/Weather, Diseases/Weather/Exposure).
-- With Lifestyle: Hobbies the character climbs into the tub with Lifestyle's own animations (Bob_Tub_Enter, then
-- Bob_Tub_Base after 8 % of the bath), stands at Lifestyle's tub positions and is put back where it stood afterwards;
-- the bath also counts as Lifestyle's cold bath. Without Lifestyle, the plain "Loot" animation facing the tub.

require "TimedActions/ISBaseTimedAction"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Lifestyle = require "ExtensiveHealthRedone/Game/Lifestyle"

local ColdBath = {}

-- Main tub halves, and the other half's sprite -> the directions to look for the main half.
local MAIN = {
    fixtures_bathroom_01_25 = true, fixtures_bathroom_01_26 = true,
    fixtures_bathroom_01_52 = true, fixtures_bathroom_01_55 = true,
}
local SUB = {
    fixtures_bathroom_01_24 = true, fixtures_bathroom_01_27 = true,
    fixtures_bathroom_01_53 = true, fixtures_bathroom_01_54 = true,
}
local HEARTBEAT_MINUTES = 5
-- Share of the bath after which the character settles from climbing in to sitting.
local SETTLE_AT = 0.08

local function spriteName(object)
    local sprite = object and object:getSprite()
    return sprite and sprite:getName() or nil
end

local function mainOn(square)
    if not square then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if MAIN[spriteName(objects:get(i))] then
            return objects:get(i)
        end
    end
    return nil
end

-- The main half of the tub a clicked object belongs to, or nil.
function ColdBath.tubOf(object)
    local name = spriteName(object)
    if MAIN[name] then
        return object
    elseif SUB[name] then
        local square = object:getSquare()
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local main = mainOn(getCell():getGridSquare(square:getX() + d[1], square:getY() + d[2], square:getZ()))
            if main then
                return main
            end
        end
    end
    return nil
end

local function hasHeatStroke(player)
    local conditions = Client.section(player, "conditions")
    return conditions ~= nil and conditions.active ~= nil and conditions.active.heat_stroke ~= nil
end

local function hasWater(tub)
    return tub:hasWater() and tub:getFluidAmount() >= Data.heatStroke.BATH_WATER
end

-- Timed action -------------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneColdBathAction : ISBaseTimedAction
---@field tub IsoObject
---@field startedAt number
---@field beatAt number
local ColdBathAction = ISBaseTimedAction:derive("ExtensiveHealthRedoneColdBathAction")

---@param character IsoPlayer
---@param tub IsoObject
---@return ExtensiveHealthRedoneColdBathAction
function ColdBathAction:new(character, tub)
    local o = ISBaseTimedAction.new(self, character) --[[@as ExtensiveHealthRedoneColdBathAction]]
    o.tub = tub
    o.maxTime = -1
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end

function ColdBathAction:isValid()
    return not self.character:isDead() and hasHeatStroke(self.character)
end

local function tubArgs(tub)
    local square = tub:getSquare()
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

local function place(character, tub, offsets)
    local square = tub:getSquare()
    character:setX(square:getX() + offsets[1])
    character:setY(square:getY() + offsets[2])
end

-- The character leaves the tub: back to where it stood, with the splash Lifestyle plays.
local function climbOut(action)
    if action.inTub then
        action.inTub = nil
        action.character:setX(action.startX)
        action.character:setY(action.startY)
        action.character:getEmitter():playSound("Tub_End")
    end
end

function ColdBathAction:start()
    local facing = Lifestyle.active() and Lifestyle.TUB_FACING[spriteName(self.tub)] or nil
    if facing then
        self.facing = facing
        self.inTub = true
        self.startX, self.startY = self.character:getX(), self.character:getY()
        place(self.character, self.tub, Lifestyle.TUB_ENTER[facing])
        self:setActionAnim(Lifestyle.TUB_ANIM_ENTER)
        self.character:getEmitter():playSound("Tub_Splash1")
    else
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
        self.character:faceThisObject(self.tub)
    end
    self.startedAt = Env.gameMinutes()
    self.beatAt = self.startedAt
    ColdBath.current[self.character] = self
    Client.send(self.character, "weather.bathStart", tubArgs(self.tub))
    self.character:Say(getText("UI_EHR_ColdBath_Start"))
end

function ColdBathAction:update()
    local now = Env.gameMinutes()
    self.character:setMetabolicTarget(Metabolics.LightWork)
    local progress = math.min(1, (now - self.startedAt) / Data.heatStroke.BATH_MINUTES)
    self:setJobDelta(progress)
    if self.inTub and not self.settled and progress > SETTLE_AT then
        self.settled = true
        place(self.character, self.tub, Lifestyle.TUB_SEAT[self.facing])
        self:setActionAnim(Lifestyle.TUB_ANIM_SEAT)
    end
    if now - self.beatAt >= HEARTBEAT_MINUTES then
        self.beatAt = now
        Client.send(self.character, "weather.bathBeat", {})
    end
end

function ColdBathAction:stop()
    climbOut(self)
    ColdBath.current[self.character] = nil
    Client.send(self.character, "weather.bathStop", {})
    ISBaseTimedAction.stop(self)
end

function ColdBathAction:perform()
    climbOut(self)
    Lifestyle.markColdBath(self.character)
    ColdBath.current[self.character] = nil
    ISBaseTimedAction.perform(self)
end

-- The running bath action per local player, so the server's "done" can finish it.
ColdBath.current = {}

Client.on("coldBathDone", function(args)
    local player = Client.localPlayer(args.owner)
    local action = player and ColdBath.current[player]
    if action then
        action:forceComplete()
    end
end)

-- Context menu --------------------------------------------------------------------------------------------------------

local function onBath(player, tub)
    if luautils.walkAdj(player, tub:getSquare()) then
        ISTimedActionQueue.add(ColdBathAction:new(player, tub))
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    if test or not player or player:getVehicle() or not hasHeatStroke(player) then
        return
    end
    for _, object in ipairs(worldobjects) do
        local tub = ColdBath.tubOf(object)
        if tub then
            local option = context:addOptionOnTop(getText("UI_EHR_Context_TakeColdBath"), player, onBath, tub)
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = getText("UI_EHR_Context_TakeColdBathDesc")
            if not hasWater(tub) then
                option.notAvailable = true
                tooltip.description = getText("UI_EHR_Context_TakeColdBathNoWater")
            end
            option.toolTip = tooltip
            return
        end
    end
end)

return ColdBath
