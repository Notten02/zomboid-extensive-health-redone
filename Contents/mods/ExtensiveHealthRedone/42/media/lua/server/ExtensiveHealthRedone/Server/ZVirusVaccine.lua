-- Zombie Virus Vaccine (B42 port by rEXX, Workshop 3615135168) beside us. Its Knox cure, delay and accidental infection
-- need nothing from us: they write vanilla's infection and our knox_infection display mirrors vanilla. Three ties (all
-- server side, only while the mod is on; docs/porting/phase10/zombie-virus-vaccine.md):
--   * its syringe blood draw costs blood (Transfusion.sample) and stamps the drawer's blood type on the sample;
--   * a finished Knox blood test of it (positive or negative) teaches Knox knowledge (Knox.learnFromBloodTest);
--   * Knox progress follows the infection timers while it is on (Knox.progress, set in Server/Knox facts).
-- The vaccine mod exposes plain module tables; its own OnClientCommand handler reads their fields at call time, so wrapping
-- a field here works whichever mod loads first. A change to its module names or return values is logged and skipped.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Vaccine = require "ExtensiveHealthRedone/Game/ZVirusVaccine"
local BloodData = require "ExtensiveHealthRedone/Data/Blood"
local Transfusion = require "ExtensiveHealthRedone/Blood/Transfusion"
local Knox = require "ExtensiveHealthRedone/Diseases/Knox/Knox"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"

local log = Env.logger("ZVirusVaccine")

local ServerVaccine = {}

ServerVaccine.COLLECT_MODULE = "HealthSystem/LabCollectBloodLogic_Server"
ServerVaccine.TEST_MODULE = "HealthSystem/BloodTestLogic_Server"
-- The blood sample syringes its draw hands out (Lab_Collect: LabItems.CmpSyringe[Reusable]WithBlood).
ServerVaccine.SAMPLES = {
    ["LabItems.CmpSyringeWithBlood"] = true,
    ["LabItems.CmpSyringeReusableWithBlood"] = true,
}

local function sampleIds(player)
    local ids = {}
    for _, item in ipairs(Items.findAll(player, ServerVaccine.SAMPLES)) do
        ids[item:getID()] = true
    end
    return ids
end

local function notice(player, key)
    Transport.toClient(player, "notice", { key = key, owner = PlayerKey.of(player) })
end

-- The draw: refused (the vaccine mod's code never runs, so the syringe stays) when the character has too little blood;
-- otherwise it runs, and each new sample syringe costs blood and carries the drawer's blood type.
function ServerVaccine.wrapCollect(logic)
    local original = logic.ProcessCollection
    logic.ProcessCollection = function(player, ...)
        local key = Runtime.attach(player)
        local state = key and Runtime.store:get(key)
        if not state then
            return original(player, ...)
        end
        local refusal = Transfusion.sampleRefusal(state)
        if refusal then
            notice(player, refusal)
            log:info(key, "refused a blood sample:", refusal)
            return nil
        end
        local before = sampleIds(player)
        local result = original(player, ...)
        local drawn = 0
        for _, item in ipairs(Items.findAll(player, ServerVaccine.SAMPLES)) do
            if not before[item:getID()] then
                drawn = drawn + 1
                item:getModData()[BloodData.DONOR_KEY] = state.identity.bloodType
                Items.syncModData(player, item)
            end
        end
        if drawn > 0 then
            for _ = 1, drawn do
                Runtime.applyNow(key, Transfusion.sample)
            end
            log:info(key, "gave a blood sample,", drawn * BloodData.SAMPLE_ML, "mL")
        end
        return result
    end
end

-- The Knox blood test: a result (not an unusable sample) teaches the character what the virus is.
function ServerVaccine.wrapTest(logic)
    local original = logic.ProcessTest
    logic.ProcessTest = function(player, ...)
        local result = original(player, ...)
        if result == "Positive" or result == "Negative" then
            local key = Runtime.attach(player)
            if key then
                Runtime.applyNow(key, function(p)
                    if Knox.learnFromBloodTest(p) then
                        p.client("knowledgeLearned", { name = "UI_EHR_Disease_Knox_Infection" })
                        log:info(key, "learned about Knox from a blood test:", result)
                    end
                end)
            end
        end
        return result
    end
end

local WRAPS = {
    { module = ServerVaccine.COLLECT_MODULE, field = "ProcessCollection", wrap = ServerVaccine.wrapCollect },
    { module = ServerVaccine.TEST_MODULE, field = "ProcessTest", wrap = ServerVaccine.wrapTest },
}

local installed = false

-- Wraps the two vaccine functions, once, when the mod is on. A pcall at the boundary to an optional mod (its modules or
-- fields may change under us), logged.
function ServerVaccine.install()
    if installed or not Vaccine.active() then
        return false
    end
    installed = true
    for _, w in ipairs(WRAPS) do
        local ok, logic = pcall(require, w.module)
        if ok and type(logic) == "table" and type(logic[w.field]) == "function" then
            w.wrap(logic)
            log:info("wrapped", w.module .. "." .. w.field)
        else
            log:warn("Zombie Virus Vaccine's", w.module, w.field, "not found; its", w.field, "is left alone:",
                tostring(logic))
        end
    end
    return true
end

-- Forgets the install (tests, and a new game in the same session).
function ServerVaccine.reset()
    installed = false
    Vaccine.reset()
end

Events.OnGameStart.Add(ServerVaccine.install)
Events.OnServerStarted.Add(ServerVaccine.install)

return ServerVaccine
