-- World loot on the authority: our entries in the vanilla distribution
-- tables, the package fill and Knox facility items as containers fill, and zombie loot. The data is in Data/Loot and
-- Data/LootFill, the rules in Loot/Build, Loot/Apply and Loot/Fill; this file only touches the game.
--
-- Where loot rolls: single player and the dedicated server fill containers, an MP client asks the server for a
-- container's items (ISInventoryPage requestServerItemsForContainer), so an MP client loads this file too and stops
-- at the first line. Its own distribution tables are never used to roll loot.
--
-- Timing and sandbox options:
--   * Entries are written at OnPreDistributionMerge, before ItemPickerJava.Parse snapshots the tables. In single
--     player the save's sandbox file may not be loaded yet at that point (Continue/Load), so we load it first, the
--     way vanilla's MainScreen does (getSandboxOptions():loadCurrentGameBinFile()). A dedicated server has its
--     sandbox loaded before the world.
--   * Fallback: at OnInitGlobalModData (the first event after the sandbox is certainly loaded) the options are read
--     again; if they differ from what was used, our entries are taken back out, written again and the tables
--     re-parsed. That also covers paths where the preload misses.
--   * The package fill, Knox items and zombie loot read their options live.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Data = require "ExtensiveHealthRedone/Data/Loot"
local FillData = require "ExtensiveHealthRedone/Data/LootFill"
local Build = require "ExtensiveHealthRedone/Loot/Build"
local Apply = require "ExtensiveHealthRedone/Loot/Apply"
local Fill = require "ExtensiveHealthRedone/Loot/Fill"

local log = Env.logger("Loot")

local ServerLoot = {}

-- What the last write used and did: { options, record, report }.
local applied = nil

local function tables()
    return {
        procedural = ProceduralDistributions and ProceduralDistributions.list,
        suburbs = SuburbsDistributions,
        vehicles = VehicleDistributions,
    }
end

-- Single player: load the save's sandbox file before reading options. An uncertain engine path,
-- so a failure is logged and the fallback at OnInitGlobalModData still corrects the options.
local function preloadSandbox()
    if isServer() then
        return
    end
    local ok, err = pcall(function()
        if checkSaveFileExists("map_sand.bin") then
            getSandboxOptions():loadCurrentGameBinFile()
        end
    end)
    if not ok then
        log:warn("could not preload the save's sandbox options:", err)
    end
end

local function describe(options)
    return "MedicationLootMultiplier " .. tostring(options.medication)
        .. ", MedicalWatchLootMultiplier " .. tostring(options.watch)
        .. ", HouseholdPrescriptionLoot " .. tostring(options.gates.HouseholdPrescriptionLoot)
end

-- Writes all our distribution entries with these options.
function ServerLoot.apply(options)
    local t = tables()
    local record = Apply.newRecord()
    local report = Apply.write(Build.targets(Data, options), t, record)
    Apply.defineBox(t.suburbs, Data.box.type, Build.box(Data, options))
    local watchTarget = Build.fullType(Data.MODULE, Data.watch.target)
    report.watchLists = Apply.mirror(t.procedural, Data.watch.source, watchTarget, options.watch, record)
    report.roomProcs, report.roomsSkipped = Apply.roomProcs(t.suburbs, Data.roomProcs)
    applied = { options = options, record = record, report = report }
    log:info("loot: added", report.added, "entries to", report.lists, "lists; watch in", report.watchLists,
        "lists;", describe(options))
    if #report.missing > 0 then
        log:warn("loot lists missing in this build:", table.concat(report.missing, ", "))
    end
    if #report.shared > 0 then
        log:warn("loot lists skipped, they share a table with another target:", table.concat(report.shared, ", "))
    end
    if #report.roomsSkipped > 0 then
        log:warn("medical room containers not changed:", table.concat(report.roomsSkipped, ", "))
    end
    return report
end

-- Takes our entries back out, writes them again with these options and re-snapshots the tables.
function ServerLoot.reapply(options)
    if applied then
        Apply.undo(applied.record)
    end
    ServerLoot.apply(options)
    local ok, err = pcall(function()
        ItemPickerJava.Parse()
    end)
    if not ok then
        log:warn("ItemPickerJava.Parse failed after re-applying loot:", err)
    end
end

local function onPreDistributionMerge()
    preloadSandbox()
    -- A second merge in the same Lua session (if the engine ever does one) must not stack our entries.
    if applied then
        Apply.undo(applied.record)
    end
    ServerLoot.apply(Build.options(Env.sandbox))
end

local function onInitGlobalModData()
    if not applied then
        return
    end
    local now = Build.options(Env.sandbox)
    if Build.sameOptions(now, applied.options) then
        return
    end
    log:warn("loot options changed after the distribution merge (was", describe(applied.options) .. "); re-applying")
    ServerLoot.reapply(now)
end

-- Package fill --------------------------------------------------------------------------------------------------------

local function fillSettings()
    return Fill.profile(FillData, Env.sandbox("MedicationPackageFill", FillData.defaultProfile)),
        Env.sandbox("AllowFullPharmacyPackages", true) ~= false
end

-- Leaves a full package of ours with a random number of doses. Only full packages: a container refilled on loot
-- respawn may hold packages a player already used.
local function fillItem(item, location, profile, allowFull)
    if not FillData.fillItems[item:getFullType()] or not instanceof(item, "DrainableComboItem") then
        return
    end
    local max = item:getMaxUses()
    if item:getCurrentUses() < max then
        return
    end
    local doses = Fill.doses(max, profile, location, allowFull, Env.rng)
    if doses < max then
        item:setCurrentUses(doses)
    end
end

-- The container's items, and one level into kits, bags and the Medicine Storage Box filled with it.
local function fillContainer(container, location, profile, allowFull, depth)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if depth > 0 then
                local inner = Fill.subLocation(FillData, item:getType(), location)
                fillContainer(item:getItemContainer(), inner, profile, allowFull, depth - 1)
            end
        else
            fillItem(item, location, profile, allowFull)
        end
    end
end

-- Knox facility items -------------------------------------------------------------------------------------------------

-- Rolls once per container: the flag lives in the furniture object's modData, so loot respawn never rolls again.
local function knoxItems(container, containerType)
    if Env.sandbox("KnoxCureItemsEnabled", true) == false then
        return
    end
    local parent = container:getParent()
    local square = parent and parent:getSquare()
    if not square then
        return
    end
    local items = Fill.knoxItems(FillData.knox, square:getX(), square:getY(), square:getZ(), containerType)
    if not items then
        return
    end
    local modData = parent:getModData()
    modData.ehrKnoxLoot = modData.ehrKnoxLoot or {}
    local slot = tostring(containerType)
    if modData.ehrKnoxLoot[slot] then
        return
    end
    modData.ehrKnoxLoot[slot] = true
    for _, fullType in ipairs(Fill.knoxRoll(items, Env.rng)) do
        container:AddItem(fullType)
        log:debug("Knox item", fullType, "spawned at", square:getX(), square:getY(), square:getZ())
    end
end

-- A sub-container's fill passes an ItemPickerContainer instead (Umbrella: "probably a bug"); those items are
-- reached through the outer container.
local function onFillContainer(roomType, containerType, container)
    if not instanceof(container, "ItemContainer") then
        return
    end
    local profile, allowFull = fillSettings()
    fillContainer(container, Fill.location(FillData, roomType, containerType), profile, allowFull, 1)
    -- After the fill, so Knox items stay full.
    knoxItems(container, containerType)
end

-- Zombie loot ---------------------------------------------------------------------------------------------------------

local zombiePool = Build.zombiePool(FillData.zombie, Data)

-- At death the zombie's clothing and attached items exist but its loot is not rolled yet (Umbrella).
local function onZombieDead(zombie)
    if Env.sandbox("ZombieLootEnabled", true) == false then
        return
    end
    local chance = tonumber(Env.sandbox("ZombieLootChance", 5)) or 5
    if chance <= 0 then
        return
    end
    local modData = zombie:getModData()
    if modData.ehrLootRolled then
        return
    end
    modData.ehrLootRolled = true
    if not Fill.percent(chance, Env.rng) then
        return
    end
    local fullType = Fill.pick(zombiePool, Env.rng)
    local item = fullType and zombie:getInventory():AddItem(fullType)
    if item then
        local profile = fillSettings()
        fillItem(item, FillData.zombieLocation, profile, false)
    end
end

-- Events --------------------------------------------------------------------------------------------------------------

-- Every event exists in the game; the offline fake game has only a few, which is not worth failing a test for.
local function on(name, fn)
    local event = Events[name]
    if not event then
        log:warn("event", name, "is missing; loot handler not registered")
        return
    end
    event.Add(fn)
end

on("OnPreDistributionMerge", onPreDistributionMerge)
on("OnInitGlobalModData", onInitGlobalModData)
on("OnFillContainer", onFillContainer)
on("OnZombieDead", onZombieDead)

-- Debug commands ------------------------------------------------------------------------------------------------------

local function reportText()
    if not applied then
        return "Loot was not applied this session (OnPreDistributionMerge did not run)."
    end
    local r = applied.report
    local lines = {
        "Loot options: " .. describe(applied.options),
        "Entries: " .. r.added .. " in " .. r.lists .. " lists; medical watch in " .. r.watchLists .. " lists",
        "Medical room procs added: " .. r.roomProcs,
        "Missing lists: " .. (#r.missing > 0 and table.concat(r.missing, ", ") or "none"),
        "Shared-table lists skipped: " .. (#r.shared > 0 and table.concat(r.shared, ", ") or "none"),
        "Room containers skipped: " .. (#r.roomsSkipped > 0 and table.concat(r.roomsSkipped, ", ") or "none"),
        "Now: " .. describe(Build.options(Env.sandbox)),
    }
    return table.concat(lines, "\n")
end

Runtime.registry:register("debug.lootReport", {
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 3, seconds = 10 },
    handler = function(ctx)
        Transport.toClient(ctx.actor.player, "debugDump", { text = reportText() })
    end,
})

-- Re-reads the sandbox options and writes our entries again (for testing a changed multiplier without a restart).
-- Containers already filled keep their loot.
Runtime.registry:register("debug.lootReapply", {
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 1, seconds = 10 },
    handler = function(ctx)
        ServerLoot.reapply(Build.options(Env.sandbox))
        log:info(ctx.actor.key, "debug: loot re-applied")
        Transport.toClient(ctx.actor.player, "debugDump", { text = reportText() })
    end,
})

return ServerLoot
