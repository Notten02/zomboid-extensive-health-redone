-- Wires disease flyers and the Wild Plants guide to the authority (Phase 8; docs/porting/phase8/flyers-knowledge-radio.md
-- section 1). The rules are Knowledge/Learn and the item table Data/Flyers; this file only translates.
-- An MP client loads this file too and stops at the first line.
--
-- Decisions:
--   - Flyers are read with vanilla's ISReadABook like any literature (maintainer default 2026-10-14): vanilla's reading
--     time (pages x MinutesPerPage), its darkness, driving and Illiterate checks, resuming, multi-select, and the
--     script's mood values. v0.9 replaced the action with a client-only one (c/EHR_FlyerHook.lua:321-372) that skipped
--     all of that and never applied the mood values.
--   - Knowledge is decided here, on the authority, from the real item in the finished action: no client command can
--     teach anything (v0.9's UnlockDisease and HerbalSearch/UnlockKnowledge trusted the client).
--   - The recipe guides need nothing here: vanilla teaches their LearnedRecipes.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local FlyerData = require "ExtensiveHealthRedone/Data/Flyers"
local Learn = require "ExtensiveHealthRedone/Knowledge/Learn"
local Knowledge = require "ExtensiveHealthRedone/Conditions/Knowledge"

local log = Env.logger("Flyers")

local Flyers = {}

-- ISReadABook:complete runs on the authority (the server in MP, the game in SP). On a server it also runs, and returns
-- true, for a read that was interrupted (forceStopped); that teaches nothing.
Patches.on("readBookComplete", {
    name = "flyers",
    after = function(results, action)
        local item = action.item
        if results[1] == false or action.forceStopped or not item then
            return
        end
        local fullType = item:getFullType()
        local entry = FlyerData.entry(fullType)
        if not entry then
            return
        end
        local key = Runtime.attach(action.character)
        if not key then
            return
        end
        local outcome = Runtime.applyNow(key, function(p)
            return Learn.read(p, entry)
        end)
        log:info(key, "read", fullType, "->", tostring(outcome))
    end,
})

-- Debug ------------------------------------------------------------------------------------------------------------------

-- forget: clears what flyers and the radio taught (diseases, the Wild Plants guide, broadcasts heard), so they can be
-- tested again. Knox knowledge from the Herald and a profession grant stay.
Runtime.registry:register("debug.knowledge", {
    args = { action = { type = "string", oneOf = { forget = true } } },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local knowledge = p.state.knowledge
            local knox = knowledge.knoxHerald and knowledge.diseases[Knowledge.KNOX] or nil
            knowledge.diseases = { [Knowledge.KNOX] = knox }
            knowledge.wildPlants = false
            knowledge.radioHeard = {}
            p.dirty("knowledge")
        end)
        log:info(ctx.actor.key, "debug: knowledge", args.action)
    end,
})

log:info("flyers loaded")

return Flyers
