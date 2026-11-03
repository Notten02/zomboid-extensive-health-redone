-- Visible blood and dirt for the food and washing rules (Diseases/Food): what touches the food at a bite, and what
-- "Wash Hands" cleans. Read on the authority for the rules and on the client for the menu and the action length.
--
-- Without The Only Cure (or before its data is ready) both are what they always were: both hands, and the hands and
-- arms. With it (Game/OnlyCure, Wounds/Amputation):
--   * the eating surface: each side's hand, or the prosthesis worn there, averaged over the ones there are; with
--     neither on either side the character eats face first, and the head counts.
--   * washing: the parts still there and the prostheses worn ("Prosthesis_L" / "Prosthesis_R"); with no hand or
--     prosthesis left, the face ("Head") instead: mode "face".

local Washing = require "ExtensiveHealthRedone/Diseases/Food/Washing"
local Amputation = require "ExtensiveHealthRedone/Wounds/Amputation"
local OnlyCure = require "ExtensiveHealthRedone/Game/OnlyCure"

local BodySoil = {}

local function skin(visual, name)
    local part = BloodBodyPartType[name]
    return { blood = visual:getBlood(part), dirt = visual:getDirt(part) }
end

-- A garment's worst blood and dirt over the parts it covers (as Server/Immunity reads clothing).
function BodySoil.clothing(item)
    local soil = { blood = 0, dirt = 0 }
    local visual = item and item:getVisual()
    if not visual then
        return soil
    end
    local covered = item:getCoveredParts()
    for i = 0, covered:size() - 1 do
        local part = covered:get(i)
        soil.blood = math.max(soil.blood, visual:getBlood(part))
        soil.dirt = math.max(soil.dirt, visual:getDirt(part))
    end
    return soil
end

-- What touches the food: { blood = 0-1, dirt = 0-1 }.
function BodySoil.hands(player)
    local visual = player:getHumanVisual()
    local toc = OnlyCure.read(player)
    if not toc then
        local blood = (visual:getBlood(BloodBodyPartType.Hand_L) + visual:getBlood(BloodBodyPartType.Hand_R)) / 2
        local dirt = (visual:getDirt(BloodBodyPartType.Hand_L) + visual:getDirt(BloodBodyPartType.Hand_R)) / 2
        return { blood = blood, dirt = dirt }
    end
    local surfaces = {}
    for _, side in ipairs(Amputation.SIDES) do
        local hand = Amputation.hand(toc, side)
        if hand == "hand" then
            surfaces[#surfaces + 1] = skin(visual, "Hand_" .. side)
        elseif hand == "prosthesis" then
            surfaces[#surfaces + 1] = BodySoil.clothing(OnlyCure.prosthesis(player, side))
        end
    end
    if #surfaces == 0 then
        surfaces[1] = skin(visual, "Head")
    end
    return Washing.average(surfaces)
end

-- What washing cleans: soil { [part] = { blood, dirt } } for Washing.plan, and the mode, "hands" or "face".
function BodySoil.wash(player)
    local visual = player:getHumanVisual()
    local toc = OnlyCure.read(player)
    local soil = {}
    if not toc then
        for _, name in ipairs(Washing.PARTS) do
            soil[name] = skin(visual, name)
        end
        return soil, "hands"
    end
    if Amputation.noHands(toc) then
        soil.Head = skin(visual, "Head")
        return soil, "face"
    end
    local missing = Amputation.missing(toc)
    for _, name in ipairs(Washing.PARTS) do
        if not missing[name] then
            soil[name] = skin(visual, name)
        end
    end
    for _, side in ipairs(Amputation.SIDES) do
        if Amputation.hand(toc, side) == "prosthesis" then
            local item = OnlyCure.prosthesis(player, side)
            if item then
                soil["Prosthesis_" .. side] = BodySoil.clothing(item)
            end
        end
    end
    return soil, "hands"
end

return BodySoil
