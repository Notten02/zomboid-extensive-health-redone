-- Our lines under the vanilla tooltip of EHR items (docs/porting/phase7/tooltips-moodles-watch.md, Part A, option B).
-- Vanilla keeps drawing its whole tooltip (condition, weight, uses and freshness bars, other mods' lines), so nothing
-- is lost the way v0.9's replacement tooltip lost it.
--
-- How: the tooltipInvRender patch point (ISToolTipInv.render). Before vanilla's render, the panel's item is swapped
-- for a stand-in whose DoTooltip calls the real item's DoTooltip and then appends our lines through the tooltip's
-- layout API; after the render the real item is put back. Every other field and method of the stand-in forwards to
-- the real item. If a render ever throws between the two, the next render finds the stale stand-in and unwraps it.
--
--   ItemTooltip.addProvider(function(item, player) return lines or nil end)
-- Lines have the UI/ItemInfo shape: { label = Text, value = Text?, color = Draw colour, progress = 0-1?, wrap = bool? }.
-- The built-in provider is UI/ItemInfo for our medication, supplies, blood bags and Knox items.

require "ISUI/ISToolTipInv"

local Env = require "ExtensiveHealthRedone/Game/Env"
local Patches = require "ExtensiveHealthRedone/Game/Patches"
local BloodData = require "ExtensiveHealthRedone/Data/Blood"
local Spoilage = require "ExtensiveHealthRedone/Blood/Spoilage"
local ItemInfo = require "ExtensiveHealthRedone/UI/ItemInfo"
local Client = require "ExtensiveHealthRedone/Client/Client"
local Text = require "ExtensiveHealthRedone/Client/Text"
local Draw = require "ExtensiveHealthRedone/Client/Draw"

local log = Env.logger("ItemTooltip")

local ItemTooltip = {}

-- Width our wrapped text may take, at least (the vanilla tooltip may be narrower or wider).
ItemTooltip.WRAP_WIDTH = 260
ItemTooltip.PAD = 5

local providers = {}

function ItemTooltip.addProvider(fn)
    providers[#providers + 1] = fn
end

-- Translated keys, cached: ItemInfo asks for the authored keys an item has.
local known = {}
local function has(key)
    local k = known[key]
    if k == nil then
        k = getTextOrNull(key) ~= nil
        known[key] = k
    end
    return k
end

-- The player reading the tooltip: the tooltip's character, else the player carrying the item, else the only local
-- player. In split screen without either, nobody (knowledge-gated lines then read as unknown).
function ItemTooltip.reader(tooltip, item)
    local character = tooltip and tooltip:getCharacter()
    if character and instanceof(character, "IsoPlayer") then
        return character
    end
    local container = item:getOutermostContainer()
    local owner = container and container:getCharacter()
    if owner and instanceof(owner, "IsoPlayer") then
        return owner
    end
    if getNumActivePlayers() == 1 then
        return getSpecificPlayer(0)
    end
    return nil
end

local function itemContext(item, player)
    local ctx = { has = has, sandbox = Env.sandbox, firstAid = 0 }
    if player then
        ctx.firstAid = player:getPerkLevel(Perks.Doctor)
        ctx.knowledge = Client.section(player, "knowledge")
        local identity = Client.section(player, "identity")
        ctx.bloodType = identity and identity.bloodType
    end
    local fullType = item:getFullType()
    if ItemInfo.OTHER[fullType] == "bag" then
        local frozen = instanceof(item, "Food") and item:isFrozen()
        local hoursLeft, state = Spoilage.hoursLeft(item:getModData()[BloodData.SPOILAGE_KEY], Env.gameMinutes() / 60,
            frozen)
        ctx.spoilage = { state = state, hoursLeft = hoursLeft, frozen = frozen }
    elseif ItemInfo.OTHER[fullType] == "prepared" then
        local total = item:getMinutesToCook()
        if total and total > 0 then
            ctx.preparation = item:getCookingTime() / total
        end
    end
    return ctx
end

-- Every provider's lines for this item, in order; nil when there are none.
function ItemTooltip.lines(item, player)
    local all = {}
    local fullType = item:getFullType()
    if ItemInfo.covers(fullType) then
        for _, line in ipairs(ItemInfo.lines(fullType, itemContext(item, player)) or {}) do
            all[#all + 1] = line
        end
    end
    for _, provider in ipairs(providers) do
        for _, line in ipairs(provider(item, player) or {}) do
            all[#all + 1] = line
        end
    end
    return #all > 0 and all or nil
end

local function rgb(name)
    local c = Draw.color(name)
    return c[1], c[2], c[3]
end

-- Appends our lines under what vanilla drew, and grows the tooltip to fit.
local function append(tooltip, lines)
    local font = tooltip:getFont()
    local wrapWidth = math.max(ItemTooltip.WRAP_WIDTH, tooltip:getWidth() - 2 * ItemTooltip.PAD)
    local layout = tooltip:beginLayout()
    for _, line in ipairs(lines) do
        local r, g, b = rgb(line.color)
        local label = Text.t(line.label)
        if line.wrap then
            for _, part in ipairs(Draw.wrap(label, font, wrapWidth)) do
                layout:addItem():setLabel(part, r, g, b, 1)
            end
        else
            local row = layout:addItem()
            -- A bar takes the value column (both drawn there overlap), so its value joins the label.
            if line.value and line.progress then
                label = label .. " " .. Text.t(line.value)
            end
            row:setLabel(label, r, g, b, 1)
            if line.value and not line.progress then
                row:setValue(Text.t(line.value), r, g, b, 1)
            end
            if line.progress then
                row:setProgress(math.max(0, math.min(1, line.progress)), r, g, b, 1)
            end
        end
    end
    local bottom = layout:render(ItemTooltip.PAD, tooltip:getHeight(), tooltip)
    tooltip:endLayout(layout)
    tooltip:setHeight(bottom + ItemTooltip.PAD)
end

local REAL = {}     -- stand-in field holding the real item
local failed = {}   -- full type -> true once its lines failed (logged once, not every frame)

local function standIn(item, lines)
    local proxy = {}
    proxy[REAL] = item
    proxy.DoTooltip = function(_, tooltip)
        item:DoTooltip(tooltip)
        local ok, err = pcall(append, tooltip, lines)
        if not ok and not failed[item:getFullType()] then
            failed[item:getFullType()] = true
            log:error("tooltip lines for", item:getFullType(), "failed:", err)
        end
    end
    -- The proxy's metatable __index is a table, not a function: Starlit Library's own render wrap reads
    -- getmetatable(item).__index.DoTooltip (the Java class table for a real item) and errors on a function. Whatever
    -- such a library writes there lands on this throw-away table, so it never reaches the item class.
    local forward = setmetatable({}, {
        __index = function(_, key)
            local value = item[key]
            if type(value) == "function" then
                return function(_, ...)
                    return value(item, ...)
                end
            end
            return value
        end,
    })
    return setmetatable(proxy, { __index = forward })
end

local function realItem(item)
    if type(item) == "table" and rawget(item, REAL) then
        return rawget(item, REAL)
    end
    return item
end

Patches.on("tooltipInvRender", {
    name = "ehrItemTooltip",
    before = function(panel)
        local item = realItem(panel.item)
        panel.item = item
        if not item or not instanceof(item, "InventoryItem") then
            return
        end
        local lines = ItemTooltip.lines(item, ItemTooltip.reader(panel.tooltip, item))
        if lines then
            panel.item = standIn(item, lines)
        end
    end,
    after = function(_, panel)
        panel.item = realItem(panel.item)
    end,
})

return ItemTooltip
