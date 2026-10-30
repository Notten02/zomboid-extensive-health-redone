-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla objects passed to the hooks are deliberately partial.
---@diagnostic disable: missing-fields
-- The wiring part replaces a few fake globals for this spec only.
---@diagnostic disable: duplicate-set-field
-- The food-borne disease group: bite and water risks, the risk accumulator, the five diseases' effects, washing, and
-- the server wiring (eating, drinking, washing hands) against tests/support/fake_game.lua.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Risk = require("ExtensiveHealthRedone/Diseases/Food/Risk")
local Washing = require("ExtensiveHealthRedone/Diseases/Food/Washing")
local Data = require("ExtensiveHealthRedone/Diseases/Food/Data")
local Sim = require("support/sim")

local IDS = { "food_poisoning", "gastroenteritis", "trichinosis", "toxin_poisoning", "dysentery" }

local function run(p, minutes, step)
    step = step or 1
    local done = 0
    while done < minutes do
        Engine.step(Sim.step(p), defs, step)
        done = done + step
    end
end

---@return table
local function contract(p, id, opts)
    return Engine.contract(p, defs, id, opts) --[[@as table]]
end

local function food(props)
    local f = { fullType = "Base.Apple", type = "apple", name = "apple", fresh = true, poisonPower = 0 }
    for k, v in pairs(props or {}) do
        f[k] = v
    end
    return f
end

local function risksById(list)
    local byId = {}
    for _, r in ipairs(list) do
        byId[r.id] = r
    end
    return byId
end

describe("food-borne diseases", function()
    describe("definitions", function()
        it("registers the five diseases with their switches, timings and knowledge", function()
            local options = { food_poisoning = "FoodPoisoningEnabled", gastroenteritis = "GastroenteritisEnabled",
                trichinosis = "TrichinosisEnabled", toxin_poisoning = "ToxinPoisoningEnabled",
                dysentery = "DysenteryEnabled" }
            for _, id in ipairs(IDS) do
                assert.truthy(defs[id], id)
                assert.equal(options[id], defs[id].enabledOption)
                assert.equal("DiseaseSpeed", defs[id].speedOption)
                assert.equal(id, defs[id].knowledge)
            end
            assert.is_true(defs.food_poisoning.selfEvident)
            -- The guide's timings.
            assert.same({ 4, 12 }, defs.gastroenteritis.incubation)
            assert.same({ 24, 72 }, defs.gastroenteritis.duration)
            assert.same({ 24, 48 }, defs.trichinosis.incubation)
            assert.same({ 168, 288 }, defs.trichinosis.duration)
            assert.same({ 1, 4 }, defs.toxin_poisoning.incubation)
            assert.same({ 24, 96 }, defs.toxin_poisoning.duration)
        end)

        it("scales the timings by DiseaseSpeed", function()
            local p = Sim.context({ floats = { 0, 1 }, sandbox = { DiseaseSpeed = 2 } })
            local c = contract(p, "toxin_poisoning")
            assert.near(60 / 2, c.left, 1e-9)
            assert.near(96 * 60 / 2, c.duration, 1e-9)
        end)
    end)

    describe("bite risks", function()
        it("rates rotten, burned, stale and raw dangerous food, times portion and multiplier", function()
            local p = Sim.context({ sandbox = { FoodPoisoningChanceMultiplier = 2 } })
            local rotten = risksById(Risk.ofBite(p, food({ rotten = true }), nil, 0.5))
            assert.near(0.70, rotten.food_poisoning.chance, 1e-9)
            assert.equal("rotten", rotten.food_poisoning.reason)

            local plain = Sim.context()
            assert.near(0.05, risksById(Risk.ofBite(plain, food({ burnt = true }), nil, 1)).food_poisoning.chance, 1e-9)
            local raw = risksById(Risk.ofBite(plain, food({ dangerousUncooked = true, fresh = false }), nil, 1))
            assert.near(1 - 0.65 * 0.90, raw.food_poisoning.chance, 1e-9)
            assert.equal("uncooked + stale", raw.food_poisoning.reason)
            assert.same({}, Risk.ofBite(plain, food(), nil, 1))
            assert.same({}, Risk.ofBite(plain, food({ dangerousUncooked = true, cooked = true }), nil, 1))
        end)

        it("treats raw rodents, small game and pork as trichinosis sources, matched by full type", function()
            local p = Sim.context()
            for _, fullType in ipairs({ "Base.DeadRat", "Base.Rabbitmeat", "Base.DeadSquirrel", "Base.PorkChop" }) do
                local r = risksById(Risk.ofBite(p, food({ fullType = fullType, dangerousUncooked = true }), nil, 1))
                assert.near(0.70, r.trichinosis.chance, 1e-9, fullType)
                -- The raw risk of that meat is trichinosis, not food poisoning.
                assert.is_nil(r.food_poisoning, fullType)
            end
            assert.equal("uncooked pork", Risk.ofBite(p, food({ fullType = "Base.Pork" }), nil, 1)[1].reason)
            assert.same({}, Risk.ofBite(p, food({ fullType = "Base.Pork", cooked = true }), nil, 1))
            -- Modded game meat by its item type; preserved meat and v0.9's false positives don't count.
            assert.truthy(risksById(Risk.ofBite(p, food({ fullType = "Mod.BoarMeat", type = "boarmeat" }), nil, 1))
                .trichinosis)
            assert.same({}, Risk.ofBite(p, food({ fullType = "Mod.BearMeatJerky", type = "bearmeatjerky" }), nil, 1))
            assert.same({}, Risk.ofBite(p, food({ fullType = "Base.WaterRationCan", type = "waterrationcan" }), nil, 1))
        end)

        it("rates bloody and dirty hands for gastroenteritis, capped", function()
            local p = Sim.context()
            local r = risksById(Risk.ofBite(p, food(), { blood = 1, dirt = 1 }, 1))
            assert.near(0.23, r.gastroenteritis.chance, 1e-9)
            assert.equal("bloody and dirty hands", r.gastroenteritis.reason)
            assert.same({}, Risk.ofBite(p, food(), { blood = 0.2, dirt = 0.2 }, 1))
            local high = Sim.context({ sandbox = { GastroenteritisChanceMultiplier = 5 } })
            assert.near(1, risksById(Risk.ofBite(high, food(), { blood = 1, dirt = 1 }, 1)).gastroenteritis.chance, 1e-9)
        end)
    end)

    describe("risk accumulator", function()
        it("stacks risky bites until the roll succeeds, and clears on contraction", function()
            local p = Sim.context({ floats = { 0.5, 0.5 } })
            local bite = { { id = "food_poisoning", chance = 0.35, reason = "uncooked" } }
            assert.same({}, Risk.applyBite(p, defs, bite))                -- 0.35 vs 0.5: no
            assert.near(0.35, p.state.exposure.data.food.food_poisoning, 1e-9)
            assert.same({ "food_poisoning" }, Risk.applyBite(p, defs, bite)) -- 0.70 vs 0.5: yes
            assert.is_nil(p.state.exposure.data.food.food_poisoning)
            assert.truthy(p.state.conditions.active.food_poisoning)
        end)

        it("is guaranteed from 0.80, and skips disabled or active diseases", function()
            local p = Sim.context({ float = 0.999 })
            assert.same({ "food_poisoning" },
                Risk.applyBite(p, defs, { { id = "food_poisoning", chance = 0.8, reason = "rotten" } }))
            local off = Sim.context({ float = 0, sandbox = { DiseaseEnabled = false } })
            assert.same({}, Risk.applyBite(off, defs, { { id = "food_poisoning", chance = 0.5, reason = "x" } }))
            assert.is_nil(off.state.exposure.data.food.food_poisoning)
        end)

        it("decays by 0.20 per hour and makes the character queasy before any disease", function()
            local p = Sim.context()
            p.state.exposure.data.food = { food_poisoning = 0.4 }
            Risk.update(p, 60)
            assert.near(0.2, p.state.exposure.data.food.food_poisoning, 1e-9)
            assert.is_true(Sim.resolve(p, "SICKNESS", 0) > 0)
            Risk.update(Sim.step(p), 60)
            assert.is_nil(p.state.exposure.data.food.food_poisoning)
        end)
    end)

    describe("toxin poisoning", function()
        it("always poisons, by source severity, and announces the bitter taste", function()
            local p = Sim.context({ float = 0.999 })
            local c = Risk.applyToxin(p, defs, 3, "mushroom", 1) --[[@as table]]
            assert.truthy(c)
            assert.equal("mushroom", c.data.toxinType)
            assert.near(0.96, c.severity, 1e-9)
            assert.is_true(Sim.said(p, "UI_EHR_Text_ThatTastedWrong"))
            assert.is_nil(Risk.applyToxin(Sim.context(), defs, 0, "berry", 1))
        end)

        it("raises the severity of an active poisoning instead of starting another", function()
            local p = Sim.context()
            local c = Risk.applyToxin(p, defs, 1, "berry", 1) --[[@as table]]
            local first = c.severity
            Risk.applyToxin(p, defs, 4, "mushroom", 1)
            assert.is_true(c.severity > first)
            assert.equal(c, p.state.conditions.active.toxin_poisoning)
        end)

        it("blurs vision in recurring stage-3 episodes, the first at once", function()
            local p = Sim.context()
            local c = contract(p, "toxin_poisoning", { stage = 3 })
            c.left = 1e9
            run(p, 1)
            assert.equal(1, p.fx.values.blur)
            run(p, 10)                    -- episodes last 10-20 minutes (rng.int gives the low end)
            assert.equal(0, p.fx.values.blur)
            run(p, 26)                    -- next one 25-45 minutes later
            assert.equal(1, p.fx.values.blur)
        end)

        it("drains health at mushroom stage 3 unless treated, and not for other toxins", function()
            local p = Sim.context()
            local c = contract(p, "toxin_poisoning", { stage = 3, severity = 1 })
            c.left, c.data.toxinType = 1e9, "mushroom"
            run(p, 21, 21)
            assert.near(1.55, p.body.damages[1].hp, 1e-9)
            assert.equal(0, p.body.heal.Hand_L)
            local berry = Sim.context()
            local b = contract(berry, "toxin_poisoning", { stage = 3 })
            b.left, b.data.toxinType = 1e9, "berry"
            run(berry, 21, 21)
            assert.equal(0, #berry.body.damages)
        end)
    end)

    describe("effects", function()
        it("food poisoning vomits with a line and a noise, and drains endurance", function()
            local p = Sim.context({ float = 0 })
            local c = contract(p, "food_poisoning", { stage = 3 })
            c.left = 1e9
            run(p, 1)
            assert.equal("vomit", p.noises[1][1])
            assert.is_true(Sim.resolve(p, "ENDURANCE", 1) < 1)
            assert.is_true(Sim.resolve(p, "SICKNESS", 0) > 0)
        end)

        it("gastroenteritis keeps the stage-3 nausea floor", function()
            local p = Sim.context()
            contract(p, "gastroenteritis", { stage = 3, severity = 0.1 }).left = 1e9
            run(p, 120)
            assert.near(0.56, Sim.resolve(p, "SICKNESS", 0.56), 1e-9)
            assert.is_true(Sim.resolve(p, "SICKNESS", 0.3) > 0.3)
        end)

        it("trichinosis stage 3 aches every muscle, slows, and drains health to death untreated", function()
            local p = Sim.context()
            local c = contract(p, "trichinosis", { stage = 3, severity = 1 })
            c.left = 1e9
            p.facts.health = 10
            run(p, 15, 15)
            assert.near(40, p.body.pains.UpperLeg_L.trichinosis, 1e-9)
            assert.equal(0.8, p.fx.values.speed)
            assert.near(3.3, p.body.damages[1].hp, 1e-9)

            local treated = Sim.context({ treatment = { curing = { trichinosis = true } } })
            contract(treated, "trichinosis", { stage = 3 }).left = 1e9
            run(treated, 15, 15)
            assert.equal(0, #treated.body.damages)
        end)

        it("dysentery keeps its thirst cap even with relief and bleeds down to a floor", function()
            local p = Sim.context({ treatment = { relief = { ["dysentery.diarrhea"] = 0.85 } } })
            contract(p, "dysentery", { stage = 2 }).left = 1e9
            run(p, 1)
            assert.near(0.5, Sim.resolve(p, "THIRST", 0.5), 1e-9)   -- capped at 0.5, never pushed above
            assert.near(0.6, Sim.resolve(p, "THIRST", 0.6), 1e-9)   -- and never lowered
            assert.near(18, p.body.pains.Torso_Lower.dysentery, 1e-9)
            assert.equal(1, p.fx.values.speed)

            local bleeding = Sim.context()
            contract(bleeding, "dysentery", { stage = 2 }).left = 1e9
            bleeding.state.blood.volume = 4551
            run(bleeding, 60)
            assert.equal(4550, bleeding.state.blood.volume)
        end)

        it("dysentery slows only at stage 3, and its pain ends with the disease", function()
            local p = Sim.context()
            contract(p, "dysentery", { stage = 3 }).left = 1e9
            run(p, 1)
            assert.equal(0.7, p.fx.values.speed)
            Engine.cure(p, defs, "dysentery")
            run(p, 1)
            assert.is_nil(p.body.pains.Torso_Lower)
            assert.equal(1, p.fx.values.speed)
        end)

        it("says it is over on natural recovery only", function()
            local p = Sim.context()
            contract(p, "food_poisoning", { stage = 4 }).left = 1
            run(p, 2)
            assert.is_true(Sim.said(p, Data.RECOVERED_LINE))
            local cured = Sim.context()
            contract(cured, "food_poisoning", { stage = 4 })
            Engine.cure(cured, defs, "food_poisoning")
            assert.is_false(Sim.said(cured, Data.RECOVERED_LINE))
        end)
    end)

    describe("water", function()
        it("classifies world water sources", function()
            assert.equal("toilet", Risk.waterSource({ customName = "toilet", tainted = true }))
            assert.equal("river", Risk.waterSource({ sprite = "blends_natural_02_5", tainted = true }))
            assert.equal("rainCollector", Risk.waterSource({ rainCatcher = true, tainted = true }))
            assert.equal("rainCollector", Risk.waterSource({ sprite = "carpentry_02_54" }))
            assert.equal("tainted", Risk.waterSource({ name = "well", tainted = true }))
            assert.equal("tap", Risk.waterSource({ customName = "sink" }))
        end)

        it("rolls dysentery once per drink by source, x the multiplier; tap water is safe", function()
            local p = Sim.context({ floats = { 0.49 } })
            assert.truthy(Risk.applyWater(p, defs, "toilet"))
            assert.equal("toilet", p.state.conditions.active.dysentery.source)
            assert.is_nil(Risk.applyWater(Sim.context({ float = 0 }), defs, "tap"))
            assert.is_nil(Risk.applyWater(Sim.context({ floats = { 0.16 } }), defs, "river"))
            assert.truthy(Risk.applyWater(Sim.context({ floats = { 0.29 }, sandbox = { DysenteryChanceMultiplier = 2 } }),
                defs, "river"))
        end)
    end)

    describe("washing", function()
        it("plans the dirty hand and arm parts, with less water and time with soap", function()
            assert.is_nil(Washing.plan({ Hand_L = { blood = 0, dirt = 0 } }, false))
            local soil = { Hand_L = { blood = 0.5, dirt = 0 }, Hand_R = { blood = 0, dirt = 0.3 } }
            local two = Washing.plan(soil, false) --[[@as table]]
            assert.same({ "Hand_L", "Hand_R" }, two.parts)
            assert.is_true(two.bloody)
            assert.near(0.5, two.water, 1e-9)
            assert.equal(Washing.MIN_TICKS, two.ticks)
            for _, part in ipairs(Washing.PARTS) do
                soil[part] = { blood = 0, dirt = 1 }
            end
            local plain = Washing.plan(soil, false) --[[@as table]]
            local soap = Washing.plan(soil, true) --[[@as table]]
            assert.is_false(plain.bloody)
            assert.near(1.5, plain.water, 1e-9)
            assert.near(0.9, soap.water, 1e-9)
            assert.is_true(soap.ticks < plain.ticks)
        end)
    end)
end)

insulate("single-player wiring: food-borne diseases", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- Fakes only this spec needs.
    _G.ItemTag = { HIDE_UNCOOKED = "hideuncooked" }
    _G.Fluid = { TaintedWater = "TaintedWater" }
    local visualsSent = 0
    _G.sendHumanVisual = function() visualsSent = visualsSent + 1 end
    local squares = {}
    local cell = _G.getCell()
    _G.getCell = function()
        cell.getGridSquare = function(_, x, y, z) return squares[x .. "," .. y .. "," .. z] end
        return cell
    end
    _G.ISEatFoodAction.serverStop = function() end
    _G.ISDrinkFluidAction = {
        new = function(_, character, item) return { character = character, item = item,
            fluidContainer = item.fluid } end,
        complete = function() return true end,
    }
    _G.ISTakeWaterAction = { complete = function() return true end }

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    -- Visuals: [part name] = { blood, dirt }.
    local soil = {}
    function player:getHumanVisual()
        return {
            getBlood = function(_, part) return (soil[part.name] or {}).blood or 0 end,
            getDirt = function(_, part) return (soil[part.name] or {}).dirt or 0 end,
            setBlood = function(_, part, v) soil[part.name] = soil[part.name] or {}; soil[part.name].blood = v end,
            setDirt = function(_, part, v) soil[part.name] = soil[part.name] or {}; soil[part.name].dirt = v end,
        }
    end
    function player:resetModelNextFrame() end
    function player.inventory:contains(item)
        return item.container == self
    end
    function player.inventory:getSoapList()
        return { size = function() return 0 end }
    end

    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Server/Food")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local said = {}
    Client.on("say", function(args) said[#said + 1] = args.key end)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    local function foodItem(props)
        local item = player.inventory:add(props.fullType or "Base.Apple", { food = true })
        local p = props
        function item:getHerbalistType() return p.herbalist end
        function item:getDisplayName() return p.name or "Food" end
        function item:getType() return (p.fullType or "Base.Apple"):match("%.(.+)$") end
        function item:isRotten() return p.rotten == true end
        function item:isFresh() return p.fresh ~= false end
        function item:isBurnt() return false end
        function item:isCooked() return p.cooked == true end
        function item:isCookable() return true end
        function item:isbDangerousUncooked() return p.dangerousUncooked == true end
        function item:hasTag() return false end
        function item:getPoisonPower() return p.poison or 0 end
        function item:getHungerChange() return -0.2 end
        return item
    end

    local function clear()
        state().conditions.active = {}
        state().exposure.data.food = nil
    end

    it("rolls food poisoning when rotten food is eaten", function()
        game.float = 0
        ISEatFoodAction.complete({ character = player, item = foodItem({ rotten = true }), percentage = 1 })
        assert.truthy(state().conditions.active.food_poisoning)
        clear()
    end)

    it("poisons on a toxic mushroom and says so", function()
        ISEatFoodAction.complete({ character = player, item = foodItem({ name = "Mushroom", poison = 2 }) })
        assert.equal("mushroom", state().conditions.active.toxin_poisoning.data.toxinType)
        assert.equal("UI_EHR_Text_ThatTastedWrong", said[#said])
        clear()
    end)

    it("rolls gastroenteritis from dirty hands at the meal", function()
        game.float = 0
        soil.Hand_L, soil.Hand_R = { blood = 1, dirt = 1 }, { blood = 1, dirt = 1 }
        ISEatFoodAction.complete({ character = player, item = foodItem({}), percentage = 1 })
        assert.truthy(state().conditions.active.gastroenteritis)
        soil.Hand_L, soil.Hand_R = nil, nil
        clear()
    end)

    it("rolls the partial bite of a cancelled meal", function()
        game.float = 0
        local action = { character = player, item = foodItem({ rotten = true }), percentage = 0.5,
            getJobDelta = function() return 0.5 end }
        ISEatFoodAction.serverStop(action)
        assert.truthy(state().conditions.active.food_poisoning)
        clear()
    end)

    it("rolls dysentery for tainted water from a container, read when the action is made", function()
        game.float = 0
        local fluid = { contains = function(_, f) return f == "TaintedWater" end }
        local bottle = player.inventory:add("Base.WaterBottle")
        bottle.fluid = fluid
        local action = ISDrinkFluidAction:new(player, bottle, 1)
        fluid.contains = function() return false end     -- drunk empty by the end
        ISDrinkFluidAction.complete(action)
        assert.equal("tainted", state().conditions.active.dysentery.source)
        clear()
    end)

    it("rolls dysentery by world source, and not when filling a container", function()
        game.float = 0
        local toilet = {
            getProperties = function() return { get = function() return "Toilet" end } end,
            getSprite = function() return { getName = function() return "fixtures_bathroom_01_0" end } end,
            getName = function() return "Toilet" end,
            getFluidContainer = function() return { getRainCatcher = function() return 0 end } end,
            isTaintedWater = function() return true end,
        }
        ISTakeWaterAction.complete({ character = player, item = { }, waterObject = toilet })
        assert.is_nil(state().conditions.active.dysentery)
        ISTakeWaterAction.complete({ character = player, waterObject = toilet })
        assert.equal("toilet", state().conditions.active.dysentery.source)
        clear()
    end)

    it("washes hands at a sink in reach, using its water", function()
        local sq = FakeGame.newSquare(101, 100, 0)
        squares["101,100,0"] = sq
        local used = 0
        sq.objects[1] = {
            getFluidAmount = function() return 5 end,
            useFluid = function(_, amount) used = used + amount; return amount end,
            transmitModData = function() end,
        }
        soil.Hand_L = { blood = 0.6, dirt = 0.4 }
        -- What EHRWashHandsAction's complete() runs (Actions/WashHands); a client can't send it.
        local Authority = require("ExtensiveHealthRedone/Actions/Authority")
        Client.send(player, "food.washHands", { x = 101, y = 100, z = 0 })
        assert.equal(0.6, soil.Hand_L.blood)
        assert.is_true(Authority.run(player, "food.washHands", { x = 101, y = 100, z = 0 }))
        assert.same({ blood = 0, dirt = 0 }, soil.Hand_L)
        assert.near(0.25, used, 1e-9)
        assert.equal(1, visualsSent)
        assert.equal("UI_EHR_Text_WashesHandsMuchBetter", said[#said])

        local far = FakeGame.newSquare(110, 100, 0)
        squares["110,100,0"] = far
        far.objects[1] = sq.objects[1]
        soil.Hand_R = { blood = 1, dirt = 0 }
        Authority.run(player, "food.washHands", { x = 110, y = 100, z = 0 })
        assert.equal(1, soil.Hand_R.blood)
    end)
end)
