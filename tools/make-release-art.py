#!/usr/bin/env python3
"""Generates the mod's icon, poster and Workshop preview. Original artwork, drawn from scratch with Pillow.

    python3 tools/make-release-art.py            writes the three files below
    python3 tools/make-release-art.py --out DIR  writes them under DIR instead (a scratch check)

Outputs (paths relative to the repo root):
    Contents/mods/ExtensiveHealthRedone/42/icon.png     256x256 RGBA  mod.info icon=
    Contents/mods/ExtensiveHealthRedone/42/poster.png   512x512 RGB   mod.info poster=
    preview.png                                         256x256 RGB   Workshop item preview (the in-game uploader
                                                                      demands exactly 256x256 and at most 1000 KB)

The motif is a blood drop with a pulse line, on a dark monitor-like background. There is deliberately no cross: a
red cross on white is the Red Cross emblem, a protected symbol. No Project Zomboid art or name is used.

Needs only Python 3 and Pillow (`pip install --user pillow` or the distro package). Text uses the first of a few common
bold sans-serif fonts that is installed (DejaVu, Liberation, Noto), else Pillow's built-in font, so the lettering can
differ a little between machines. Everything is drawn at 4x and scaled down for smooth edges.
"""
import argparse
import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("Pillow is required: pip install --user pillow (or your distro's python-pillow package)")

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MOD_DIR = os.path.join(REPO, "Contents", "mods", "ExtensiveHealthRedone", "42")
SS = 4  # supersampling factor

BG_TOP = (36, 21, 26)
BG_BOTTOM = (13, 10, 12)
GRID = (255, 255, 255, 14)
BLOOD = (200, 30, 46)
BLOOD_DARK = (122, 12, 26)
BLOOD_LIGHT = (236, 78, 88)
PULSE = (247, 242, 240)
TEXT_DIM = (176, 160, 162)

FONT_CANDIDATES = [
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/Library/Fonts/Arial Bold.ttf",
]

# One heartbeat, x in 0..1 across the width, y as a fraction of the amplitude (negative is up).
PULSE_SHAPE = [
    (0.00, 0.00), (0.20, 0.00), (0.25, -0.10), (0.30, 0.00), (0.38, 0.00), (0.42, 0.14),
    (0.49, -0.62), (0.56, 0.36), (0.61, 0.00), (0.70, 0.00), (0.76, -0.17), (0.82, 0.00), (1.00, 0.00),
]


def font(px):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, px)
    try:
        return ImageFont.load_default(px)
    except TypeError:  # Pillow older than 10.1 has no sized built-in font
        return ImageFont.load_default()


def lerp(a, b, t):
    return a + (b - a) * t


def vertical_gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        px.line([(0, y), (w, y)], fill=tuple(int(lerp(top[i], bottom[i], t)) for i in range(3)))
    return img


def bezier(p0, p1, p2, steps=24):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


def drop_polygon(cx, cy, r, height):
    """A teardrop: a circle of radius r centred (cx, cy) with a curved point `height` above the centre."""
    tip = (cx, cy - height)
    cos_t = r / height
    sin_t = math.sqrt(1 - cos_t * cos_t)
    right = (cx + r * sin_t, cy - r * cos_t)
    left = (cx - r * sin_t, cy - r * cos_t)
    # The sides curve inwards a little (concave), which reads as a drop rather than a cone.
    pull = r * 0.16
    mid_r = ((tip[0] + right[0]) / 2 - pull, (tip[1] + right[1]) / 2 + pull * 0.2)
    mid_l = ((tip[0] + left[0]) / 2 + pull, (tip[1] + left[1]) / 2 + pull * 0.2)
    pts = bezier(tip, mid_r, right)
    a0 = math.atan2(right[1] - cy, right[0] - cx)
    a1 = math.atan2(left[1] - cy, left[0] - cx) + 2 * math.pi
    for i in range(1, 80):
        a = lerp(a0, a1, i / 80)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    pts += list(reversed(bezier(tip, mid_l, left)))
    return pts


def draw_polyline(draw, pts, width, fill):
    for a, b in zip(pts, pts[1:]):
        draw.line([a, b], fill=fill, width=int(width))
    rad = width / 2
    for x, y in pts:
        draw.ellipse([x - rad, y - rad, x + rad, y + rad], fill=fill)


def draw_drop_with_pulse(img, cx, cy, r, height, pulse_w, pulse_amp, pulse_thick, pulse_x0, pulse_x1):
    """Draws the drop (with shading) and the pulse line over it onto img (RGBA, already at supersampled size)."""
    poly = drop_polygon(cx, cy, r, height)

    # Soft shadow under the drop.
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + r * 0.05, y + r * 0.10) for x, y in poly], fill=(0, 0, 0, 150))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(r * 0.10)))

    # Body: dark outline, then the red fill slightly smaller, then a lighter inner area for volume.
    d = ImageDraw.Draw(img)
    d.polygon(poly, fill=BLOOD_DARK)
    inner = Image.new("L", img.size, 0)
    ImageDraw.Draw(inner).polygon(poly, fill=255)
    shrink = inner.filter(ImageFilter.MinFilter(max(3, int(r * 0.07) // 2 * 2 + 1)))
    body = Image.new("RGBA", img.size, BLOOD + (255,))
    img.paste(body, (0, 0), shrink)

    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - r * 0.78, cy - r * 0.55, cx - r * 0.18, cy + r * 0.25], fill=BLOOD_LIGHT + (150,))
    glow = glow.filter(ImageFilter.GaussianBlur(r * 0.16))
    clip = Image.new("L", img.size, 0)
    ImageDraw.Draw(clip).polygon(poly, fill=255)
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", img.size, 0), clip))
    img.alpha_composite(glow)

    # A thin highlight arc along the lower left of the round part.
    hl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    rr = r * 0.74
    ImageDraw.Draw(hl).arc([cx - rr, cy - rr, cx + rr, cy + rr], 140, 205, fill=(255, 255, 255, 110), width=max(2, int(r * 0.07)))
    img.alpha_composite(hl.filter(ImageFilter.GaussianBlur(r * 0.012)))

    # Pulse line: a dark halo for separation, then the white line.
    pts = [(pulse_x0 + (pulse_x1 - pulse_x0) * x, cy + r * 0.05 + pulse_amp * y) for x, y in PULSE_SHAPE]
    halo = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_polyline(ImageDraw.Draw(halo), pts, pulse_thick * 1.9, (20, 6, 10, 170))
    img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(pulse_thick * 0.5)))
    line = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_polyline(ImageDraw.Draw(line), pts, pulse_thick, PULSE + (255,))
    img.alpha_composite(line)


def background(size, vignette=True, grid=True):
    s = size * SS
    img = vertical_gradient(s, s, BG_TOP, BG_BOTTOM).convert("RGBA")
    if grid:
        g = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        gd = ImageDraw.Draw(g)
        step = s // 16
        for i in range(0, s + 1, step):
            gd.line([(i, 0), (i, s)], fill=GRID, width=max(1, SS // 2))
            gd.line([(0, i), (s, i)], fill=GRID, width=max(1, SS // 2))
        img.alpha_composite(g)
    if vignette:
        v = Image.new("L", (s, s), 0)
        ImageDraw.Draw(v).ellipse([-s * 0.15, -s * 0.15, s * 1.15, s * 1.15], fill=255)
        v = v.filter(ImageFilter.GaussianBlur(s * 0.12))
        dark = Image.new("RGBA", (s, s), (0, 0, 0, 120))
        dark.putalpha(Image.eval(v, lambda p: 120 - int(p * 120 / 255)))
        img.alpha_composite(dark)
    return img


def fit_text(draw, text, max_w, start_px):
    px = start_px
    while px > 6:
        f = font(px)
        box = draw.textbbox((0, 0), text, font=f)
        if box[2] - box[0] <= max_w:
            return f, box
        px -= 2
    f = font(6)
    return f, draw.textbbox((0, 0), text, font=f)


def centered_text(img, text, cy, max_w, start_px, fill, shadow=True):
    draw = ImageDraw.Draw(img)
    f, box = fit_text(draw, text, max_w, start_px)
    w, h = box[2] - box[0], box[3] - box[1]
    x = (img.width - w) / 2 - box[0]
    y = cy - h / 2 - box[1]
    if shadow:
        draw.text((x + SS, y + SS * 1.5), text, font=f, fill=(0, 0, 0, 200))
    draw.text((x, y), text, font=f, fill=fill)


def make_icon(size=256):
    s = size * SS
    img = background(size, vignette=False, grid=False)
    # Rounded-square plate with transparent corners.
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.18), fill=255)
    cx, cy, r = s * 0.5, s * 0.65, s * 0.225
    draw_drop_with_pulse(img, cx, cy, r, r * 2.45, 0, s * 0.27, s * 0.055, s * 0.07, s * 0.93)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    # Thin red rim so the plate holds its shape on dark list backgrounds.
    rim = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([SS, SS, s - SS - 1, s - SS - 1], radius=int(s * 0.18), outline=BLOOD_DARK + (255,), width=SS * 3)
    out.alpha_composite(rim)
    return out.resize((size, size), Image.LANCZOS)


def make_poster(size=512, subtitle=True):
    s = size * SS
    img = background(size)
    cx, cy, r = s * 0.5, s * 0.48, s * 0.165
    draw_drop_with_pulse(img, cx, cy, r, r * 2.55, 0, s * 0.19, s * 0.030, s * 0.06, s * 0.94)
    centered_text(img, "EXTENSIVE HEALTH", s * 0.745, s * 0.84, int(s * 0.082), PULSE + (255,))
    centered_text(img, "REDONE", s * 0.855, s * 0.60, int(s * 0.125), BLOOD_LIGHT + (255,))
    if subtitle:
        centered_text(img, "BLOOD  \u00b7  DISEASE  \u00b7  MEDICATION  \u00b7  IMMUNITY", s * 0.943, s * 0.84,
                      int(s * 0.034), TEXT_DIM + (255,), shadow=False)
    return img.convert("RGB").resize((size, size), Image.LANCZOS)


def save_png(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print(f"wrote {os.path.relpath(path, REPO) if path.startswith(REPO) else path}  {img.size[0]}x{img.size[1]}  {os.path.getsize(path)} bytes")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", help="write under this directory instead of the repo (same relative layout)")
    args = ap.parse_args()
    root = os.path.abspath(args.out) if args.out else REPO
    mod_dir = os.path.join(root, os.path.relpath(MOD_DIR, REPO))

    save_png(make_icon(256), os.path.join(mod_dir, "icon.png"))
    save_png(make_poster(512), os.path.join(mod_dir, "poster.png"))
    # The in-game uploader requires exactly 256x256 and at most 1000 KB (vanilla UI_WorkshopError_Preview*).
    preview = make_poster(256, subtitle=False)
    path = os.path.join(root, "preview.png")
    save_png(preview, path)
    assert preview.size == (256, 256) and os.path.getsize(path) <= 1000 * 1000


if __name__ == "__main__":
    main()
