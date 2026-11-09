---@diagnostic disable: undefined-global
-- E2E (dev only), client side: wears clothing with vanilla's action, and reports the mirrored trench foot and its
-- Monitor row.
require "PZE2E/PZE2E"

local Client = require "ExtensiveHealthRedone/Client/Client"
local Monitor = require "ExtensiveHealthRedone/UI/Monitor"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"

PZE2E.answer("wear", function(args)
    local player = getPlayer()
    local inv = player:getInventory()
    local queued = {}
    for _, t in ipairs(args.types) do
        local item = inv:getFirstTypeRecurse(t)
        if item then
            ISTimedActionQueue.add(ISWearClothing:new(player, item))
            queued[#queued + 1] = t
        end
    end
    return { queued = queued }
end)

local SECTIONS = { "identity", "knowledge", "blood", "body", "wounds", "conditions", "exposure", "meds", "knox" }

PZE2E.answer("mirror", function()
    local player = getPlayer()
    local s = {}
    for _, name in ipairs(SECTIONS) do
        s[name] = Client.section(player, name)
    end
    local c = s.conditions and s.conditions.active and s.conditions.active.trench_foot
    local feet = 0
    for _, entry in pairs(c and c.data and c.data.parts or {}) do
        if entry.stage == 1 then
            feet = feet + 1
        end
    end
    local model = Monitor.build({ state = s, firstAid = 0, defs = defs,
        sandbox = function(_, default) return default end })
    local row
    for _, r in ipairs(model.conditions) do
        if r.id == "trench_foot" then
            row = r
        end
    end
    return {
        stage = c and c.stage or 0,
        feet = feet / 2,
        exposure = s.exposure and s.exposure.feet or -1,
        name = row and row.name and row.name.key or "none",
        description = row and row.description and row.description.key or "none",
    }
end)
