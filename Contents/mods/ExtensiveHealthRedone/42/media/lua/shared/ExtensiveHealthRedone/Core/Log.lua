-- Levelled logger. A disabled level costs one comparison: arguments are only turned into text when the level is on.
--
--   local log = Log.new("Sync", print, "info")
--   log:debug("sent", count, "sections")    -- "[ExtensiveHealthRedone] DEBUG Sync: sent 3 sections"
--   if log:enabled("trace") then log:trace(expensiveDump()) end
--
-- Arguments are joined with spaces through tostring, so there are no format strings and no Kahlua string.format
-- quirks to worry about.

local Log = {}

Log.LEVELS = { off = 0, error = 1, warn = 2, info = 3, debug = 4, trace = 5 }

local PREFIX = "[ExtensiveHealthRedone] "

local Logger = {}
Logger.__index = Logger

local function levelValue(name)
    local value = Log.LEVELS[name]
    if not value then
        error("unknown log level " .. tostring(name), 3)
    end
    return value
end

-- tag: short module name shown in each line. sink: function(line), e.g. print. level: a name from Log.LEVELS.
function Log.new(tag, sink, level)
    return setmetatable({ tag = tag, sink = sink, level = levelValue(level or "info") }, Logger)
end

function Logger:setLevel(name)
    self.level = levelValue(name)
end

function Logger:enabled(name)
    return Log.LEVELS[name] <= self.level
end

local function emit(self, label, value, ...)
    if value > self.level then
        return
    end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    self.sink(PREFIX .. label .. " " .. self.tag .. ": " .. table.concat(parts, " "))
end

function Logger:error(...) emit(self, "ERROR", 1, ...) end
function Logger:warn(...) emit(self, "WARN", 2, ...) end
function Logger:info(...) emit(self, "INFO", 3, ...) end
function Logger:debug(...) emit(self, "DEBUG", 4, ...) end
function Logger:trace(...) emit(self, "TRACE", 5, ...) end

-- A logger that drops everything; the default where a module's logger is optional.
Log.silent = Log.new("silent", function() end, "off")

return Log
