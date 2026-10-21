-- The Medical Monitor Watch battery, as pure rules on a plain state. The state lives in the watch's item modData under
-- KEY, in v0.9's format so old watches carry over: { version = 1, installed = bool, charge = 0..1 }. A watch without
-- that table counts as full: that is how a watch spawns with a full battery (v0.9 EHR_WatchBatteryCore.lua; spec
-- docs/porting/phase7/tooltips-moodles-watch.md Part C). Game/Watch reads and writes it on items; Server/Watch drains.
--
-- A battery lasts LIFETIME_HOURS of game time while the watch is worn or held (v0.9 drained worn watches only; held
-- now counts too, because a held watch also gives the time). A watch in a bag keeps its charge.

local WatchBattery = {}

WatchBattery.KEY = "EHR_WatchBattery"
WatchBattery.VERSION = 1
WatchBattery.LIFETIME_HOURS = 168
WatchBattery.EPSILON = 0.000001
WatchBattery.BATTERY = "Base.Battery"
WatchBattery.TYPES = {
    ["ExtensiveHealth.EHRMedicalWatch_Left"] = true,
    ["ExtensiveHealth.EHRMedicalWatch_Right"] = true,
}

local function clamp01(v)
    v = tonumber(v) or 0
    if v ~= v then
        return 0
    end
    return math.max(0, math.min(1, v))
end

-- A normalised copy of raw modData (nil = a full, installed battery).
function WatchBattery.read(raw)
    if type(raw) ~= "table" then
        return { installed = true, charge = 1 }
    end
    local installed = raw.installed ~= false
    return { installed = installed, charge = installed and clamp01(raw.charge == nil and 1 or raw.charge) or 0 }
end

-- The table to store in modData.
function WatchBattery.toModData(state)
    return { version = WatchBattery.VERSION, installed = state.installed == true,
        charge = state.installed and clamp01(state.charge) or 0 }
end

function WatchBattery.powered(state)
    return state.installed == true and state.charge > WatchBattery.EPSILON
end

-- Whole percent for display and sync: at least 1 while powered, 0 otherwise.
function WatchBattery.percent(state)
    if not WatchBattery.powered(state) then
        return 0
    end
    return math.max(1, math.floor(state.charge * 100 + 0.5))
end

-- Drains minutes of wear. Returns changed, depleted (it just ran out).
function WatchBattery.drain(state, minutes)
    if not WatchBattery.powered(state) or not minutes or minutes <= 0 then
        return false, false
    end
    local before = state.charge
    state.charge = clamp01(before - minutes / 60 / WatchBattery.LIFETIME_HOURS)
    if state.charge <= WatchBattery.EPSILON then
        state.charge = 0
    end
    return state.charge ~= before, state.charge <= 0
end

-- Why a battery with this charge (0-1) can't go in now, or nil.
function WatchBattery.insertRefusal(state, batteryCharge)
    if state.installed then
        return "installed"
    end
    if clamp01(batteryCharge) <= WatchBattery.EPSILON then
        return "empty"
    end
    return nil
end

function WatchBattery.insert(state, batteryCharge)
    state.installed = true
    state.charge = clamp01(batteryCharge)
end

function WatchBattery.removeRefusal(state)
    return not state.installed and "missing" or nil
end

-- Takes the battery out. Returns its charge, which the removed battery keeps.
function WatchBattery.remove(state)
    local charge = state.charge
    state.installed = false
    state.charge = 0
    return charge
end

return WatchBattery
