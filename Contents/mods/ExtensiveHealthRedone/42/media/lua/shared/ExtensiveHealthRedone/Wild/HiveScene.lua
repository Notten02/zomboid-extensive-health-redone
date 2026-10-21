-- The hive search's scene on the client: the trunk, the hive and webs the server said the tree holds, the bees and
-- spiders, the start zone, the corridor the hand may move in, and touch tests. Cosmetic and pure (rng passed in);
-- the server never trusts any of it beyond the residual trust noted in Wild/Search.
-- From v0.9 c/EHR_HiveWebSearch.lua:206-375 (docs/porting/phase8/herbal-and-hive-minigames.md section 7). Change:
-- touches are tested along the hand's whole movement since the last update, not one sample per frame (H18), so a
-- fast mouse can't tunnel through a bee.

local HiveScene = {}

HiveScene.HAND_W = 32               -- the hand sprite
HiveScene.HAND_HIT = 24             -- its hit box
HiveScene.DT_MIN = 0.006            -- seconds per update, clamped (v0.9)
HiveScene.DT_MAX = 0.055
HiveScene.JOYPAD_SPEED = 220        -- px/s for the hand on a controller

local BEES = 9
local BEE_W, BEE_H = 22, 18
local SPIDER_W, SPIDER_H = 28, 24
local WEB_SIZE = 58

local function clamp(value, low, high)
    if low > high then
        low, high = high, low
    end
    if value < low then
        return low
    elseif value > high then
        return high
    end
    return value
end

local function lerp(a, b, t)
    return a + (b - a) * clamp(t, 0, 1)
end

local function overlap(a, b)
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

local function inside(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- board: { x, y, w, h } in panel coordinates (v0.9: 24, 112, 612, 390). hive: bool; webs: 0-3.
function HiveScene.new(rng, board, hive, webs)
    local tree = { x = board.x + math.floor(board.w * 0.43), y = board.y + 44, w = 110, h = board.h - 56 }
    local scene = {
        board = board, tree = tree, webs = {}, bees = {}, spiders = {},
        start = { x = board.x + 34, y = board.y + board.h - 42, w = board.w - 68, h = 30 },
    }
    if hive then
        local h = { kind = "hive", x = board.x + math.floor(board.w * 0.5) - 55, y = board.y + 14, w = 110, h = 80 }
        scene.hive = h
        local zone = { x = h.x - 84, y = h.y - 18, w = h.w + 168, h = 150 }
        for _ = 1, BEES do
            local speed = 150 + rng.int(0, 54)
            local angle = rng.int(0, 627) / 100
            local x, y = zone.x + rng.int(0, zone.w - 1), zone.y + rng.int(0, zone.h - 1)
            -- Up to 8 tries for a spot at least 30 px from the other bees.
            for _ = 1, 8 do
                local cx, cy = zone.x + rng.int(0, zone.w - 1), zone.y + rng.int(0, zone.h - 1)
                local clear = true
                for _, bee in ipairs(scene.bees) do
                    local dx, dy = cx - bee.x, cy - bee.y
                    if dx * dx + dy * dy < 900 then
                        clear = false
                        break
                    end
                end
                if clear then
                    x, y = cx, cy
                    break
                end
            end
            scene.bees[#scene.bees + 1] = { kind = "bee", x = x, y = y, w = BEE_W, h = BEE_H,
                vx = math.cos(angle) * speed, vy = math.sin(angle) * speed, zone = zone }
        end
    end
    local slots = {
        { x = tree.x - 54, y = tree.y + 72 },
        { x = tree.x + tree.w - 10, y = tree.y + math.floor(tree.h * 0.45) },
        { x = tree.x - 48, y = tree.y + math.floor(tree.h * 0.70) },
    }
    webs = math.max(0, math.min(#slots, webs or 0))
    for i = 1, webs do
        scene.webs[i] = { kind = "web", x = slots[i].x, y = slots[i].y, w = WEB_SIZE, h = WEB_SIZE }
    end
    local spiders = webs > 0 and webs + (hive and 1 or 0) or 0
    for _ = 1, spiders do
        local speed = 118 + rng.int(0, 41)
        local dir = rng.int(0, 1) == 0 and -1 or 1
        scene.spiders[#scene.spiders + 1] = { kind = "spider",
            x = tree.x + 12 + rng.int(0, math.max(1, tree.w - 34) - 1),
            y = tree.y + 16 + rng.int(0, math.max(1, tree.h - 42) - 1),
            w = SPIDER_W, h = SPIDER_H, vx = dir * speed * 0.35, vy = rng.int(0, 1) == 0 and -speed or speed,
            zone = tree }
    end
    return scene
end

local function move(mover, dt)
    local z = mover.zone
    mover.x = mover.x + mover.vx * dt
    mover.y = mover.y + mover.vy * dt
    if mover.x < z.x then
        mover.x, mover.vx = z.x, math.abs(mover.vx)
    end
    if mover.y < z.y then
        mover.y, mover.vy = z.y, math.abs(mover.vy)
    end
    if mover.x + mover.w > z.x + z.w then
        mover.x, mover.vx = z.x + z.w - mover.w, -math.abs(mover.vx)
    end
    if mover.y + mover.h > z.y + z.h then
        mover.y, mover.vy = z.y + z.h - mover.h, -math.abs(mover.vy)
    end
end

-- Moves the bees and spiders by dt real seconds (clamped). Returns the clamped dt.
function HiveScene.step(scene, dt)
    dt = clamp(dt, HiveScene.DT_MIN, HiveScene.DT_MAX)
    for _, bee in ipairs(scene.bees) do
        move(bee, dt)
    end
    for _, spider in ipairs(scene.spiders) do
        move(spider, dt)
    end
    return dt
end

-- The corridor's left and right limits for the hand's centre at height y: the trunk, widening toward the hive near
-- the top and toward each web around its height.
function HiveScene.bounds(scene, y)
    local tr, half = scene.tree, HiveScene.HAND_W / 2
    local left, right = tr.x + half, tr.x + tr.w - half
    local h = scene.hive
    if h then
        local from, to = tr.y + 132, h.y + h.h * 0.45
        local t = clamp((from - y) / math.max(1, from - to), 0, 1)
        left = lerp(left, h.x + half, t)
        right = lerp(right, h.x + h.w - half, t)
    end
    for _, web in ipairs(scene.webs) do
        local t = 1 - clamp(math.abs(y - (web.y + web.h / 2)) / 54, 0, 1)
        if t > 0 then
            left = math.min(left, lerp(left, web.x + half, t))
            right = math.max(right, lerp(right, web.x + web.w - half, t))
        end
    end
    return left, right
end

-- Clamps a wanted hand position into the corridor, from the hive (or trunk) top down to the start zone.
function HiveScene.constrain(scene, x, y)
    local half = HiveScene.HAND_W / 2
    local top = scene.tree.y + half
    if scene.hive then
        top = math.min(top, scene.hive.y + half)
    end
    local cy = clamp(y, top, scene.start.y + scene.start.h / 2)
    local left, right = HiveScene.bounds(scene, cy)
    return clamp(x, left, right), cy
end

function HiveScene.handBox(x, y)
    local half = HiveScene.HAND_HIT / 2
    return { x = x - half, y = y - half, w = HiveScene.HAND_HIT, h = HiveScene.HAND_HIT }
end

-- The first bee or spider the hand touches moving from (x0, y0) to (x1, y1), tested every half hit box along the
-- way. Returns "bee", "spider" or nil.
function HiveScene.touch(scene, x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / (HiveScene.HAND_HIT / 2)))
    for i = 0, steps do
        local box = HiveScene.handBox(x0 + dx * i / steps, y0 + dy * i / steps)
        for _, bee in ipairs(scene.bees) do
            if overlap(box, bee) then
                return "bee"
            end
        end
        for _, spider in ipairs(scene.spiders) do
            if overlap(box, spider) then
                return "spider"
            end
        end
    end
    return nil
end

-- The hive or web under the hand, or nil.
function HiveScene.targetAt(scene, x, y)
    local box = HiveScene.handBox(x, y)
    if scene.hive and not scene.hive.pending and overlap(box, scene.hive) then
        return scene.hive
    end
    for _, web in ipairs(scene.webs) do
        if not web.pending and overlap(box, web) then
            return web
        end
    end
    return nil
end

function HiveScene.inStart(scene, x, y)
    return inside(x, y, scene.start)
end

function HiveScene.remove(scene, target)
    if target == scene.hive then
        scene.hive = nil
        return
    end
    for i = #scene.webs, 1, -1 do
        if scene.webs[i] == target then
            table.remove(scene.webs, i)
            return
        end
    end
end

function HiveScene.isEmpty(scene)
    return scene.hive == nil and #scene.webs == 0
end

return HiveScene
