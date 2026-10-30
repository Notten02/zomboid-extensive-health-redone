-- Wires Knox to the authority: the Knox facts reader, the four item commands, the Kentucky Herald hook,
-- the Patient Zero trait grant and debug commands. The rules are Diseases/Knox; this file only translates.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Items = require "ExtensiveHealthRedone/Server/Items"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local Data = require "ExtensiveHealthRedone/Diseases/Knox/Data"
local Knox = require "ExtensiveHealthRedone/Diseases/Knox/Knox"
local KnoxItems = require "ExtensiveHealthRedone/Diseases/Knox/Items"
local Vaccine = require "ExtensiveHealthRedone/Game/ZVirusVaccine"

local log = Env.logger("Knox")

local ServerKnox = {}

ServerKnox.ITEMS = {
    geneTherapy = "ExtensiveHealth.GeneTherapyKit",
    antibodyTest = "ExtensiveHealth.AntibodyTestKit",
    immunobooster = "ExtensiveHealth.ImmunoboosterShot",
    phalanx = "ExtensiveHealth.PhalanxPills",
}

-- The Patient Zero trait token from media/registries.lua.
local function traitToken()
    return EHRCharacterTraits and EHRCharacterTraits.patientzero or nil
end

-- Facts ----------------------------------------------------------------------------------------------------------------

local function share(stats, stat)
    if not stat then
        return 0
    end
    local min, max = stat:getMinimumValue(), stat:getMaximumValue()
    if max <= min then
        return 0
    end
    return math.max(0, math.min(1, (stats:get(stat) - min) / (max - min)))
end

Facts.extend("knox", function(player, facts)
    local damage = player:getBodyDamage()
    local stats = player:getStats()
    local list = damage:getBodyParts()
    local partInfected, bitten = false, false
    for i = 0, list:size() - 1 do
        local part = list:get(i)
        partInfected = partInfected or part:IsInfected()
        bitten = bitten or part:bitten()
    end
    local infected = damage:IsInfected()
    local timerProgress
    local started, duration = damage:getInfectionTime(), damage:getInfectionMortalityDuration()
    if infected and started >= 0 and duration > 0 then
        -- Vanilla stamps the infection with the character's hours survived (not the world age, which differs after a
        -- death or in a world a character joined late); Antibodies and Zombie Virus Vaccine read it the same way.
        local now = player:getHoursSurvived()
        timerProgress = math.max(0, math.min(1, (now - started) / duration))
    end
    local token = traitToken()
    facts.knox = {
        infected = infected,
        partInfected = partInfected,
        bitten = bitten,
        level = share(stats, CharacterStat.ZOMBIE_INFECTION),
        fever = share(stats, CharacterStat.ZOMBIE_FEVER),
        timerProgress = timerProgress,
        hasTrait = token ~= nil and player:hasTrait(token),
        -- Zombie Virus Vaccine delays the infection through its timers (Server/ZVirusVaccine).
        followTimer = Vaccine.active() or nil,
    }
end)

-- Patient Zero trait ---------------------------------------------------------------------------------------------------

-- Adds the trait to an immune gene-therapy survivor (unless the sandbox disables it) and syncs it to the client.
function ServerKnox.grantTrait(player, key)
    local state = Runtime.store:get(key)
    local token = traitToken()
    if not state or not token or Env.sandbox("PatientZeroTraitDisabled", false) == true then
        return false
    end
    if not player:hasTrait(token) then
        player:getCharacterTraits():add(token)
        if isServer() then
            -- vanilla's PF_Recipes + PF_Traits + PF_AlreadyReadBook (ISReadABook:complete)
            sendSyncPlayerFields(player, 0x00000007)
        end
        log:info(key, "granted the Patient Zero trait")
    end
    state.knox.immunityTraitGranted = true
    Runtime.store:markDirty(key, "knox")
    return true
end

-- Items ------------------------------------------------------------------------------------------------------------------

-- Registers one item command: the rules run on the actor (Knox items are used on yourself), then the item is used up
-- as the rules say. Phalanx is a 3-dose drainable; the others are single items. Only Actions/Knox's EHRKnoxAction
-- runs it, when its time is up (`action = true`).
local function itemCommand(name, fullType, rule, after)
    Runtime.registry:register("knox." .. name, {
        args = { item = { type = "item", types = { [fullType] = true } } },
        action = true,
        rate = { count = 2, seconds = 5 },
        handler = function(ctx, args)
            local key = ctx.actor.key
            local result = Runtime.applyNow(key, rule)
            if not result then
                return
            end
            if result.consume > 0 then
                Items.useOne(args.item.item)
            end
            log:debug(key, "used", fullType, "->", result.outcome, result.chance and ("chance " .. result.chance) or "")
            if after then
                after(ctx, result)
            end
        end,
    })
end

itemCommand("geneTherapy", ServerKnox.ITEMS.geneTherapy, KnoxItems.geneTherapy, function(ctx, result)
    if result.grantTrait then
        ServerKnox.grantTrait(ctx.actor.player, ctx.actor.key)
    end
end)
itemCommand("antibodyTest", ServerKnox.ITEMS.antibodyTest, KnoxItems.antibodyTest)
itemCommand("immunobooster", ServerKnox.ITEMS.immunobooster, KnoxItems.immunobooster)
itemCommand("phalanx", ServerKnox.ITEMS.phalanx, KnoxItems.phalanx)

-- Kentucky Herald --------------------------------------------------------------------------------------------------------

local function learn(key)
    return Runtime.applyNow(key, function(p)
        if Knox.learnFromHerald(p) then
            p.say("UI_EHR_Knox_HeraldLearned")
            return true
        end
        return false
    end)
end

-- ISReadABook:complete runs on the authority and records the print media read. Only this, never a client message,
-- unlocks Knox knowledge.
Patches.on("readBookComplete", {
    name = "knoxHerald",
    after = function(results, action)
        local item = action.item
        -- On a server vanilla's complete returns true for an interrupted read too; forceStopped tells them apart.
        if results[1] == false or action.forceStopped or not item or not item:hasModData() then
            return
        end
        local media = item:getModData().printMedia
        if not media then
            return
        end
        local id, title = media.id, media.title
        log:debug("print media read:", tostring(id), tostring(title))
        if Knox.isHerald(id) or Knox.isHerald(title) then
            local key = Runtime.attach(action.character)
            if key and learn(key) then
                log:info(key, "read the Kentucky Herald (", tostring(id), ") - Knox knowledge unlocked")
            end
        end
    end,
})

-- A character who read the issue before (vanilla remembers print media read) learns it too.
local function readHeraldBefore(player)
    for _, id in ipairs(Data.HERALD_IDS) do
        if player:isPrintMediaRead(id) then
            return id
        end
    end
    return nil
end

-- Every 10 game minutes: the trait for survivors still missing it, and the Herald read before.
Runtime.scheduler:every("knox", 10, function()
    for _, key in ipairs(Runtime.store:keys()) do
        local player = Runtime.playerFor(key)
        local state = Runtime.store:get(key)
        if player and state then
            local knox = state.knox
            if knox.geneTherapyImmune and not knox.immunityTraitGranted and not knox.patientZeroTraitSource then
                ServerKnox.grantTrait(player, key)
            end
            if not state.knowledge.knoxHerald then
                local id = readHeraldBefore(player)
                if id and learn(key) then
                    log:info(key, "had read the Kentucky Herald (", id, ") - Knox knowledge unlocked")
                end
            end
        end
    end
end, { coalesce = true })

-- Debug --------------------------------------------------------------------------------------------------------------------

Runtime.registry:register("debug.knox", {
    args = {
        action = { type = "string", oneOf = { immune = true, mortal = true, booster = true, expire = true,
            herald = true, resetPhalanx = true } },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local knox = p.state.knox
            if args.action == "immune" then
                knox.geneTherapyImmune = true
            elseif args.action == "mortal" then
                knox.geneTherapyImmune, knox.patientZeroTraitSource, knox.immunityTraitGranted = false, false, false
            elseif args.action == "booster" then
                knox.boosterLeft, knox.boosterCooldown = Data.BOOSTER_MINUTES, Data.BOOSTER_COOLDOWN_MINUTES
            elseif args.action == "expire" then
                knox.boosterLeft, knox.boosterCooldown, knox.effects = 0, 0, {}
            elseif args.action == "herald" then
                Knox.learnFromHerald(p)
            elseif args.action == "resetPhalanx" then
                knox.phalanxUses = 0
            end
            p.dirty("knox")
        end)
        log:info(ctx.actor.key, "debug: knox", args.action)
    end,
})

log:info("knox loaded")

return ServerKnox
