-- Wires the immune system (Immunity/Immunity) to the authority: the hygiene facts it reads and a debug command. An
-- MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"

local log = Env.logger("Immunity")

local ServerImmunity = {}

-- Dirt and blood (0-1 each) averaged over every BloodBodyPartType. Per part the worst of the skin and every worn
-- garment covering it counts: the guide names "clothing and body" dirtiness and bloodiness, and B42 puts most
-- blood and dirt on the outermost garment, not the skin.
function ServerImmunity.soil(player)
    local count = BloodBodyPartType.MAX:index()
    if count <= 0 then
        return { dirt = 0, blood = 0 }
    end
    local visual = player:getHumanVisual()
    local dirt, blood = {}, {}
    for i = 0, count - 1 do
        local part = BloodBodyPartType.FromIndex(i)
        dirt[i], blood[i] = visual:getDirt(part), visual:getBlood(part)
    end
    local worn = player:getWornItems()
    for w = 0, worn:size() - 1 do
        local item = worn:get(w):getItem()
        local itemVisual = instanceof(item, "Clothing") and item:getVisual()
        if itemVisual then
            local covered = item:getCoveredParts()
            for c = 0, covered:size() - 1 do
                local part = covered:get(c)
                local i = part:index()
                dirt[i] = math.max(dirt[i] or 0, itemVisual:getDirt(part))
                blood[i] = math.max(blood[i] or 0, itemVisual:getBlood(part))
            end
        end
    end
    local totalDirt, totalBlood = 0, 0
    for i = 0, count - 1 do
        totalDirt, totalBlood = totalDirt + dirt[i], totalBlood + blood[i]
    end
    return { dirt = totalDirt / count, blood = totalBlood / count }
end

Facts.extend("hygiene", function(player, facts)
    facts.hygiene = ServerImmunity.soil(player)
end)

-- Debug ------------------------------------------------------------------------------------------------------------

Runtime.registry:register("debug.immunity", {
    args = {
        score = { type = "number", min = 0, max = 100, optional = true },
    },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        Runtime.applyNow(ctx.actor.key, function(p)
            local im = p.state.immunity
            if args.score then
                im.score = args.score
            end
            im.tick = 0     -- recompute on the next step
            p.dirty("immunity")
        end)
        log:info(ctx.actor.key, "debug: immunity", tostring(args.score))
    end,
})

log:info("immunity loaded")

return ServerImmunity
