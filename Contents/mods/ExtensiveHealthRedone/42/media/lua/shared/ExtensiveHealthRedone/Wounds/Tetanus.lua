-- Tetanus triggers (W12: all four). Each roll is x TetanusChanceMultiplier; the first success starts tetanus
-- (Conditions/Tetanus) with a hidden incubation.
--   glass:  a deep wound with lodged glass rolls at once, then every 12 h while the glass stays, 40 % rising by 15 %
--           per 12 h to 70 % (v0.9)
--   crash:  a deep wound that appears while in a vehicle (ours: 40 %)
--   walk:   glass that appears in a foot outside a vehicle, i.e. walking on broken glass (ours: 20 %)
--   dirty:  a deep wound without glass, left unbandaged or under a dirty bandage, rolls every 12 h of that (ours: 15 %)
-- state.wounds.tetanus: { glass = { [part] = { elapsed, rolls } }, dirty = { [part] = elapsed },
--                         seen = { [part] = { deep = bool, glass = bool } } }

local Data = require("ExtensiveHealthRedone/Data/Wounds").tetanus
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local Tetanus = {}

function Tetanus.glassChance(rolls)
    return math.min(Data.GLASS_MAX, Data.GLASS_FIRST + rolls * Data.GLASS_STEP)
end

local function roll(p, chance, source, defs)
    local mult = tonumber(p.sandbox("TetanusChanceMultiplier", 1.0)) or 1
    if Chance.roll(p.rng, math.min(1, chance * mult)) then
        if Engine.contract(p, defs, "tetanus", { source = source }) then
            Speech.stage(p, Data.LINE)
            return true
        end
    end
    return false
end

-- Whether the trigger bookkeeping changed (for syncing).
local function track(p, t, name, fact, dt, armed, defs)
    local seen = t.seen[name] or {}
    local deep, glass = fact.deep == true, fact.glass == true
    local changed = seen.deep ~= deep or seen.glass ~= glass
    t.seen[name] = { deep = deep, glass = glass }

    -- First sight of this part after attach only records it (armed is false), so a login never counts as "new".
    if armed then
        if deep and not seen.deep and p.facts.inVehicle then
            if roll(p, Data.CRASH, "crash", defs) then return true end
        end
        if glass and not seen.glass and BodyParts.feet[name] and not p.facts.inVehicle and not deep then
            if roll(p, Data.WALK_GLASS, "glass", defs) then return true end
        end
    end

    if deep and glass then
        local g = t.glass[name]
        if not g then
            g = { elapsed = 0, rolls = 0 }
            t.glass[name] = g
            changed = true
            if roll(p, Tetanus.glassChance(0), "glass", defs) then return true end
            g.rolls = 1
        else
            g.elapsed = g.elapsed + dt
            if g.elapsed >= g.rolls * Data.GLASS_EVERY_HOURS * 60 then
                local chance = Tetanus.glassChance(g.rolls)
                g.rolls = g.rolls + 1
                if roll(p, chance, "glass", defs) then return true end
            end
        end
    elseif t.glass[name] then
        t.glass[name] = nil
        changed = true
    end

    local dirty = deep and not glass and (not fact.bandaged or fact.bandageDirty)
    if dirty then
        local elapsed = (t.dirty[name] or 0) + dt
        if elapsed >= Data.DIRTY_EVERY_HOURS * 60 then
            elapsed = elapsed - Data.DIRTY_EVERY_HOURS * 60
            t.dirty[name] = elapsed
            if roll(p, Data.DIRTY, "dirtyWound", defs) then return true end
        end
        t.dirty[name] = elapsed
    elseif t.dirty[name] then
        t.dirty[name] = nil
        changed = true
    end
    return changed
end

-- armed: false on the first step after a player attaches.
function Tetanus.update(p, dt, defs, armed)
    local t = p.state.wounds.tetanus
    local facts = (p.facts and p.facts.parts) or {}
    local active = p.state.conditions.active.tetanus ~= nil or not Engine.enabled(p, defs.tetanus)
    local changed = false
    for _, name in ipairs(BodyParts.names) do
        local fact = facts[name] or {}
        if active then
            local seen = t.seen[name] or {}
            if seen.deep ~= (fact.deep == true) or seen.glass ~= (fact.glass == true) then
                t.seen[name] = { deep = fact.deep == true, glass = fact.glass == true }
                changed = true
            end
        elseif track(p, t, name, fact, dt, armed, defs) then
            changed = true
            if p.state.conditions.active.tetanus then
                active = true
            end
        end
    end
    if changed then
        p.dirty("wounds")
    end
end

return Tetanus
