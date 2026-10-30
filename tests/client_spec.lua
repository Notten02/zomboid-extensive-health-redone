-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, inject-field
-- The client files load against stand-ins for the vanilla UI classes, register their handlers, and behave: the stitch
-- minigame replaces the vanilla stitch action, lockjaw refuses food, the medication menu offers, refuses and warns
-- from the mirror and its action reaches the server once, consent routes answers by purpose, combat stimulants put
-- weapon speed back, and the wake and sleep messages follow the server.
-- The panels themselves (drawing, clicks) need the game; this catches wiring and load mistakes.

insulate("client files", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- Stand-ins for the vanilla classes and helpers the client files use at load time or in these tests.
    local function class()
        local c = {}
        c.__index = c
        function c:derive(name)
            local d = setmetatable({ Type = name }, { __index = self })
            d.__index = d
            return d
        end
        function c.new(self, a)
            local o = setmetatable({}, self)
            o.character = a
            return o
        end
        function c:perform() self.performed = true end
        function c:initialise() end
        function c:addToUIManager() end
        return c
    end
    for _, name in ipairs({ "TimedActions/ISBaseTimedAction", "ISUI/ISInventoryPaneContextMenu", "ISUI/ISPanel",
        "ISUI/ISButton", "ISUI/ISModalDialog" }) do
        package.preload[name] = function() return true end
    end
    _G.ISBaseTimedAction = class()
    _G.ISPanel = class()
    _G.ISButton = class()
    _G.ISModalDialog = class()
    _G.ISInventoryPaneContextMenu = { transferIfNeeded = function() end }
    _G.getCore = function()
        return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end }
    end
    -- A context menu that records its options (ISContextMenu's addOption, getOptionFromName, removeOptionByName).
    local function newContext()
        local menu = { options = {} }
        function menu:addOption(name, target, onSelect)
            local option = { name = name, target = target, onSelect = onSelect }
            self.options[#self.options + 1] = option
            return option
        end
        function menu:getOptionFromName(name)
            for _, o in ipairs(self.options) do
                if o.name == name then return o end
            end
        end
        function menu:removeOptionByName(name)
            for i, o in ipairs(self.options) do
                if o.name == name then
                    table.remove(self.options, i)
                    return
                end
            end
        end
        function menu:addSubMenu(parent, sub) parent.subMenu = sub end
        return menu
    end
    _G.ISContextMenu = { getNew = function() return newContext() end }
    _G.ISWorldObjectContextMenu = {
        addToolTip = function()
            local t = { description = "" }
            function t:setName(name) self.name = name end
            return t
        end,
    }
    _G.ISTimedActionQueue = { added = {}, add = function(a) table.insert(ISTimedActionQueue.added, a) end }
    -- The consent prompt (Client/Consent) for split-screen patients.
    function ISModalDialog:isReallyVisible() return true end
    function ISModalDialog:destroy() end
    _G.JoypadState = _G.JoypadState or { players = {} }
    _G.getItemNameFromFullType = function(fullType) return fullType end
    _G.HaloTextHelper = { shown = {}, addBadText = function(_, t) table.insert(HaloTextHelper.shown, t) end,
        addText = function(_, t) table.insert(HaloTextHelper.shown, t) end }
    for _, name in ipairs({ "OnPlayerUpdate", "OnFillInventoryObjectContextMenu" }) do
        local handlers = {}
        _G.Events[name] = { Add = function(fn) table.insert(handlers, fn) end, handlers = handlers }
    end

    -- Item tooltips and moodles: fonts, Mod Options, mods, and a tooltip panel that renders its item.
    -- Filled in a loop: LuaLS would otherwise take these strings as the type of UIFont's fields everywhere.
    local fonts = rawget(_G, "UIFont") or {}
    for _, name in ipairs({ "Small", "Medium", "Large" }) do
        fonts[name] = fonts[name] or name
    end
    rawset(_G, "UIFont", fonts)
    _G.getTextManager = _G.getTextManager or function()
        return { getFontHeight = function() return 12 end, MeasureStringX = function(_, _, s) return 6 * #s end }
    end
    _G.Keyboard = _G.Keyboard or { KEY_J = 36, KEY_G = 34, KEY_H = 35 }
    local englishKeys = {}
    for _, file in ipairs({ "Tooltip.json", "UI.json" }) do
        local source = require("LuaSource").read("Contents/mods/ExtensiveHealthRedone/42/media/lua/shared/Translate/EN/"
            .. file)
        for key in source:gmatch('"([%w_]+)"%s*:') do englishKeys[key] = true end
    end
    _G.getTextOrNull = function(key) return englishKeys[key] and key or nil end
    ---@diagnostic disable-next-line: duplicate-set-field
    _G.getActivatedMods = function()
        return { contains = function(_, id) return id == "MoodleFramework" end }
    end
    _G.getTexture = function(path) return { path = path } end
    package.preload["ISUI/ISToolTipInv"] = function() return true end
    _G.ISToolTipInv = { render = function(panel)
        local item, tooltip = rawget(panel, "item"), rawget(panel, "tooltip")
        if item then item:DoTooltip(tooltip) end
    end }
    -- A fake MoodleFramework (its public API) that records what EHR sets.
    package.preload["MF_ISMoodle"] = function()
        local moodles = {}
        local function newMoodle()
            local m = { value = 0.5, titles = {}, pictures = {} }
            function m:setThresholds() end
            function m:setChevronCount() end
            function m:setBackground() end
            function m:setPicture(_, level, t) self.pictures[level] = t end
            function m:setTitle(_, level, t) self.titles[level] = t end
            function m:setDescription(_, level, t) self.desc = t end
            function m:setValue(v) self.value = v end
            return m
        end
        rawset(_G, "MF", {
            moodles = moodles,
            createMoodle = function(name) moodles[name] = moodles[name] or newMoodle() end,
            getMoodle = function(name) return moodles[name] end,
        })
        return true
    end

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local Effects = require("ExtensiveHealthRedone/Client/Effects")
    require("ExtensiveHealthRedone/Client/BloodMenu")
    require("ExtensiveHealthRedone/Client/Consent")
    require("ExtensiveHealthRedone/Client/StitchMinigame")
    local MedicationMenu = require("ExtensiveHealthRedone/Client/MedicationMenu")
    local ItemTooltip = require("ExtensiveHealthRedone/Client/ItemTooltip")
    local Moodles = require("ExtensiveHealthRedone/Client/Moodles")
    local Sleep = require("ExtensiveHealthRedone/Client/Sleep")
    local PlayerKey = require("ExtensiveHealthRedone/Game/PlayerKey")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("speaks lines the server sends", function()
        Client.mirror:forget("nobody")
        local Transport = require("ExtensiveHealthRedone/Game/Transport")
        Transport.toClient(player, "say", { key = "UI_EHR_Dialogue_Blood_Stage1", owner = "sp:0" })
        assert.equal("UI_EHR_Dialogue_Blood_Stage1", player.said[#player.said])
        Transport.toClient(player, "notice", { key = "UI_EHR_MedAction_RequiresIVKit", owner = "sp:0" })
        assert.equal("UI_EHR_MedAction_RequiresIVKit", HaloTextHelper.shown[#HaloTextHelper.shown])
    end)

    it("replaces the vanilla stitch action with the minigame for a deep wound without glass", function()
        local part = player.body:part("ForeArm_L")
        part.flags.deep = true
        local action = ISStitch:new(player, player, { thread = true }, part, true)
        assert.equal("ExtensiveHealthRedoneStitchOpen", action.Type)
        part.flags.glass = true
        local vanilla = ISStitch:new(player, player, { thread = true }, part, true)
        assert.is_nil(vanilla.Type)
        part.flags.glass = nil
        game.sandbox.StitchMinigameEnabled = false
        assert.is_nil(ISStitch:new(player, player, { thread = true }, part, true).Type)
        game.sandbox.StitchMinigameEnabled = nil
        part.flags = {}
    end)

    it("opens the minigame only once the server has opened a session", function()
        local StitchMinigame = require("ExtensiveHealthRedone/Client/StitchMinigame")
        local part = player.body:part("ForeArm_L")
        part.flags.deep = true
        ISStitch:new(player, player, { thread = true }, part, true):perform()
        assert.is_nil(StitchMinigame.panel())
        assert.equal("UI_EHR_StitchMinigame_NoNeedle", HaloTextHelper.shown[#HaloTextHelper.shown])
        local needle = player.inventory:add("Base.SutureNeedle")
        ISStitch:new(player, player, needle, part, true):perform()
        local panel = StitchMinigame.panel()
        assert.truthy(panel)
        assert.truthy(panel.session)
        function panel.setVisible() end
        function panel.removeFromUIManager() end
        panel:close()
        assert.is_nil(StitchMinigame.panel())
        player.inventory:Remove(needle)
        part.flags = {}
    end)

    it("refuses food while the mirrored tetanus locks the jaw", function()
        local food = { character = player, item = player.inventory:add("Base.Apple", { hunger = -0.1 }) }
        assert.is_true(ISEatFoodAction.isValid(food))
        player.modData.ExtensiveHealthRedone.conditions.active.tetanus = {
            stage = 2, left = 1e6, duration = 1e6, extra = 0, severity = 1, data = {},
        }
        game.advance(1)                      -- the server sets lockjaw and syncs it
        assert.is_true(Effects.lockjaw(player))
        assert.is_false(ISEatFoodAction.isValid(food))
        assert.equal("UI_EHR_Tetanus_CantEat", player.said[#player.said])
    end)
    describe("medication", function()
        local plainText = _G.getText
        -- getText with its arguments visible: "key|arg1|arg2".
        before_each(function()
            rawset(_G, "getText", function(key, ...)
                local parts = { key }
                for i = 1, select("#", ...) do
                    parts[#parts + 1] = tostring((select(i, ...)))
                end
                return table.concat(parts, "|")
            end)
        end)
        after_each(function() rawset(_G, "getText", plainText) end)

        ---@diagnostic disable-next-line: duplicate-set-field
        function player.inventory:contains(item) return item.container == self end
        ---@diagnostic disable-next-line: duplicate-set-field
        function player.inventory:containsRecursive(item) return item.container == self end

        local function medItem(owner, fullType, uses)
            local item = owner.inventory:add(fullType, { uses = uses, maxUses = uses })
            function item:getDisplayName() return self.fullType end
            function item:getCustomMenuOption() return nil end
            function item:getCurrentUses() return self.uses end
            function item:getMaxUses() return self.maxUses end
            function item:setJobDelta() end
            function item:setJobType() end
            return item
        end

        -- Fills a context menu for item the way vanilla calls our handlers (a stack entry), after vanilla's options.
        local function menuFor(item, vanillaOptions)
            local menu = newContext()
            for _, name in ipairs(vanillaOptions or {}) do
                menu:addOption(name)
            end
            for _, handler in ipairs(Events.OnFillInventoryObjectContextMenu.handlers) do
                handler(0, menu, { { items = { item } } })
            end
            return menu
        end

        local function find(menu, prefix)
            for _, o in ipairs(menu.options) do
                if o.name:sub(1, #prefix) == prefix then return o end
            end
        end

        it("refuses an IV drug without an IV kit, with the reason in red", function()
            local vanco = medItem(player, "ExtensiveHealth.IVVancomycin")
            local option = find(menuFor(vanco), "UI_EHR_MedAction_UseWithTier")
            assert.equal("UI_EHR_MedAction_UseWithTier|ExtensiveHealth.IVVancomycin|UI_EHR_MedAction_Tier_Clinical",
                option.name)
            assert.is_true(option.notAvailable)
            local text = option.toolTip.description
            assert.truthy(text:find("UI_EHR_MedAction_Treats|", 1, true))
            assert.truthy(text:find("UI_EHR_Disease_sepsis", 1, true))
            assert.truthy(text:find("UI_EHR_MedAction_SingleUse", 1, true))
            assert.truthy(text:find("<RGB:1,0.3,0.3> UI_EHR_MedReason_RequiresIVKit", 1, true))
            local kit = player.inventory:add("ExtensiveHealth.IVKit", { uses = 1 })
            assert.is_false(find(menuFor(vanco), "UI_EHR_MedAction_UseWithTier").notAvailable)
            player.inventory:Remove(kit)
            player.inventory:Remove(vanco)
        end)

        it("takes a course dose once through the action, then shows the course and refuses an early dose", function()
            local tablets = medItem(player, "ExtensiveHealth.ColdFluTablets", 8)
            local option = find(menuFor(tablets), "UI_EHR_MedAction_UseWithTier")
            assert.is_false(option.notAvailable)
            assert.truthy(option.toolTip.description:find("UI_EHR_MedAction_Remaining|8|8", 1, true))
            option.onSelect()
            local action = ISTimedActionQueue.added[#ISTimedActionQueue.added]
            assert.equal("EHRMedicationAction", action.Type)
            assert.equal(90, action.maxTime)
            assert.is_true(action:isValid())
            action:perform()                    -- the client's half sends nothing (a client can't send the dose)
            assert.equal(8, tablets.uses)
            assert.is_true(action:complete())  -- the authority's half (Actions/Authority)
            assert.equal(7, tablets.uses)
            game.advance(1)
            local meds = Client.section(player, "meds")
            assert.equal(1, meds.courses.ColdFluTablets.count)
            option = find(menuFor(tablets), "UI_EHR_MedAction_UseWithTier")
            assert.is_true(option.notAvailable)
            local text = option.toolTip.description
            assert.truthy(text:find("UI_EHR_Med_Tooltip_Dose|1|8", 1, true))
            assert.truthy(text:find("UI_EHR_Med_Tooltip_NextDoseIn|", 1, true))
            assert.truthy(text:find("<RGB:1,0.3,0.3> UI_EHR_Text_TheCurrentColdMedicineDoseIsStillActive", 1, true))
            player.inventory:Remove(tablets)
        end)

        it("replaces vanilla's Take pills on our homemade pills", function()
            local pills = medItem(player, "ExtensiveHealth.HomemadePainkillers", 16)
            local menu = menuFor(pills, { "ContextMenu_Take_pills" })
            assert.is_nil(menu:getOptionFromName("ContextMenu_Take_pills"))
            assert.truthy(find(menu, "UI_EHR_MedAction_UseWithTier|ExtensiveHealth.HomemadePainkillers"))
            player.inventory:Remove(pills)
        end)

        it("warns on vanilla's own option when a vanilla pill dose would not count", function()
            local caffeine = medItem(player, "Base.PillsVitamins", 5)
            local menu = menuFor(caffeine, { "ContextMenu_Take_pills" })
            assert.is_nil(menu:getOptionFromName("ContextMenu_Take_pills").toolTip)
            assert.is_nil(find(menu, "UI_EHR_MedAction_UseWithTier"))
            local doses = Client.section(player, "meds").doses
            doses.CaffeinePills = { since = 0 }
            menu = menuFor(caffeine, { "ContextMenu_Take_pills" })
            doses.CaffeinePills = nil
            local option = menu:getOptionFromName("ContextMenu_Take_pills")
            assert.is_nil(option.notAvailable)
            local text = option.toolTip.description
            assert.truthy(text:find("<RGB:1,0.6,0.2> UI_EHR_Text_TheCaffeineIsStillActiveMoreWouldBeAVeryBadIdea", 1,
                true))
            assert.truthy(text:find("UI_EHR_Med_Tooltip_Wasted", 1, true))
            player.inventory:Remove(caffeine)
        end)

        -- A second local player next to the first (split screen), with a synced mirror.
        local function addPatient()
            local patient = game.addPlayer({ x = 101, y = 100 })
            function patient:getIndex() return 1 end
            game.events.OnCreatePlayer.trigger(1, patient)
            game.advance(1)
            return patient
        end

        it("gives medication to a nearby player after their consent for that item, one dose", function()
            local patient = addPatient()
            local syrup = medItem(player, "ExtensiveHealth.CoughSyrup", 6)
            local parent = find(menuFor(syrup), "UI_EHR_Med_GiveTo")
            assert.truthy(parent and parent.subMenu)
            local entry = parent.subMenu.options[1]
            assert.equal(patient:getUsername(), entry.name)
            local queued = #ISTimedActionQueue.added
            entry.onSelect()
            assert.equal(queued, #ISTimedActionQueue.added)   -- nothing starts before the answer
            -- A transfusion answer doesn't start the medication action, nor does a yes for another item.
            Client.send(patient, "consent.answer", { from = PlayerKey.ref(player), purpose = "transfuse",
                item = syrup.id, accepted = true })
            Client.send(patient, "consent.answer", { from = PlayerKey.ref(player), purpose = "medicate",
                item = syrup.id + 1, accepted = true })
            assert.equal(queued, #ISTimedActionQueue.added)
            Client.send(patient, "consent.answer", { from = PlayerKey.ref(player), purpose = "medicate",
                item = syrup.id, accepted = true })
            local action = ISTimedActionQueue.added[#ISTimedActionQueue.added]
            assert.equal(queued + 1, #ISTimedActionQueue.added)
            assert.equal("EHRMedicationAction", action.Type)
            assert.equal(patient, action.target)
            assert.equal(120, action.maxTime)
            assert.is_true(action:isValid())
            patient.x = 105                                    -- out of reach
            assert.is_false(action:isValid())
            patient.x = 101
            action:perform()
            assert.equal(6, syrup.uses)
            assert.is_true(action:complete())
            game.advance(1)
            assert.equal(5, syrup.uses)
            assert.truthy(Client.section(patient, "meds").doses.CoughSyrup)
            -- The yes covered that one dose.
            assert.is_false(action:complete())
            assert.equal(5, syrup.uses)
            player.inventory:Remove(syrup)
            game.removePlayer(patient)
        end)

        it("offers vanilla pills to a nearby player, and gives them through medication.give", function()
            local patient = addPatient()
            local pills = medItem(player, "Base.PillsBeta", 10)
            local menu = menuFor(pills, { "ContextMenu_Take_pills" })
            assert.is_nil(find(menu, "UI_EHR_MedAction_UseWithTier"))
            local parent = find(menu, "UI_EHR_Med_GiveTo")
            assert.truthy(parent and parent.subMenu)
            parent.subMenu.options[1].onSelect()
            Client.send(patient, "consent.answer", { from = PlayerKey.ref(player), purpose = "medicate",
                item = pills.id, accepted = true })
            local action = ISTimedActionQueue.added[#ISTimedActionQueue.added]
            assert.equal("medication.give", action.command)
            -- On yourself our action has no command: vanilla's Take pills does that.
            assert.is_nil(MedicationMenu.Action:new(player, pills).command)
            assert.is_true(action:complete())
            assert.equal(9, pills.uses)
            assert.equal(pills, patient.body.pillsTaken[#patient.body.pillsTaken])
            player.inventory:Remove(pills)
            game.removePlayer(patient)
        end)

        it("lists what can be given to a patient (Give.options), and transfuses through Give.start", function()
            local Give = require("ExtensiveHealthRedone/Client/Give")
            local patient = addPatient()
            local items = {
                syrup = medItem(player, "ExtensiveHealth.CoughSyrup", 6),
                syrup2 = medItem(player, "ExtensiveHealth.CoughSyrup", 6),
                pills = medItem(player, "Base.Pills", 10),
                vanco = medItem(player, "ExtensiveHealth.IVVancomycin"),
                bag = player.inventory:add("ExtensiveHealth.BloodBagONeg", { food = true }),
                saline = player.inventory:add("ExtensiveHealth.SalineBag"),
                -- Not giveable: an apple, a tea that may not be given, vanilla tea.
                apple = player.inventory:add("Base.Apple", { food = true }),
                relaxant = player.inventory:add("ExtensiveHealth.RelaxantTea", { food = true }),
                tea = player.inventory:add("Base.HotDrinkTea", { food = true }),
            }
            local list = Give.options(player, patient)
            local labels = {}
            for i, o in ipairs(list) do
                labels[i] = o.label
            end
            assert.same({ "Base.Pills", "ExtensiveHealth.BloodBagONeg", "ExtensiveHealth.CoughSyrup",
                "ExtensiveHealth.IVVancomycin", "ExtensiveHealth.SalineBag" }, labels)
            assert.equal(items.syrup, list[3].item)
            assert.equal(2, list[3].count)
            assert.same({ "medicate", "transfuse", "medicate", "medicate", "transfuse" },
                { list[1].kind, list[2].kind, list[3].kind, list[4].kind, list[5].kind })
            assert.is_true(list[1].available)
            assert.is_nil(list[1].reason)
            assert.is_false(list[2].available)
            assert.equal("UI_EHR_MedAction_RequiresIVKit", list[2].reason)
            assert.equal("UI_EHR_MedReason_RequiresIVKit", list[4].reason)

            -- The bag says whether it suits the patient only when the doctor knows blood types.
            local kit = player.inventory:add("ExtensiveHealth.IVKit", { uses = 1 })
            assert.equal("ExtensiveHealth.BloodBagONeg", Give.options(player, patient)[2].label)
            player.firstAid = 8
            local bag = Give.options(player, patient, "A+")[2]
            assert.equal("ExtensiveHealth.BloodBagONeg UI_EHR_Transfusion_CompatibleSuffix", bag.label)
            assert.is_true(bag.available)
            -- Without a type from the caller, the split-screen mirror's.
            local patientType = Client.section(patient, "identity").bloodType
            assert.truthy(patientType)
            assert.truthy(Give.options(player, patient)[2].label:find("Suffix", 1, true))
            player.firstAid = 0

            patient.x = 110
            for _, o in ipairs(Give.options(player, patient)) do
                assert.is_false(o.available)
                assert.equal("UI_EHR_MPMedication_TooFar", o.reason)
            end
            patient.x = 101

            patient.modData.ExtensiveHealthRedone.blood.volume = 3000
            assert.is_false(Give.start(player, patient, items.apple))
            assert.is_true(Give.start(player, patient, items.bag))
            local queued = #ISTimedActionQueue.added
            Client.send(patient, "consent.answer", { from = PlayerKey.ref(player), purpose = "transfuse",
                item = items.bag.id, accepted = true })
            local action = ISTimedActionQueue.added[#ISTimedActionQueue.added]
            assert.equal(queued + 1, #ISTimedActionQueue.added)
            assert.equal("EHRTransfusionAction", action.Type)
            assert.equal(300, action.maxTime)
            assert.is_true(action:complete())
            assert.equal(0, player.inventory:count("ExtensiveHealth.BloodBagONeg"))
            assert.is_nil(kit.container)
            for _, item in pairs(items) do
                player.inventory:Remove(item)
            end
            game.removePlayer(patient)
        end)

        it("puts a stimulated weapon's speed back on swap, on expiry and on a weapon still boosted", function()
            local realInstanceof = _G.instanceof
            rawset(_G, "instanceof", function(obj, class)
                if class == "HandWeapon" then return obj.weapon == true end
                return realInstanceof(obj, class)
            end)
            local function weapon(speed)
                local w = { weapon = true, speed = speed, modData = {} }
                function w:getBaseSpeed() return self.speed end
                function w:setBaseSpeed(v) self.speed = v end
                function w:getModData() return self.modData end
                return w
            end
            local axe, bat = weapon(1), weapon(0.8)
            local stim = {}
            player.hands.primary = axe
            Effects.applyAttackSpeed(stim, player, 2)
            assert.equal(2, axe.speed)
            Effects.applyAttackSpeed(stim, player, 2)          -- nothing changed: no double boost
            assert.equal(2, axe.speed)
            player.hands.primary = bat
            Effects.applyAttackSpeed(stim, player, 2)
            assert.equal(1, axe.speed)
            assert.is_nil(axe.modData[Effects.STIM_KEY])
            assert.equal(1.6, bat.speed)
            Effects.applyAttackSpeed(stim, player, 1)
            assert.equal(0.8, bat.speed)
            -- A weapon dropped while boosted and picked up later with no effect running.
            axe.speed, axe.modData[Effects.STIM_KEY] = 2, 1
            player.hands.primary = nil
            player.hands.secondary = axe
            Effects.applyAttackSpeed(stim, player, 1)
            assert.equal(1, axe.speed)
            player.hands.primary, player.hands.secondary = nil, nil
            rawset(_G, "instanceof", realInstanceof)
        end)

        it("names the sleep blocker the server reports", function()
            local effects = Client.section(player, "effects")
            effects.sleepBy = "caffeine"
            assert.equal("UI_EHR_Caffeine_NoSleep", Sleep.reason(player))
            effects.sleepBy = "medInsomnia"
            assert.equal("UI_EHR_Sleep_CantSleep", Sleep.reason(player))
            effects.sleepBy = false
            assert.equal("UI_EHR_Sleep_CantSleep", Sleep.reason(player))
        end)

        it("wakes the player when the server says so", function()
            rawset(_G, "getSleepingEvent", function()
                return { wakeUp = function(_, who) who.asleep = false end }
            end)
            _G.UIManager = { setFadeBeforeUI = function() end, FadeIn = function() end }
            function player:setAsleep(v) self.asleep = v end
            function player:setForceWakeUpTime(v) self.wakeAt = v end
            function player:getIndex() return 0 end
            player.asleep = true
            local Transport = require("ExtensiveHealthRedone/Game/Transport")
            Transport.toClient(player, "wake", { owner = "sp:0", reason = "epinephrine" })
            assert.is_false(player.asleep)
            assert.equal(-1, player.wakeAt)
            -- Without a working SleepingEvent the flags still end the sleep.
            rawset(_G, "getSleepingEvent", function() error("no sleeping event") end)
            player.asleep = true
            Transport.toClient(player, "wake", { owner = "sp:0" })
            assert.is_false(player.asleep)
        end)
    end)
    describe("item tooltips and moodles", function()
        -- The fake game's instanceof doesn't know InventoryItem; our fake items are the ones with a full type.
        local plainInstanceof = _G.instanceof
        before_each(function()
            rawset(_G, "instanceof", function(obj, class)
                if class == "InventoryItem" then return type(obj) == "table" and obj.fullType ~= nil end
                return plainInstanceof(obj, class)
            end)
        end)
        after_each(function() rawset(_G, "instanceof", plainInstanceof) end)

        -- A tooltip that records the layout rows our lines add.
        local function newTooltip(character)
            local t = { rows = {}, height = 40, width = 200 }
            function t:getCharacter() return character end
            function t:getFont() return "Small" end
            function t:getWidth() return self.width end
            function t:getHeight() return self.height end
            function t:setHeight(h) self.height = h end
            function t:beginLayout()
                local layout = { rows = t.rows }
                function layout:addItem()
                    local row = {}
                    function row:setLabel(text) self.label = text end
                    function row:setValue(text) self.value = text end
                    function row:setProgress(f) self.progress = f end
                    table.insert(self.rows, row)
                    return row
                end
                function layout:render(_, top) return top + 10 * #self.rows end
                return layout
            end
            function t:endLayout() end
            return t
        end

        it("appends our lines after vanilla's tooltip and puts the real item back", function()
            local item = player.inventory:add("ExtensiveHealth.IVVancomycin")
            item.drawn = 0
            function item:DoTooltip() self.drawn = self.drawn + 1 end
            function item:getOutermostContainer() return nil end
            local panel = { item = item, tooltip = newTooltip(player) }
            ISToolTipInv.render(panel)
            assert.equal(1, item.drawn)
            assert.equal(item, panel.item)
            assert.truthy(#panel.tooltip.rows > 3)
            assert.truthy(panel.tooltip.height > 40)

            local apple = player.inventory:add("Base.Apple")
            apple.drawn = 0
            function apple:DoTooltip() self.drawn = self.drawn + 1 end
            function apple:getOutermostContainer() return nil end
            local plain = { item = apple, tooltip = newTooltip(player) }
            ISToolTipInv.render(plain)
            assert.equal(1, apple.drawn)
            assert.equal(0, #plain.tooltip.rows)
            player.inventory:Remove(item)
            player.inventory:Remove(apple)
        end)

        it("lets a library swap DoTooltip on the item's metatable while rendering (Starlit Library)", function()
            local item = player.inventory:add("ExtensiveHealth.IVVancomycin")
            function item:getOutermostContainer() return nil end
            local panel = { item = item, tooltip = newTooltip(player) }
            local swapped
            -- What Starlit's ISToolTipInv.render wrap does around the vanilla render, seen from inside it.
            ---@diagnostic disable-next-line: duplicate-set-field
            function item:DoTooltip()
                local classTable = getmetatable(panel.item).__index
                local old = classTable.DoTooltip
                classTable.DoTooltip = function() end
                classTable.DoTooltip = old
                swapped = true
            end
            ISToolTipInv.render(panel)
            assert.is_true(swapped)
            assert.equal(item, panel.item)
            assert.truthy(#panel.tooltip.rows > 3)
            player.inventory:Remove(item)
        end)

        it("takes lines from other providers too", function()
            local watch = player.inventory:add("ExtensiveHealth.EHRMedicalWatch_Left")
            function watch:DoTooltip() end
            function watch:getOutermostContainer() return nil end
            ItemTooltip.addProvider(function(it)
                if it == watch then
                    return { { label = { raw = "Battery" }, value = { raw = "50%" }, color = "green", progress = 0.5 } }
                end
            end)
            local panel = { item = watch, tooltip = newTooltip(player) }
            ISToolTipInv.render(panel)
            -- With a bar, the value joins the label (both in the value column would overlap).
            assert.equal("Battery 50%", panel.tooltip.rows[1].label)
            assert.is_nil(panel.tooltip.rows[1].value)
            assert.equal(0.5, panel.tooltip.rows[1].progress)
            player.inventory:Remove(watch)
        end)

        it("shows the Medical Alert through MoodleFramework, and hides it with the option off", function()
            player.modData.ExtensiveHealthRedone.conditions.active.tetanus = {
                stage = 2, left = 1e6, duration = 1e6, extra = 0, severity = 1, data = {},
            }
            game.advance(1)
            Moodles.updateAll()
            local alert = MF.moodles.EHR_MedicalAlert
            assert.equal(0.25, alert.value)
            assert.equal("UI_EHR_Moodle_MedicalAlert_Title", alert.titles[2])
            assert.equal(0.5, MF.moodles.EHR_CorpseExposure.value)
            local Options = require("ExtensiveHealthRedone/Client/Options")
            local get = Options.get
            rawset(Options, "get", function(id) return id ~= "ShowEHRMoodles" and get(id) end)
            Moodles.updateAll()
            assert.equal(0.5, alert.value)
            rawset(Options, "get", get)
            player.modData.ExtensiveHealthRedone.conditions.active.tetanus = nil
            game.advance(1)
        end)
    end)
end)
