-- Hive and spiderweb search rules: what a tree holds and taking from it. Pure; the random source is passed in.
-- A tree's contents never expire; an empty or emptied tree gets a cooldown (Wild/SpotCooldowns).

local Data = require("ExtensiveHealthRedone/Data/WildSearch").hive

local HiveTree = {}

HiveTree.TARGETS = { hive = true, web = true }

-- A freshly inspected tree: { hive = bool, webs = 0-3 }. 60% are empty.
function HiveTree.roll(rng)
    if rng.int(0, 99) >= Data.CONTENT_CHANCE then
        return { hive = false, webs = 0 }
    end
    local hive = rng.int(0, 99) < Data.HIVE_CHANCE
    local roll = rng.int(0, 99)
    local webs = 0
    for count = 0, #Data.WEBS - 1 do
        roll = roll - Data.WEBS[count + 1]
        if roll < 0 then
            webs = count
            break
        end
    end
    if not hive and webs == 0 then
        webs = 1
    end
    return { hive = hive, webs = math.min(Data.MAX_WEBS, webs) }
end

function HiveTree.isEmpty(content)
    return not content.hive and (content.webs or 0) <= 0
end

function HiveTree.has(content, target)
    if target == "hive" then
        return content.hive == true
    elseif target == "web" then
        return (content.webs or 0) > 0
    end
    return false
end

-- Takes one target out of the contents. Returns the item's full type, or nil when the target isn't there.
function HiveTree.collect(content, target)
    if not HiveTree.has(content, target) then
        return nil
    end
    if target == "hive" then
        content.hive = false
        return Data.HONEYCOMB
    end
    content.webs = content.webs - 1
    return Data.SPIDERWEB
end

return HiveTree
