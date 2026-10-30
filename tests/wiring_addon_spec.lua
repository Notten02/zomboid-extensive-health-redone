-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, need-check-nil, inject-field, missing-fields

-- The add-on extension points end to end in single-player mode (tests/support/fake_game.lua): an add-on's state
-- section saved and synced, its own patch point, bite listener, noise, passive-skill drain, slowed wound and fracture
-- healing, reopened wounds and the healing timers in the facts. What vanilla does with the values needs the game.

insulate("single-player wiring: add-on extension points", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install({ root = "./" })

    _G.ISAddonTarget = { run = function(_, x) return x * 2 end }
    -- Vanilla drinks bit by bit: consumedRatio follows the progress (delta) times the share the action drinks.
    _G.ISDrinkFluidAction = { updateEat = function(action, delta) action.consumedRatio = delta * action.target end }
    _G.ItemTag = { HIDE_UNCOOKED = "HIDE_UNCOOKED", MUFFLE_SNEEZE = "MUFFLE_SNEEZE" }

    local addonOptions = game.sandboxFor("AddonMod")
    addonOptions.Loud = false
    game.addEvent("EveryTenMinutes")

    -- The add-on's shared code, loaded before EHR's server files like in the game.
    local Schema = require("ExtensiveHealthRedone/Core/Schema")
    Schema.registerSection("addonReserves", { defaults = function() return { c = 75 } end })
    local Patches = require("ExtensiveHealthRedone/Game/Patches")
    Patches.define({ name = "addonRun", path = "ISAddonTarget.run", side = "server" })
    local seen = {}
    Patches.on("addonRun", { name = "addon", after = function(results, _, x) seen[#seen + 1] = { x, results[1] } end })
    local Tweaks = require("ExtensiveHealthRedone/Game/ItemTweaks")
    Tweaks.add({ item = "AddonMod.Tablets", property = "UseDelta", value = "0.1", reason = "test" })

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({ levels = { Strength = 5 }, perkXp = { Strength = 520 } })
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Food = require("ExtensiveHealthRedone/Server/Food")
    local Noise = require("ExtensiveHealthRedone/Server/Noise")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    it("saves the add-on section with the player and syncs it like EHR's own", function()
        assert.same({ c = 75, v = 1 }, state().addonReserves)
        Runtime.applyNow(Runtime.attach(player), function(p)
            p.state.addonReserves.c = 40
            p.dirty("addonReserves")
        end)
        Runtime.flushDirty()
        assert.equal(40, Client.section(player, "addonReserves").c)
    end)

    it("knows a section registered after the runtime loaded", function()
        Schema.registerSection("addonLate", { defaults = function() return { n = 1 } end })
        assert.equal(1, state().addonLate.n)
        Runtime.applyNow(Runtime.attach(player), function(p) p.dirty("addonLate") end)
        Runtime.flushDirty()
        assert.equal(1, Client.section(player, "addonLate").n)
    end)

    it("installs the add-on's patch point and calls its listener", function()
        assert.equal(6, ISAddonTarget.run(nil, 3))
        assert.same({ { 3, 6 } }, seen)
        assert.has_error(function() Patches.define({ name = "addonRun", path = "ISAddonTarget.run" }) end)
    end)

    it("lets an add-on follow every sip of a drink, including one stopped part way", function()
        local sips = {}
        Patches.on("drinkFluidUpdateEat", {
            name = "addonSips",
            before = function(action) action.addonBefore = action.consumedRatio end,
            after = function(_, action) sips[#sips + 1] = action.consumedRatio - action.addonBefore end,
        })
        local action = { consumedRatio = 0, target = 0.5 }
        ISDrinkFluidAction.updateEat(action, 0.2)
        ISDrinkFluidAction.updateEat(action, 0.6)
        assert.equal(2, #sips)
        assert.near(0.1, sips[1], 1e-9)
        assert.near(0.2, sips[2], 1e-9)
    end)

    it("reads another mod's sandbox namespace", function()

        local Env = require("ExtensiveHealthRedone/Game/Env")
        assert.is_false(Env.sandbox("AddonMod.Loud", true))
        assert.equal(7, Env.sandbox("AddonMod.Missing", 7))
        assert.is_false(Env.sandbox("DebugMode", true))
    end)

    it("applies the add-on's item tweak at boot", function()
        local changed = {}
        _G.ScriptManager = { instance = { getItem = function(_, fullType)
            return { DoParam = function(_, prop, value) changed[#changed + 1] = fullType .. "." .. prop .. "=" .. value end }
        end } }
        game.events.OnGameBoot.trigger()
        assert.truthy(table.concat(changed, ","):find("AddonMod.Tablets.UseDelta=0.1", 1, true))
        assert.has_error(function() Tweaks.add({ item = "AddonMod.Late", property = "Weight", value = "1",
            reason = "late" }) end)
    end)

    it("passes what was eaten to a bite listener, with EHR's portion, inside a step", function()
        local bites = {}
        Food.onBite({
            name = "addonNutrition",
            describe = function(item) return { fullType = item:getFullType() } end,
            bite = function(p, data, portion)
                bites[#bites + 1] = { data.fullType, portion }
                p.state.addonReserves.c = p.state.addonReserves.c + 10 * portion
            end,
        })
        local item = player.inventory:add("Base.Orange", { food = true })
        function item:getHerbalistType() return nil end
        function item:getType() return "Orange" end
        function item:isRotten() return false end
        function item:isFresh() return true end
        function item:isBurnt() return false end
        function item:isCooked() return false end
        function item:isCookable() return false end
        function item:isbDangerousUncooked() return false end
        function item:hasTag() return false end
        function item:getPoisonPower() return 0 end
        game.float = 0.99
        local before = state().addonReserves.c
        ISEatFoodAction.complete({ character = player, item = item, percentage = 0.5 })

        assert.same({ { "Base.Orange", 0.5 } }, bites)
        assert.equal(before + 5, state().addonReserves.c)
    end)

    it("plays an add-on noise", function()
        Noise.register("addonShout", { male = "AddonShoutM", female = "AddonShoutF", radius = 30, volume = 20,
            audioOption = "AddonMod.Loud" })
        player.worldSounds = {}
        player.sounds = {}
        Runtime.applyNow(Runtime.attach(player), function(p) p.noise("addonShout") end)
        assert.same({}, player.sounds)     -- the add-on's own option muted the voice
        assert.equal(30, player.worldSounds[#player.worldSounds].radius)
        assert.has_error(function() Noise.register("cough", { male = "a", female = "b", radius = 1, volume = 1 }) end)
    end)

    it("drains a passive skill in whole XP and takes a level once the XP falls below it", function()
        Runtime.sim:add({ name = "addonWasting", order = 150, update = function(p)
            p.perks:drain("Strength", "addon:protein", 30)
        end })
        game.advance(60)
        local lost = 520 - player.perkXp.Strength
        assert.truthy(lost >= 28 and lost <= 30, "lost " .. lost)
        assert.equal(4, player.levels.Strength)
    end)

    it("slows a cut and a fracture to the wished share of vanilla's healing", function()
        local hand = player.body:part("Hand_L")
        local arm = player.body:part("ForeArm_L")
        hand.flags.cut = true
        hand.times.cut = 10
        arm.times.fracture = 20
        Runtime.sim:add({ name = "addonSlowHealing", order = 150, update = function(p)
            p.body:woundSpeed("Hand_L", "addon:scurvy", 0.5)
            p.body:fractureSpeed("ForeArm_L", "addon:vitD", 0.25)
        end })
        game.advance(1)
        -- Vanilla heals: the timers drop by 2 between two steps.
        hand.times.cut = hand.times.cut - 2
        arm.times.fracture = arm.times.fracture - 2
        game.advance(1)
        assert.near(9, hand.times.cut, 1e-6)
        assert.near(19.5, arm.times.fracture, 1e-6)
        local facts = require("ExtensiveHealthRedone/Server/Facts").read(player, {})
        assert.near(9, facts.parts.Hand_L.cutTime, 1e-6)
        assert.is_true(facts.parts.ForeArm_L.fracture)
    end)

    it("reopens a wound", function()
        Runtime.applyNow(Runtime.attach(player), function(p) p.body:reopen("Hand_R", "addon:scurvy", "deep") end)
        assert.is_true(player.body:part("Hand_R").flags.deep)
    end)
end)
