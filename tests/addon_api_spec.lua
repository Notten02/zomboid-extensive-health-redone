-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, need-check-nil
-- The extension points for add-on mods, in pure code: state sections, condition registration and its flags,
-- knowledge strands, Monitor row providers, medication registration and dose listeners, drug interactions, rate
-- modifiers, wound and fracture healing speed, reopened wounds, night vision and aim, perk drains, log prefixes and
-- stale-food exemptions.
-- Each block requires its modules inside insulate(), so what it registers doesn't reach other specs.

insulate("add-on state sections", function()
    local Schema = require("ExtensiveHealthRedone/Core/Schema")
    local StateStore = require("ExtensiveHealthRedone/Core/StateStore")

    Schema.registerSection("addonNutrition", {
        version = 3,
        defaults = function() return { reserves = { c = 75 }, meals = {} } end,
        migrations = {
            [1] = function(s) s.reserves = { c = s.vitaminC or 0 }; s.vitaminC = nil end,
            [2] = function(s) s.meals = s.meals or {} end,
        },
        exam = true,
    })

    it("adds the section, with its version, to every new state", function()
        local state = Schema.new({ int = function(lo) return lo end })
        assert.same({ reserves = { c = 75 }, meals = {}, v = 3 }, state.addonNutrition)
        assert.equal("addonNutrition", Schema.SECTIONS[#Schema.SECTIONS])
        assert.is_true(Schema.ADDONS.addonNutrition.exam)
    end)

    it("fills the section into an old save that never had it", function()
        local state = Schema.new({ int = function(lo) return lo end })
        state.addonNutrition = nil
        assert.is_true(Schema.upgradeSections(state))
        Schema.fillDefaults(state)
        assert.equal(3, state.addonNutrition.v)
    end)

    it("migrates a saved section through its own chain", function()
        local state = { addonNutrition = { v = 1, vitaminC = 40 } }
        assert.is_true(Schema.upgradeSections(state))
        assert.same({ reserves = { c = 40 }, meals = {}, v = 3 }, state.addonNutrition)
    end)

    it("leaves a state alone when the section is newer than its add-on", function()
        local state = { addonNutrition = { v = 4, keep = true } }
        local ok, err = Schema.upgradeSections(state)
        assert.is_false(ok)
        assert.truthy(err:find("newer"))
        assert.equal(4, state.addonNutrition.v)
    end)

    it("rejects duplicates and bad specs", function()
        assert.has_error(function() Schema.registerSection("addonNutrition", { defaults = function() return {} end }) end)
        assert.has_error(function() Schema.registerSection("blood", { defaults = function() return {} end }) end)
        assert.has_error(function() Schema.registerSection("noDefaults", {}) end)
        assert.has_error(function() Schema.registerSection("badVersion", { defaults = function() return {} end,
            version = 0 }) end)
    end)

    it("tells listeners, and a store learns sections added after it was built", function()
        local store = StateStore.new({ "meta" }, "epoch")
        store:attach("k", { meta = {} })
        local heard
        Schema.onSection(function(name) heard = name; store:addSection(name) end)
        Schema.registerSection("addonLate", { defaults = function() return { x = 1 } end })
        assert.equal("addonLate", heard)
        assert.equal(1, store:revision("k", "addonLate"))
        store:markDirty("k", "addonLate")
        assert.equal(2, store:takeDelta("k").sections.addonLate.rev)
    end)
end)

insulate("add-on sections and the admin's full heal", function()
    local Schema = require("ExtensiveHealthRedone/Core/Schema")
    local FullHeal = require("ExtensiveHealthRedone/Admin/FullHeal")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")
    local StatAggregator = require("ExtensiveHealthRedone/Core/StatAggregator")
    local Sim = require("support/sim")

    -- A full heal zeroes the Knox stats too.
    local function context()
        local ranges = { ZOMBIE_INFECTION = { min = 0, max = 100 }, ZOMBIE_FEVER = { min = 0, max = 100 },
            BOREDOM = { min = 0, max = 100 }, POISON = { min = 0, max = 100 } }
        for name, range in pairs(Sim.RANGES) do
            ranges[name] = range
        end
        local p = Sim.context()
        p.stats = StatAggregator.new(ranges)
        return p
    end

    Schema.registerSection("addonKept", { defaults = function() return { level = 0 } end })
    Schema.registerSection("addonHealed", { defaults = function() return { level = 0 } end, resetOnHeal = true })
    local heard = {}
    FullHeal.onHeal(function(p, mode) heard[#heard + 1] = mode; p.state.addonKept.healed = true end)

    it("resets only resetOnHeal sections on a heal, all of them on a reset, and calls the listeners", function()
        local p = context()
        p.state.addonKept.level, p.state.addonHealed.level = 5, 5

        FullHeal.apply(p, defs, "heal")
        assert.equal(5, p.state.addonKept.level)
        assert.is_true(p.state.addonKept.healed)
        assert.equal(0, p.state.addonHealed.level)
        assert.is_nil(p.dirtied.addonKept)
        assert.equal(1, p.dirtied.addonHealed)
        FullHeal.apply(p, defs, "reset")
        assert.is_true(p.state.addonKept.healed)   -- reset to defaults first, then the listener ran again
        assert.same({ "heal", "reset" }, heard)
        assert.equal(1, p.dirtied.addonKept)
    end)
end)

insulate("add-on conditions", function()
    local Registration = require("ExtensiveHealthRedone/Conditions/Registration")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")
    local DiseaseInfo = require("ExtensiveHealthRedone/Data/DiseaseInfo")
    local Immunity = require("ExtensiveHealthRedone/Immunity/Immunity")
    local MoodleLevels = require("ExtensiveHealthRedone/UI/MoodleLevels")
    local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
    local Sim = require("support/sim")

    Registration.register("addon_quiet", {
        name = "UI_Addon_Quiet", driven = true, drive = function(_, c) return c.stage end, master = false, xp = false,
        alert = false, pressure = false, enabledOption = "AddonMod.QuietEnabled",
        display = { icon = "Addon_Quiet", category = "nutrition", unknownName = "UI_Addon_Unknown_Tired",
            unknownDesc = "UI_Addon_Unknown_Tired_Desc", handbook = true, lockedDesc = "UI_Addon_ReadTheBook" },
    })
    Registration.register("addon_half", { name = "UI_Addon_Half", duration = { 10, 10 }, pressure = "half" })

    it("adds the definition and how it is shown", function()
        assert.equal("UI_Addon_Quiet", defs.addon_quiet.name)
        assert.equal("Addon_Quiet", DiseaseInfo.icon("addon_quiet"))
        local name, desc = DiseaseInfo.unknownKeys("addon_quiet")
        assert.equal("UI_Addon_Unknown_Tired", name)
        assert.equal("UI_Addon_Unknown_Tired_Desc", desc)
        assert.equal("addon_quiet", DiseaseInfo.ORDER[#DiseaseInfo.ORDER])
        assert.equal(DiseaseInfo.UNKNOWN_ICON, DiseaseInfo.icon("addon_half"))
    end)

    it("shows its own text on a locked handbook entry", function()
        local Handbook = require("ExtensiveHealthRedone/UI/Handbook")
        local entry
        for _, e in ipairs(Handbook.build({ diseases = {} }, 0, defs).entries) do
            if e.id == "addon_quiet" then
                entry = e
            end
        end
        assert.is_false(entry.known)
        assert.equal("UI_Addon_ReadTheBook", entry.locked.key)
    end)

    it("rejects duplicates and bad definitions", function()
        assert.has_error(function() Registration.register("addon_quiet", { name = "x" }) end)
        assert.has_error(function() Registration.register("sepsis", { name = "x" }) end)
        assert.has_error(function() Registration.register("addon_noname", {}) end)
        assert.has_error(function() Registration.register("addon_bad", { name = "x", pressure = true }) end)
        assert.has_error(function() Registration.register("addon_nodrive", { name = "x", driven = true }) end)
    end)

    it("runs through the engine with an add-on sandbox option and the master switch ignored", function()
        local p = Sim.context({ sandbox = { DiseaseEnabled = false, ["AddonMod.QuietEnabled"] = true } })
        assert.truthy(Engine.contract(p, defs, "addon_quiet", { stage = 2 }))
        local off = Sim.context({ sandbox = { ["AddonMod.QuietEnabled"] = false } })
        local _, why = Engine.contract(off, defs, "addon_quiet")
        assert.equal("disabled", why)
    end)

    it("adds no disease pressure with pressure = false and half with \"half\"", function()
        local p = Sim.context()
        p.state.conditions.active.addon_quiet = { stage = 4 }
        assert.equal(0, Immunity.pressure(p.state))
        p.state.conditions.active.addon_half = { stage = 2 }
        assert.equal(6, Immunity.pressure(p.state))
    end)

    it("never raises the Medical Alert with alert = false", function()
        local level = MoodleLevels.medical({ active = { addon_quiet = { stage = 4 } } }, nil, nil)
        assert.equal(0, level)
        level = MoodleLevels.medical({ active = { addon_half = { stage = 3 } } }, nil, nil)
        assert.equal(3, level)
    end)
end)

insulate("knowledge strands", function()
    local Knowledge = require("ExtensiveHealthRedone/Conditions/Knowledge")
    local Learn = require("ExtensiveHealthRedone/Knowledge/Learn")
    local Sim = require("support/sim")

    Knowledge.registerStrand("nutrition", function(_, _, _, level)
        return { name = level >= 1, stage = level >= 2, progress = level >= 2 }
    end)
    local def = { name = "UI_Addon_Scurvy", strand = "nutrition" }

    it("judges a strand condition by the strand alone, not by medical knowledge", function()
        local p = Sim.context()
        p.state.knowledge.professionGrant = "ehrdoctor"
        assert.same({ name = false, stage = false, progress = false }, Knowledge.of(p.state, def, 10))
        assert.equal("learned", Learn.strand(p, "nutrition", 1, "UI_Addon_Book"))
        assert.same({ name = true, stage = false, progress = false }, Knowledge.of(p.state, def, 0))
        assert.equal("learned", Learn.strand(p, "nutrition", 2))
        assert.same({ name = true, stage = true, progress = true }, Knowledge.of(p.state, def, 0))
    end)

    it("only raises a level, and says when something was learned", function()
        local p = Sim.context()
        Learn.strand(p, "nutrition", 2, "UI_Addon_Trait")
        assert.equal("known", Learn.strand(p, "nutrition", 1, "UI_Addon_Book"))
        assert.equal(2, p.state.knowledge.strands.nutrition)
        assert.equal(1, #p.sent)
        assert.same({ "knowledgeLearned", { name = "UI_Addon_Trait" } }, p.sent[1])
    end)

    it("knows nothing of an unregistered strand, and rejects a second registration", function()
        assert.is_false(Knowledge.of(Sim.context().state, { strand = "other" }, 10).name)
        assert.has_error(function() Knowledge.registerStrand("nutrition", function() end) end)
    end)
end)

insulate("Monitor row providers", function()
    local Monitor = require("ExtensiveHealthRedone/UI/Monitor")
    local Text = require("ExtensiveHealthRedone/UI/Text")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")
    local Sim = require("support/sim")

    Monitor.addRowProvider("addonReserves", function(input)
        if (input.state.knowledge.strands or {}).nutrition then
            return { { known = true, name = Text.key("UI_Addon_LowVitaminC") } }
        end
        return {}
    end)
    Monitor.addRowProvider("broken", function() error("boom") end, 200)

    it("adds the rows after the others and survives a failing provider", function()
        local p = Sim.context()
        local input = { state = p.state, firstAid = 0, defs = defs, sandbox = p.sandbox, parts = {} }
        assert.equal(0, #Monitor.build(input).conditions)
        p.state.knowledge.strands.nutrition = 1
        local rows = Monitor.build(input).conditions
        assert.equal(1, #rows)
        assert.same(Text.key("UI_Addon_LowVitaminC"), rows[1].name)
        assert.truthy(Monitor.providerErrors.broken:find("boom"))
    end)

    it("rejects a second provider with the same name", function()
        assert.has_error(function() Monitor.addRowProvider("addonReserves", function() end) end)
    end)
end)

insulate("a condition's Monitor row", function()
    local Monitor = require("ExtensiveHealthRedone/UI/Monitor")
    local Text = require("ExtensiveHealthRedone/UI/Text")
    local Registration = require("ExtensiveHealthRedone/Conditions/Registration")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")
    local Sim = require("support/sim")

    Registration.register("addon_rowed", {
        name = "UI_Addon_Rowed", driven = true, drive = function(_, c) return c.stage end, master = false, xp = false,
        monitorRow = function(row, c, known, input)
            if known.name then
                row.description = Text.key("UI_Addon_EatFruit")
            end
            if known.progress then
                row.progress = input.state.addonLevel / 100
                row.status = Text.key("UI_Addon_Recovering")
            end
        end,
    })
    Registration.register("addon_broken_row", {
        name = "UI_Addon_Broken", driven = true, drive = function(_, c) return c.stage end, master = false, xp = false,
        monitorRow = function() error("boom") end,
    })

    local function rowOf(rows, id)
        for _, row in ipairs(rows) do
            if row.id == id then
                return row
            end
        end
    end

    it("lets the condition change its row by what the reader knows, and survives a failing hook", function()
        local p = Sim.context()
        p.state.addonLevel = 40
        p.state.conditions.active.addon_rowed = { stage = 2 }
        p.state.conditions.active.addon_broken_row = { stage = 1 }
        local input = { state = p.state, firstAid = 0, defs = defs, sandbox = p.sandbox, parts = {} }
        local row = rowOf(Monitor.build(input).conditions, "addon_rowed")
        assert.is_nil(row.progress)
        assert.same(Text.raw("??%"), row.progressText)
        local model = Monitor.build(input)
        assert.truthy(Monitor.rowErrors.addon_broken_row:find("boom"))
        assert.truthy(rowOf(model.conditions, "addon_broken_row"))
        input.firstAid = 10
        p.state.knowledge.professionGrant = "ehrdoctor"
        row = rowOf(Monitor.build(input).conditions, "addon_rowed")
        assert.same(Text.key("UI_Addon_EatFruit"), row.description)
        assert.equal(0.4, row.progress)
        assert.same(Text.key("UI_Addon_Recovering"), row.status)
    end)

    it("rejects a monitorRow that isn't a function", function()
        assert.has_error(function() Registration.register("addon_badrow", { name = "x", monitorRow = true }) end)
    end)
end)

insulate("add-on medication", function()
    local MedData = require("ExtensiveHealthRedone/Medication/Data")
    local Doses = require("ExtensiveHealthRedone/Medication/Doses")
    local Interactions = require("ExtensiveHealthRedone/Medication/Interactions")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")
    local Sim = require("support/sim")

    MedData.register("AddonMod.IronTablets", {
        id = "AddonIron", name = "UI_Addon_Iron", route = "pill", tier = 1, active = 24, interval = 24, doses = 3,
        course = true, category = "ironSupplement",
    })
    Interactions.register("addonIronAntibiotic", { a = "ironSupplement", b = "antibiotic", line = "UI_Addon_IronWarn" })
    local heard = {}
    Doses.onDose(function(_, med, outcome) heard[#heard + 1] = med.id .. ":" .. outcome.result end)

    it("indexes the entry like a built-in one", function()
        local med = MedData.byId.AddonIron
        assert.equal("AddonMod.IronTablets", med.fullType)
        assert.is_true(MedData.ownRoute["AddonMod.IronTablets"])
        assert.same({}, med.targets)
        assert.is_true(MedData.tracksCourse(med))
    end)

    it("rejects known items and ids, unknown routes", function()
        assert.has_error(function() MedData.register("AddonMod.IronTablets", { id = "Other", route = "pill" }) end)
        assert.has_error(function() MedData.register("AddonMod.Other", { id = "AddonIron", route = "pill" }) end)
        assert.has_error(function() MedData.register("AddonMod.Other2", { id = "Other2", route = "teleport" }) end)
        assert.has_error(function() MedData.register("AddonMod.Other3", { id = "Other3", route = "pill",
            vanilla = "smoke" }) end)
    end)

    it("runs a course without cures, tells the dose listeners, and ends once every dose is in", function()
        local p = Sim.context()
        local med = MedData.byId.AddonIron
        assert.equal("taken", Doses.take(p, defs, med).result)
        assert.equal(1, p.state.meds.courses.AddonIron.count)
        assert.equal("wasted", Doses.take(p, defs, med).result)     -- before 90 % of the interval
        assert.same({ "AddonIron:taken" }, heard)
        for _ = 1, 2 do
            Doses.update(p, defs, 24 * 60)
            assert.equal("taken", Doses.take(p, defs, med).result)
        end
        assert.equal(3, p.state.meds.courses.AddonIron.count)
        Doses.update(p, defs, 1)
        assert.is_nil(p.state.meds.courses.AddonIron)
        assert.equal(3, #heard)
    end)

    it("fires a registered interaction", function()
        local p = Sim.context()
        Interactions.update(p, { ironSupplement = true, antibiotic = true })
        assert.is_true(p.state.meds.pairs.addonIronAntibiotic)
        assert.truthy(Sim.said(p, "UI_Addon_IronWarn"))
        assert.has_error(function() Interactions.register("addonIronAntibiotic", { a = "x", b = "y", line = "z" }) end)
    end)
end)

describe("rate modifiers", function()
    local Modifiers = require("ExtensiveHealthRedone/Core/Modifiers")
    local Blood = require("ExtensiveHealthRedone/Blood/Blood")
    local Sim = require("support/sim")

    it("keeps the lowest factor per key and reads 1 for an untouched key", function()
        local mods = Modifiers.new()
        assert.equal(1, mods:get("bloodRegen"))
        mods:scale("bloodRegen", "a", 0.8)
        mods:scale("bloodRegen", "b", 0.5)
        mods:scale("bloodRegen", "c", 0.9)
        assert.equal(0.5, mods:get("bloodRegen"))
        assert.equal("b", mods:source("bloodRegen"))
        assert.has_error(function() mods:scale("bloodRegen", nil, 0.5) end)
    end)

    it("slows blood volume recovery", function()
        local function regained(factor)
            local p = Sim.context()
            p.state.blood.volume = 4000
            if factor then
                p.mods:scale("bloodRegen", "test", factor)
            end
            Blood.update(p, 60)
            return p.state.blood.volume - 4000
        end
        local full, half = regained(nil), regained(0.5)
        assert.truthy(full > 0)
        assert.near(full / 2, half, 1e-6)
    end)
end)

describe("wound and fracture healing speed, reopened wounds", function()
    local BodyAggregator = require("ExtensiveHealthRedone/Core/BodyAggregator")

    it("lets a slowed timer fall by factor x vanilla's drop, and accepts a timer that went up", function()
        assert.same({ nil, 10 }, { BodyAggregator.resolveTimer(0.5, 10, nil) })
        assert.same({ 9, 9 }, { BodyAggregator.resolveTimer(0.5, 8, 10) })
        assert.same({ nil, 15 }, { BodyAggregator.resolveTimer(0.5, 15, 9) })
        assert.same({ nil, nil }, { BodyAggregator.resolveTimer(1, 8, 10) })
        assert.same({ nil, nil }, { BodyAggregator.resolveTimer(0.5, 0, 10) })
    end)

    it("keeps the lowest speed per part and the worst reopened wound", function()
        local body = BodyAggregator.new()
        body:woundSpeed("Hand_L", "a", 0.7)
        body:woundSpeed("Hand_L", "b", 0.4)
        body:fractureSpeed("ForeArm_L", "c", 0.6)
        body:reopen("Hand_L", "a", "cut")
        body:reopen("Hand_L", "b", "scratch")
        body:reopen("Hand_L", "c", "deep")
        assert.equal(0.4, body.woundSpeeds.Hand_L)
        assert.equal(0.6, body.fractureSpeeds.ForeArm_L)
        assert.same({ kind = "deep", source = "c" }, body.reopened.Hand_L)
        assert.has_error(function() body:reopen("Hand_L", "a", "bite") end)
    end)
end)

describe("night vision, aim and perk drains", function()
    local ClientEffects = require("ExtensiveHealthRedone/Core/ClientEffects")
    local PerkAggregator = require("ExtensiveHealthRedone/Core/PerkAggregator")

    it("keeps the strongest night blindness and the lowest aim", function()
        local fx = ClientEffects.new()
        fx:nightVision("a", 0.3)
        fx:nightVision("b", 0.7)
        fx:aim("a", 0.9)
        fx:aim("b", 0.6)
        local section = ClientEffects.defaults()
        fx:writeTo(section)
        assert.equal(0.7, section.night)
        assert.equal(0.6, section.aim)
    end)

    it("keeps the highest drain per passive skill", function()
        local perks = PerkAggregator.new()
        perks:drain("Strength", "a", 2)
        perks:drain("Strength", "b", 5)
        perks:drain("Strength", "c", 3)
        assert.equal(5, perks:get("Strength"))
        assert.equal(0, perks:get("Fitness"))
        assert.has_error(function() perks:drain("Cooking", "a", 1) end)
    end)
end)

describe("log prefix", function()
    local Log = require("ExtensiveHealthRedone/Core/Log")

    it("starts an add-on's lines with its own name", function()
        local lines = {}
        local log = Log.new("Reserves", function(line) lines[#lines + 1] = line end, "info", "[AddonMod] ")
        log:info("ready")
        Log.new("Sync", function(line) lines[#lines + 1] = line end, "info"):info("ok")
        assert.same({ "[AddonMod] INFO Reserves: ready", "[ExtensiveHealthRedone] INFO Sync: ok" }, lines)
    end)
end)

insulate("stale food exemptions", function()
    local Risk = require("ExtensiveHealthRedone/Diseases/Food/Risk")
    local stale = { fullType = "Base.PotOfSoup", type = "potofsoup", fresh = false, cooked = true, heat = 1.5 }

    it("counts stale food as risky when no add-on lifts it", function()
        local chance, reason = Risk.foodPoisoning(stale, 0)
        assert.truthy(chance > 0)
        assert.equal("stale", reason)
        assert.is_nil(Risk.staleExemption(stale))
    end)

    it("lifts only the stale risk, and only for the food the rule picks", function()
        Risk.exemptStale("addonReheated", function(food) return food.cooked and food.heat >= 1.3 end)
        Risk.exemptStale("addonBroken", function() error("boom") end)
        assert.equal(0, (Risk.foodPoisoning(stale, 0)))
        assert.equal("addonReheated", Risk.staleExemption(stale))
        local cold = { fullType = "Base.PotOfSoup", type = "potofsoup", fresh = false, cooked = true, heat = 1 }
        assert.truthy(Risk.foodPoisoning(cold, 0) > 0)
        local rotten = { fullType = "Base.PotOfSoup", type = "potofsoup", rotten = true, cooked = true, heat = 1.5 }
        local _, why = Risk.foodPoisoning(rotten, 0)
        assert.equal("rotten", why)
    end)

    it("rejects duplicates and bad rules", function()
        assert.has_error(function() Risk.exemptStale("addonReheated", function() return true end) end)
        assert.has_error(function() Risk.exemptStale("addonNoFn") end)
    end)
end)
