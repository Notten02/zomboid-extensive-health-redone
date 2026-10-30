-- Every condition definition, by id. The wound and blood conditions are Data/Conditions timings merged with their
-- behaviour module; the disease groups (Diseases/<Group>/Group.lua) bring complete definitions.

local data = require "ExtensiveHealthRedone/Data/Conditions"
local Groups = require "ExtensiveHealthRedone/Diseases/Groups"

local modules = {
    cellulitis = require "ExtensiveHealthRedone/Conditions/Cellulitis",
    sepsis = require "ExtensiveHealthRedone/Conditions/Sepsis",
    tetanus = require "ExtensiveHealthRedone/Conditions/Tetanus",
    ahtr = require "ExtensiveHealthRedone/Conditions/AHTR",
}

local defs = {}
for id, timing in pairs(data) do
    local def = {}
    for k, v in pairs(timing) do
        def[k] = v
    end
    for k, v in pairs(modules[id] or {}) do
        if type(v) == "function" then
            def[k] = v
        end
    end
    defs[id] = def
end

for _, group in ipairs(Groups) do
    for id, def in pairs(group.conditions) do
        if defs[id] then
            error("condition " .. id .. " is defined twice")
        end
        defs[id] = def
    end
end

return defs
