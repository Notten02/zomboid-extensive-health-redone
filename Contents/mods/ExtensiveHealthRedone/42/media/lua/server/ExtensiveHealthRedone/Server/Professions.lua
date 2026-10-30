-- Wires the EHR professions to the authority: the profession facts reader and the knowledge-grant system. The rule is
-- Data/Professions.grantKnowledge; this file only translates.
--
-- The grant is decided here, on the authority, every simulation step (idempotent: it writes once, then nothing), so a
-- character created before the mod was added, or on a dedicated server where OnCreatePlayer never fires, gets it
-- too. Everything else the professions give comes from the scripts: levels, the Scalpel Master trait
-- (Server/Scalpel) and the 24 recipes (GrantedRecipes).
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local Data = require "ExtensiveHealthRedone/Data/Professions"

local log = Env.logger("Professions")

local ServerProfessions = {}

-- The character's profession id when it is one of ours ("ehrdoctor", "ehrsurgeon"), else nil. Compared by registry
-- token (media/registries.lua), as vanilla does on the server (VehicleUtils.testProfession); getName() is not used,
-- its value for a modded profession is uncertain.
function ServerProfessions.of(player)
    local tokens = EHRCharacterProfessions
    if not tokens then
        return nil
    end
    local desc = player:getDescriptor()
    if not desc then
        return nil
    end
    for _, id in ipairs(Data.IDS) do
        local token = tokens[id]
        if token and desc:isCharacterProfession(token) then
            return id
        end
    end
    return nil
end

Facts.extend("profession", function(player, facts)
    facts.profession = ServerProfessions.of(player)
end)

-- Early, before anything that reads knowledge in the same step.
Runtime.sim:add({
    name = "professionKnowledge",
    order = 50,
    update = function(p)
        if Data.grantKnowledge(p.state, p.facts.profession) then
            p.dirty("knowledge")
            log:info(p.key, "granted", p.facts.profession, "disease knowledge")
        end
    end,
})

-- Debug --------------------------------------------------------------------------------------------------------------

-- reset: forget the grant (and blood_types), so the next step grants it again to an EHR profession;
-- doctor: grant as an EHR Doctor whatever the profession (to look at the monitor and handbook with full knowledge).
Runtime.registry:register("debug.professionKnowledge", {
    args = { action = { type = "string", oneOf = { reset = true, doctor = true } } },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local knowledge = p.state.knowledge
            if args.action == "reset" then
                knowledge.professionGrant = nil
                for _, id in ipairs(Data.GRANT_KNOWLEDGE) do
                    knowledge.diseases[id] = nil
                end
            else
                Data.grantKnowledge(p.state, "ehrdoctor")
            end
            p.dirty("knowledge")
        end)
        log:info(ctx.actor.key, "debug: profession knowledge", args.action)
    end,
})

log:info("professions loaded")

return ServerProfessions
