-- Examining another player, the doctor's side (the server half is Server/Exam).
--
-- "Examine Health (<name>)" sits right after vanilla's Medical Check on the world context menu of another player (MP,
-- or a split-screen player in single player); vanilla's Medical Check stays untouched. It is greyed out with the
-- reason beyond RANGE tiles or on another floor (0 in the same vehicle). Choosing it asks the patient (consent purpose
-- "exam", Client/Consent); on a yes the server starts a session and sends the patient's EHR Monitor as the doctor may
-- see it ("examModel").
--
-- The exam window: a collapsible window titled with the patient's name, one per patient (several patients at once
-- are fine), drawing the server's model with the EHR Monitor's own view (Client/MonitorView with a source), compact
-- or expanded like the Monitor tab. Its Administer button lists what the doctor can give this patient (Client/Give;
-- each dose asks its own consent). Wounds are treated from its diagram as from the Monitor's (right click, items dropped
-- on a part) through vanilla's treatment menu for the patient; the exam's yes stands for vanilla's Medical Check
-- request (see Treatment below). It sends "exam.keep" every KEEP_SECONDS while open, and closes on X (telling the
-- server), on "examEnd" from the server, on the doctor's death, and when the two are out of range here.
-- Controller: the window takes the focus; B closes, A opens Administer, X switches compact/expanded, Y opens the
-- handbook, d-pad up/down picks a body part, left/right scroll the details.
--
-- The patient's side: a short notice when a session starts ("examNotice").

require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "XpSystem/ISUI/ISHealthPanel"

local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Consent = require "ExtensiveHealthRedone/Client/Consent"
local MonitorView = require "ExtensiveHealthRedone/Client/MonitorView"
local Handbook = require "ExtensiveHealthRedone/Client/Handbook"
local Draw = require "ExtensiveHealthRedone/Client/Draw"
local Text = require "ExtensiveHealthRedone/Client/Text"

local Exam = {}

Exam.RANGE = 3              -- Server/Exam.RANGE (Server/Consent.RANGE)
Exam.KEEP_SECONDS = 30      -- well inside the server's 300 s idle limit
Exam.TREAT_RANGE = 2        -- vanilla's Medical Check window: within 2 tiles each way (ISHealthPanel:update)

-- Why the server ended an exam -> what the doctor reads ("closed": the doctor's own doing, nothing to say).
local END_TEXT = {
    too_far = "UI_EHR_Exam_Ended_TooFar",
    idle = "UI_EHR_Exam_Ended_Idle",
    gone = "UI_EHR_Exam_Ended_Gone",
    none = "UI_EHR_Exam_Failed",
}

-- [doctorKey .. ">" .. patientKey] = open window
local windows = {}
-- The same ids for asks still waiting: a model only opens a window the doctor asked for (a late model after closing
-- must not reopen it).
local asked = {}

local function pairId(doctorKey, patientKey)
    return tostring(doctorKey) .. ">" .. tostring(patientKey)
end

-- Reading the game ------------------------------------------------------------------------------------------------

-- Tiles between two players, 0 in the same vehicle, nil on different floors (as Server/Players.distance).
function Exam.distance(a, b)
    local vehicle = a:getVehicle()
    if vehicle and vehicle == b:getVehicle() then
        return 0
    end
    if math.floor(a:getZ()) ~= math.floor(b:getZ()) then
        return nil
    end
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end

function Exam.inRange(doctor, patient)
    local d = Exam.distance(doctor, patient)
    return d ~= nil and d <= Exam.RANGE
end

-- The name vanilla's Medical Check window uses: the (disguised) display name in MP, the character's name otherwise.
function Exam.displayName(player)
    if isClient() then
        return player:getDisguisedDisplayName()
    end
    local descriptor = player:getDescriptor()
    return descriptor:getForename() .. " " .. descriptor:getSurname()
end

-- The player a server reference names on this client (PlayerKey.ref), or nil.
local function findPlayer(ref)
    local player
    if isClient() then
        player = type(ref) == "number" and getPlayerByOnlineID(ref) or nil
    else
        local index = tonumber(tostring(ref):match("^sp:(%d+)$"))
        player = index and getSpecificPlayer(index)
    end
    if player and not player:isDead() then
        return player
    end
    return nil
end

-- Another living player (not an animal: B42's animals are IsoPlayers too).
local function isPatient(object, doctor)
    return object ~= nil and object ~= doctor and instanceof(object, "IsoPlayer")
        and not instanceof(object, "IsoAnimal") and not object:isDead()
end

-- The players a world context menu is about: IsoPlayers among the objects (the controller's A-button menu adds them
-- directly, ISButtonPrompt), players standing on the clicked squares, and the target of vanilla's Medical Check
-- option when it carries one. In list order, without duplicates.
function Exam.candidates(doctor, context, worldobjects, medicalCheck)
    local list, seen = {}, {}
    local function add(object)
        if isPatient(object, doctor) and not seen[object] then
            seen[object] = true
            list[#list + 1] = object
        end
    end
    local squares = {}
    for _, object in ipairs(worldobjects or {}) do
        add(object)
        local square = object:getSquare()
        if square and not squares[square] then
            squares[square] = true
            local moving = square:getMovingObjects()
            for i = 0, moving:size() - 1 do
                add(moving:get(i))
            end
        end
    end
    if medicalCheck then
        for i = 1, 10 do
            local param = medicalCheck["param" .. i]
            if type(param) == "userdata" or type(param) == "table" then
                add(param)
            end
        end
    end
    return list
end

-- Vanilla's Medical Check option (built in Java; the label may carry a suffix), or nil.
local function medicalCheckOption(context)
    local label = getText("ContextMenu_Medical_Check")
    for _, option in ipairs(context.options or {}) do
        if type(option.name) == "string" and option.name:sub(1, #label) == label then
            return option
        end
    end
    return nil
end

-- The context menu ------------------------------------------------------------------------------------------------

function Exam.onExamine(doctor, patient)
    if not Exam.inRange(doctor, patient) then
        HaloTextHelper.addBadText(doctor, getText("UI_EHR_Context_TooFar"))
        return
    end
    local id = pairId(PlayerKey.of(doctor), PlayerKey.of(patient))
    local window = windows[id]
    if window then
        if window.isCollapsed then
            window.isCollapsed = false
            window:clearMaxDrawHeight()
        end
        window:bringToTop()
        if JoypadState.players[window.playerNum + 1] then
            setJoypadFocus(window.playerNum, window)
        end
        return
    end
    asked[id] = true
    Consent.ask(doctor, patient, "exam", function(player, ref)
        Exam.open(player, ref)
    end)
end

local function fill(playerNum, context, worldobjects, test)
    local doctor = getSpecificPlayer(playerNum)
    if not doctor or doctor:isDead() then
        return
    end
    local medicalCheck = medicalCheckOption(context)
    local patients = Exam.candidates(doctor, context, worldobjects, medicalCheck)
    if #patients == 0 then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    local after = medicalCheck and medicalCheck.name or getText("ContextMenu_Medical_Check")
    for _, patient in ipairs(patients) do
        local name = getText("UI_EHR_Context_ExamineHealthOf", Exam.displayName(patient))
        local option = context:insertOptionAfter(after, name, doctor, Exam.onExamine, patient)
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        if Exam.inRange(doctor, patient) then
            tooltip:setName(getText("UI_EHR_Context_ExamineHealth"))
            tooltip.description = getText("UI_EHR_Context_ExamineHealthDesc")
        else
            option.notAvailable = true
            tooltip:setName(getText("UI_EHR_Context_TooFar"))
            tooltip.description = getText("UI_EHR_Context_TooFarDesc", Exam.RANGE)
        end
        option.toolTip = tooltip
        after = name
    end
end

Events.OnFillWorldObjectContextMenu.Add(fill)

-- The window ------------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneExamWindow : ISCollapsableWindowJoypad
---@field id string
---@field playerNum integer
---@field doctor IsoPlayer
---@field patient IsoPlayer
---@field ref any            the patient as the server names them (PlayerKey.ref)
---@field model table?       the server's UI/Monitor model, nil until the first arrives
---@field overall number?
---@field keptAt number
---@field view ExtensiveHealthRedoneMonitorView
---@field administerButton ISButton
---@field health ISHealthPanel?  the patient's vanilla Health panel for treatment, made on first use
---@field vanillaOpen boolean?   vanilla's Medical Check window for the patient was open last frame
---@field drawJoypadFocus boolean?
local Window = ISCollapsableWindowJoypad:derive("ExtensiveHealthRedoneExamWindow")

---@param x number
---@param y number
---@param doctor IsoPlayer
---@param patient IsoPlayer
---@param ref any
---@param id string
---@return ExtensiveHealthRedoneExamWindow
function Window:new(x, y, doctor, patient, ref, id)
    local o = ISCollapsableWindowJoypad.new(self, x, y, 420, 640) --[[@as ExtensiveHealthRedoneExamWindow]]
    o:setTitle(getText("UI_EHR_Examining", Exam.displayName(patient)))
    o:setResizable(false)
    o.id = id
    o.doctor = doctor
    o.patient = patient
    o.ref = ref
    o.playerNum = doctor:getIndex()
    o.keptAt = getTimestampMs()
    return o
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local window = self
    local source = {
        subject = self.patient,
        read = function()
            return window.model, window.overall
        end,
        health = function(bodyPartType)
            return window:healthPart(bodyPartType)
        end,
    }
    self.view = MonitorView:new(0, self:titleBarHeight(), self.playerNum, source)
    self.view:initialise()
    self:addChild(self.view)
    self.view:onOpened()
    local label = getText("UI_EHR_Exam_Administer")
    self.administerButton = ISButton:new(0, Draw.PAD, Draw.width(label) + 16, Draw.SMALL + 6, label, self,
        Window.openAdminister)
    self.administerButton:initialise()
    self.view:addHeaderButton(self.administerButton)
end

function Window:setModel(model, overall)
    self.model = model
    self.overall = overall
    self.view:markStale()
end

-- Treatment ---------------------------------------------------------------------------------------------------------
-- Through a vanilla ISHealthPanel set up as vanilla's Medical Check sets one up (ISMedicalCheckAction:perform): the
-- patient's panel with the doctor as its other player, so vanilla's handlers, timed actions and other mods' additions
-- all apply. It is never shown, so the checks its update() makes are made here: the doctor within TREAT_RANGE (the
-- exam itself allows RANGE), and the patient's body damage arriving. In MP the doctor's client receives a remote
-- patient's body damage only while it asks for it: from the window opening to its closing. Asking is not repeated at
-- treatment time (a menu built right after asking can find the remote body empty); instead the window asks again when
-- vanilla's own Medical Check window for the same patient closes, since that stops the updates.

local function remote(patient)
    return isClient() and not patient:isLocalPlayer()
end

-- Vanilla's Medical Check window for this patient is open (it receives the same updates).
local function vanillaWindowOpen(patient)
    local window = ISMedicalCheckAction and ISMedicalCheckAction.getHealthWindowForPlayer(patient)
    return window ~= nil and window:getIsVisible()
end

function Window:receiveBodyDamage(on)
    if not remote(self.patient) then
        return
    end
    if on then
        self.doctor:startReceivingBodyDamageUpdates(self.patient)
    elseif not vanillaWindowOpen(self.patient) then
        self.doctor:stopReceivingBodyDamageUpdates(self.patient)
    end
end

-- Each frame: vanilla's Medical Check window for the patient just closed, so its updates stopped; ask again.
function Window:watchVanillaWindow()
    local open = vanillaWindowOpen(self.patient)
    if self.vanillaOpen and not open then
        self:receiveBodyDamage(true)
    end
    self.vanillaOpen = open
end

-- Within vanilla's treatment reach: TREAT_RANGE tiles each way on the same floor, or in the same vehicle.
function Window:inTreatRange()
    local d = Exam.distance(self.doctor, self.patient)
    return d ~= nil and (d == 0 or math.abs(self.doctor:getX() - self.patient:getX()) <= Exam.TREAT_RANGE
        and math.abs(self.doctor:getY() - self.patient:getY()) <= Exam.TREAT_RANGE)
end

-- The patient's vanilla Health panel and body part for the diagram's treatment (Client/MonitorView), or nil with a
-- notice beyond reach.
function Window:healthPart(bodyPartType)
    if not self:inTreatRange() then
        HaloTextHelper.addBadText(self.doctor, getText("UI_EHR_Context_TooFar"))
        return nil
    end
    if not self.health then
        local health = ISHealthPanel:new(self.patient, 0, 0, 400, 400)
        health:initialise()
        health:instantiate()
        health:setOtherPlayer(self.doctor)
        self.health = health
    end
    self.health.doctorLevel = self.doctor:getPerkLevel(Perks.Doctor)
    local body = remote(self.patient) and self.patient:getBodyDamageRemote() or self.patient:getBodyDamage()
    return self.health, body:getBodyPart(bodyPartType)
end

-- Why the window must close here, or nil.
function Window:closeReason()
    local doctor = self.doctor
    if getSpecificPlayer(self.playerNum) ~= doctor or doctor:isDead() then
        return "gone"
    end
    if findPlayer(self.ref) ~= self.patient then
        return "gone"
    end
    if not Exam.inRange(doctor, self.patient) then
        return "too_far"
    end
    return nil
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    local reason = self:closeReason()
    if reason then
        Exam.close(self.id, true, reason)
        return
    end
    self:watchVanillaWindow()
    local now = getTimestampMs()
    if now - self.keptAt >= Exam.KEEP_SECONDS * 1000 then
        self.keptAt = now
        Client.send(self.doctor, "exam.keep", { target = self.ref })
    end
end

-- What the doctor can give (Client/Give: labels and reasons are translated already), as a small menu under the
-- button. The patient's blood type comes from the model, so a bag says whether it suits them (when the doctor knows).
local function giveText(value)
    if type(value) == "table" then
        return Text.t(value)
    end
    return tostring(value)
end

function Window:openAdminister()
    local Give = require "ExtensiveHealthRedone/Client/Give"
    local button = self.administerButton
    local context = ISContextMenu.get(self.playerNum, button:getAbsoluteX(), button:getAbsoluteY() + button:getHeight())
    local entries = Give and Give.options(self.doctor, self.patient, self.model and self.model.bloodType) or {}
    if #entries == 0 then
        context:addOption(getText("UI_EHR_Exam_AdministerNone")).notAvailable = true
    end
    for _, entry in ipairs(entries) do
        local label = giveText(entry.label)
        if (tonumber(entry.count) or 1) > 1 then
            label = label .. " (" .. tostring(entry.count) .. ")"
        end
        local option = context:addOption(label, self, Window.administer, entry.item)
        if not entry.available then
            option.notAvailable = true
            if entry.reason then
                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip.description = giveText(entry.reason)
                option.toolTip = tooltip
            end
        end
    end
    if JoypadState.players[self.playerNum + 1] then
        ---@diagnostic disable-next-line: inject-field
        context.origin = self
        context.mouseOver = 1
        setJoypadFocus(self.playerNum, context)
    end
end

function Window:administer(item)
    local Give = require "ExtensiveHealthRedone/Client/Give"
    if Give and Exam.inRange(self.doctor, self.patient) then
        Give.start(self.doctor, self.patient, item)
    end
end

function Window:close()
    Exam.close(self.id, true)
end

function Window:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    self.drawJoypadFocus = true
end

function Window:onLoseJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onLoseJoypadFocus(self, joypadData)
    self.drawJoypadFocus = false
end

function Window:onJoypadDown(button)
    if button == Joypad.BButton then
        self:close()
    elseif button == Joypad.AButton then
        self:openAdminister()
    elseif button == Joypad.XButton then
        self.view:toggleExpanded()
    elseif button == Joypad.YButton then
        Handbook.toggle(self.playerNum, self)
    end
end

function Window:onJoypadDirUp()
    self.view:stepPart(-1)
end

function Window:onJoypadDirDown()
    self.view:stepPart(1)
end

function Window:onJoypadDirLeft()
    self.view:scroll(-60)
end

function Window:onJoypadDirRight()
    self.view:scroll(60)
end

-- API ---------------------------------------------------------------------------------------------------------------

function Exam.window(doctorKey, patientKey)
    return windows[pairId(doctorKey, patientKey)]
end

-- Opens (or returns) the window for a patient the server names by ref. nil when the patient isn't here.
function Exam.open(doctor, ref)
    local patient = findPlayer(ref)
    if not patient or not doctor or doctor:isDead() then
        return nil
    end
    local id = pairId(PlayerKey.of(doctor), PlayerKey.of(patient))
    asked[id] = nil
    if windows[id] then
        return windows[id]
    end
    local playerNum = doctor:getIndex()
    local count = 0
    for _ in pairs(windows) do
        count = count + 1
    end
    local x = getPlayerScreenLeft(playerNum) + 70 + 24 * count
    local y = getPlayerScreenTop(playerNum) + 50 + 32 * count
    local window = Window:new(x, y, doctor, patient, ref, id)
    window:initialise()
    window:instantiate()
    windows[id] = window
    window:setVisible(true)
    window:addToUIManager()
    window:bringToTop()
    window:receiveBodyDamage(true)
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, window)
    end
    return window
end

-- Closes a window. notify: tell the server (the doctor closed it here); reason: what the doctor reads.
function Exam.close(id, notify, reason)
    local window = windows[id]
    if not window then
        return
    end
    windows[id] = nil
    window:setVisible(false)
    window:removeFromUIManager()
    window:receiveBodyDamage(false)
    local doctor = window.doctor
    if notify then
        Client.send(doctor, "exam.close", { target = window.ref })
    end
    if not doctor:isDead() then
        if reason and END_TEXT[reason] then
            HaloTextHelper.addBadText(doctor, getText(END_TEXT[reason]))
        end
        if window.joyfocus then
            setJoypadFocus(window.playerNum, nil)
        end
    end
end

-- Messages ----------------------------------------------------------------------------------------------------------

Client.on("examModel", function(args)
    local doctor = Client.localPlayer(args.owner)
    if not doctor then
        return
    end
    local id = pairId(args.owner, args.patient)
    local window = windows[id]
    if not window and asked[id] then
        window = Exam.open(doctor, args.target)
    end
    if window then
        window:setModel(args.model, tonumber(args.overall))
    elseif not asked[id] then
        -- Nobody here wants it (closed a moment ago): end the session rather than let it idle out.
        Client.send(doctor, "exam.close", { target = args.target })
    end
end)

Client.on("examEnd", function(args)
    local doctor = Client.localPlayer(args.owner)
    if not doctor then
        return
    end
    local id = pairId(args.owner, args.patient)
    local hadWindow = windows[id] ~= nil
    asked[id] = nil
    Exam.close(id, false, args.reason)
    if not hadWindow and args.reason ~= "closed" and END_TEXT[args.reason] and not doctor:isDead() then
        HaloTextHelper.addBadText(doctor, getText(END_TEXT[args.reason]))
    end
end)

Client.on("examNotice", function(args)
    local patient = Client.localPlayer(args.owner)
    if patient then
        HaloTextHelper.addText(patient, getText("UI_EHR_Exam_BeingExamined", tostring(args.name)))
    end
end)

-- The doctor died: every window of theirs goes (the server ends the sessions on its own).
Events.OnPlayerDeath.Add(function(player)
    local closing = {}
    for id, window in pairs(windows) do
        if window.doctor == player or window.patient == player then
            closing[#closing + 1] = id
        end
    end
    for _, id in ipairs(closing) do
        Exam.close(id, false)
    end
end)

return Exam
