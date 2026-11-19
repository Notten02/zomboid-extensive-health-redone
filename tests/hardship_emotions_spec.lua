-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions and items are deliberately partial.
---@diagnostic disable: missing-fields
-- The stand-in for Emotions replaces our EHR functions, as Emotions does.
---@diagnostic disable: duplicate-set-field
-- Hardship: Emotions beside us: the pure rules first (corpse risk factors, the Knox reveal threshold), then the server
-- wiring against the fake game with a stand-in for Emotions that wraps the EHR functions the way its
-- server/HardshipEmotions/HE_Hooks.lua does, and a stand-in for its public API (registerStrain, registerBlock and
-- addDizzy, as in HE_Traits.lua and HE_Engine.lua; checked against 2.22.16).
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Exposure = require("ExtensiveHealthRedone/Diseases/Corpse/Exposure")
local Knox = require("ExtensiveHealthRedone/Diseases/Knox/Knox")
local Importer = require("ExtensiveHealthRedone/Core/Importer")
local Legacy = require("ExtensiveHealthRedone/Data/LegacyEHR")
local Sim = require("support/sim")

local function corpses(p, t)
    p.facts.corpses = { fresh = t.fresh or 0, decomposing = t.decomposing or 0, rotten = t.rotten or 0,
        env = t.env or 1, protection = 0, sealed = false }
end

describe("corpse risk factors (facts.corpseRisk)", function()
    it("scale the corpse meter's build-up", function()
        local p = Sim.context()
        corpses(p, { rotten = 5, env = 1.5 })
        p.facts.corpseRisk = { corpse = 2, spores = 1, chance = {} }
        Exposure.update(Sim.step(p), 60, defs)
        assert.near(75, p.state.exposure.corpse, 1e-6)        -- 5 rotten x 5/h x 1.5 x 2
    end)

    it("scale the spore meter's build-up", function()
        local plain, risky = Sim.context(), Sim.context()
        for _, p in ipairs({ plain, risky }) do
            p.facts.env.wetness = 0.5
            corpses(p, { rotten = 2 })
        end
        risky.facts.corpseRisk = { corpse = 1, spores = 1.5, chance = {} }
        Exposure.update(Sim.step(plain), 60, defs)
        Exposure.update(Sim.step(risky), 60, defs)
        assert.is_true(plain.state.exposure.spores > 0)
        assert.near(plain.state.exposure.spores * 1.5, risky.state.exposure.spores, 1e-6)
    end)

    it("raise the hourly contraction roll, at most to certain", function()
        local function caught(factor)
            local p = Sim.context()
            p.state.exposure.corpse = 86
            p.state.exposure.data.corpse = { minutes = 60, sinceRoll = 60, sinceSmell = 0, sporeMinutes = 0,
                sporeSinceRoll = 0 }
            corpses(p, { fresh = 1 })
            p.facts.corpseRisk = factor and { chance = { corpse_sickness = factor } } or nil
            p.rng = Sim.rng({ float = 0.5 })
            Exposure.update(Sim.step(p), 1, defs)
            return p.state.conditions.active.corpse_sickness ~= nil
        end
        assert.is_false(caught(nil))        -- about 0.32 < 0.5
        assert.is_true(caught(2))           -- about 0.64
        assert.is_true(caught(100))         -- capped at 1
    end)

    it("are 1 without the facts", function()
        local p = Sim.context()
        corpses(p, { rotten = 5, env = 1.5 })
        Exposure.update(Sim.step(p), 60, defs)
        assert.near(37.5, p.state.exposure.corpse, 1e-6)
    end)
end)

describe("Knox reveal threshold", function()
    it("shows an infection at once without one", function()
        assert.is_true(Knox.revealed({ infected = true, level = 0.01 }))
    end)

    it("holds the infection back until progress reaches it", function()
        assert.is_false(Knox.revealed({ infected = true, level = 0.29, revealAt = 0.3 }))
        assert.is_true(Knox.revealed({ infected = true, level = 0.3, revealAt = 0.3 }))
        assert.is_true(Knox.revealed({ infected = true, level = 0.1, timerProgress = 0.4, revealAt = 0.3 }))
    end)
end)

describe("the importer and our mirror", function()
    it("does not take the mirror for the original mod's data", function()
        local modData = {
            EHR_Blood = { [Legacy.MIRROR_FLAG] = true, currentVolume = 4000, maxVolume = 5000 },
            EHR_Disease = { [Legacy.MIRROR_FLAG] = true, active = {} },
        }
        assert.is_false(Importer.hasOldData(modData))
        assert.equal(0, Importer.removeOldKeys(modData))
        assert.truthy(modData.EHR_Blood)
    end)

    it("still finds real old data beside it", function()
        local modData = {
            EHR_Disease = { [Legacy.MIRROR_FLAG] = true, active = {} },
            EHR_Immunity = { score = 70 },
        }
        assert.same({ "EHR_Immunity" }, Importer.oldKeys(modData))
    end)
end)

-- Hardship: Emotions' classification of an EHR drug (HE_Hooks.lua, ehrKind), as it reads our tables.
local function ehrKind(fullType)
    local M = EHR and EHR.Medication
    if not M or not fullType then return nil end
    if string.find(fullType, "Epinephrine", 1, true) then return "epinephrine" end
    local data = M.Database and M.Database[fullType]
    local cat = data and data.displayName and M.DrugCategories and M.DrugCategories[data.displayName]
    if cat == "stimulant" then
        if fullType == "Base.PillsVitamins" or data.displayName == "Caffeine Pills" then return "caffeine" end
        return "stimulant"
    elseif cat == "epinephrine" then return "epinephrine"
    elseif cat == "beta blocker" then return "beta"
    elseif cat == "sleep aid" then return "sed:sleep"
    elseif cat == "antipsychotic" then return "sed:antipsychotic"
    elseif cat == "muscle relaxant" then return "sed:relaxant"
    elseif cat == "painkiller" then return "sed:painkiller"
    end
    return nil
end

-- A stand-in for Emotions' installEHR / installEHRCorpses: the same wrappers, recording what reached them.
local function installFakeEmotions(vulnerability)
    local seen = { doses = {} }
    local M, CS, D = EHR.Medication, EHR.CorpseSickness, EHR.Disease
    local use = M.UseConsumedMedication
    M.UseConsumedMedication = function(player, fullType)
        local result = use(player, fullType)
        if result then
            seen.doses[#seen.doses + 1] = { player = player, fullType = fullType, kind = ehrKind(fullType) }
        end
        return result
    end
    local env, fungal, try = CS.GetEnvironmentMultiplier, CS.GetFungalEnvironment, D.TryContract
    CS.GetEnvironmentMultiplier = function(player) return env(player) * vulnerability.value end
    CS.GetFungalEnvironment = function(player)
        local mult, risk, reason = fungal(player)
        return mult * vulnerability.value, risk, reason
    end
    D.TryContract = function(player, id, chance)
        if id == "corpse_sickness" or id == "cadaveric_aspergillosis" then
            chance = math.min(1, chance * vulnerability.value)
        end
        return try(player, id, chance)
    end
    return seen
end

-- A stand-in for Emotions' public API (the HardshipEmotions global): its registries keyed by provider id, and the
-- dizziness reports. Emotions' shared files load before any server file, so tests set it before requiring Main.
local function installFakeApi(without)
    local api = { strain = {}, block = {}, dizzy = {} }
    local HE = {}
    if without ~= "registerStrain" then
        HE.registerStrain = function(id, fn) api.strain[id] = fn return true end
    end
    if without ~= "registerBlock" then
        HE.registerBlock = function(id, fn) api.block[id] = fn return true end
    end
    HE.addDizzy = function(player, minutes, level)
        api.dizzy[#api.dizzy + 1] = { player = player, minutes = minutes, level = level }
    end
    _G.HardshipEmotions = HE
    return api
end

local function body(ageHours, game)
    return {
        isSkeleton = function() return false end,
        isAnimal = function() return false end,
        getDeathTime = function() return game.minutes / 60 - ageHours end,
    }
end

insulate("single-player wiring: Hardship: Emotions on", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.mods.HardshipEmotions = true
    _G.ISTakePillAction = { complete = function() return true end }
    local api = installFakeApi()
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
    local MedData = require("ExtensiveHealthRedone/Medication/Data")
    local ServerEmotions = require("ExtensiveHealthRedone/Server/HardshipEmotions")
    local SideEffects = require("ExtensiveHealthRedone/Medication/SideEffects")
    game.events.OnGameStart.trigger()
    local vulnerability = { value = 1 }
    local seen = installFakeEmotions(vulnerability)
    game.advance(2)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    local function key()
        return Runtime.attach(player)
    end

    it("sets a global EHR table of ours, once", function()
        assert.is_true(EHR.Redone)
        local mine = EHR
        game.events.OnGameStart.trigger()
        game.events.OnServerStarted.trigger()
        assert.equal(mine, EHR)
    end)

    it("names our drugs so Emotions classifies them like the original's", function()
        assert.equal("caffeine", ehrKind("Base.PillsVitamins"))
        assert.equal("beta", ehrKind("Base.PillsBeta"))
        assert.equal("sed:painkiller", ehrKind("Base.Pills"))
        assert.equal("sed:sleep", ehrKind("Base.PillsSleepingTablets"))
        assert.is_nil(ehrKind("Base.Antibiotics"))
        for fullType, med in pairs(MedData.byType) do
            if med.category == "stimulant" and fullType ~= "Base.PillsVitamins" then
                assert.equal("stimulant", ehrKind(fullType), fullType)
            elseif med.category == "muscleRelaxant" then
                assert.equal("sed:relaxant", ehrKind(fullType), fullType)
            elseif med.category == "antipsychotic" then
                assert.equal("sed:antipsychotic", ehrKind(fullType), fullType)
            elseif med.category == "epinephrine" then
                assert.equal("epinephrine", ehrKind(fullType), fullType)
            end
        end
    end)

    it("reports a dose that counted to Emotions, for the patient", function()
        local pills = player.inventory:add("Base.PillsBeta")
        ISTakePillAction.complete({ character = player, item = pills })
        local last = seen.doses[#seen.doses]
        assert.equal(player, last.player)
        assert.equal("Base.PillsBeta", last.fullType)
        assert.equal("beta", last.kind)
    end)

    it("does not report a wasted dose", function()
        local before = #seen.doses
        ISTakePillAction.complete({ character = player, item = player.inventory:add("Base.PillsVitamins") })
        ISTakePillAction.complete({ character = player, item = player.inventory:add("Base.PillsVitamins") })
        assert.equal(before + 1, #seen.doses)       -- the second caffeine dose is too early: wasted
    end)

    it("keeps the original's blood and disease modData up to date", function()
        Runtime.applyNow(key(), function(p)
            Engine.contract(p, defs, "concussion", { severity = 0.65 })
        end)
        state().blood.volume = 3900
        game.advance(2)
        local md = player.modData
        assert.near(state().blood.volume, md.EHR_Blood.currentVolume, 2)
        assert.is_true(md.EHR_Blood.currentVolume < 3950)
        assert.equal(state().blood.max, md.EHR_Blood.maxVolume)
        assert.equal(3, md.EHR_Disease.active.concussion.stage)
        assert.near(0.65, md.EHR_Disease.active.concussion.severity, 1e-9)
        assert.is_false(Importer.hasOldData(md))
    end)

    it("drops a condition from the mirror once it ends", function()
        Runtime.applyNow(key(), function(p)
            Engine.cure(p, defs, "concussion", "cured")
        end)
        game.advance(2)
        assert.is_nil(player.modData.EHR_Disease.active.concussion)
    end)

    it("asks Emotions for its corpse factors while corpses are around", function()
        vulnerability.value = 1.5
        local risk = ServerEmotions.corpseRisk(player)
        assert.near(1.5, risk.corpse, 1e-9)
        assert.near(1.5, risk.spores, 1e-9)
        assert.near(1.5, risk.chance.corpse_sickness, 1e-9)
        assert.near(1.5, risk.chance.cadaveric_aspergillosis, 1e-9)
        -- 5 rotten corpses outdoors give 25 points an hour, 12.5 in half an hour; with Emotions' 1.5 that is 18.75,
        -- less the up to 5 minutes before the next corpse scan sees them (at least 15.6).
        state().exposure.corpse = 0
        player.square.deadBodies = { body(50, game), body(50, game), body(50, game), body(50, game), body(50, game) }
        game.advance(30)
        assert.is_true(state().exposure.corpse > 14, tostring(state().exposure.corpse))
        player.square.deadBodies = {}
        vulnerability.value = 1
    end)

    it("keeps an early Knox infection off the displays until 30 %", function()
        player.body.knox = { infected = true, time = game.minutes / 60 - 1, duration = 60 }
        player.body:part("Hand_L").knox = true
        player.stats.ZOMBIE_INFECTION = 10
        game.advance(2)
        assert.is_nil(state().conditions.active.knox_infection)
        player.stats.ZOMBIE_INFECTION = 35
        game.advance(2)
        assert.truthy(state().conditions.active.knox_infection)
        player.body.knox = { infected = false, time = -1, duration = -1 }
        player.body:part("Hand_L").knox = false
        player.stats.ZOMBIE_INFECTION = 0
        game.advance(2)
        assert.is_nil(state().conditions.active.knox_infection)
    end)

    local function strain()
        return api.strain.ExtensiveHealthRedone(player)
    end

    local function focusBlocked()
        return api.block.ExtensiveHealthRedone(player, "focus")
    end

    it("registers a strain provider and a focus blocker with Emotions' API, once", function()
        assert.is_function(api.strain.ExtensiveHealthRedone)
        assert.is_function(api.block.ExtensiveHealthRedone)
        local provider = api.strain.ExtensiveHealthRedone
        game.events.OnGameStart.trigger()
        assert.equal(provider, api.strain.ExtensiveHealthRedone)
    end)

    it("reports strain from the medical alert level", function()
        assert.equal(0, strain())
        assert.is_false(focusBlocked())
        Runtime.applyNow(key(), function(p)
            Engine.contract(p, defs, "concussion", {})        -- starts at stage 3
        end)
        assert.equal(ServerEmotions.STRAIN[3], strain())
        assert.is_true(focusBlocked())
        Runtime.applyNow(key(), function(p)
            Engine.cure(p, defs, "concussion", "cured")
        end)
        assert.equal(0, strain())
        assert.is_false(focusBlocked())
    end)

    it("counts the new diseases the original never had", function()
        Runtime.applyNow(key(), function(p)
            Engine.contract(p, defs, "trench_foot", { stage = 2 })
        end)
        assert.equal(ServerEmotions.STRAIN[2], strain())
        assert.is_false(focusBlocked())                    -- only from level 3
        Runtime.applyNow(key(), function(p)
            Engine.cure(p, defs, "trench_foot", "cured")
        end)
    end)

    it("blocks focus only, never another feeling", function()
        Runtime.applyNow(key(), function(p)
            Engine.contract(p, defs, "concussion", {})
        end)
        assert.is_false(api.block.ExtensiveHealthRedone(player, "something"))
        Runtime.applyNow(key(), function(p)
            Engine.cure(p, defs, "concussion", "cured")
        end)
    end)

    it("reports dizziness every minute our vision blur lasts, and blocks focus meanwhile", function()
        local before, strainBefore = #api.dizzy, strain()
        Runtime.applyNow(key(), function(p)
            SideEffects.start(p, "dizziness")              -- one blur episode, 0.6
        end)
        game.advance(3)
        assert.is_true(#api.dizzy > before)
        local last = api.dizzy[#api.dizzy]
        assert.equal(player, last.player)
        assert.equal(ServerEmotions.DIZZY_MINUTES, last.minutes)
        assert.equal(2, last.level)                        -- 0.6: strong
        assert.is_true(focusBlocked())
        assert.equal(strainBefore, strain())               -- a side effect is not illness
        game.advance(30)                                   -- the episode is over
        local after = #api.dizzy
        game.advance(3)
        assert.equal(after, #api.dizzy)
    end)

    it("stops when IntegrateEHR is switched off, and clears the mirror", function()
        _G.SandboxVars.HardshipEmotions = { IntegrateEHR = false }
        assert.is_nil(strain())
        assert.is_false(focusBlocked())
        local before = #seen.doses
        ISTakePillAction.complete({ character = player, item = player.inventory:add("Base.PillsSleepingTablets") })
        assert.equal(before, #seen.doses)
        game.advance(2)
        assert.is_nil(player.modData.EHR_Blood)
        assert.is_nil(player.modData.EHR_Disease)
        _G.SandboxVars.HardshipEmotions = nil
    end)
end)

insulate("single-player wiring: Hardship: Emotions with its Knox option off", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.mods.HardshipEmotions = true
    _G.SandboxVars.HardshipEmotions = { EHRHideKnox = false }
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("shows a Knox infection at once", function()
        player.body.knox = { infected = true, time = game.minutes / 60 - 1, duration = 60 }
        player.body:part("Hand_L").knox = true
        player.stats.ZOMBIE_INFECTION = 10
        game.advance(2)
        assert.truthy(player.modData.ExtensiveHealthRedone.conditions.active.knox_infection)
    end)
end)

insulate("single-player wiring: Hardship: Emotions off", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("makes no EHR global and writes nothing in the original's shape", function()
        assert.is_nil(EHR)
        assert.is_nil(player.modData.EHR_Blood)
        assert.is_nil(player.modData.EHR_Disease)
    end)

    it("shows a Knox infection at once", function()
        player.body.knox = { infected = true, time = game.minutes / 60 - 1, duration = 60 }
        player.body:part("Hand_L").knox = true
        player.stats.ZOMBIE_INFECTION = 10
        game.advance(2)
        assert.truthy(player.modData.ExtensiveHealthRedone.conditions.active.knox_infection)
    end)
end)

insulate("single-player wiring: a global EHR we didn't make", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.mods.HardshipEmotions = true
    local theirs = { Medication = {} }
    _G.EHR = theirs
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("is left alone, and nothing is mirrored", function()
        assert.equal(theirs, EHR)
        assert.is_true(game.logged("a global EHR table already exists"))
        assert.is_nil(player.modData.EHR_Blood)
    end)
end)

insulate("single-player wiring: an Emotions version without the strain API", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.mods.HardshipEmotions = true
    local api = installFakeApi("registerStrain")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("skips that tie with a warning and keeps the others", function()
        assert.is_true(game.logged("has no registerStrain; the strain tie is off"))
        assert.is_function(api.block.ExtensiveHealthRedone)
        assert.truthy(player.modData.EHR_Blood)
    end)
end)
