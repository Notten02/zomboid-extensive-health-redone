-- Writes built loot (Loot/Build) into the game's distribution tables. The tables are plain Lua tables, so this module
-- takes them as arguments and is tested offline with stand-ins; Server/Loot passes the real globals.
--
--   tables = { procedural = ProceduralDistributions.list, suburbs = SuburbsDistributions,
--              vehicles = VehicleDistributions }
--
-- A list that does not exist is reported, never aliased to another list. Everything written goes into
-- a record, so Apply.undo can take it back out (the re-apply when the sandbox options turn out to differ, Server/Loot).

local Apply = {}

function Apply.newRecord()
    return { inserts = {}, rolls = {} }
end

-- The distribution table a target writes into, or nil.
function Apply.resolve(tables, kind, name)
    local dist
    if kind == "proc" then
        dist = tables.procedural and tables.procedural[name]
    elseif kind == "vehicle" then
        dist = tables.vehicles and tables.vehicles[name]
    elseif kind == "bag" then
        local suburbs = tables.suburbs
        dist = suburbs and (suburbs[name] or (suburbs.all and suburbs.all[name]))
    elseif kind == "postbox" then
        dist = tables.suburbs and tables.suburbs.all and tables.suburbs.all[name]
    end
    if type(dist) == "table" and type(dist.items) == "table" then
        return dist
    end
    return nil
end

local function remember(record, items, names)
    record.inserts[#record.inserts + 1] = { items = items, names = names }
end

-- Writes every built target. Returns { added = entries, lists = lists written, missing = { "kind:name" },
-- shared = { "kind:name" } }. Two targets that resolve to one table (a build where one list aliases another) would
-- put every item in twice, so the second is skipped and reported.
function Apply.write(built, tables, record)
    local report = { added = 0, lists = 0, missing = {}, shared = {} }
    local written = {}
    for _, target in ipairs(built) do
        local count = #target.front + #target.back
        if count > 0 then
            local dist = Apply.resolve(tables, target.kind, target.list)
            if not dist then
                report.missing[#report.missing + 1] = target.kind .. ":" .. target.list
            elseif written[dist.items] then
                report.shared[#report.shared + 1] = target.kind .. ":" .. target.list
            else
                written[dist.items] = true
                local items, names = dist.items, {}
                -- Front entries go first, in their built order.
                for i = #target.front, 1, -1 do
                    local entry = target.front[i]
                    table.insert(items, 1, entry.chance)
                    table.insert(items, 1, entry.item)
                    names[entry.item] = true
                end
                for _, entry in ipairs(target.back) do
                    items[#items + 1] = entry.item
                    items[#items + 1] = entry.chance
                    names[entry.item] = true
                end
                remember(record, items, names)
                report.added = report.added + count
                report.lists = report.lists + 1
                local rolls = tonumber(dist.rolls)
                if target.minRolls and rolls and rolls < target.minRolls then
                    record.rolls[#record.rolls + 1] = { dist = dist, rolls = dist.rolls }
                    dist.rolls = target.minRolls
                end
            end
        end
    end
    return report
end

-- Removes every entry in an items list whose name is in the set, keeping the rest in order.
local function strip(items, names)
    local kept = {}
    for i = 1, #items, 2 do
        if not names[items[i]] then
            kept[#kept + 1] = items[i]
            kept[#kept + 1] = items[i + 1]
        end
    end
    for i = #items, 1, -1 do
        items[i] = nil
    end
    for i, v in ipairs(kept) do
        items[i] = v
    end
end

-- Takes back everything a record wrote: our entries and raised rolls. The tables are the same objects (vanilla's
-- merge appends into them), so a record from OnPreDistributionMerge is still valid afterwards.
function Apply.undo(record)
    for _, insert in ipairs(record.inserts) do
        strip(insert.items, insert.names)
    end
    for i = #record.rolls, 1, -1 do
        local entry = record.rolls[i]
        entry.dist.rolls = entry.rolls
    end
    record.inserts, record.rolls = {}, {}
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

-- Mirrors a vanilla item into the medical watch: in every procedural list holding the source (with or without its
-- module), one target entry at the sum of the source's weights x mult (vanilla lists the watch twice in two
-- store lists, so the sum keeps their intended total). Returns the number of lists.
function Apply.mirror(procedural, source, target, mult, record)
    if not procedural or mult <= 0 then
        return 0
    end
    local bare = source:match("^[^.]+%.(.+)$") or source
    local count = 0
    for _, name in ipairs(sortedKeys(procedural)) do
        local items = type(procedural[name]) == "table" and procedural[name].items
        if type(items) == "table" then
            local sum = 0
            for i = 1, #items, 2 do
                if (items[i] == source or items[i] == bare) and tonumber(items[i + 1]) then
                    sum = sum + items[i + 1]
                end
            end
            if sum > 0 then
                items[#items + 1] = target
                items[#items + 1] = sum * mult
                remember(record, items, { [target] = true })
                count = count + 1
            end
        end
    end
    return count
end

local function hasProc(procList, name)
    for _, entry in ipairs(procList) do
        if entry.name == name then
            return true
        end
    end
    return false
end

-- Adds vanilla procedural lists to raw room containers (Data/Loot roomProcs). A missing container is created; an
-- empty item container is converted; one with its own items is left alone; an existing proc is not added twice, so
-- running this again changes nothing. Returns added, skipped (list of "room.container" names).
function Apply.roomProcs(suburbs, roomProcs)
    local added, skipped = 0, {}
    for _, rp in ipairs(roomProcs) do
        local room = suburbs and suburbs[rp.room]
        if type(room) ~= "table" then
            skipped[#skipped + 1] = rp.room .. "." .. rp.container
        else
            local dist = room[rp.container]
            if dist == nil then
                dist = { procedural = true, procList = {} }
                room[rp.container] = dist
            end
            if not (dist.procedural and dist.procList) then
                if type(dist.items) == "table" and #dist.items > 0 then
                    dist = nil
                else
                    dist.procedural, dist.procList = true, {}
                    dist.items, dist.rolls, dist.junk = nil, nil, nil
                end
            end
            if not dist then
                skipped[#skipped + 1] = rp.room .. "." .. rp.container
            elseif not hasProc(dist.procList, rp.proc) then
                dist.procList[#dist.procList + 1] = {
                    name = rp.proc, min = rp.min, max = rp.max, weightChance = rp.weight,
                }
                added = added + 1
            end
        end
    end
    return added, skipped
end

-- The Medicine Storage Box's contents, keyed by its item type (replaced wholesale, so re-running is safe).
function Apply.defineBox(suburbs, boxType, built)
    if not suburbs then
        return false
    end
    suburbs[boxType] = built
    return true
end

return Apply
