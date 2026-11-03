-- The Only Cure in the facts, on the authority: facts.toc (Game/OnlyCure's snapshot, for Wounds/Amputation),
-- facts.missing, a cut part read as missing and unwounded (so no system starts anything on it), and the part under a
-- fresh stump read as wounded (Wounds/Infection keeps an incubation there going while the stump is open). Without the
-- mod, or before its data is ready, the facts stay as they are.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Facts = require "ExtensiveHealthRedone/Server/Facts"
local OnlyCure = require "ExtensiveHealthRedone/Game/OnlyCure"
local Amputation = require "ExtensiveHealthRedone/Wounds/Amputation"

local ServerOnlyCure = {}

-- What a cut part reads as.
local function missingPart()
    return {
        missing = true, health = 100, bleeding = false, bandaged = false, bandageDirty = false, deep = false,
        glass = false, bullet = false, cut = false, bite = false, scratch = false, burn = false, stitched = false,
        infected = false, wound = false, fracture = false,
        scratchTime = 0, cutTime = 0, deepTime = 0, burnTime = 0, fractureTime = 0,
    }
end

function ServerOnlyCure.apply(toc, facts)
    facts.toc = toc
    facts.missing = Amputation.missing(toc)
    for _, name in ipairs(Amputation.LIMBS) do
        if facts.missing[name] then
            facts.parts[name] = missingPart()
        end
    end
    for _, stump in ipairs(Amputation.stumps(toc)) do
        local part = facts.parts[stump.part]
        if part and not (stump.healed or stump.cauterized) then
            part.stump = stump.limb
            part.wound = true
        end
    end
end

Facts.extend("toc", function(player, facts)
    local toc = OnlyCure.read(player)
    if toc then
        ServerOnlyCure.apply(toc, facts)
    end
end)

return ServerOnlyCure
