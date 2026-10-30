-- The companion panel docked beside Mini Health Panel: blood, infected wounds, sepsis and the worst illness at a
-- glance. Pure view model, built from the mirrored state with what the reader knows, like the Monitor (UI/Monitor),
-- so it never tells more than the Monitor does.
--
--   MiniHealth.build({ state = mirror sections, firstAid = 0-10, defs = Conditions/Registry, watch = true when a
--                      powered Medical Monitor Watch is worn, sandbox = function(name, default) })
--   -> { rows = { { label = key, value = Text, color = colour name } x4 } }
--
-- Blood needs the watch (as in the Monitor; sandbox MedicalWatchRequired off lifts that). Infected wounds are counted
-- from the wound model, which vanilla's own health panel shows too. Sepsis and the illness show a stage only to a
-- reader who can tell stages (First Aid), else "?"; nothing active shows "--".

local Text = require "ExtensiveHealthRedone/UI/Text"
local Knowledge = require "ExtensiveHealthRedone/Conditions/Knowledge"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local MiniHealth = {}

-- Blood colour by share of full volume: above 70 green, 50 yellow, 30 orange, else red.
MiniHealth.BLOOD = { { 70, "green" }, { 50, "yellow" }, { 30, "orange" }, { 0, "red" } }

local NONE = "--"
local SEPSIS = "sepsis"

local function bloodRow(input)
    local b = input.state.blood or {}
    local visible = input.watch == true or input.sandbox("MedicalWatchRequired", true) == false
    if not visible then
        return { label = "UI_EHR_Mini_Blood", value = Text.raw("?"), color = "dim" }
    end
    local max = tonumber(b.max) or 0
    local percent = max > 0 and math.max(0, math.min(100, (tonumber(b.volume) or max) / max * 100)) or 0
    local color = "red"
    for _, step in ipairs(MiniHealth.BLOOD) do
        if percent > step[1] then
            color = step[2]
            break
        end
    end
    return { label = "UI_EHR_Mini_Blood", value = Text.percent(percent), color = color }
end

local function infectedRow(input)
    local count = 0
    local parts = input.state.wounds and input.state.wounds.parts or {}
    for _, name in ipairs(Tables.sortedKeys(parts)) do
        if parts[name].phase == "infected" then
            count = count + 1
        end
    end
    return { label = "UI_EHR_Mini_Infection", value = Text.raw(count), color = count > 0 and "orange" or "dim" }
end

-- The stage text of an active condition for this reader: a stage word, or "?".
local function stageValue(input, id, c, prefix)
    local def = input.defs[id]
    local known = def and Knowledge.of(input.state, def, input.firstAid) or { stage = false }
    if known.stage then
        return Text.key(prefix .. math.max(1, math.min(4, c.stage)))
    end
    return Text.raw("?")
end

local function sepsisRow(input)
    local c = input.state.conditions and input.state.conditions.active and input.state.conditions.active[SEPSIS]
    if not c then
        return { label = "UI_EHR_Mini_Sepsis", value = Text.raw(NONE), color = "dim" }
    end
    return { label = "UI_EHR_Mini_Sepsis", value = stageValue(input, SEPSIS, c, "UI_EHR_Mini_SepsisStage_"), color = "red" }
end

-- The worst stage among the other active conditions the reader can place; "?" when there are some but none placeable.
local function diseaseRow(input)
    local active = input.state.conditions and input.state.conditions.active or {}
    local worstId, worst
    local any = false
    for _, id in ipairs(Tables.sortedKeys(active)) do
        if id ~= SEPSIS and input.defs[id] then
            any = true
            local known = Knowledge.of(input.state, input.defs[id], input.firstAid)
            if known.stage and (not worst or active[id].stage > worst.stage) then
                worstId, worst = id, active[id]
            end
        end
    end
    if not any then
        return { label = "UI_EHR_Mini_Disease", value = Text.raw(NONE), color = "dim" }
    end
    if not worst then
        return { label = "UI_EHR_Mini_Disease", value = Text.raw("?"), color = "yellow" }
    end
    return { label = "UI_EHR_Mini_Disease", value = stageValue(input, worstId, worst, "UI_EHR_Mini_DiseaseStage_"),
        color = "yellow" }
end

function MiniHealth.build(input)
    return { rows = { bloodRow(input), infectedRow(input), sepsisRow(input), diseaseRow(input) } }
end

-- Where the companion goes beside the host panel: to its right, or to its left when that would leave the screen.
-- Returns x, y, dockedRight.
function MiniHealth.dock(host, panelWidth, screenWidth, gap)
    local right = host.x + host.width
    if right + gap + panelWidth > screenWidth then
        return host.x - panelWidth - gap, host.y, false
    end
    return right + gap, host.y, true
end

return MiniHealth
