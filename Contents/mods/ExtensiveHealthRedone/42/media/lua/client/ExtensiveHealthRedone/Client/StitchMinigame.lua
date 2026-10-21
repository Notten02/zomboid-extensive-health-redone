-- The suture minigame. When StitchMinigameEnabled is on, stitching a deep wound without glass from the vanilla Health
-- tab first opens this panel: click 12 moving stitch points in order. First Aid gives more allowed misses, bigger
-- targets and less wobble. The result (misses) goes to the server, which rolls the outcome; on success the real
-- vanilla stitch action then runs as usual, so other mods' stitching items still work.
-- From v0.9 EHR_StitchMinigame.lua (docs/porting/phase3/stitch-minigame-and-b42-api.md, part A). Changes: the wobble
-- runs on real time instead of frames, and moving or cancelling after starting counts as a dirty attempt (W34).
-- Phase 9: the panel opens only once the server has opened a session (consent, a needle, a wound to stitch); for
-- another player without consent the doctor is asked to request it first. The server, not this file, decides what a
-- stitch does (Server/Health: SA-1 to SA-3).
-- Not yet: joypad support (v0.9 had none either).

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TimedActions/ISBaseTimedAction"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Stitch = require "ExtensiveHealthRedone/Wounds/Stitch"
local Data = require("ExtensiveHealthRedone/Data/Wounds").stitch
local Client = require "ExtensiveHealthRedone/Client/Client"
local Consent = require "ExtensiveHealthRedone/Client/Consent"

local StitchMinigame = {}

local DOCTOR_MOVE = 0.35
local PATIENT_MOVE = 0.45

local function text(key)
    return getText("UI_EHR_StitchMinigame_" .. key)
end

local textures = {}
local function texture(name)
    if textures[name] == nil then
        textures[name] = getTexture("media/textures/EHR_Stitch_" .. name .. ".png") or false
    end
    return textures[name] or nil
end

-- The panel ---------------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneStitchPanel : ISPanel
---@field doctor IsoPlayer
---@field patient IsoPlayer
---@field item InventoryItem
---@field bodyPart BodyPart
---@field session number?
---@field maxMisses number
---@field tolerance number
---@field amplitude number
---@field speed number
---@field pointSize number
---@field activeSize number
---@field misses number
---@field index number
---@field flash number
---@field startMs number
---@field doctorX number
---@field doctorY number
---@field patientX number
---@field patientY number
---@field board { x: number, y: number, w: number, h: number }
---@field horizontal boolean
---@field points table[]
---@field done boolean?
local Panel = ISPanel:derive("ExtensiveHealthRedoneStitchPanel")

---@type ExtensiveHealthRedoneStitchPanel?
local instance

---@param doctor IsoPlayer
---@param patient IsoPlayer
---@param item InventoryItem
---@param bodyPart BodyPart
---@return ExtensiveHealthRedoneStitchPanel
function Panel:new(doctor, patient, item, bodyPart)
    local w, h = 560, 450
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local o = ISPanel.new(self, x, y, w, h) --[[@as ExtensiveHealthRedoneStitchPanel]]
    o.doctor, o.patient, o.item, o.bodyPart = doctor, patient, item, bodyPart
    o.moveWithMouse = true
    o.backgroundColor = { r = 0.08, g = 0.05, b = 0.05, a = 0.95 }
    o.borderColor = { r = 0.6, g = 0.1, b = 0.1, a = 1 }
    local level = doctor:getPerkLevel(Perks.Doctor)
    local f = math.min(8, math.max(0, level)) / 8
    o.maxMisses = Stitch.maxMisses(level)
    o.tolerance = 7 + math.floor(f * 9 + 0.5)
    o.amplitude = 34 - math.floor(f * 12 + 0.5)
    o.speed = (0.150 - f * 0.080) * 60          -- radians per second (v0.9: per frame at about 60 fps)
    o.pointSize = 4 + math.floor(f * 4 + 0.5)
    o.activeSize = 6 + math.floor(f * 9 + 0.5)
    o.misses, o.index, o.flash = 0, 1, 0
    o.startMs = getTimestampMs()
    o.doctorX, o.doctorY = doctor:getX(), doctor:getY()
    o.patientX, o.patientY = patient:getX(), patient:getY()
    o.board = { x = 24, y = 126, w = w - 48, h = h - 206 }
    o:generatePoints()
    return o
end

function Panel:generatePoints()
    local b = self.board
    self.horizontal = ZombRand(2) == 0
    self.points = {}
    for i = 1, Data.POINTS do
        local p = { phase = ZombRand(628) / 100 }
        if self.horizontal then
            p.x = b.x + 56 + (i - 1) * (b.w - 112) / (Data.POINTS - 1)
            p.y = b.y + b.h / 2 + ((i % 2 == 1) and -56 or 56)
        else
            p.x = b.x + b.w / 2 + ((i % 2 == 1) and -68 or 68)
            p.y = b.y + 32 + (i - 1) * (b.h - 64) / (Data.POINTS - 1)
        end
        self.points[i] = p
    end
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    local cancel = ISButton:new(self.width - 88, 8, 72, 26, text("Cancel"), self, Panel.onCancel)
    cancel:initialise()
    self:addChild(cancel)
end

-- Where point i is now: the current point wobbles, the others stay put.
function Panel:position(i)
    local p = self.points[i]
    if p.hitX then
        return p.hitX, p.hitY
    end
    if i ~= self.index then
        return p.x, p.y
    end
    local t = (getTimestampMs() - self.startMs) / 1000 * self.speed
    local main = math.sin(t + p.phase) * self.amplitude
    local side = math.cos(1.37 * t + p.phase + 1.7) * self.amplitude * 0.42
    if self.horizontal then
        return p.x + side, p.y + main
    end
    return p.x + main, p.y + side
end

function Panel:onMouseDown(x, y)
    local b = self.board
    if x < b.x or x > b.x + b.w or y < b.y or y > b.y + b.h or self.done then
        return ISPanel.onMouseDown(self, x, y)
    end
    local px, py = self:position(self.index)
    local dx, dy = x - px, y - py
    if dx * dx + dy * dy <= self.tolerance * self.tolerance then
        self.points[self.index].hitX, self.points[self.index].hitY = px, py
        self.index = self.index + 1
        self.flash = 8
        if self.index > Data.POINTS then
            self:finish("success")
        end
    else
        self.misses = self.misses + 1
        self.flash = -8
        if self.misses >= self.maxMisses then
            self:finish("failed")
        end
    end
    return true
end

function Panel:onCancel()
    self:finish("cancelled")
end

local function moved(character, x, y, limit)
    local dx, dy = character:getX() - x, character:getY() - y
    return dx * dx + dy * dy > limit * limit
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
    local part = self.bodyPart
    if self.doctor:isDead() or not self.doctor:getInventory():contains(self.item)
        or not part:deepWounded() or part:stitched() then
        self:close()
        return
    end
    if moved(self.doctor, self.doctorX, self.doctorY, DOCTOR_MOVE)
        or (self.patient ~= self.doctor and moved(self.patient, self.patientX, self.patientY, PATIENT_MOVE)) then
        self:finish("cancelled")
    end
end

local function dottedLine(panel, x1, y1, x2, y2, size, r, g, b, a)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.max(1, math.floor(math.sqrt(dx * dx + dy * dy) / 2))
    for s = 0, steps do
        local t = s / steps
        panel:drawRect(x1 + dx * t - size / 2, y1 + dy * t - size / 2, size, size, a, r, g, b)
    end
end

local function point(panel, name, x, y, size, r, g, b)
    local tex = texture(name)
    if tex then
        panel:drawTextureScaled(tex, x - size / 2, y - size / 2, size, size, 1, 1, 1, 1)
    else
        panel:drawRect(x - size / 2, y - size / 2, size, size, 1, r, g, b)
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    local grime = texture("PanelGrime")
    if grime then
        self:drawTextureScaled(grime, 0, 42, self.width, self.height - 42, 0.42, 1, 1, 1)
    end
    self:drawRect(0, 0, self.width, 42, 0.9, 0.35, 0.05, 0.05)
    self:drawText(text("Title"), 16, 8, 1, 1, 1, 1, UIFont.Medium)
end

function Panel:render()
    ISPanel.render(self)
    local part = BodyPartType.getDisplayName(self.bodyPart:getType())
    self:drawText(text("Target") .. ": " .. tostring(part), 24, 54, 1, 1, 1, 1, UIFont.Small)
    self:drawText(text("Hint"), 24, 78, 0.8, 0.8, 0.8, 1, UIFont.Small)
    local band = Stitch.band(Stitch.quality(self.misses))
    local label = band:sub(1, 1):upper() .. band:sub(2)
    self:drawText(text("Quality") .. ": " .. text(label), self.width - 190, 54, 1, 0.85, 0.4, 1, UIFont.Small)
    self:drawText(text("Misses") .. ": " .. self.misses .. "/" .. self.maxMisses, self.width - 190, 78,
        1, 0.6, 0.6, 1, UIFont.Small)

    local b = self.board
    self:drawRect(b.x, b.y, b.w, b.h, 0.85, 0.25, 0.12, 0.10)
    self:drawRectBorder(b.x, b.y, b.w, b.h, 1, 0.6, 0.2, 0.2)
    local wound = texture(self.horizontal and "WoundHorizontal" or "WoundVertical")
    if wound then
        self:drawTextureScaled(wound, b.x, b.y, b.w, b.h, 1, 1, 1, 1)
    end

    local lastX, lastY
    for i = 1, Data.POINTS do
        local x, y = self:position(i)
        if self.points[i].hitX then
            if lastX then
                dottedLine(self, lastX, lastY, x, y, 3, 0.85, 0.8, 0.7, 1)
            end
            lastX, lastY = x, y
            point(self, "PointDone", x, y, self.pointSize + 10, 0.4, 0.9, 0.4)
        elseif i == self.index then
            if lastX then
                dottedLine(self, lastX, lastY, x, y, 1, 0.85, 0.8, 0.7, 0.7)
            end
            local r, g = 1, 0.9
            if self.flash < 0 then r, g = 1, 0.2 end
            point(self, "PointActive", x, y, self.activeSize + 16, r, g, 0.3)
            self:drawRectBorder(x - self.activeSize, y - self.activeSize, self.activeSize * 2,
                self.activeSize * 2, 0.8, r, g, 0.3)
        else
            point(self, "PointIdle", x, y, self.pointSize + 10, 0.7, 0.7, 0.7)
        end
    end
    self:drawText(text("Steady"), 24, self.height - 34, 0.7, 0.7, 0.7, 1, UIFont.Small)
end

function Panel:close()
    self.done = true
    self:setVisible(false)
    self:removeFromUIManager()
    if instance == self then
        instance = nil
    end
end

-- outcome: "success", "failed" or "cancelled".
function Panel:finish(outcome)
    if self.done then
        return
    end
    self:close()
    local started = self.misses > 0 or self.index > 1
    if self.session then
        Client.send(self.doctor, "stitch.result", {
            session = self.session, misses = self.misses, outcome = outcome, started = started,
        })
    end
    if outcome == "success" then
        StitchMinigame.vanillaStitch(self.doctor, self.patient, self.item, self.bodyPart)
    elseif outcome == "failed" then
        self.doctor:Say(text("FailLine"))
    end
end

-- Opening, and handing over to vanilla ---------------------------------------------------------------------------------

local bypass = false

function StitchMinigame.vanillaStitch(doctor, patient, item, bodyPart)
    bypass = true
    local action = ISStitch:new(doctor, patient, item, bodyPart, true)
    bypass = false
    ISTimedActionQueue.add(action)
end

-- Waiting for the server's answer to stitch.begin, per doctor: { doctor, patient, item, bodyPart, part, asked, atMs }.
local requests = {}
local REQUEST_MS = 10000    -- an answer later than this is ignored (the server's session simply expires)

-- Asks the server for a session; the panel opens when it arrives ("stitchSession"). Stitching another player needs
-- their consent (or an exam session they agreed to): the server answers "stitchDenied" with no_consent, and the
-- doctor then asks once (Client/Consent) and starts over on a yes. asked: this is the start-over after a yes.
function StitchMinigame.open(doctor, patient, item, bodyPart, asked)
    if instance then
        instance:close()
    end
    requests[PlayerKey.of(doctor)] = { doctor = doctor, patient = patient, item = item, bodyPart = bodyPart,
        part = bodyPart:getIndex(), asked = asked == true, atMs = getTimestampMs() }
    local args = { part = bodyPart:getIndex() }
    if patient ~= doctor then
        args.target = PlayerKey.ref(patient)
    end
    Client.send(doctor, "stitch.begin", args)
end

-- The open panel, or nil (tests).
function StitchMinigame.panel()
    return instance
end

-- The open request a server answer is for, used up; nil when there is none (or it is too old).
local function takeRequest(args)
    local request = requests[args.owner]
    if not request or request.part ~= args.part then
        return nil
    end
    requests[args.owner] = nil
    if getTimestampMs() - request.atMs > REQUEST_MS then
        return nil
    end
    return request
end

Client.on("stitchSession", function(args)
    local request = takeRequest(args)
    if not request then
        return
    end
    if instance then
        instance:close()
    end
    instance = Panel:new(request.doctor, request.patient, request.item, request.bodyPart)
    instance.session = args.id
    instance:initialise()
    instance:addToUIManager()
end)

Client.on("stitchDenied", function(args)
    local request = takeRequest(args)
    if not request then
        return
    end
    if args.reason == "no_consent" and not request.asked then
        Consent.ask(request.doctor, request.patient, "stitch", function()
            StitchMinigame.open(request.doctor, request.patient, request.item, request.bodyPart, true)
        end)
    elseif args.reason == "no_needle" then
        HaloTextHelper.addBadText(request.doctor, getText("UI_EHR_StitchMinigame_NoNeedle"))
    else
        HaloTextHelper.addBadText(request.doctor, getText("UI_EHR_StitchMinigame_Refused"))
    end
end)

-- A one-tick action so the minigame opens in turn with the actions queued before it (walking to the patient).
---@class ExtensiveHealthRedoneStitchOpen : ISBaseTimedAction
---@field patient IsoPlayer
---@field item InventoryItem
---@field bodyPart BodyPart
local OpenAction = ISBaseTimedAction:derive("ExtensiveHealthRedoneStitchOpen")

---@return ExtensiveHealthRedoneStitchOpen
function OpenAction:new(doctor, patient, item, bodyPart)
    local o = ISBaseTimedAction.new(self, doctor) --[[@as ExtensiveHealthRedoneStitchOpen]]
    o.patient, o.item, o.bodyPart = patient, item, bodyPart
    o.maxTime = 1
    return o
end

function OpenAction:isValid()
    return self.bodyPart:deepWounded() and not self.bodyPart:haveGlass() and not self.bodyPart:stitched()
end

function OpenAction:perform()
    StitchMinigame.open(self.character, self.patient, self.item, self.bodyPart)
    ISBaseTimedAction.perform(self)
end

-- Replaces the vanilla stitch action with the minigame. One of the two intercepts allowed by Core/PatchPoints.
Patches.on("stitchNew", {
    name = "stitchMinigame",
    intercept = function(_, doctor, patient, item, bodyPart, doIt)
        if bypass or not doIt or not doctor or not patient or not bodyPart or not item then
            return false
        end
        if Env.sandbox("StitchMinigameEnabled", true) == false then
            return false
        end
        if not bodyPart:deepWounded() or bodyPart:haveGlass() or bodyPart:stitched() then
            return false
        end
        return true, OpenAction:new(doctor, patient, item, bodyPart)
    end,
})

return StitchMinigame
