-- The Last Prescription's rules (Phase 8; docs/porting/phase8/flyers-knowledge-radio.md Part C): when a slot airs, what
-- it says, how the story advances, who counts as a listener and when to judge it. Pure: the clock, the world state and
-- plain device tables are passed in. Server/Radio does the game work.
--
-- Schedule (v0.9 sv/EHR_Radio.lua:145-201, sv/EHR_RadioMessages.lua:558-636), day = nights survived + 1:
--   09:00  tip ((day mod 21) + 1); a listener gets 4 First Aid XP once (radioHeard "<day>:9:XP:4")
--   15:00  the next story episode; no reward
--   21:00  disease file (((day - 1) mod 20) + 1); a listener learns the id once ("<day>:21:KNOW:<id>"), never Knox
-- Fixed against v0.9 (decided 2026-10-14): the story is a stored world-wide index that advances only when an episode
-- airs, so a missed 15:00 skips nothing; after episode 22 the loop recording (22) replays daily. v0.9 derived it from the
-- day and wrapped to episode 1 on day 23. Tips and files stay on the day rotation.
--
-- World state ({ lastSlot = "<day>:<hour>", story = last episode aired }) is a plain table the server keeps in global
-- ModData; clean() repairs anything a save or a client could have put there.
--
-- Listeners (maintainer default: vanilla's rule; v0.9 s/EHR_RadioInteractions.lua:37-55, vanilla
-- ISRadioInteractions.playerInRange/checkPlayer): alive, awake, and a device that is on, tuned to 47.0, powered and not
-- muted is carried, is the radio of the vehicle they sit in, or stands within 5 tiles on their floor and their side of
-- inside/outside. A world device with headphones plugged in counts for nobody.
--
-- Judging (maintainer default): when the final line airs. Server/Radio reads the channel's progress each game minute and
-- calls check(); if the server never shows line progress, the fallback rewards anyone listening at any check from 5 to
-- 15 minutes after the start.

local Data = require "ExtensiveHealthRedone/Data/Radio"

local Station = {}

function Station.day(nightsSurvived)
    return math.floor(tonumber(nightsSurvived) or 0) + 1
end

function Station.slotKey(day, hour)
    return tostring(day) .. ":" .. tostring(hour)
end

-- Tip number for a day (v0.9 pick(morningTips, day, 1): day 1 airs tip 2).
function Station.tipFor(day)
    return (day % #Data.TIP_LINES) + 1
end

-- File number for a day (v0.9 pick(diseaseEpisodes, day, 0)).
function Station.fileFor(day)
    return ((day - 1) % #Data.FILES) + 1
end

-- The episode the next 15:00 airs.
function Station.nextStory(world)
    return math.min((world.story or 0) + 1, #Data.STORY_LINES)
end

-- A world state from whatever was stored: lastSlot a "<day>:<hour>" string, story a whole number 0..22.
function Station.clean(raw)
    raw = type(raw) == "table" and raw or {}
    local lastSlot = raw.lastSlot
    if type(lastSlot) ~= "string" or not lastSlot:match("^%-?%d+:%d+$") then
        lastSlot = nil
    end
    local story = math.floor(tonumber(raw.story) or 0)
    story = math.max(0, math.min(story, #Data.STORY_LINES))
    return { lastSlot = lastSlot, story = story }
end

-- The slot to air now ("morning", "afternoon", "evening"), or nil: off, not a slot hour, or this slot aired already.
-- Any minute of the slot hour will do, so a clock that jumps (sleep, fast-forward) or a server started at 09:40 still
-- airs it.
function Station.due(world, day, hour, enabled)
    if not enabled then
        return nil
    end
    local slot = Data.SLOTS[hour]
    if not slot or world.lastSlot == Station.slotKey(day, hour) then
        return nil
    end
    return slot
end

local function line(key, color, args)
    return { key = key, color = Data.COLORS[color], args = args }
end

local function numbered(lines, prefix, n, count, color)
    for i = 1, count do
        lines[#lines + 1] = line(prefix .. n .. "_" .. i, color)
    end
end

-- Builds a broadcast: { id, slot, day, hour, lines = { { key, color = { r, g, b }, args = { keys } } },
-- story = episode (15:00), heard = radioHeard key and reward (09:00, 21:00) }. A line's args are translation keys
-- whose text fills %1.. of its own text. suffix makes the broadcast id unique per airing.
function Station.build(slot, day, world, suffix)
    local hour = Data.HOURS[slot]
    if not hour then
        return nil
    end
    local b = { slot = slot, day = day, hour = hour, lines = {},
        id = "EHR-LP-" .. day .. "-" .. hour .. "-" .. tostring(suffix or 0) }
    if slot == "morning" then
        local n = Station.tipFor(day)
        b.lines[1] = line("UI_EHR_Radio_Intro_Morning", "static")
        numbered(b.lines, "UI_EHR_Radio_Tip_", n, Data.TIP_LINES[n], "tip")
        b.tip = n
        b.heard = Station.slotKey(day, hour) .. ":XP:4"
        b.reward = { kind = "xp" }
    elseif slot == "afternoon" then
        local n = Station.nextStory(world)
        b.lines[1] = line("UI_EHR_Radio_Intro_Afternoon", "static")
        numbered(b.lines, "UI_EHR_Radio_Story_", n, Data.STORY_LINES[n], "host")
        b.story = n
    elseif slot == "evening" then
        local n = Station.fileFor(day)
        local id = Data.FILES[n]
        local name = "UI_EHR_Disease_" .. id
        local file = "UI_EHR_Radio_File_" .. id
        b.lines = {
            line("UI_EHR_Radio_Intro_Evening", "static"),
            line("UI_EHR_Radio_File_Title", "medical", { name }),
            line("UI_EHR_Radio_File_Cause", "host", { file .. "_Cause" }),
            line("UI_EHR_Radio_File_Symptoms", "warning", { file .. "_Symptoms" }),
            line("UI_EHR_Radio_File_Treatment", "tip", { file .. "_Treatment" }),
            line("UI_EHR_Radio_File_WriteDown", "medical", { name }),
        }
        b.file = n
        b.heard = Station.slotKey(day, hour) .. ":KNOW:" .. id
        b.reward = { kind = "know", id = id, name = name }
    end
    return b
end

-- Records an airing in the world state: the slot is done and the story moves on.
function Station.aired(world, b)
    world.lastSlot = Station.slotKey(b.day, b.hour)
    if b.story then
        world.story = math.max(world.story or 0, b.story)
    end
end

-- Listeners -------------------------------------------------------------------------------------------------------------

-- device: { kind = "carried" | "vehicle" | "world", on, channel, battery (battery powered), power (0-1), volume,
-- headphones (vanilla getHeadphoneType: -1 none), x, y, z, outside }.
function Station.tuned(device)
    return device.on == true and device.channel == Data.FREQUENCY
        and (not device.battery or (device.power or 0) > 0)
        and (device.volume or 0) > 0
end

-- listener: { x, y, z, outside }.
function Station.reaches(listener, device)
    if device.kind == "carried" or device.kind == "vehicle" then
        return true
    end
    if (device.headphones or -1) >= 0 then
        return false
    end
    return math.floor(device.z or 0) == math.floor(listener.z or 0)
        and math.abs((device.x or 0) - (listener.x or 0)) <= Data.RANGE
        and math.abs((device.y or 0) - (listener.y or 0)) <= Data.RANGE
        and (device.outside == true) == (listener.outside == true)
end

-- listener: { alive, awake, x, y, z, outside }; devices: a list of device tables.
function Station.listening(listener, devices)
    if not listener.alive or not listener.awake then
        return false
    end
    for _, device in ipairs(devices) do
        if Station.tuned(device) and Station.reaches(listener, device) then
            return true
        end
    end
    return false
end

-- Judging ----------------------------------------------------------------------------------------------------------------

-- Starts watching a broadcast with a reward. now: game minutes.
function Station.watch(b, now)
    return { id = b.id, heard = b.heard, reward = b.reward, day = b.day, lines = #b.lines, started = now,
        progressSeen = false, done = false }
end

-- One check while a broadcast airs. progress: { ours = still the channel's airing broadcast, line = its current line
-- number or nil }. Returns true when listeners are to be judged now; watch.done is set on the last judgement.
function Station.check(watch, now, progress)
    if watch.done then
        return false
    end
    local elapsed = now - watch.started
    local lineNo = tonumber(progress.line)
    if lineNo and lineNo > 0 then
        watch.progressSeen = true
    end
    -- The final line is up (whether the number counts aired lines or is the current index), the broadcast ended or
    -- was replaced, or it ran too long.
    if not progress.ours or (lineNo and lineNo >= watch.lines - 1) or elapsed >= Data.WATCH_LIMIT then
        watch.done = true
        return true
    end
    if not watch.progressSeen and elapsed >= Data.FALLBACK_FROM then
        if elapsed >= Data.FALLBACK_UNTIL then
            watch.done = true
        end
        return true
    end
    return false
end

return Station
