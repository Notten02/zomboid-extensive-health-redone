-- What the two wild-search panels (Client/HerbalSearch, Client/HiveSearch) share: the short search action that
-- walks up, takes a moment and then asks the server to start (the server answers with a session, and only then does
-- a panel open), texture lookup, the joypad focus hand-over, and position checks. The server decides everything
-- (Server/WildSearch); these files only draw and send intents.
-- From v0.9 c/EHR_HerbalSearch.lua:274-304 and c/EHR_HiveWebSearch.lua:166-200 (docs/porting/phase8/
-- herbal-and-hive-minigames.md sections 1 and 5). Change: the server is asked after the action, not before, so the
-- 42 / 48 s timer starts when the panel opens.

require "TimedActions/ISBaseTimedAction"

local Client = require "ExtensiveHealthRedone/Client/Client"

local WildSearch = {}

WildSearch.ACTION_RANGE = 3.8       -- tiles; v0.9's herbal action limit

local textures = {}

-- A texture under media/textures, or nil when missing (looked up once).
function WildSearch.texture(name)
    if textures[name] == nil then
        textures[name] = getTexture("media/textures/" .. name .. ".png") or false
    end
    return textures[name] or nil
end

-- Distance in tiles from the player to the square's centre (nil on another floor).
function WildSearch.distance(player, x, y, z)
    if math.floor(player:getZ()) ~= z then
        return nil
    end
    local dx, dy = player:getX() - (x + 0.5), player:getY() - (y + 0.5)
    return math.sqrt(dx * dx + dy * dy)
end

-- The player moved more than limit tiles from (x, y) on either axis (v0.9's check).
function WildSearch.moved(player, x, y, limit)
    return math.abs(player:getX() - x) > limit or math.abs(player:getY() - y) > limit
end

-- The square a right-click is about: the first square that passes test(square) among the clicked objects' squares,
-- then the clicked point and its 8 neighbours, nearest first. A tree or a tall bush is drawn up and to the left of
-- its own square, so the point under the cursor is often a neighbour of it; vanilla's foraging menu reads the same
-- 3x3 around the click (ISSearchManager.OnFillWorldObjectContextMenu). Returns the square, or nil.
function WildSearch.findSquare(playerNum, context, worldobjects, test)
    local seen = {}
    local function try(square)
        if square and not seen[square] then
            seen[square] = true
            return test(square)
        end
        return false
    end
    for _, object in ipairs(worldobjects) do
        local square = object:getSquare()
        if try(square) then
            return square
        end
    end
    local player = getSpecificPlayer(playerNum)
    if not player or not context or not context.x then
        return nil
    end
    local z = math.floor(player:getZ())
    local fx, fy = screenToIsoX(playerNum, context.x, context.y, z), screenToIsoY(playerNum, context.x, context.y, z)
    local cx, cy = math.floor(fx), math.floor(fy)
    local around = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = getCell():getGridSquare(cx + dx, cy + dy, z)
            if square then
                local ox, oy = cx + dx + 0.5 - fx, cy + dy + 0.5 - fy
                around[#around + 1] = { square = square, d = ox * ox + oy * oy }
            end
        end
    end
    table.sort(around, function(a, b) return a.d < b.d end)
    for _, entry in ipairs(around) do
        if try(entry.square) then
            return entry.square
        end
    end
    return nil
end

-- Joypad ----------------------------------------------------------------------------------------------------------------

-- Gives a controller player's focus to the panel, so B always closes it and the game doesn't keep the input.
function WildSearch.focus(panel, playerNum)
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, panel)
    end
end

function WildSearch.unfocus(panel, playerNum)
    local joypad = JoypadState.players[playerNum + 1]
    if joypad and joypad.focus == panel then
        setJoypadFocus(playerNum, nil)
    end
end

function WildSearch.panelPosition(playerNum, w, h)
    local x = getPlayerScreenLeft(playerNum) + (getPlayerScreenWidth(playerNum) - w) / 2
    local y = getPlayerScreenTop(playerNum) + (getPlayerScreenHeight(playerNum) - h) / 2
    return math.max(0, math.floor(x)), math.max(0, math.floor(y))
end

-- Search action ---------------------------------------------------------------------------------------------------------

---@class ExtensiveHealthRedoneWildSearchAction : ISBaseTimedAction
---@field square IsoGridSquare
---@field command string
---@field lootPosition string
---@field sent boolean?
local SearchAction = ISBaseTimedAction:derive("ExtensiveHealthRedoneWildSearchAction")

-- command: the server command sent at the end ("herb.begin", "hive.begin").
---@param character IsoPlayer
---@param square IsoGridSquare
---@param command string
---@param ticks number
---@param lootPosition string
---@return ExtensiveHealthRedoneWildSearchAction
function SearchAction:new(character, square, command, ticks, lootPosition)
    local o = ISBaseTimedAction.new(self, character) --[[@as ExtensiveHealthRedoneWildSearchAction]]
    o.square = square
    o.command = command
    o.lootPosition = lootPosition
    o.maxTime = character:isTimedActionInstant() and 1 or ticks
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end

function SearchAction:isValid()
    local d = WildSearch.distance(self.character, self.square:getX(), self.square:getY(), self.square:getZ())
    return d ~= nil and d <= WildSearch.ACTION_RANGE and self.character:getVehicle() == nil
end

function SearchAction:start()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", self.lootPosition)
end

-- Sends at most once (a relaunched action performs again).
function SearchAction:perform()
    if not self.sent then
        self.sent = true
        Client.send(self.character, self.command,
            { x = self.square:getX(), y = self.square:getY(), z = self.square:getZ() })
    end
    ISBaseTimedAction.perform(self)
end

WildSearch.Action = SearchAction

-- Walks next to the square, then runs the search action.
function WildSearch.start(player, square, command, ticks, lootPosition)
    if luautils.walkAdj(player, square, true) then
        ISTimedActionQueue.add(SearchAction:new(player, square, command, ticks, lootPosition))
    end
end

-- The game objects the menu reads squares from need these; built once.
local vegetationApi
function WildSearch.vegetationApi()
    if not vegetationApi then
        vegetationApi = { canBeCut = IsoFlagType.canBeCut, zonesAt = getZones }
    end
    return vegetationApi
end

return WildSearch
