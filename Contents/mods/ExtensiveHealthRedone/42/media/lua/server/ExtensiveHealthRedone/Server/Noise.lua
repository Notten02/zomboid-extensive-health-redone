-- Plays the sounds illness makes (Data/Noise): the voice sound on the character, heard by everyone near, and the world
-- noise that draws zombies. Runs on the authority: Server/Runtime hands it the p.noise requests of a step.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Data = require "ExtensiveHealthRedone/Data/Noise"

local log = Env.logger("Noise")

local Noise = {}

-- Adds a sound kind for p.noise from an add-on mod: def has the Data/Noise fields (male, female, radius, volume,
-- optional audioOption, which may name the add-on's own option as "Namespace.Option", and muffled). Errors on a known
-- kind. Call it from the add-on's server code.
function Noise.register(kind, def)
    if type(kind) ~= "string" or Data[kind] then
        error("noise " .. tostring(kind) .. " is already registered", 2)
    end
    if type(def) ~= "table" or type(def.male) ~= "string" or type(def.female) ~= "string"
        or type(def.radius) ~= "number" or type(def.volume) ~= "number" then
        error("noise " .. kind .. " needs male, female, radius and volume", 2)
    end
    Data[kind] = def
end


-- A held item that muffles a sneeze or cough (vanilla Tissue, ToiletPaper, PaperNapkins2), or nil.
local function muffler(player)
    for _, item in ipairs({ player:getPrimaryHandItem(), player:getSecondaryHandItem() }) do
        if item and item:hasTag(ItemTag.MUFFLE_SNEEZE) and item:getCurrentUses() > 0 then
            return item
        end
    end
    return nil
end

local function play(player, sound)
    if isServer() then
        sendPlaySound(sound, false, player)
    else
        player:playSound(sound)
    end
end

-- kind: a Data/Noise entry. args.muffle = false skips the tissue check (a scream can't be muffled); args.radius and
-- args.volume override the entry's world noise (pain cries scale with ZombieAttractionRadius).
function Noise.emit(player, kind, args)
    local def = Data[kind]
    if not def then
        log:warn("unknown noise", kind)
        return
    end
    local radius = args and tonumber(args.radius) or def.radius
    local volume = args and tonumber(args.volume) or def.volume
    local male, female = def.male, def.female
    local tissue = def.muffled and (args == nil or args.muffle ~= false) and muffler(player)
    if tissue then
        radius, volume = def.muffled.radius, def.muffled.volume
        male, female = def.muffled.male, def.muffled.female
        tissue:UseAndSync()
    end
    if not def.audioOption or Env.sandbox(def.audioOption, true) ~= false then
        play(player, player:isFemale() and female or male)
    end
    if radius > 0 then
        player:addWorldSoundUnlessInvisible(radius, volume, true)
    end
end

return Noise
