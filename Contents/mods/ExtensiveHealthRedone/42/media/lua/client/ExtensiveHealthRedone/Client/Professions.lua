-- Character creation: EHR Doctor and EHR Surgeon start in their own outfits (Data/Professions.OUTFITS; maintainer
-- decisions 2026-10-14 and 2026-10-20: a lab coat for both, scrubs for the surgeon). Cosmetic only.
--
-- Vanilla dresses a profession from ClothingSelectionDefinitions[desc:getCharacterProfession():getName()]
-- (CharacterCreationMain.lua:1344, :1861; the table is defined in shared/Definitions). What getName() returns for a
-- modded profession is not documented (another B42 mod keys "rlp:labintern" as "labintern"), so each outfit is put
-- under every name it could be: our id, getName(), toString(), and the registered id as written and lower-cased.
-- An outfit another mod already set for one of these names is kept. Applied at load and again at OnGameBoot, in case vanilla's definitions load after us.

local Data = require "ExtensiveHealthRedone/Data/Professions"

local ClientProfessions = {}

-- The registered ids (media/registries.lua).
ClientProfessions.REGISTERED = { ehrdoctor = "ExtensiveHealth:ehrdoctor", ehrsurgeon = "ExtensiveHealth:ehrsurgeon" }

local function names(id)
    local list, seen = {}, {}
    local function add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    add(id)
    local token = EHRCharacterProfessions and EHRCharacterProfessions[id]
    if token then
        add(token:getName())
        add(tostring(token))    -- a Java object's toString()
    end
    local registered = ClientProfessions.REGISTERED[id]
    if registered then
        add(registered)
        add(registered:lower())
    end
    return list
end

-- Returns how many names were set.
function ClientProfessions.installOutfits()
    local defs = ClothingSelectionDefinitions
    if type(defs) ~= "table" then
        return 0
    end
    local count = 0
    for _, id in ipairs(Data.IDS) do
        local outfit = Data.OUTFITS[id]
        for _, name in ipairs(names(id)) do
            if defs[name] == nil then
                defs[name] = outfit
                count = count + 1
            end
        end
    end
    return count
end

ClientProfessions.installOutfits()
Events.OnGameBoot.Add(ClientProfessions.installOutfits)

return ClientProfessions
