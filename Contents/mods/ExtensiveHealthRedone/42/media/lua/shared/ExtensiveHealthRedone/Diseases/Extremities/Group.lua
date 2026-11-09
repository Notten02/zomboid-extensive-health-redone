-- Disease group: Extremities. The cold and wet injuries of the hands and feet. Server/Extremities reads the socks,
-- shoes, gloves and skin into facts.extremities (Diseases/Extremities/Inputs); the meters live in
-- exposure.data.extremities (Meters), and each condition keeps its affected parts in its scratch (Parts).
-- Conditions/Registry and Systems.lua pick both lists up.
-- Systems: { name, order (310-390 triggers before the engine), update(p, dt, defs) }.

local Blisters = require "ExtensiveHealthRedone/Diseases/Extremities/Blisters"
local TrenchFoot = require "ExtensiveHealthRedone/Diseases/Extremities/TrenchFoot"
local Gangrene = require "ExtensiveHealthRedone/Diseases/Extremities/Gangrene"
local Frostbite = require "ExtensiveHealthRedone/Diseases/Extremities/Frostbite"
local Parts = require "ExtensiveHealthRedone/Diseases/Extremities/Parts"
local Amputation = require "ExtensiveHealthRedone/Wounds/Amputation"

local systems = {}
for _, list in ipairs({ Blisters.systems, TrenchFoot.systems, Frostbite.systems }) do
    for _, system in ipairs(list) do
        systems[#systems + 1] = system
    end
end

-- The Only Cure: a cut hand takes its frostbite and gangrene with it (the last gangrenous part gone cures it).
Amputation.onCut("extremities", function(p, part, known, defs)
    local c = p.state.conditions.active.frostbite
    if c then
        Parts.drop(p, c, part)
    end
    Gangrene.dropPart(p, defs, part, known)
end)

return {
    conditions = {
        foot_blisters = Blisters,
        trench_foot = TrenchFoot,
        gangrene = Gangrene,
        frostbite = Frostbite,
    },
    systems = systems,
}
