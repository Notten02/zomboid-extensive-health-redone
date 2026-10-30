-- The hive and spiderweb search on the client: the "Harvest hive or web" option on any outdoor tree (everyone may try),
-- and the panel: start the hand in the zone below the trunk, guide it up to the honeycomb or a web without touching
-- a bee or spider, and grab, within 48 s. The server rolled and keeps what the tree holds; it only answers with the
-- counts (the scene here is cosmetic, Wild/HiveScene), gives an item per accepted grab, and hurts the hand when this
-- client reports a touch (Server/WildSearch).
-- Touches are tested along the hand's path; the menu answers the controller's test pass and a controller plays with
-- the left stick (hand at a fixed speed), A to start or grab and B to cancel; result and injury lines are spoken here
-- (a server-side Say doesn't reach the player in MP).

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISWorldObjectContextMenu"

local Env = require "ExtensiveHealthRedone/Game/Env"
local HiveScene = require "ExtensiveHealthRedone/Wild/HiveScene"
local Vegetation = require "ExtensiveHealthRedone/Wild/Vegetation"
local Data = require("ExtensiveHealthRedone/Data/WildSearch").hive
local Client = require "ExtensiveHealthRedone/Client/Client"
local WildSearch = require "ExtensiveHealthRedone/Client/WildSearch"
local Draw = require "ExtensiveHealthRedone/Client/Draw"

local HiveSearch = {}

HiveSearch.ACTION_TICKS = 22
HiveSearch.MOVE_LIMIT = 0.75        -- tiles from where the panel opened
HiveSearch.RANGE = 4.5              -- tiles from the tree
HiveSearch.STICK_DEADZONE = 0.25

local FOUND_KEYS = { hive = "UI_EHR_HiveWebSearch_FoundHoneycomb", web = "UI_EHR_HiveWebSearch_FoundSpiderweb" }

-- The panel ---------------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneHivePanel : ISPanel
---@field character IsoPlayer
---@field playerNum number
---@field session number
---@field sx number
---@field sy number
---@field sz number
---@field seconds number
---@field scene table
---@field active boolean
---@field handX number?
---@field handY number?
---@field padX number
---@field padY number
---@field flash number
---@field startMs number
---@field lastMs number
---@field startX number
---@field startY number
---@field done boolean?
local Panel = ISPanel:derive("ExtensiveHealthRedoneHivePanel")

---@type ExtensiveHealthRedoneHivePanel?
local instance

---@param character IsoPlayer
---@param args table
---@return ExtensiveHealthRedoneHivePanel
function Panel:new(character, args)
    local w, h = 660, 560
    local playerNum = character:getIndex()
    local x, y = WildSearch.panelPosition(playerNum, w, h)
    local o = ISPanel.new(self, x, y, w, h) --[[@as ExtensiveHealthRedoneHivePanel]]
    o.character, o.playerNum = character, playerNum
    o.session = args.id
    o.sx, o.sy, o.sz = args.x, args.y, args.z
    o.seconds = tonumber(args.seconds) or Data.SECONDS
    o.moveWithMouse = true
    o.backgroundColor = { r = 0.014, g = 0.012, b = 0.010, a = 0.97 }
    o.borderColor = { r = 1.0, g = 0.44, b = 0.07, a = 0.95 }
    o.scene = HiveScene.new(Env.rng, { x = 24, y = 112, w = w - 48, h = h - 170 }, args.hive == true,
        tonumber(args.webs) or 0)
    o.active = false
    local start = o.scene.start
    o.padX, o.padY = start.x + start.w / 2, start.y + start.h / 2
    o.flash = 0
    o.startMs = getTimestampMs()
    o.lastMs = o.startMs
    o.startX, o.startY = character:getX(), character:getY()
    return o
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    local cancel = ISButton:new(self.width - 88, 8, 72, 26, getText("UI_EHR_HiveWebSearch_Cancel"), self, Panel.close)
    cancel:initialise()
    self:addChild(cancel)
end

function Panel:remaining()
    return math.max(0, self.seconds - (getTimestampMs() - self.startMs) / 1000)
end

-- Where the player wants the hand: the mouse, or the controller's virtual pointer.
function Panel:wanted()
    if self.joyfocus then
        return self.padX, self.padY
    end
    return getMouseX() - self:getAbsoluteX(), getMouseY() - self:getAbsoluteY()
end

-- Starts the hand in the start zone, or grabs what's under it.
function Panel:press(x, y)
    if self.done then
        return
    end
    if not self.active then
        if HiveScene.inStart(self.scene, x, y) then
            self.active = true
            self.handX, self.handY = HiveScene.constrain(self.scene, x, y)
            self.flash = 8
            self.character:Say(getText("UI_EHR_HiveWebSearch_StartLine"))
        else
            self.flash = 10
            self.character:Say(getText("UI_EHR_HiveWebSearch_NeedStartLine"))
        end
        return
    end
    local target = HiveScene.targetAt(self.scene, self.handX, self.handY)
    if target then
        target.pending = true
        Client.send(self.character, "hive.collect", { session = self.session, target = target.kind })
    end
end

function Panel:onMouseDown(x, y)
    local b = self.scene.board
    if self.done or x < b.x or x > b.x + b.w or y < b.y or y > b.y + b.h then
        return ISPanel.onMouseDown(self, x, y)
    end
    self:press(x, y)
    return true
end

-- The server's answer to a grab.
function Panel:collected(args)
    local target
    if args.target == "hive" then
        target = self.scene.hive
    else
        for _, web in ipairs(self.scene.webs) do
            if web.pending then
                target = web
                break
            end
        end
    end
    if args.ok then
        if target then
            HiveScene.remove(self.scene, target)
        end
        self.flash = 8
        self.character:Say(getText(FOUND_KEYS[args.target]))
    elseif target then
        target.pending = nil
        if args.reason == "absent" then
            HiveScene.remove(self.scene, target)
        end
    end
    if args.done or HiveScene.isEmpty(self.scene) then
        self:close()
    end
end

function Panel:update()
    ISPanel.update(self)
    if self.done then
        return
    end
    if self.flash > 0 then
        self.flash = self.flash - 1
    end
    local player = self.character
    local d = WildSearch.distance(player, self.sx, self.sy, self.sz)
    if player:isDead() or d == nil or d > HiveSearch.RANGE
        or WildSearch.moved(player, self.startX, self.startY, HiveSearch.MOVE_LIMIT) or self:remaining() <= 0 then
        self:close()
        return
    end
    local now = getTimestampMs()
    local dt = HiveScene.step(self.scene, (now - self.lastMs) / 1000)
    self.lastMs = now
    if self.joyfocus then
        local ax, ay = getJoypadMovementAxisX(self.joyfocus.id), getJoypadMovementAxisY(self.joyfocus.id)
        if math.abs(ax) < HiveSearch.STICK_DEADZONE then ax = 0 end
        if math.abs(ay) < HiveSearch.STICK_DEADZONE then ay = 0 end
        self.padX = self.padX + ax * HiveScene.JOYPAD_SPEED * dt
        self.padY = self.padY + ay * HiveScene.JOYPAD_SPEED * dt
        if self.active then
            self.padX, self.padY = HiveScene.constrain(self.scene, self.padX, self.padY)
        else
            local b = self.scene.board
            self.padX = math.max(b.x, math.min(b.x + b.w, self.padX))
            self.padY = math.max(b.y, math.min(b.y + b.h, self.padY))
        end
    end
    if not self.active then
        return
    end
    local wx, wy = self:wanted()
    local x, y = HiveScene.constrain(self.scene, wx, wy)
    local touched = HiveScene.touch(self.scene, self.handX, self.handY, x, y)
    self.handX, self.handY = x, y
    if touched then
        Client.send(player, "hive.sting", { session = self.session, kind = touched })
        self:close()
    end
end

function Panel:onJoypadDown(button)
    if button == Joypad.AButton then
        self:press(self.padX, self.padY)
    elseif button == Joypad.BButton then
        self:close()
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    self:drawRect(0, 0, self.width, 42, 0.96, 0.055, 0.020, 0.010)
    self:drawText(getText("UI_EHR_HiveWebSearch_Title"), 16, 8, 0.92, 0.90, 0.84, 1, UIFont.Medium)
end

local function sprite(panel, name, r, alpha, color)
    local tex = WildSearch.texture(name)
    if tex then
        panel:drawTextureScaled(tex, r.x, r.y, r.w, r.h, alpha, 1, 1, 1)
    else
        panel:drawRect(r.x, r.y, r.w, r.h, alpha, color[1], color[2], color[3])
    end
end

function Panel:drawTrunk()
    local tr = self.scene.tree
    self:drawRect(tr.x, tr.y, tr.w, tr.h, 1.0, 0.30, 0.18, 0.08)
    self:drawRect(tr.x + 12, tr.y, 18, tr.h, 0.32, 0.14, 0.08, 0.03)
    self:drawRect(tr.x + tr.w - 25, tr.y, 13, tr.h, 0.24, 0.14, 0.08, 0.03)
    for i = 0, 7 do
        self:drawRect(tr.x + 8, tr.y + 16 + i * 33, tr.w - 18, 2, 0.18, 0.58, 0.34, 0.14)
    end
end

function Panel:render()
    ISPanel.render(self)
    local text, dim, green = Draw.color("text"), Draw.color("dim"), Draw.color("green")
    local scene = self.scene
    self:drawText(getText("UI_EHR_HiveWebSearch_HintLine1"), 24, 54, text[1], text[2], text[3], 1, UIFont.Small)
    local hint = self.joyfocus and "UI_EHR_HiveWebSearch_JoypadHint" or "UI_EHR_HiveWebSearch_HintLine2"
    self:drawText(getText(hint), 24, 78, dim[1], dim[2], dim[3], 1, UIFont.Small)
    self:drawText(getText("UI_EHR_HiveWebSearch_Time") .. ": " .. math.ceil(self:remaining()) .. "s",
        self.width - 130, 58, dim[1], dim[2], dim[3], 1, UIFont.Small)

    local b = scene.board
    self:drawRect(b.x, b.y, b.w, b.h, 0.92, 0.032, 0.045, 0.030)
    self:drawRectBorder(b.x, b.y, b.w, b.h, 0.85, 0.75, 0.31, 0.05)
    self:drawTrunk()
    if scene.hive then
        sprite(self, "EHR_Honeycomb", scene.hive, scene.hive.pending and 0.5 or 0.96, { 0.74, 0.44, 0.08 })
        self:drawRectBorder(scene.hive.x, scene.hive.y, scene.hive.w, scene.hive.h, 0.7, 1.0, 0.68, 0.20)
    end
    for _, web in ipairs(scene.webs) do
        sprite(self, "EHR_Spiderweb", web, web.pending and 0.5 or 0.95, { 0.86, 0.86, 0.80 })
    end
    for _, bee in ipairs(scene.bees) do
        sprite(self, "EHR_Honeybee", bee, 1.0, { 0.95, 0.78, 0.08 })
    end
    for _, spider in ipairs(scene.spiders) do
        sprite(self, "EHR_Spider", spider, 1.0, { 0.08, 0.06, 0.05 })
    end

    local start = scene.start
    self:drawRect(start.x, start.y, start.w, start.h, self.active and 0.30 or 0.58, 0.08, 0.28, 0.10)
    self:drawRectBorder(start.x, start.y, start.w, start.h, 0.9, green[1], green[2], green[3])
    local label = self.active and "UI_EHR_HiveWebSearch_HandActive" or "UI_EHR_HiveWebSearch_StartZone"
    self:drawTextCentre(getText(label), start.x + start.w / 2, start.y + 7, green[1], green[2], green[3], 1,
        UIFont.Small)
    if self.flash > 0 then
        self:drawRect(b.x, b.y, b.w, b.h, 0.08, 1.0, 0.68, 0.20)
    end

    local hx, hy = self.handX, self.handY
    if not self.active and self.joyfocus then
        hx, hy = self.padX, self.padY
    end
    if hx then
        local size = HiveScene.HAND_W
        sprite(self, "EHR_GrabbingHand", { x = hx - size / 2, y = hy - size / 2, w = size, h = size },
            self.active and 0.96 or 0.5, { 1.0, 0.92, 0.72 })
    end
end

-- Closing without a grab or touch tells the server nothing: the contents stay and the session runs out.
function Panel:close()
    self.done = true
    WildSearch.unfocus(self, self.playerNum)
    self:setVisible(false)
    self:removeFromUIManager()
    if instance == self then
        instance = nil
    end
end

-- Opening, and the server's answers ---------------------------------------------------------------------------------

function HiveSearch.open(player, args)
    if instance then
        instance:close()
    end
    instance = Panel:new(player, args)
    instance:initialise()
    instance:addToUIManager()
    WildSearch.focus(instance, instance.playerNum)
end

Client.on("hiveSession", function(args)
    local player = Client.localPlayer(args.owner)
    if player and not player:isDead() then
        HiveSearch.open(player, args)
    end
end)

Client.on("hiveDenied", function(args)
    local player = Client.localPlayer(args.owner)
    if not player then
        return
    end
    if args.reason == "none" then
        player:Say(getText("UI_EHR_HiveWebSearch_None"))
    elseif args.reason == "depleted" then
        player:Say(getText("UI_EHR_HiveWebSearch_Depleted"))
    end
end)

Client.on("hiveCollected", function(args)
    if instance and instance.session == args.id and Client.localPlayer(args.owner) == instance.character then
        instance:collected(args)
    elseif args.ok then
        local player = Client.localPlayer(args.owner)
        if player then
            player:Say(getText(FOUND_KEYS[args.target] or "UI_EHR_HiveWebSearch_FoundSpiderweb"))
        end
    end
end)

Client.on("hiveStung", function(args)
    local player = Client.localPlayer(args.owner)
    if player and not player:isDead() then
        player:Say(getText(args.gloved and "UI_EHR_HiveWebSearch_GlovesLine" or "UI_EHR_HiveWebSearch_HazardLine"))
    end
end)

-- Context menu --------------------------------------------------------------------------------------------------------

function HiveSearch.onSearch(player, square)
    WildSearch.start(player, square, "hive.begin", HiveSearch.ACTION_TICKS, "Mid")
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or player:getVehicle() then
        return
    end
    local square = WildSearch.findSquare(playerNum, context, worldobjects, Vegetation.isTreeSquare)
    if not square then
        return
    end
    if test then
        ISWorldObjectContextMenu.setTest()
        return
    end
    local label = getText("UI_EHR_HiveWebSearch_Context")
    local option = context:addOptionOnTop(label, player, HiveSearch.onSearch, square)
    option.iconTexture = WildSearch.texture("EHR_SearchHoneyWeb")
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(label)
    tooltip.description = getText("UI_EHR_HiveWebSearch_ContextDesc")
    option.toolTip = tooltip
end)

HiveSearch.Panel = Panel

return HiveSearch
