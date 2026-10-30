-- The look of our panels (EHR Monitor, Immune System, handbook): a "worn medical device" palette and drawing
-- helpers, on any ISUIElement. Colour names are also what the view models (UI/*) use.

local Draw = {}

Draw.FONT_SMALL = UIFont.Small
Draw.FONT_MEDIUM = UIFont.Medium
Draw.FONT_LARGE = UIFont.Large
Draw.SMALL = getTextManager():getFontHeight(UIFont.Small)
Draw.MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
Draw.LARGE = getTextManager():getFontHeight(UIFont.Large)
Draw.PAD = 10

-- { r, g, b, a }
Draw.C = {
    background = { 0.025, 0.025, 0.028, 0.97 },
    panel = { 0.055, 0.055, 0.06, 0.94 },
    panelSoft = { 0.09, 0.085, 0.085, 0.72 },
    border = { 0.48, 0.14, 0.12, 1 },
    borderDim = { 0.24, 0.10, 0.09, 1 },
    text = { 0.92, 0.91, 0.86, 1 },
    dim = { 0.62, 0.62, 0.62, 1 },
    green = { 0.22, 0.88, 0.30, 1 },
    blue = { 0.20, 0.78, 1.0, 1 },
    yellow = { 0.95, 0.74, 0.18, 1 },
    orange = { 1.0, 0.36, 0.12, 1 },
    red = { 0.86, 0.05, 0.045, 1 },
    redDark = { 0.30, 0.015, 0.015, 1 },
    purple = { 0.58, 0.20, 0.72, 1 },
    track = { 0.025, 0.025, 0.028, 0.90 },
}

function Draw.color(name)
    return Draw.C[name] or Draw.C.text
end

function Draw.rect(ui, x, y, w, h, c, alpha)
    ui:drawRect(x, y, w, h, alpha or c[4], c[1], c[2], c[3])
end

function Draw.border(ui, x, y, w, h, c, alpha)
    ui:drawRectBorder(x, y, w, h, alpha or c[4], c[1], c[2], c[3])
end

-- Text cut to fit maxW with "...".
function Draw.fit(text, font, maxW)
    local tm = getTextManager()
    if not maxW or tm:MeasureStringX(font, text) <= maxW then
        return text
    end
    local cut = text
    while #cut > 1 and tm:MeasureStringX(font, cut .. "...") > maxW do
        cut = cut:sub(1, #cut - 1)
    end
    return cut .. "..."
end

function Draw.width(text, font)
    return getTextManager():MeasureStringX(font or UIFont.Small, text)
end

-- Draws text in a named colour (or an rgba table); maxW cuts it. align: "left" (default), "right", "centre".
function Draw.text(ui, text, x, y, color, font, maxW, align)
    font = font or UIFont.Small
    local c = type(color) == "table" and color or Draw.color(color or "text")
    text = Draw.fit(text, font, maxW)
    if align == "right" then
        ui:drawTextRight(text, x, y, c[1], c[2], c[3], c[4], font)
    elseif align == "centre" then
        ui:drawTextCentre(text, x, y, c[1], c[2], c[3], c[4], font)
    else
        ui:drawText(text, x, y, c[1], c[2], c[3], c[4], font)
    end
end

-- Word-wraps text into lines no wider than maxW (spaces only; a long word stays whole).
function Draw.wrap(text, font, maxW)
    local lines, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if line ~= "" and Draw.width(candidate, font) > maxW then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

-- A framed box with an optional title (Medium, red) and 24 px icon; returns the y below the title.
function Draw.frame(ui, x, y, w, h, title, icon)
    Draw.rect(ui, x, y, w, h, Draw.C.panel)
    Draw.border(ui, x, y, w, h, Draw.C.borderDim)
    Draw.rect(ui, x + 1, y + 1, w - 2, 1, Draw.C.border, 0.35)
    if not title then
        return y + Draw.PAD
    end
    local tx = x + Draw.PAD
    if icon then
        ui:drawTextureScaled(icon, tx, y + 6, 24, 24, 1, 1, 1, 1)
        tx = tx + 30
    end
    Draw.text(ui, title, tx, y + 6, "red", UIFont.Medium, w - (tx - x) - Draw.PAD)
    local line = y + math.max(30, Draw.MEDIUM + 10)
    Draw.rect(ui, x + Draw.PAD, line, w - 2 * Draw.PAD, 1, Draw.C.border, 0.6)
    return line + 6
end

-- A section title: a dark red band with red Medium text. Returns the y below it.
function Draw.section(ui, title, x, y, w)
    local h = Draw.MEDIUM + 8
    Draw.rect(ui, x, y, w, h, Draw.C.redDark, 0.46)
    Draw.text(ui, title, x + 8, y + 4, "red", UIFont.Medium, w - 16)
    Draw.rect(ui, x, y + h - 1, w, 1, Draw.C.border, 0.8)
    return y + h + 6
end

-- A bar: dark track, fill share 0-1 in a colour, a soft highlight, a border, and an optional marker at a share.
function Draw.bar(ui, x, y, w, h, share, color, marker)
    share = math.max(0, math.min(1, share or 0))
    local c = type(color) == "table" and color or Draw.color(color or "green")
    Draw.rect(ui, x, y, w, h, Draw.C.track)
    local fill = math.floor((w - 2) * share + 0.5)
    if fill > 0 then
        ui:drawRect(x + 1, y + 1, fill, h - 2, 0.88, c[1], c[2], c[3])
        if h >= 8 then
            ui:drawRect(x + 1, y + 1, fill, math.max(2, math.floor(h * 0.18)), 0.20, 1.0, 0.88, 0.72)
        end
    end
    Draw.border(ui, x, y, w, h, Draw.C.borderDim)
    if marker then
        local mx = x + math.floor((w - 2) * math.max(0, math.min(1, marker)))
        Draw.rect(ui, mx, y - 2, 2, h + 4, Draw.C.text)
    end
end

-- An 8x8 colour swatch.
function Draw.swatch(ui, x, y, color)
    local c = type(color) == "table" and color or Draw.color(color)
    ui:drawRect(x, y, 8, 8, 1, c[1], c[2], c[3])
end

-- Room left beside the last tab of vanilla's character window, so a full tab strip doesn't look cramped (and at
-- least 1 pixel, or the strip shows a needless scroll arrow).
Draw.TAB_SPARE = 16

-- The width of every tab of the tab panel a view sits in (vanilla's character window) plus TAB_SPARE, so our views
-- never make the tab strip scroll; 0 outside a tab panel.
function Draw.tabsWidth(view)
    local panel = view.parent --[[@as ISTabPanel?]]
    if panel and panel.getWidthOfAllTabs then
        return panel:getWidthOfAllTabs() + Draw.TAB_SPARE
    end
    return 0
end

-- Vanilla scrolls the tab strip when its tabs don't fit (on a narrower vanilla tab) and leaves it scrolled. Once our
-- wider view makes them fit, scroll it back so no tab is cut off.
function Draw.fitTabs(view)
    local panel = view.parent --[[@as ISTabPanel?]]
    if panel and panel.getWidthOfAllTabs and (panel.scrollX or 0) < 0 and panel:getWidthOfAllTabs() <= panel.width then
        panel.scrollX = 0
    end
end

-- Our button look: dark red with a red border and light text, readable on our panels (vanilla's default is dark grey
-- on dark).
function Draw.styleButton(button)
    button.backgroundColor = { r = 0.30, g = 0.015, b = 0.015, a = 0.95 }
    button.backgroundColorMouseOver = { r = 0.55, g = 0.08, b = 0.06, a = 1 }
    button.borderColor = { r = 0.86, g = 0.05, b = 0.045, a = 1 }
    button.textColor = { r = 0.95, g = 0.94, b = 0.90, a = 1 }
end

local textures = {}

-- A texture from common/media/textures by name (without .png), cached; nil when missing.
function Draw.texture(name)
    if not name then
        return nil
    end
    local t = textures[name]
    if t == nil then
        t = getTexture("media/textures/" .. name .. ".png") or false
        textures[name] = t
    end
    return t or nil
end

return Draw
