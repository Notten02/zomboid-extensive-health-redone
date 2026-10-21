-- The medicinal plant search on the client: the "Search medicinal plants" option on a bush that is a search patch
-- (Wild/Vegetation, the same test the server makes), shown to players with the Wild Plants guide or First Aid 4 and
-- Foraging 4, and the panel: 16 covered plant signs; pick up to 8-10 of them in 42 s to find 3 promising plants
-- while avoiding thorns. The server holds the board: each pick is sent and the server reveals that one sign (so a
-- modified client can't see the thorns), keeps the counts, hurts the hand on a thorn and rolls the find at the end
-- (Server/WildSearch). This panel draws and sends intents only.
-- From v0.9 c/EHR_HerbalSearch.lua (docs/porting/phase8/herbal-and-hive-minigames.md sections 1-2, 13.2, 13.8).
-- Changes: every sign is drawn the same size (H7); quality is shown from the server's counts without latching (H8);
-- cancelling after a pick spends the spot (H9); the menu answers the controller's test pass (H19); a controller
-- moves a cursor over the 4 x 4 grid with the D-pad, A picks and B cancels.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISWorldObjectContextMenu"

local Data = require("ExtensiveHealthRedone/Data/WildSearch").herb
local HerbalBoard = require "ExtensiveHealthRedone/Wild/HerbalBoard"
local Vegetation = require "ExtensiveHealthRedone/Wild/Vegetation"
local Client = require "ExtensiveHealthRedone/Client/Client"
local WildSearch = require "ExtensiveHealthRedone/Client/WildSearch"
local Draw = require "ExtensiveHealthRedone/Client/Draw"

local HerbalSearch = {}

HerbalSearch.ACTION_TICKS = 24
HerbalSearch.MOVE_LIMIT = 0.6       -- tiles from where the panel opened
HerbalSearch.RANGE = 4.2            -- tiles from the bush
HerbalSearch.PENDING_MS = 3000      -- a pick without an answer is given up after this

local COLS, ROWS = 4, 4
local MARKER = 25                   -- px, every sign alike
local CLICK_RADIUS = MARKER * 0.72

local QUALITY_KEYS = {
    excellent = "UI_EHR_HerbalSearch_QualityExcellent", good = "UI_EHR_HerbalSearch_QualityGood",
    rough = "UI_EHR_HerbalSearch_QualityRough", poor = "UI_EHR_HerbalSearch_QualityPoor",
}
local QUALITY_COLORS = { excellent = "green", good = "blue", rough = "yellow", poor = "orange" }
local REVEALED = { target = "EHR_HerbalSearch_Leaf", hazard = "EHR_HerbalSearch_Thorn", decoy = "EHR_HerbalSearch_Decoy" }
local REVEALED_COLORS = { target = "green", hazard = "red", decoy = "dim" }

-- Whether the local player may search (the server checks again).
function HerbalSearch.canSearch(player)
    local knowledge = Client.section(player, "knowledge")
    return HerbalBoard.canSearch(knowledge ~= nil and knowledge.wildPlants == true,
        player:getPerkLevel(Perks.Doctor), player:getPerkLevel(Perks.PlantScavenging))
end

-- The panel ---------------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneHerbalPanel : ISPanel
---@field character IsoPlayer
---@field playerNum number
---@field session number
---@field sx number
---@field sy number
---@field sz number
---@field maxPicks number
---@field seconds number
---@field firstAid number
---@field foraging number
---@field picks number
---@field hits number
---@field misses number
---@field hazards number
---@field points table[]
---@field cursor number
---@field pending table?
---@field flash number
---@field startMs number
---@field startX number
---@field startY number
---@field board { x: number, y: number, w: number, h: number }
---@field done boolean?
---@field waiting boolean?
local Panel = ISPanel:derive("ExtensiveHealthRedoneHerbalPanel")

---@type ExtensiveHealthRedoneHerbalPanel?
local instance

---@param character IsoPlayer
---@param args table
---@return ExtensiveHealthRedoneHerbalPanel
function Panel:new(character, args)
    local w, h = 620, 450
    local playerNum = character:getIndex()
    local x, y = WildSearch.panelPosition(playerNum, w, h)
    local o = ISPanel.new(self, x, y, w, h) --[[@as ExtensiveHealthRedoneHerbalPanel]]
    o.character, o.playerNum = character, playerNum
    o.session = args.id
    o.sx, o.sy, o.sz = args.x, args.y, args.z
    o.maxPicks = tonumber(args.maxPicks) or Data.BASE_PICKS
    o.seconds = tonumber(args.seconds) or Data.SECONDS
    o.firstAid = character:getPerkLevel(Perks.Doctor)
    o.foraging = character:getPerkLevel(Perks.PlantScavenging)
    o.picks, o.hits, o.misses, o.hazards = 0, 0, 0, 0
    o.moveWithMouse = true
    o.backgroundColor = { r = 0.014, g = 0.012, b = 0.010, a = 0.97 }
    o.borderColor = { r = 0.08, g = 0.35, b = 0.12, a = 1 }
    o.board = { x = 24, y = 130, w = w - 48, h = h - 204 }
    o.flash, o.cursor = 0, 1
    o.startMs = getTimestampMs()
    o.startX, o.startY = character:getX(), character:getY()
    o:generatePoints()
    return o
end

-- Where the 16 signs are drawn: one per cell, jittered by up to 23% of the cell size. Cosmetic only.
function Panel:generatePoints()
    local b = self.board
    local cellW, cellH = b.w / COLS, b.h / ROWS
    self.points = {}
    for i = 1, COLS * ROWS do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local jx, jy = math.floor(cellW * 0.46), math.floor(cellH * 0.46)
        self.points[i] = {
            x = b.x + math.floor(col * cellW + cellW / 2) + ZombRand(jx) - math.floor(cellW * 0.23),
            y = b.y + math.floor(row * cellH + cellH / 2) + ZombRand(jy) - math.floor(cellH * 0.23),
        }
    end
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    local cancel = ISButton:new(self.width - 88, 8, 72, 26, getText("UI_EHR_HerbalSearch_Cancel"), self, Panel.onCancel)
    cancel:initialise()
    self:addChild(cancel)
end

function Panel:remaining()
    return math.max(0, self.seconds - (getTimestampMs() - self.startMs) / 1000)
end

-- Sends one pick (cell 0 = empty space) unless one is still waiting for its answer.
function Panel:pick(cell)
    if self.done or self.waiting or self.pending or self.picks >= self.maxPicks then
        return
    end
    if cell > 0 and self.points[cell].kind then
        return
    end
    self.pending = { cell = cell, ms = getTimestampMs() }
    Client.send(self.character, "herb.pick", { session = self.session, cell = cell })
end

function Panel:pointAt(x, y)
    local best, bestD = 0, CLICK_RADIUS
    for i, p in ipairs(self.points) do
        if not p.kind then
            local dx, dy = x - p.x, y - p.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= bestD then
                best, bestD = i, d
            end
        end
    end
    return best
end

function Panel:onMouseDown(x, y)
    local b = self.board
    if self.done or x < b.x or x > b.x + b.w or y < b.y or y > b.y + b.h then
        return ISPanel.onMouseDown(self, x, y)
    end
    self:pick(self:pointAt(x, y))
    return true
end

-- The server's answer to a pick.
function Panel:reveal(args)
    self.pending = nil
    if args.refused then
        return
    end
    if args.cell > 0 and self.points[args.cell] then
        self.points[args.cell].kind = args.kind
    end
    self.picks, self.hits = tonumber(args.picks) or self.picks, tonumber(args.hits) or self.hits
    self.misses, self.hazards = tonumber(args.misses) or self.misses, tonumber(args.hazards) or self.hazards
    if args.outcome == "hit" then
        self.flash = 9
    elseif args.outcome == "hazard" then
        self.flash = -13
        self.character:Say(getText(args.gloved and "UI_EHR_HerbalSearch_GlovesLine" or "UI_EHR_HerbalSearch_HazardLine"))
    else
        self.flash = -8
    end
    if args.done then
        self.waiting = true      -- the result follows
    end
end

function Panel:onCancel()
    self:stop("cancel")
end

-- Ends the panel and tells the server why (it decides whether the spot is spent or the find is rolled).
function Panel:stop(reason)
    if self.done then
        return
    end
    self:close()
    Client.send(self.character, "herb.stop", { session = self.session, reason = reason })
end

function Panel:update()
    ISPanel.update(self)
    if self.done then
        return
    end
    if self.flash > 0 then
        self.flash = self.flash - 1
    elseif self.flash < 0 then
        self.flash = self.flash + 1
    end
    if self.pending and getTimestampMs() - self.pending.ms > HerbalSearch.PENDING_MS then
        self.pending = nil
    end
    local player = self.character
    if player:isDead() then
        self:close()
        return
    end
    local d = WildSearch.distance(player, self.sx, self.sy, self.sz)
    if d == nil or d > HerbalSearch.RANGE or WildSearch.moved(player, self.startX, self.startY, HerbalSearch.MOVE_LIMIT) then
        self:stop("cancel")
    elseif self:remaining() <= 0 then
        if self.waiting then
            self:close()        -- the result never came; the server's own deadline ends the session
        else
            self:stop("time")
        end
    end
end

-- Joypad: D-pad moves the cursor, A picks, B cancels.
function Panel:moveCursor(dx, dy)
    local col, row = (self.cursor - 1) % COLS, math.floor((self.cursor - 1) / COLS)
    col = math.max(0, math.min(COLS - 1, col + dx))
    row = math.max(0, math.min(ROWS - 1, row + dy))
    self.cursor = row * COLS + col + 1
end

function Panel:onJoypadDirLeft() self:moveCursor(-1, 0) end
function Panel:onJoypadDirRight() self:moveCursor(1, 0) end
function Panel:onJoypadDirUp() self:moveCursor(0, -1) end
function Panel:onJoypadDirDown() self:moveCursor(0, 1) end

function Panel:onJoypadDown(button)
    if button == Joypad.AButton then
        self:pick(self.cursor)
    elseif button == Joypad.BButton then
        self:stop("cancel")
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    self:drawRect(0, 0, self.width, 42, 0.96, 0.018, 0.05, 0.020)
    self:drawText(getText("UI_EHR_HerbalSearch_Title"), 16, 8, 0.92, 0.90, 0.84, 1, UIFont.Medium)
end

local function marker(panel, name, x, y, alpha, color)
    local tex = WildSearch.texture(name)
    if tex then
        panel:drawTextureScaled(tex, x - MARKER / 2, y - MARKER / 2, MARKER, MARKER, alpha, 1, 1, 1)
    else
        Draw.rect(panel, x - MARKER / 2, y - MARKER / 2, MARKER, MARKER, Draw.color(color), alpha)
    end
end

function Panel:render()
    ISPanel.render(self)
    local text, dim = Draw.color("text"), Draw.color("dim")
    self:drawText(getText("UI_EHR_HerbalSearch_Target"), 24, 54, text[1], text[2], text[3], 1, UIFont.Small)
    self:drawText(getText("UI_EHR_HerbalSearch_HintLine1"), 24, 82, dim[1], dim[2], dim[3], 1, UIFont.Small)
    self:drawText(getText("UI_EHR_HerbalSearch_HintLine2"), 24, 104, dim[1], dim[2], dim[3], 1, UIFont.Small)
    local band = HerbalBoard.band(HerbalBoard.quality(self.hits, self.misses, self.hazards, self.firstAid, self.foraging))
    local qc = Draw.color(QUALITY_COLORS[band])
    local right = self.width - 230
    self:drawText(getText("UI_EHR_HerbalSearch_Quality") .. ": " .. getText(QUALITY_KEYS[band]), right, 54,
        qc[1], qc[2], qc[3], 1, UIFont.Small)
    self:drawText(getText("UI_EHR_HerbalSearch_Samples") .. ": " .. self.hits .. "/" .. Data.REQUIRED_HITS, right, 78,
        dim[1], dim[2], dim[3], 1, UIFont.Small)
    self:drawText(getText("UI_EHR_HerbalSearch_Time") .. ": " .. math.ceil(self:remaining()) .. "s", right, 100,
        dim[1], dim[2], dim[3], 1, UIFont.Small)

    local b = self.board
    self:drawRect(b.x, b.y, b.w, b.h, 0.92, 0.032, 0.045, 0.030)
    local background = WildSearch.texture("EHR_HerbalSearch_Background")
    if background then
        self:drawTextureScaled(background, b.x, b.y, b.w, b.h, 0.88, 1, 1, 1)
    end
    self:drawRectBorder(b.x, b.y, b.w, b.h, 0.85, 0.08, 0.35, 0.12)
    if self.flash > 0 then
        self:drawRect(b.x, b.y, b.w, b.h, 0.09, 0.1, 1.0, 0.18)
    elseif self.flash < 0 then
        self:drawRect(b.x, b.y, b.w, b.h, 0.13, 1.0, 0.08, 0.04)
    end
    local gold = Draw.color("yellow")
    for i, p in ipairs(self.points) do
        if p.kind and REVEALED[p.kind] then
            marker(self, REVEALED[p.kind], p.x, p.y, 0.96, REVEALED_COLORS[p.kind])
            self:drawRectBorder(p.x - MARKER / 2 - 2, p.y - MARKER / 2 - 2, MARKER + 4, MARKER + 4, 0.9,
                gold[1], gold[2], gold[3])
        else
            local pending = self.pending and self.pending.cell == i
            marker(self, "EHR_HerbalSearch_Marker", p.x, p.y, pending and 0.5 or 0.92, "dim")
        end
        if self.joyfocus and i == self.cursor then
            self:drawRectBorder(p.x - MARKER / 2 - 5, p.y - MARKER / 2 - 5, MARKER + 10, MARKER + 10, 1, 1, 1, 1)
        end
    end
    local hint = self.joyfocus and "UI_EHR_HerbalSearch_JoypadHint" or "UI_EHR_HerbalSearch_FinishHint"
    self:drawText(getText(hint), 24, self.height - 34, dim[1], dim[2], dim[3], 1, UIFont.Small)
    self:drawText(getText("UI_EHR_HerbalSearch_Picks") .. ": " .. self.picks .. "/" .. self.maxPicks,
        self.width - 112, self.height - 34, dim[1], dim[2], dim[3], 1, UIFont.Small)
end

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

function HerbalSearch.open(player, args)
    if instance then
        instance:close()
    end
    instance = Panel:new(player, args)
    instance:initialise()
    instance:addToUIManager()
    WildSearch.focus(instance, instance.playerNum)
end

local function current(args)
    if instance and instance.session == args.id and Client.localPlayer(args.owner) == instance.character then
        return instance
    end
    return nil
end

Client.on("herbSession", function(args)
    local player = Client.localPlayer(args.owner)
    if player and not player:isDead() then
        HerbalSearch.open(player, args)
    end
end)

Client.on("herbDenied", function(args)
    local player = Client.localPlayer(args.owner)
    if player and args.reason == "depleted" then
        player:Say(getText("UI_EHR_HerbalSearch_Depleted"))
    end
end)

Client.on("herbReveal", function(args)
    local panel = current(args)
    if panel then
        panel:reveal(args)
    end
end)

Client.on("herbClosed", function(args)
    local panel = current(args)
    if panel then
        panel:close()
    end
end)

-- The find. Spoken by the client: a server-side Say doesn't reach the player in MP (v0.9 H10).
Client.on("herbResult", function(args)
    local panel = current(args)
    if panel then
        panel:close()
    end
    local player = Client.localPlayer(args.owner)
    if not player or player:isDead() then
        return
    end
    if args.depleted then
        player:Say(getText("UI_EHR_HerbalSearch_Depleted"))
    elseif args.found and args.item then
        local name = getItemNameFromFullType(tostring(args.item))
        local count = tonumber(args.count) or 1
        if count > 1 then
            name = name .. " x" .. count
        end
        player:Say(getText("UI_EHR_HerbalSearch_Found", name))
    else
        player:Say(getText("UI_EHR_HerbalSearch_None"))
    end
end)

-- Context menu --------------------------------------------------------------------------------------------------------

local function isPatch(square)
    return Vegetation.isPatch(square, WildSearch.vegetationApi())
end

function HerbalSearch.onSearch(player, square)
    WildSearch.start(player, square, "herb.begin", HerbalSearch.ACTION_TICKS, "Low")
end

-- At a search patch the option always shows; without the guide or the skills it is greyed out and says what it needs
-- (the server checks the same rule).
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or player:getVehicle() then
        return
    end
    local square = WildSearch.findSquare(playerNum, context, worldobjects, isPatch)
    if not square then
        return
    end
    local allowed = HerbalSearch.canSearch(player)
    if test then
        if allowed then
            ISWorldObjectContextMenu.setTest()
        end
        return
    end
    local label = getText("UI_EHR_HerbalSearch_Context")
    local option = context:addOptionOnTop(label, player, HerbalSearch.onSearch, square)
    option.iconTexture = WildSearch.texture("EHR_SearchPlants")
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(label)
    tooltip.description = getText(allowed and "UI_EHR_HerbalSearch_ContextDesc" or "UI_EHR_HerbalSearch_NeedKnowledge")
    option.toolTip = tooltip
    option.notAvailable = not allowed
end)

HerbalSearch.Panel = Panel

return HerbalSearch
