-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- state.meds.overdose is false or a record; the tests read it after an overdose.
---@diagnostic disable: undefined-field
-- Medication (Phase 5): the database, dose courses, relief, overdose, timed effects, side effects, interactions and
-- First Aid XP, as pure rules on a test context (tests/support/sim.lua).
local Data = require("ExtensiveHealthRedone/Medication/Data")
local Doses = require("ExtensiveHealthRedone/Medication/Doses")
local Provider = require("ExtensiveHealthRedone/Medication/Provider")
local System = require("ExtensiveHealthRedone/Medication/System")
local Effects = require("ExtensiveHealthRedone/Medication/Effects")
local SideEffects = require("ExtensiveHealthRedone/Medication/SideEffects")
local Interactions = require("ExtensiveHealthRedone/Medication/Interactions")
local Overdose = require("ExtensiveHealthRedone/Medication/Overdose")
local XpData = require("ExtensiveHealthRedone/Data/Xp")
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Sim = require("support/sim")

local MOD = "Contents/mods/ExtensiveHealthRedone/42/media/"

local function med(fullType)
    return assert(Data.byType[fullType], fullType)
end

-- A context with the real provider over its own state.
local function context(opts)
    local p = Sim.context(opts)
    p.treatment = Provider.new(p.state)
    p.facts.norm = { THIRST = 0.2 }
    return p
end

local function step(p, minutes)
    for _ = 1, minutes or 1 do
        Sim.step(p)
        p.treatment = Provider.new(p.state)
        System.update(p, 1, defs)
    end
end

local function infect(p, id, stage)
    p.state.conditions.active[id] = { stage = stage or 2, left = 1e6, len = {}, duration = 0, extra = 0,
        severity = 1, data = {} }
end

local function take(p, fullType, opts)
    return Doses.take(p, defs, med(fullType), opts)
end

describe("medication database", function()
    local function readKeys()
        local f = assert(io.open(MOD .. "lua/shared/Translate/EN/UI.json"))
        local text = f:read("*a")
        f:close()
        local keys = {}
        for key in text:gmatch('"([%w_]+)"%s*:') do
            keys[key] = true
        end
        return keys
    end
    local keys = readKeys()

    local function scriptItems()
        local items = {}
        for _, file in ipairs({ "EHR_Items.txt", "EHR_HomemadeSupplies.txt" }) do
            local f = assert(io.open(MOD .. "scripts/" .. file))
            for name in f:read("*a"):gmatch("item%s+([%w_]+)") do
                items["ExtensiveHealth." .. name] = true
            end
            f:close()
        end
        return items
    end

    it("names only items that exist, and every key it uses is translated", function()
        local items = scriptItems()
        for fullType, m in pairs(Data.byType) do
            if fullType:find("^ExtensiveHealth%.") then
                assert.is_true(items[fullType] == true, fullType .. " is not in the item scripts")
            end
            for _, field in ipairs({ "name", "line", "earlyLine" }) do
                local key = m[field]
                if key ~= nil then
                    assert.is_true(keys[key] == true, fullType .. " uses a missing key " .. tostring(key))
                end
            end
            assert.is_true(m.silent == true or m.name ~= nil, fullType .. " has no display name")
            assert.truthy(Data.ROUTES[m.route], fullType .. " has no route")
        end
        for id, side in pairs(SideEffects.DEFS) do
            assert.is_true(keys[side.name] == true, "side effect " .. id .. " name " .. side.name)
        end
        for id, pair in pairs(Interactions.PAIRS) do
            assert.is_true(keys[pair.line] == true, "interaction " .. id .. " line " .. pair.line)
        end
    end)

    it("refers only to real conditions, effects and side effects", function()
        for fullType, m in pairs(Data.byType) do
            for _, id in ipairs(m.targets) do
                assert.is_true(defs[id] ~= nil or id == "woundInfection", fullType .. " targets unknown " .. id)
            end
            for _, spec in ipairs(m.effects or {}) do
                assert.truthy(Effects.DEFS[spec.id], fullType .. " effect " .. spec.id)
            end
            for _, id in ipairs(m.side or {}) do
                assert.truthy(SideEffects.DEFS[id], fullType .. " side effect " .. id)
            end
            if Data.isCourse(m) then
                assert.is_true(m.interval > 0 and Data.curesAnything(m), fullType .. " course without interval or cure")
            end
        end
    end)

    it("matches the checklist's course and cure times (maintainer, Phase 5)", function()
        assert.equal(28, med("ExtensiveHealth.ColdFluTablets").cures.common_cold)
        assert.equal(8, med("ExtensiveHealth.ColdFluTablets").doses)
        assert.equal(48, med("ExtensiveHealth.AntiviralCapsules").cures.gastroenteritis)
        assert.equal(72, med("ExtensiveHealth.AntibioticOintment").cures.cellulitis)
        assert.equal(120, med("ExtensiveHealth.Buprenorphine").cures.painkiller_addiction)
        assert.equal(36, med("ExtensiveHealth.IVAntibiotics").cures.sepsis)
        assert.equal(72, med("ExtensiveHealth.AlbendazoleInjection").cures.trichinosis)
        assert.equal(24, med("ExtensiveHealth.ChelationKit").cures.toxin_poisoning)
        assert.equal("ivKit", med("ExtensiveHealth.ChelationKit").supply)
        assert.is_nil(med("Base.PillsBeta").treats)          -- W8: no hypothermia relief
        assert.is_true(med("Base.Pills").addiction)
        assert.is_nil(med("ExtensiveHealth.HomemadePainkillers").addiction)   -- W18
    end)
end)

describe("dose courses", function()
    it("cures the common cold after 8 doses over 28 hours, holding the stage meanwhile", function()
        local p = context()
        infect(p, "common_cold")
        local cold = "ExtensiveHealth.ColdFluTablets"
        for dose = 1, 8 do
            assert.equal("taken", take(p, cold).result)
            assert.is_true(p.treatment:curing("common_cold"))
            if dose < 8 then
                step(p, 4 * 60)
            end
        end
        step(p, 1)
        assert.is_nil(p.state.conditions.active.common_cold)
        assert.is_nil(Doses.course(p.state, med(cold)))
        assert.is_true(Sim.said(p, "UI_EHR_Med_CourseCured"))
        assert.same({ "cure", "common_cold" }, p.xps[#p.xps])
    end)

    it("refuses an early cold tablet but wastes an early antiviral, which overdoses", function()
        local p = context()
        infect(p, "common_cold")
        take(p, "ExtensiveHealth.ColdFluTablets")
        step(p, 60)
        local refused = take(p, "ExtensiveHealth.ColdFluTablets")
        assert.equal("refused", refused.result)
        assert.is_false(refused.consume)
        assert.equal("UI_EHR_Text_TheCurrentColdMedicineDoseIsStillActive", refused.reason)

        take(p, "ExtensiveHealth.AntiviralCapsules")
        step(p, 60)
        local early = take(p, "ExtensiveHealth.AntiviralCapsules")
        assert.equal("wasted", early.result)
        assert.is_true(early.consume)
        assert.equal(1, Doses.course(p.state, med("ExtensiveHealth.AntiviralCapsules")).count)
        assert.equal(2, p.state.meds.overdose.level)     -- 7 of 8 hours early: share 0.875
    end)

    it("counts a course dose from 90% of its interval, and wastes one taken earlier", function()
        local p = context()
        infect(p, "cellulitis")
        local ointment = "ExtensiveHealth.AntibioticOintment"      -- 8 h interval, wasted while active otherwise
        take(p, ointment)
        step(p, 408)                                                -- 6 h 48 min: 85 %
        assert.equal("UI_EHR_Text_TheCurrentOintmentDoseIsStillActiveMoreNowWillBe",
            Doses.wasteReason(p.state, med(ointment)))
        assert.equal(24, Doses.nextDoseIn(p.state, med(ointment)))   -- 90 % is 7 h 12 min
        step(p, 30)                                                 -- 7 h 18 min: past 90 %
        assert.is_nil(Doses.wasteReason(p.state, med(ointment)))
        assert.equal(0, Doses.nextDoseIn(p.state, med(ointment)))
        assert.equal("taken", take(p, ointment).result)
        assert.equal(2, Doses.course(p.state, med(ointment)).count)

        local antiviral = "ExtensiveHealth.AntiviralCapsules"       -- 8 h, on the overdose list
        take(p, antiviral)
        step(p, 7 * 60)                                             -- 87.5 %: too early
        assert.equal("wasted", take(p, antiviral).result)
        assert.equal(1, p.state.meds.overdose.level)
    end)

    it("wastes a vanilla-consumed dose it would have refused", function()
        local p = context()
        take(p, "Base.PillsVitamins")
        local again = take(p, "Base.PillsVitamins", { consumed = true })
        assert.equal("wasted", again.result)
        assert.is_true(Sim.said(p, "UI_EHR_Text_TheCaffeineIsStillActiveMoreWouldBeAVeryBadIdea"))
    end)

    it("waits for the guide's cure time after the last dose", function()
        local p = context()
        infect(p, "cellulitis")
        local ointment = "ExtensiveHealth.AntibioticOintment"
        for dose = 1, 6 do
            take(p, ointment)
            if dose < 6 then
                step(p, 8 * 60)
            end
        end
        step(p, 60)                                   -- 41 h: every dose taken, 72 h not reached
        assert.truthy(p.state.conditions.active.cellulitis)
        assert.is_true(p.treatment:curing("cellulitis"))
        assert.equal("UI_EHR_Med_AlreadyWorking", take(p, ointment).reason)
        step(p, 31 * 60)
        assert.is_nil(p.state.conditions.active.cellulitis)
    end)

    it("abandons a course a day after a missed dose", function()
        local p = context()
        infect(p, "common_cold")
        take(p, "ExtensiveHealth.ColdFluTablets")
        step(p, 4 * 60 + 24 * 60)
        assert.truthy(Doses.course(p.state, med("ExtensiveHealth.ColdFluTablets")))
        step(p, 2)
        assert.is_nil(Doses.course(p.state, med("ExtensiveHealth.ColdFluTablets")))
        assert.is_false(p.treatment:curing("common_cold"))
    end)

    it("needs an IV kit for IV antibiotics, cures sepsis 36 hours later, and refuses a second dose meanwhile", function()
        local p = context()
        infect(p, "sepsis")
        local iv = "ExtensiveHealth.IVAntibiotics"
        local refused = take(p, iv, { ctx = { supplies = { ivKit = false } } })
        assert.equal("UI_EHR_MedReason_RequiresIVKit", refused.reason)
        local given = take(p, iv, { ctx = { supplies = { ivKit = true } } })
        assert.equal("taken", given.result)
        assert.is_true(given.supply)
        assert.truthy(p.state.meds.side.nausea)
        assert.equal("UI_EHR_Med_AlreadyWorking", take(p, iv).reason)
        step(p, 36 * 60 - 1)
        assert.truthy(p.state.conditions.active.sepsis)
        step(p, 2)
        assert.is_nil(p.state.conditions.active.sepsis)
        assert.same({ "cure", "sepsis" }, p.xps[#p.xps])
    end)

    it("cures every wound infection with a course", function()
        local p = context()
        p.state.wounds.parts.Hand_L = { phase = "infected", stage = 2, left = 1e6 }
        take(p, "ExtensiveHealth.IVAntibiotics")
        assert.is_true(p.treatment:curing("woundInfection"))
        step(p, 36 * 60 + 1)
        assert.is_nil(p.state.wounds.parts.Hand_L)
    end)

    it("uses the ice pack only against heat stroke", function()
        local p = context()
        assert.equal("UI_EHR_Med_NothingToTreat", take(p, "ExtensiveHealth.InstantIcePack").reason)
        infect(p, "heat_stroke", 3)
        assert.equal("taken", take(p, "ExtensiveHealth.InstantIcePack").result)
        step(p, 30)
        assert.equal("UI_EHR_Med_IcePackStillCooling", take(p, "ExtensiveHealth.InstantIcePack").reason)
        step(p, 30)
        assert.equal("taken", take(p, "ExtensiveHealth.InstantIcePack").result)
    end)

    it("needs a wound for antiseptic cream, which then prevents new infections", function()
        local p = context()
        assert.equal("UI_EHR_MedReason_RequiresActiveWound",
            take(p, "ExtensiveHealth.AntisepticCream", { ctx = { wound = false } }).reason)
        take(p, "ExtensiveHealth.AntisepticCream", { ctx = { wound = true } })
        assert.is_true(Provider.new(p.state):active("antiseptic"))
        step(p, 8 * 60)
        assert.is_false(Provider.new(p.state):active("antiseptic"))
    end)

    it("gives the take XP at most once per interval", function()
        local p = context()
        assert.same({ "take" }, take(p, "ExtensiveHealth.CoughSyrup").xp)
        step(p, 10)
        assert.same({}, take(p, "ExtensiveHealth.CoughSyrup").xp)
        infect(p, "pneumonia")
        step(p, 30)
        assert.same({ "take", "treat" }, take(p, "ExtensiveHealth.CoughSyrup").xp)
    end)

    it("steps wound infections down with vanilla antibiotics and counts painkillers toward addiction", function()
        local p = context()
        p.state.wounds.parts.Hand_R = { phase = "infected", stage = 2, left = 1000 }
        local outcome = take(p, "Base.Antibiotics", { consumed = true })
        assert.equal(1, p.state.wounds.parts.Hand_R.stage)
        assert.same({ "take", "treat" }, outcome.xp)
        take(p, "Base.Pills", { consumed = true })
        assert.equal(1, p.state.mind.painkiller.risk)
        take(p, "ExtensiveHealth.HomemadePainkillers")
        assert.equal(1, p.state.mind.painkiller.risk)
    end)
end)

describe("relief", function()
    it("combines the best tier relief with the best specific relief", function()
        local p = context()
        take(p, "ExtensiveHealth.CoughSyrup")
        local t = Provider.new(p.state)
        assert.near(1 - 0.6 * 0.5, t:relief("pneumonia", "coughing"), 1e-9)
        assert.near(0.4, t:relief("pneumonia", "fever"), 1e-9)
        assert.equal(0, t:relief("concussion", "pain"))
        take(p, "ExtensiveHealth.CoughSuppressant")
        assert.near(1 - 0.6 * 0.5, Provider.new(p.state):relief("pneumonia", "coughing"), 1e-9)
    end)

    it("gives food diseases their tier as general relief and the specific relief separately", function()
        local p = context()
        take(p, "ExtensiveHealth.AntiNauseaTablets")
        local t = Provider.new(p.state)
        assert.near(0.4, t:relief("food_poisoning", "general"), 1e-9)
        assert.near(0.5, t:relief("food_poisoning", "nausea"), 1e-9)
        assert.near(0.75, t:relief("dysentery", "vomiting"), 1e-9)
    end)

    it("gives wound infection and sepsis no tier relief, but vanilla antibiotics ease sepsis fever", function()
        local p = context()
        take(p, "ExtensiveHealth.AntiInflammatory")
        local t = Provider.new(p.state)
        assert.near(0.55, t:relief("woundInfection", "pain"), 1e-9)
        assert.equal(0, t:relief("woundInfection", "nausea"))
        take(p, "Base.Antibiotics", { consumed = true })
        assert.near(0.15, Provider.new(p.state):relief("sepsis", "fever"), 1e-9)
    end)

    it("lets water help heat exhaustion a little, without XP, and never on top of electrolytes", function()
        local p = context()
        local water = Doses.take(p, defs, Data.byId.Water, { consumed = true })
        assert.same({}, water.xp)
        assert.same({}, p.said)
        assert.near(0.10, Provider.new(p.state):relief("heat_exhaustion", "dehydration"), 1e-9)
        assert.equal(0, Provider.new(p.state):relief("dysentery", "dehydration"))
        take(p, "ExtensiveHealth.ElectrolytePowder")
        assert.near(1 - 0.6 * 0.6, Provider.new(p.state):relief("heat_exhaustion", "dehydration"), 1e-9)
        step(p, 61)
        assert.is_nil(p.state.meds.doses.Water)
    end)

    it("halves antibiotic relief while activated charcoal is active", function()
        local p = context()
        take(p, "ExtensiveHealth.PrescriptionAntibiotics")
        assert.near(0.6, Provider.new(p.state):relief("pneumonia", "coughing"), 1e-9)
        take(p, "ExtensiveHealth.ActivatedCharcoal")
        assert.near(0.3, Provider.new(p.state):relief("pneumonia", "coughing"), 1e-9)
    end)

    it("reports active flags only while the dose lasts", function()
        local p = context()
        take(p, "Base.PillsBeta", { consumed = true })
        assert.is_true(Provider.new(p.state):active("betaBlocker"))
        step(p, 1)
        assert.is_true(p.fx.values.noSleep)
        assert.equal("betaBlocker", p.fx.values.sleepBy)
        step(p, 2 * 60)
        assert.is_false(Provider.new(p.state):active("betaBlocker"))
    end)
end)

describe("overdose", function()
    it("grows with each early dose and kills on the third", function()
        local p = context()
        assert.equal(1, Overdose.level(0.5))
        assert.equal(3, Overdose.level(0.95))
        Overdose.apply(p, 0.5)
        assert.equal(1, p.state.meds.overdose.level)
        Overdose.apply(p, 0.1)
        assert.equal(2, p.state.meds.overdose.level)
        assert.is_nil(p.body.killed)
        assert.equal("lethal", Overdose.apply(p, 0.1))
        assert.truthy(p.body.killed)
    end)

    it("holds sickness, endurance and a health cap, then wears off", function()
        local p = context()
        p.facts.health = 90
        Overdose.apply(p, 0.5)
        step(p, 1)
        assert.equal(63, 90 - p.body:resolveDamage(90))
        step(p, 8 * 60)
        assert.is_false(p.state.meds.overdose)
    end)
end)

describe("timed effects and crashes", function()
    it("holds caffeine's fatigue at zero, blocks sleep, then crashes with an insomnia roll", function()
        local p = context({ floats = {} })
        take(p, "Base.PillsVitamins", { consumed = true })
        step(p, 1)
        assert.equal("caffeine", p.fx.values.sleepBy)
        step(p, 12 * 60)
        assert.truthy(p.state.meds.side.caffeine_crash)
        assert.equal(12 * 60, p.state.mind.stimulantCooldown)
    end)

    it("locks endurance on the nitric oxide booster, then 6 hours of muscle pain", function()
        local p = context()
        take(p, "ExtensiveHealth.NitricOxideBooster")
        step(p, 1)
        assert.equal(1, p.stats:resolve("ENDURANCE", 0.2))
        step(p, 3 * 60)
        assert.truthy(p.state.meds.side.whole_body_muscle_pain)
        step(p, 1)
        assert.equal(18, p.body:painTargets().Torso_Upper)
    end)

    it("doubles attack speed and calms on combat stimulants, without a walking boost", function()
        local p = context()
        take(p, "ExtensiveHealth.CombatStimulants")
        step(p, 1)
        assert.equal(2, p.fx.values.attackSpeed)
        assert.equal(1, p.fx.values.boost)
        assert.equal(0, p.stats:resolve("PANIC", 50))
        assert.equal("refused", take(p, "ExtensiveHealth.CombatStimulants").result)
        step(p, 3 * 60)
        assert.truthy(p.state.meds.side.combat_stimulant_crash)
    end)

    it("rescues with Last Chance Epinephrine at low health and gambles above 15%", function()
        local low = context()
        low.facts.health = 10
        take(low, "ExtensiveHealth.LastChanceEpinephrine")
        assert.equal(75, low.body.restore.target)
        step(low, 1)
        assert.equal(1.2, low.fx.values.boost)
        step(low, 60)
        assert.truthy(low.state.meds.side.last_chance_headache)
        assert.truthy(low.state.meds.side.last_chance_thirst)

        local unlucky = context({ floats = { 0.1 } })
        unlucky.facts.health = 60
        take(unlucky, "ExtensiveHealth.LastChanceEpinephrine")
        assert.truthy(unlucky.body.killed)

        local lucky = context({ floats = { 0.9 } })
        lucky.facts.health = 60
        take(lucky, "ExtensiveHealth.LastChanceEpinephrine")
        assert.is_nil(lucky.body.killed)
        assert.truthy(lucky.state.meds.side.last_chance_severe_headache)
    end)

    it("wakes a blacked-out patient with epinephrine (W6)", function()
        local p = context()
        p.state.blood.blackout = true
        take(p, "ExtensiveHealth.Epinephrine")
        assert.equal("wake", p.sent[#p.sent][1])
        assert.truthy(p.state.meds.side.insomnia)
        step(p, 1)
        assert.equal("medInsomnia", p.fx.values.sleepBy)
    end)

    it("lowers thirst with electrolytes, now and over the next half hour", function()
        local p = context()
        take(p, "ExtensiveHealth.ElectrolytePowder")
        assert.near(0.2 - 0.10, p.stats:resolve("THIRST", 0.2), 1e-9)
        step(p, 30)
        assert.is_nil(p.state.meds.effects.hydration)
    end)
end)

describe("side effects", function()
    it("doesn't restart a running side effect unless forced", function()
        local p = context()
        assert.is_true(SideEffects.start(p, "nausea"))
        p.state.meds.side.nausea.left = 10
        assert.is_false(SideEffects.start(p, "nausea"))
        assert.equal(10, p.state.meds.side.nausea.left)
        assert.is_true(SideEffects.start(p, "nausea", { force = true }))
        assert.equal(4 * 60, p.state.meds.side.nausea.left)
    end)

    it("makes a walking character with tendon weakness fall now and then", function()
        local p = context({ floats = {}, float = 0.1 })
        p.facts.env.moving = true
        SideEffects.start(p, "tendon_weakness")
        step(p, 15)
        local falls = 0
        for _, sent in ipairs(p.sent) do
            if sent[1] == "fall" then
                falls = falls + 1
                assert.equal("pushedFront", sent[2].fallType)
            end
        end
        assert.equal(1, falls)
    end)
end)

describe("drug interactions", function()
    it("fire once while both are active, and again after one wore off", function()
        local p = context()
        take(p, "ExtensiveHealth.MuscleRelaxants")
        take(p, "Base.PillsBeta", { consumed = true })
        step(p, 1)
        step(p, 1)
        local warned = 0
        for _, key in ipairs(p.said) do
            if key == Interactions.PAIRS.relaxantBeta.line then
                warned = warned + 1
            end
        end
        assert.equal(1, warned)
        assert.is_true(p.state.meds.pairs.relaxantBeta)
        step(p, 2 * 60)
        assert.is_nil(p.state.meds.pairs.relaxantBeta)
    end)
end)

describe("First Aid XP", function()
    it("scales by the multiplier, adds the sepsis bonus, and stops when disabled", function()
        local options = { FirstAidXPMultiplier = 2 }
        local function sandbox(name, default)
            if options[name] == nil then return default end
            return options[name]
        end
        assert.equal(10, XpData.amount("take", nil, sandbox))
        assert.equal(90, XpData.amount("cure", "sepsis", sandbox))
        assert.equal(1, XpData.amount("forage", nil, sandbox))
        options.FirstAidXPEnabled = false
        assert.equal(0, XpData.amount("cure", "sepsis", sandbox))
        -- Foraging XP from the wild searches ignores the First Aid options.
        assert.equal("PlantScavenging", XpData.perk("forage"))
        assert.equal(1, XpData.amount("forage", nil, sandbox))
    end)

    it("is awarded when a condition ends, but not for debug ends or the Knox mirror", function()
        local p = context()
        infect(p, "common_cold")
        Engine.finish(p, defs, "common_cold", "recovered")
        infect(p, "pneumonia")
        Engine.finish(p, defs, "pneumonia", "debug")
        infect(p, "knox_infection")
        Engine.finish(p, defs, "knox_infection", "recovered")
        assert.same({ { "cure", "common_cold" } }, p.xps)
    end)
end)
