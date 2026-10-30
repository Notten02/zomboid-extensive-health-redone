-- Blurred vision for every illness that asks for it (toxin poisoning, dizziness, ...): the server's resolved
-- state.effects.blur (0-1, Core/ClientEffects) drawn with vanilla's foraging "search mode" vignette. Level 1 is a
-- full toxin episode; lower levels scale the blur, desaturation and darkness. It works in MP too: the server decides,
-- the owning client draws from the mirror.
--
-- The search-mode state is captured when blurring starts and restored when it ends. While blurred the values are
-- re-applied every frame, because vanilla's foraging manager writes the same shader.
--
-- Night blindness (state.effects.night, Core/ClientEffects:nightVision) uses the same shader with its own preset (more
-- darkness, less blur), scaled by how dark the character's square is: none at light level LIGHT_CLEAR and above, full
-- at LIGHT_DARK and below. The square's light level is read as a 0-1 value; without a square the
-- climate's daylight strength stands in. The stronger of the two effects is drawn.

local Client = require "ExtensiveHealthRedone/Client/Client"

local Vision = {}

-- { exterior, interior }, clamped to each setting's own range.
Vision.PRESET = {
    radius = { 3.5, 3.0 },
    gradient = { 5.0, 4.5 },
    blur = { 0.62, 0.52 },
    desat = { 0.30, 0.24 },
    darkness = { 0.10, 0.07 },
}
-- Night blindness: the dark closes in rather than blurring.
Vision.NIGHT = {
    radius = { 2.5, 2.0 },
    gradient = { 4.0, 3.5 },
    blur = { 0.25, 0.20 },
    desat = { 0.45, 0.40 },
    darkness = { 0.55, 0.45 },
}
Vision.LIGHT_CLEAR = 0.6
Vision.LIGHT_DARK = 0.1

-- Settings that grow with the level; radius and gradient keep the preset shape.
local SCALED = { blur = true, desat = true, darkness = true }

-- [player index] = captured state while blurred
local saved = {}

local function settings(index)
    local mode = getSearchMode():getSearchModeForPlayer(index)
    return {
        radius = mode:getRadius(),
        gradient = mode:getGradientWidth(),
        blur = mode:getBlur(),
        desat = mode:getDesat(),
        darkness = mode:getDarkness(),
    }
end

local function clamp(setting, value)
    return math.max(setting:getMin(), math.min(setting:getMax(), value))
end

local function capture(index)
    local search = getSearchMode()
    local state = { enabled = search:isEnabled(index), override = search:isOverride(index), values = {} }
    for name, setting in pairs(settings(index)) do
        state.values[name] = { setting:getExterior(), setting:getTargetExterior(), setting:getInterior(),
            setting:getTargetInterior() }
    end
    return state
end

local function apply(index, level, presets)
    local search = getSearchMode()
    search:setEnabled(index, true)
    search:setOverride(index, true)
    for name, setting in pairs(settings(index)) do
        local preset = presets[name]
        local scale = SCALED[name] and level or 1
        local exterior, interior = clamp(setting, preset[1] * scale), clamp(setting, preset[2] * scale)
        setting:set(exterior, exterior, interior, interior)
    end
end

local function restore(index, state)
    local search = getSearchMode()
    for name, setting in pairs(settings(index)) do
        local v = state.values[name]
        setting:set(v[1], v[2], v[3], v[4])
    end
    search:setOverride(index, state.override)
    search:setEnabled(index, state.enabled)
end

-- 0 in the light, 1 in the dark (see the header).
function Vision.darkness(light)
    local share = (Vision.LIGHT_CLEAR - light) / (Vision.LIGHT_CLEAR - Vision.LIGHT_DARK)
    return math.max(0, math.min(1, share))
end

local function lightAt(player)
    local square = player:getCurrentSquare()
    if square then
        return square:getLightLevel(player:getPlayerNum())
    end
    return getClimateManager():getDayLightStrength()
end

function Vision.update(player)
    local index = player:getIndex()
    local effects = Client.section(player, "effects")
    local alive = not player:isDead() and effects ~= nil
    local level = (alive and tonumber(effects.blur)) or 0
    local presets = Vision.PRESET
    local night = (alive and tonumber(effects.night)) or 0
    if night > 0 then
        local nightLevel = night * Vision.darkness(lightAt(player))
        if nightLevel > level then
            level, presets = nightLevel, Vision.NIGHT
        end
    end
    if level > 0 then
        if not saved[index] then
            saved[index] = capture(index)
        end
        apply(index, level, presets)

    elseif saved[index] then
        restore(index, saved[index])
        saved[index] = nil
    end
end

Events.OnTick.Add(function()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then
            Vision.update(player)
        end
    end
end)

return Vision
