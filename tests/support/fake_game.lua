-- A minimal stand-in for the Project Zomboid globals our adapter code uses, so the server and client wiring can run
-- offline in single-player mode. It is not a game simulation: only the calls the adapters make exist, and anything
-- else fails loudly. Install it inside an insulate() block; busted restores _G and package.loaded afterwards.
--
-- Add-on mods reuse it from their own repository: FakeGame.install({ root = "../extensive-health-redone/" }) finds
-- EHR's server and client code from there, and game.sandboxFor, game.addEvent and game.addPerk add the add-on's own
-- sandbox namespace, events and perks.

-- The fake vanilla action tables are deliberately partial.
---@diagnostic disable: missing-fields

local FakeGame = {}

local LUA = "Contents/mods/ExtensiveHealthRedone/42/media/lua/"

local function newEvent()
    local event = { handlers = {} }
    function event.Add(fn)
        event.handlers[#event.handlers + 1] = fn
    end
    function event.Remove(fn)
        for i, h in ipairs(event.handlers) do
            if h == fn then
                table.remove(event.handlers, i)
                return
            end
        end
    end
    function event.trigger(...)
        for _, h in ipairs(event.handlers) do
            h(...)
        end
    end
    return event
end

local function enum(names, extra)
    local t = {}
    for _, name in ipairs(names) do
        local value = { name = name }
        for k, v in pairs(extra or {}) do
            value[k] = v
        end
        t[name] = value
    end
    return t
end

local PART_NAMES = {
    "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper", "Torso_Lower",
    "Head", "Neck", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R",
}

-- Wound flags a test can set on a fake body part: part.flags.deep = true, ...
local FLAG_METHODS = {
    bleeding = "bleeding", bandaged = "bandaged", isBandageDirty = "bandageDirty", deepWounded = "deep",
    haveGlass = "glass", haveBullet = "bullet", isCut = "cut", bitten = "bite", scratched = "scratch",
    isBurnt = "burn", stitched = "stitched",
}

local function newPart(index)
    local part = { index = index, name = PART_NAMES[index + 1], health = 100, additionalPain = 0, flags = {},
        infected = false, infectionLevel = 0 }
    for method, flag in pairs(FLAG_METHODS) do
        part[method] = function(self) return self.flags[flag] == true end
    end
    function part:getIndex() return self.index end
    function part:getType() return { name = self.name } end
    function part:getHealth() return self.health end
    function part:SetHealth(v) self.health = v end
    function part:ReduceHealth(v) self.health = math.max(0, self.health - v) end
    function part:getBleedingTime() return self.flags.bleeding and 1 or 0 end
    function part:getAdditionalPain() return self.additionalPain end
    function part:setAdditionalPain(v) self.additionalPain = v end
    function part:isInfectedWound() return self.infected end
    function part:setInfectedWound(v) self.infected = v end
    function part:getWoundInfectionLevel() return self.infectionLevel end
    function part:setWoundInfectionLevel(v) self.infectionLevel = v end
    -- Knox (Server/Knox): part.knox = Knox-infected, part.fakeKnox = fake-infected.
    function part:IsInfected() return self.knox == true end
    function part:SetInfected(v) self.knox = v end
    function part:IsFakeInfected() return self.fakeKnox == true end
    function part:SetFakeInfected(v) self.fakeKnox = v end
    -- Scabies scratches and concussion fractures (Server/BodyWriter, Server/Corpse).
    function part:setScratched(v) self.flags.scratch = v end
    function part:getScratchTime() return self.scratchTime or 0 end
    function part:setScratchTime(v) self.scratchTime = v end
    -- Healing timers: part.times.cut and so on; a fracture flag without a timer reads 1.
    part.times = {}
    function part:getCutTime() return self.times.cut or 0 end
    function part:setCutTime(v) self.times.cut = v end
    function part:getDeepWoundTime() return self.times.deep or 0 end
    function part:setDeepWoundTime(v) self.times.deep = v end
    function part:getBurnTime() return self.times.burn or 0 end
    function part:setBurnTime(v) self.times.burn = v end
    function part:getFractureTime() return self.times.fracture or (self.flags.fracture and 1 or 0) end
    function part:setFractureTime(v) self.times.fracture = v end
    function part:setCut(v) self.flags.cut = v end
    function part:generateDeepWound() self.flags.deep = true; self.times.deep = 20 end

    -- An admin's full restore (Server/BodyWriter): health, wounds and pain back to normal; stiffness 0-100.
    function part:RestoreToFullHealth()
        self.health, self.additionalPain, self.flags = 100, 0, {}
    end
    function part:getStiffness() return self.stiffness or 0 end
    function part:setStiffness(v) self.stiffness = v end
    function part:HasInjury()
        local f = self.flags
        return f.bleeding or f.deep or f.glass or f.bullet or f.cut or f.bite or f.scratch or f.burn or false
    end
    return part
end

local function newBody()
    local body = { health = 100, parts = {} }
    for i = 0, #PART_NAMES - 1 do
        body.parts[i + 1] = newPart(i)
    end
    local list = {
        size = function() return #body.parts end,
        get = function(_, i) return body.parts[i + 1] end,
    }
    function body:getBodyParts() return list end
    function body:getOverallBodyHealth() return self.health end
    function body:setOverallBodyHealth(v) self.health = v end
    function body:ReduceGeneralHealth(v) self.health = math.max(0, self.health - v) end
    -- Knox (Server/Knox): body.knox = { infected, time, duration } (world hours; -1 when not infected).
    body.knox = { infected = false, time = -1, duration = -1 }
    function body:IsInfected() return self.knox.infected end
    function body:setInfected(v) self.knox.infected = v end
    function body:getInfectionTime() return self.knox.time end
    function body:setInfectionTime(v) self.knox.time = v end
    function body:getInfectionMortalityDuration() return self.knox.duration end
    function body:setInfectionMortalityDuration(v) self.knox.duration = v end
    -- Vanilla's cold (common cold): strength 0-100 and the moodle flag.
    body.cold = { strength = 0, has = false, catch = 0 }
    function body:getColdStrength() return self.cold.strength end
    function body:setColdStrength(v) self.cold.strength = v end
    function body:setHasACold(v) self.cold.has = v end
    function body:setCatchACold(v) self.cold.catch = v end
    -- Vanilla's pill effect (giving pills): records the item; the Java one also uses a pill (inferred), the
    -- fake leaves that to Server/Medication's fallback.
    body.pillsTaken = {}
    function body:JustTookPill(item) self.pillsTaken[#self.pillsTaken + 1] = item end
    -- What the Java version clears beyond overall health is unverified, so the fake restores only that.
    function body:RestoreToFullHealth() self.health = 100 end
    function body:part(name)
        for _, p in ipairs(self.parts) do
            if p.name == name then return p end
        end
    end
    return body
end

-- A fake inventory of fake items. Items: { id, fullType, modData, uses (drainables), usesFloat (charge), food,
-- alcoholic, hunger, clock (an alarm clock or watch) }.
local function newInventory(game)
    local inv = { items = {} }
    function inv:add(fullType, props)
        game.nextItemId = game.nextItemId + 1
        local item = { id = game.nextItemId, fullType = fullType, modData = {}, container = inv }
        for k, v in pairs(props or {}) do item[k] = v end
        function item:getID() return self.id end
        function item:getFullType() return self.fullType end
        function item:getModData() return self.modData end
        function item:getContainer() return self.container end
        function item:isAlcoholic() return self.alcoholic == true end
        function item:getHungChange() return self.hunger or 0 end
        function item:isFrozen() return self.frozen == true end
        -- Heat (Server/Temperature food temperature): .heat, vanilla's multiplier (1.0 room temperature).
        function item:IsFood() return self.food == true end
        function item:IsDrainable() return self.uses ~= nil end
        function item:getHeat() return self.heat or 1 end
        function item:getItemHeat() return self.heat or 1 end
        function item:getFluidContainer() return self.fluid end
        function item:UseAndSync()
            self.uses = (self.uses or 1) - 1
            if self.uses <= 0 then inv:Remove(self) end
        end
        -- Drainable charge 0-1 (.usesFloat, default full): the watch battery (Server/Watch).
        function item:getCurrentUsesFloat() return self.usesFloat or 1 end
        function item:setCurrentUsesFloat(v) self.usesFloat = v end
        -- Client/Give, Server/Medication.give: uses left, the name, vanilla antibiotics' power (.infectionPower).
        function item:getCurrentUses() return self.uses or 1 end
        function item:getDisplayName() return self.displayName or self.fullType end
        function item:getReduceInfectionPower() return self.infectionPower or 0 end
        self.items[#self.items + 1] = item
        return item
    end
    function inv:AddItem(fullType) return self:add(fullType) end
    function inv:Remove(item)
        for i, it in ipairs(self.items) do
            if it == item then
                table.remove(self.items, i)
                item.container = nil
                return
            end
        end
    end
    function inv:getItems()
        local items = self.items
        return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
    end
    function inv:containsRecursive(item)
        for _, it in ipairs(self.items) do
            if it == item then return true end
        end
        return false
    end
    -- The fake has no bags, so the main inventory is everything (Actions/Common.carries).
    function inv:contains(item) return self:containsRecursive(item) end
    function inv:getItemWithIDRecursiv(id)
        for _, it in ipairs(self.items) do
            if it.id == id then return it end
        end
    end
    function inv:getFirstEvalRecurse(fn)
        for _, it in ipairs(self.items) do
            if fn(it) then return it end
        end
    end
    function inv:getAllEvalRecurse(fn)
        local found = {}
        for _, it in ipairs(self.items) do
            if fn(it) then found[#found + 1] = it end
        end
        return { size = function() return #found end, get = function(_, i) return found[i + 1] end }
    end
    function inv:count(fullType)
        local n = 0
        for _, it in ipairs(self.items) do
            if it.fullType == fullType then n = n + 1 end
        end
        return n
    end
    return inv
end

-- A fake square. Tests set square.room, square.exterior, square.floor (texture name), square.snow, square.deadBodies
-- (fake corpses) and square.objects.
local function newSquare(x, y, z)
    local sq = { x = x, y = y, z = z, room = nil, exterior = true, floor = "floors_interior_tilesandwood_01_0",
        snow = false, deadBodies = {}, objects = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:isInARoom() return self.room ~= nil end
    function sq:getRoom() return self.room end
    function sq:has(flag) return flag == "exterior" and self.exterior end
    function sq:getFloor()
        local floor = self.floor
        return floor and { getTextureName = function() return floor end } or nil
    end
    local function list(t)
        return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
    end
    function sq:getDeadBodys() return list(self.deadBodies) end
    function sq:getObjects() return list(self.objects) end
    function sq:getWindow() return self.window end
    return sq
end
FakeGame.newSquare = newSquare

local function newPlayer(game, index, opts)
    local stats = { TEMPERATURE = 37 }      -- body temperature in deg C; other stats start at 0
    local player = {
        modData = opts.modData or {},
        dead = false,
        asleep = false,
        x = opts.x or 100, y = opts.y or 100, z = opts.z or 0,
        capabilities = opts.capabilities or {},
        body = newBody(),
        inventory = newInventory(game),
        firstAid = opts.firstAid or 0,
        said = {},
    }
    -- opts.items: { [id] = fullType } for tests that only need an item to exist.
    for id, fullType in pairs(opts.items or {}) do
        local item = player.inventory:add(fullType)
        item.id = id
    end
    function player:getModData() return self.modData end
    function player:getUsername() return opts.username or ("player" .. index) end
    -- Names an admin can type (Server/Admin): opts.displayName, opts.forename, opts.surname.
    function player:getDisplayName() return opts.displayName or self:getUsername() end
    function player:getDescriptor()
        return { getForename = function() return opts.forename or "" end,
            getSurname = function() return opts.surname or "" end }
    end
    -- Fitness stiffness records removed by a full restore: player.stiffnessRemoved[part name] = true.
    player.stiffnessRemoved = {}
    function player:getFitness()
        return { removeStiffnessValue = function(_, name) player.stiffnessRemoved[name] = true end }
    end
    function player:getPlayerNum() return index end
    function player:getOnlineID() return index end
    function player:isDead() return self.dead end
    function player:isAsleep() return self.asleep end
    function player:getX() return self.x end
    function player:getY() return self.y end
    function player:getZ() return self.z end
    function player:getVehicle() return self.vehicle end
    -- Skills other than First Aid: player.levels[perk name] and player.perkXp[perk name] (addXp adds to it).
    player.levels = opts.levels or {}
    player.perkXp = opts.perkXp or {}
    function player:getPerkLevel(perk)
        if perk and self.levels[perk.name] ~= nil then
            return self.levels[perk.name]
        end
        return self.firstAid
    end
    function player:getXp()
        return { getXP = function(_, perk) return player.perkXp[perk.name] or 0 end }
    end
    function player:getPerkInfo(perk)
        local level = player.levels[perk.name]
        return level and { getLevel = function() return player.levels[perk.name] end } or nil
    end
    function player:LoseLevel(perk) self.levels[perk.name] = math.max(0, (self.levels[perk.name] or 0) - 1) end

    function player:getBodyDamage() return self.body end
    function player:Kill() self.dead = true end
    -- Shared timed actions and vanilla antibiotics given to another player.
    function player:isTimedActionInstant() return false end
    function player:getReduceInfectionPower() return self.reduceInfectionPower or 0 end
    function player:setReduceInfectionPower(v) self.reduceInfectionPower = v end
    function player:Say(text) self.said[#self.said + 1] = text end
    function player:getStats()
        return {
            get = function(_, stat) return stats[stat.name] or 0 end,
            set = function(_, stat, value) stats[stat.name] = value end,
        }
    end
    function player:getRole()
        return { hasCapability = function(_, capability) return player.capabilities[capability.name] == true end }
    end
    function player:getInventory() return self.inventory end
    -- Traits (player.traits[token] = true) and print media read (player.printMediaRead[id] = true).
    player.traits = {}
    player.printMediaRead = {}
    function player:hasTrait(token) return self.traits[token] == true end
    function player:getCharacterTraits()
        return { add = function(_, token) player.traits[token] = true end }
    end
    function player:isPrintMediaRead(id) return self.printMediaRead[id] == true end
    -- Surroundings (Server/Facts env): the square under the player and what the player is doing.
    player.square = newSquare(player.x, player.y, player.z)
    player.state = { sitOnGround = false, moving = false, running = false, sprinting = false, aiming = false,
        female = opts.female == true }
    function player:getCurrentSquare() return self.square end
    function player:isSitOnGround() return self.state.sitOnGround end
    function player:isSittingOnFurniture() return self.state.sittingOnFurniture == true end
    function player:getHoursSurvived() return game.minutes / 60 end
    function player:isPlayerMoving() return self.state.moving end
    function player:isRunning() return self.state.running end
    function player:isSprinting() return self.state.sprinting end
    function player:isAiming() return self.state.aiming end
    function player:isFemale() return self.state.female end
    -- Worn items (Server/Corpse face protection): player.worn is a list of fake items. Fake clothing may carry
    -- .soil = { [BloodBodyPartType name] = { dirt, blood } } for the immunity hygiene reader (Server/Immunity).
    player.worn = {}
    function player:getWornItems()
        local worn = self.worn
        return {
            size = function() return #worn end,
            getItemByIndex = function(_, i) return worn[i + 1] end,
            -- WornItem: the item plus its body location (fake items may carry .location).
            get = function(_, i)
                local item = worn[i + 1]
                return { getItem = function() return item end, getLocation = function() return item.location end }
            end,
        }
    end
    -- Sounds and world noise (Server/Noise): recorded for tests.
    player.sounds, player.worldSounds = {}, {}
    function player:playSound(name) self.sounds[#self.sounds + 1] = name end
    function player:addWorldSoundUnlessInvisible(radius, volume)
        self.worldSounds[#self.worldSounds + 1] = { radius = radius, volume = volume }
    end
    -- Held and worn items (Server/Noise tissues, Server/Mind delirium impulses).
    player.hands = { primary = nil, secondary = nil, back = nil }
    function player:getPrimaryHandItem() return self.hands.primary end
    function player:getSecondaryHandItem() return self.hands.secondary end
    function player:getClothingItem_Back() return self.hands.back end
    -- Blood and dirt per BloodBodyPartType name (Server/Food hands reader, wash hands).
    player.visual = { blood = {}, dirt = {} }
    function player:getHumanVisual()
        local v = self.visual
        return {
            getBlood = function(_, part) return v.blood[part.name] or 0 end,
            getDirt = function(_, part) return v.dirt[part.name] or 0 end,
            setBlood = function(_, part, value) v.blood[part.name] = value end,
            setDirt = function(_, part, value) v.dirt[part.name] = value end,
        }
    end
    player.stats = stats
    return player
end

-- Installs the fake globals and puts the client and server folders on the module path.
-- opts.root: the EHR repository root, relative to the working directory or absolute, ending in "/" (default: the
-- working directory, EHR's own tests).
-- Returns the game handle: advance(minutes), tick(), addPlayer(opts), sandbox table, events, players.
function FakeGame.install(opts)
    opts = opts or {}
    local game = { minutes = 6000, realMs = 1000000, players = {}, printed = {}, nextItemId = 1000 }
    local lua = (opts.root or "") .. LUA

    package.path = lua .. "server/?.lua;" .. lua .. "client/?.lua;" .. package.path

    _G.isClient = function() return false end
    _G.isServer = function() return false end
    _G.getTimestampMs = function() return game.realMs end
    _G.getGameTime = function()
        return {
            getWorldAgeHours = function() return game.minutes / 60 end,
            getTimeOfDay = function() return (game.minutes / 60) % 24 end,
            getMonth = function() return game.month - 1 end,
        }
    end
    -- Weather: tests change game.climate.airC, .raining, .snowing.
    game.month = 7
    game.climate = { airC = 20, raining = false, snowing = false }
    _G.getClimateManager = function()
        return {
            getAirTemperatureForCharacter = function() return game.climate.airC end,
            -- Outdoor air (Server/IndoorClimate's plausibility band): game.climate.outdoorC, default airC.
            getTemperature = function() return game.climate.outdoorC or game.climate.airC end,
            isRaining = function() return game.climate.raining end,
            isSnowing = function() return game.climate.snowing end,
        }
    end
    -- Squares beyond the players' own: game.squares["x,y,z"] = FakeGame.newSquare(x, y, z) (Server/Corpse scans).
    game.squares = {}
    _G.getCell = function()
        -- The players' own squares, indexed on the first lookup through this cell (the first player wins a shared
        -- square, as a linear scan would). Without the index the corpse scan is O(players^2) (tests/load_spec.lua).
        local index
        return {
            getGridSquare = function(_, x, y, z)
                local id = x .. "," .. y .. "," .. z
                if not index then
                    index = {}
                    for _, p in ipairs(game.players) do
                        local sq = p.square
                        local at = sq.x .. "," .. sq.y .. "," .. sq.z
                        index[at] = index[at] or sq
                    end
                end
                return index[id] or game.squares[id]
            end,
            gridSquareIsSnow = function(_, x, y, z)
                for _, p in ipairs(game.players) do
                    if p.square.x == x and p.square.y == y and p.square.z == z then return p.square.snow end
                end
                return false
            end,
        }
    end
    _G.IsoFlagType = { exterior = "exterior" }
    -- BloodBodyPartType in vanilla order, with index(), FromIndex and MAX (Server/Immunity hygiene reader).
    local bloodParts = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper",
        "Torso_Lower", "Head", "Neck", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L",
        "Foot_R", "Back", "MAX" }
    _G.BloodBodyPartType = enum(bloodParts)
    for i, name in ipairs(bloodParts) do
        local part = _G.BloodBodyPartType[name]
        part.index = function() return i - 1 end
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    _G.BloodBodyPartType.FromIndex = function(i) return _G.BloodBodyPartType[bloodParts[i + 1]] end
    -- ZombRand(max) -> [0, max); ZombRand(min, max) -> [min, max). Deterministic: the middle of the range.
    _G.ZombRand = function(lo, hi)
        if hi == nil then
            lo, hi = 0, lo
        end
        return lo + math.floor((hi - lo) / 2)
    end
    -- game.float (default 0.5) is what every random float returns, so a test can force a roll either way.
    _G.ZombRandFloat = function(lo, hi) return lo + (hi - lo) * (game.float or 0.5) end
    ---@diagnostic disable-next-line: missing-fields
    _G.SandboxVars = { ExtensiveHealthRework = { DebugMode = false } }
    -- Enabled mods: game.mods["LifestyleHobbies"] = true.
    game.mods = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    _G.getActivatedMods = function()
        return { contains = function(_, id) return game.mods[id:gsub("^\\", "")] == true end }
    end
    _G.getNumActivePlayers = function() return #game.players end
    _G.getSpecificPlayer = function(i) return game.players[i + 1] end
    _G.sendPlayerStat = function() error("sendPlayerStat is for dedicated servers") end
    _G.print = function(line) game.printed[#game.printed + 1] = line end
    _G.CharacterStat = enum(require("ExtensiveHealthRedone/Data/VanillaStats"), {
        getMinimumValue = function() return 0 end,
        getMaximumValue = function() return 100 end,
    })
    _G.Capability = enum({ "CanMedicalCheat", "UseHealthCheat" })
    _G.Perks = { Doctor = { name = "Doctor" }, PlantScavenging = { name = "PlantScavenging" },
        Strength = { name = "Strength" }, Fitness = { name = "Fitness" } }
    -- More perks for an add-on's tests.
    function game.addPerk(name)
        _G.Perks[name] = _G.Perks[name] or { name = name }
        return _G.Perks[name]
    end
    -- XP awards: game.xp[username] = First Aid total; game.perkXp[perk name][username] = total for any perk
    game.xp = {}
    game.perkXp = {}
    _G.addXp = function(player, perk, amount)
        local name = player:getUsername()
        assert(perk ~= nil and _G.Perks[perk.name] == perk, "XP for an unexpected perk")
        local byPerk = game.perkXp[perk.name] or {}
        game.perkXp[perk.name] = byPerk
        byPerk[name] = (byPerk[name] or 0) + amount
        if perk == _G.Perks.Doctor then
            game.xp[name] = (game.xp[name] or 0) + amount
        end
        player.perkXp[perk.name] = (player.perkXp[perk.name] or 0) + amount
    end
    -- Levels: 100 XP each (player.levels[perk name], default 0); Server/PerkWriter's level loss.
    _G.PerkFactory = {
        getPerk = function(perk)
            return { getTotalXpForLevel = function(_, level) return level * 100 end, name = perk.name }
        end,
    }
    _G.BodyPartType = { ToString = function(t) return t.name end }
    _G.instanceof = function(obj, class)
        if class == "DrainableComboItem" then return obj.uses ~= nil end
        if class == "Food" then return obj.food == true end
        if class == "AlarmClockClothing" or class == "AlarmClock" then return obj.clock == true end
        if class == "Clothing" then
            if obj.clothing == true and not obj.getVisual then
                local soil = obj.soil or {}
                function obj.getVisual()
                    return {
                        getDirt = function(_, part) return (soil[part.name] or {}).dirt or 0 end,
                        getBlood = function(_, part) return (soil[part.name] or {}).blood or 0 end,
                    }
                end
                function obj.getCoveredParts()
                    local list = {}
                    for name in pairs(soil) do
                        list[#list + 1] = _G.BloodBodyPartType[name]
                    end
                    table.sort(list, function(a, b) return a.index() < b.index() end)
                    return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
                end
            end
            return obj.clothing == true
        end
        return false
    end
    _G.getText = function(key) return key end
    -- Vanilla timed actions the patch points wrap; a test calls e.g. ISDisinfect.complete(action).
    _G.ISDisinfect = { complete = function() return true end }
    _G.ISApplyBandage = { complete = function() return true end }
    _G.ISStitch = {
        complete = function(action)
            action.bodyPart.flags.stitched = action.doIt
            return true
        end,
        new = function(_, character, otherPlayer, item, bodyPart, doIt)
            return { character = character, otherPlayer = otherPlayer, item = item, bodyPart = bodyPart, doIt = doIt }
        end,
    }
    _G.ISEatFoodAction = {
        complete = function(action)
            action.eaten = true
            return true
        end,
        isValid = function() return true end,
    }
    _G.Events = {}
    -- An event the listed ones lack, for an add-on's code.
    function game.addEvent(name)
        _G.Events[name] = _G.Events[name] or newEvent()
        return _G.Events[name]
    end
    for _, name in ipairs({ "OnGameBoot", "OnGameStart", "OnServerStarted", "OnTick", "EveryOneMinute",
        "OnClientCommand", "OnServerCommand", "OnCreatePlayer", "OnKeyPressed",
        -- Loot, the radio, the scalpel, wild searches
        "OnPreDistributionMerge", "OnFillContainer", "OnZombieDead", "OnInitGlobalModData", "OnReceiveGlobalModData",
        "OnLoadRadioScripts", "OnEquipPrimary", "OnEquipSecondary", "OnWeaponSwing", "OnCharacterDeath",
        "OnPlayerDeath", "OnFillWorldObjectContextMenu", "OnFillInventoryObjectContextMenu" }) do
        _G.Events[name] = newEvent()
    end

    game.sandbox = _G.SandboxVars.ExtensiveHealthRework
    game.events = _G.Events
    -- Another mod's sandbox options: game.sandboxFor("MyAddon").ScurvyEnabled = false.
    function game.sandboxFor(namespace)
        _G.SandboxVars[namespace] = _G.SandboxVars[namespace] or {}
        return _G.SandboxVars[namespace]
    end


    function game.addPlayer(opts)
        local index = #game.players
        local player = newPlayer(game, index, opts or {})
        game.players[index + 1] = player
        return player
    end

    function game.removePlayer(player)
        for i, p in ipairs(game.players) do
            if p == player then
                table.remove(game.players, i)
                return
            end
        end
    end

    -- Advances game time in one-second ticks' worth of steps (10 ticks per game minute).
    function game.advance(minutes)
        local ticks = math.floor(minutes * 10 + 0.5)
        for _ = 1, ticks do
            game.minutes = game.minutes + 0.1
            game.realMs = game.realMs + 250
            game.events.OnTick.trigger()
        end
    end

    function game.logged(text)
        for _, line in ipairs(game.printed) do
            if line:find(text, 1, true) then
                return true
            end
        end
        return false
    end

    return game
end

return FakeGame
