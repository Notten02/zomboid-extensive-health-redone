-- Gives back what EHR added to stats vanilla never lowers on its own. B42 leaves SICKNESS where it is: a disease, a
-- side effect or a diet effect that raised it and then ended left it there for good (a real save kept 0.17 for 34
-- game hours with nothing asking for it). Raises and floors also never lower a stat, so a disease whose nausea eases
-- in a later stage kept the earlier stage's level until the end.
--
-- EHR keeps its share of each such stat in state.body.statOwned ([stat] = raw amount): what its own contributions
-- (and add-ons', through p.stats) added and nothing has taken away yet. The share shrinks whenever something else
-- lowers the stat, so another mod's sickness is never counted as ours. The release system lowers the stat by at most
-- `perHour` of its range per game hour, down to the highest level a source still holds it at (StatAggregator:wants)
-- and never by more than the share.
--
--   StatRelease.account(p)      before every stat write (Server/Runtime.finish: steps and one-off effects alike)
--   StatRelease.system          order 985: after the systems that ask for these stats; later ones aren't seen
--
-- Saves from before this (schema 5 and older, and imports of the original mod) never kept a share, so their leftover
-- can't be told apart from another mod's. They have body.claimLeftover set: the first step claims the stat's current
-- value as EHR's, up to `claimCap` of the range (the highest EHR's diseases raise it to), and gives it back like any
-- share. If another mod holds that value it puts it straight back, and EHR stops once the claimed share is spent.
-- Pure.

local StatRelease = {}

StatRelease.SOURCE = "statRelease"

-- [stat] = { perHour = share of the range given back per game hour, claimCap = share an old save's leftover may
-- claim }. ORDER keeps the walk deterministic.
StatRelease.STATS = {
    SICKNESS = { perHour = 0.05, claimCap = 0.65 },
}
StatRelease.ORDER = { "SICKNESS" }

-- Shares below this (raw) are dropped, so float noise never keeps a release running.
StatRelease.EPSILON = 1e-6

local function current(p, stat)
    return p.facts and p.facts.stats and p.facts.stats[stat]
end

-- The share still in the stat: never more than the stat sits above its minimum.
local function share(p, stat, value)
    local owned = tonumber(p.state.body.statOwned[stat]) or 0
    return math.max(0, math.min(owned, value - p.stats:at(stat, 0)))
end

local function store(p, stat, amount)
    p.state.body.statOwned[stat] = amount > StatRelease.EPSILON and amount or nil
end

-- Updates the shares with what this write changes. Call it right before the stat writer resolves p.stats.
function StatRelease.account(p)
    for _, stat in ipairs(StatRelease.ORDER) do
        local value = current(p, stat)
        if value then
            local after = p.stats:resolve(stat, value)
            store(p, stat, math.max(0, share(p, stat, value) + (after - value)))
        end
    end
end

-- Claims an old save's leftover once, then asks for each stat to be lowered toward what is still held.
function StatRelease.update(p, dt)
    if p.fresh or not (p.facts and p.facts.stats) then
        return
    end
    local body = p.state.body
    for _, stat in ipairs(StatRelease.ORDER) do
        local spec = StatRelease.STATS[stat]
        local value = current(p, stat)
        if value then
            local min = p.stats:at(stat, 0)
            local mine = share(p, stat, value)
            if body.claimLeftover then
                mine = math.max(mine, math.min(value - min, spec.claimCap * p.stats:span(stat)))
                store(p, stat, mine)
            end
            if mine > StatRelease.EPSILON then
                local target = math.max(value - mine, p.stats:wants(stat) or min)
                if value > target then
                    p.stats:lower(stat, StatRelease.SOURCE, target, spec.perHour * p.stats:span(stat) * dt / 60)
                end
            end
        end
    end
    body.claimLeftover = false
end

StatRelease.system = { name = "statRelease", order = 985, update = StatRelease.update }

return StatRelease
