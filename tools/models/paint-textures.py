#!/usr/bin/env python3
"""Paints the world-model texture of every item in ehr_models.ITEMS and writes the model script that ties each item's
model to its mesh and texture. Original artwork drawn from scratch with Pillow, in each item's icon colours.

    python3 tools/models/paint-textures.py            writes ehr_models.TEX_DIR/World_<Item>.png and SCRIPT_FILE
    python3 tools/models/paint-textures.py --out DIR  writes the textures and the script under DIR (a scratch check)

Run from the repo root. Each texture follows the UV layout of its mesh: ours from ehr_models.py, vanilla's as
measured from the vanilla .fbx (noted at each painter). Every rect is drawn at 4x on its own canvas and scaled down,
so neighbouring rects don't bleed into each other. No red cross anywhere (see tools/make-release-art.py).
"""
import argparse
import math
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ehr_models as M  # noqa: E402

SS = 4  # supersampling


def rgb(h):
    return M.hex_rgb(h) if isinstance(h, str) else h


def shade(h, f):
    """f < 1 darkens, f > 1 lightens towards white."""
    r, g, b = rgb(h)
    if f <= 1:
        return tuple(int(c * f) for c in (r, g, b))
    k = f - 1
    return tuple(int(c + (255 - c) * k) for c in (r, g, b))


def mix(a, b, t):
    a, b = rgb(a), rgb(b)
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Region:
    """A rect of the final texture, drawn at SS x on its own canvas. Coordinates are in final-texture pixels
    relative to the rect, as floats."""

    def __init__(self, tex, rect, bg):
        self.tex, self.rect = tex, rect
        x0, y0, x1, y1 = rect
        self.w, self.h = x1 - x0, y1 - y0
        self.im = Image.new("RGB", (self.w * SS, self.h * SS), rgb(bg))
        self.d = ImageDraw.Draw(self.im)

    def _s(self, box):
        return [v * SS for v in box]

    def rect_(self, box, fill, outline=None, width=0):
        x0, y0, x1, y1 = box
        self.d.rectangle(self._s((x0, y0, x1 - 1 / SS, y1 - 1 / SS)), fill=rgb(fill),
                         outline=rgb(outline) if outline else None, width=int(width * SS))

    def rrect(self, box, radius, fill, outline=None, width=0):
        x0, y0, x1, y1 = box
        self.d.rounded_rectangle(self._s((x0, y0, x1, y1)), radius=radius * SS, fill=rgb(fill),
                                 outline=rgb(outline) if outline else None, width=int(width * SS))

    def ellipse(self, box, fill, outline=None, width=0):
        self.d.ellipse(self._s(box), fill=rgb(fill) if fill else None, outline=rgb(outline) if outline else None,
                       width=int(width * SS))

    def circle(self, cx, cy, r, fill, outline=None, width=0):
        self.ellipse((cx - r, cy - r, cx + r, cy + r), fill, outline, width)

    def poly(self, pts, fill):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=rgb(fill))

    def line(self, pts, fill, width):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=rgb(fill), width=max(1, int(width * SS)))

    def done(self):
        small = self.im.resize((self.w, self.h), Image.LANCZOS)
        self.tex.paste(small, self.rect[:2])


def text_lines(r, x, y, widths, colour, gap=2.0, thick=0.9):
    """Unreadable 'printing': short bars standing in for text, the way vanilla's small textures do."""
    for i, w in enumerate(widths):
        r.rect_((x, y + i * gap, x + w, y + i * gap + thick), colour)


# ---- symbols for cartons and sachets, drawn into a box (x, y, size) ------------------------------------------------

def symbol(r, kind, x, y, s, mark, accent, base):
    c = (x + s / 2, y + s / 2)
    dark = shade(mark, 0.6)
    if kind == "tablets":  # a blister strip: 2 x 3 tablets
        r.rrect((x, y + s * 0.15, x + s, y + s * 0.85), s * 0.08, shade(base, 0.85), shade(base, 0.6), 0.25)
        for i in range(3):
            for j in range(2):
                r.circle(x + s * (0.2 + 0.3 * i), y + s * (0.35 + 0.3 * j), s * 0.11, mark, dark, 0.25)
    elif kind == "capsule":
        a = math.radians(-30)
        dx, dy = math.cos(a) * s * 0.36, math.sin(a) * s * 0.36
        w = s * 0.17
        r.line([(c[0] - dx, c[1] - dy), c], accent, w * 2)
        r.line([c, (c[0] + dx, c[1] + dy)], mark, w * 2)
        r.circle(c[0] - dx, c[1] - dy, w, accent)
        r.circle(c[0] + dx, c[1] + dy, w, mark)
    elif kind == "drop":
        r.poly([(c[0], y + s * 0.08), (c[0] + s * 0.3, c[1] + s * 0.1), (c[0] - s * 0.3, c[1] + s * 0.1)], mark)
        r.circle(c[0], c[1] + s * 0.14, s * 0.3, mark)
        r.circle(c[0] - s * 0.1, c[1] + s * 0.1, s * 0.07, shade(mark, 1.5))
    elif kind == "vial":
        for k, off in enumerate((-0.2, 0.2)):
            vx = c[0] + off * s
            r.rrect((vx - s * 0.12, y + s * 0.25, vx + s * 0.12, y + s * 0.92), s * 0.05, (236, 240, 242),
                    shade(base, 0.55), 0.25)
            r.rect_((vx - s * 0.1, y + s * 0.55, vx + s * 0.1, y + s * 0.9), mark)
            r.rect_((vx - s * 0.13, y + s * 0.1, vx + s * 0.13, y + s * 0.27), accent)
    elif kind == "syringe":
        yy = c[1]
        r.rect_((x + s * 0.25, yy - s * 0.1, x + s * 0.8, yy + s * 0.1), (236, 240, 242), mark, 0.25)
        r.rect_((x + s * 0.5, yy - s * 0.08, x + s * 0.79, yy + s * 0.08), mix(mark, base, 0.4))
        r.line([(x + s * 0.02, yy), (x + s * 0.25, yy)], dark, 0.4)
        r.line([(x + s * 0.8, yy), (x + s * 0.97, yy)], mark, s * 0.06)
        r.rect_((x + s * 0.93, yy - s * 0.14, x + s, yy + s * 0.14), mark)
    elif kind == "patch":
        r.rrect((x + s * 0.05, y + s * 0.2, x + s * 0.95, y + s * 0.8), s * 0.25, mark, dark, 0.25)
        r.rrect((x + s * 0.32, y + s * 0.33, x + s * 0.68, y + s * 0.67), s * 0.08, shade(mark, 1.45))
    elif kind == "inhaler":
        r.rrect((x + s * 0.2, y + s * 0.1, x + s * 0.55, y + s * 0.75), s * 0.1, mark, dark, 0.25)
        r.rrect((x + s * 0.2, y + s * 0.6, x + s * 0.92, y + s * 0.9), s * 0.08, accent, dark, 0.25)
    elif kind == "powder":
        r.rrect((x + s * 0.15, y + s * 0.1, x + s * 0.85, y + s * 0.9), s * 0.06, mark, dark, 0.25)
        r.rect_((x + s * 0.15, y + s * 0.1, x + s * 0.85, y + s * 0.25), accent)
        for i in range(5):
            r.circle(x + s * (0.3 + 0.1 * i), y + s * (0.6 + 0.08 * (i % 2)), s * 0.04, shade(mark, 1.6))
    elif kind == "tube":
        r.poly([(x + s * 0.05, y + s * 0.3), (x + s * 0.7, y + s * 0.38), (x + s * 0.7, y + s * 0.62),
                (x + s * 0.05, y + s * 0.7)], mark)
        r.rect_((x + s * 0.02, y + s * 0.26, x + s * 0.1, y + s * 0.74), dark)
        r.rect_((x + s * 0.7, y + s * 0.4, x + s * 0.95, y + s * 0.6), accent)
    elif kind == "mask":
        r.line([(x, y + s * 0.4), (x + s, y + s * 0.4)], shade(base, 0.55), 0.4)
        r.ellipse((x + s * 0.15, y + s * 0.15, x + s * 0.85, y + s * 0.85), mark, dark, 0.3)
        r.ellipse((x + s * 0.35, y + s * 0.42, x + s * 0.65, y + s * 0.72), shade(mark, 1.5))
    elif kind == "snow":
        for k in range(3):
            a = math.pi * k / 3
            dx, dy = math.cos(a) * s * 0.42, math.sin(a) * s * 0.42
            r.line([(c[0] - dx, c[1] - dy), (c[0] + dx, c[1] + dy)], mark, s * 0.08)
        r.circle(c[0], c[1], s * 0.1, base)
    elif kind == "sun":
        for k in range(8):
            a = math.pi * k / 4
            r.line([(c[0] + math.cos(a) * s * 0.28, c[1] + math.sin(a) * s * 0.28),
                    (c[0] + math.cos(a) * s * 0.46, c[1] + math.sin(a) * s * 0.46)], mark, s * 0.08)
        r.circle(c[0], c[1], s * 0.22, accent, mark, 0.3)
    else:
        raise ValueError("unknown symbol " + kind)


# ---- our meshes ------------------------------------------------------------------------------------------------------

def paint_carton(spec):
    tw, th = M.CARTON["tex"]
    rects = M.CARTON["rects"]
    base, accent, mark = spec["base"], spec["accent"], spec["mark"]
    tex = Image.new("RGB", (tw, th), rgb(base))
    if spec["symbol"] == "screen":
        return paint_case(tex, spec)
    ink = shade(accent, 0.55) if sum(rgb(base)) > 380 else shade(base, 1.6)
    # top: an accent band with "printed" name, a symbol, text lines
    r = Region(tex, rects["top"], base)
    r.rect_((0, 0, r.w, 8), accent)
    r.rect_((0, 8, r.w, 9), shade(accent, 0.7))
    text_lines(r, 2.5, 2.2, [16, 10], shade(accent, 1.7), gap=2.6, thick=1.2)
    r.rect_((0, r.h - 3, r.w, r.h), accent)
    symbol(r, spec["symbol"], r.w - 18, 10.5, 15, mark, accent, base)
    text_lines(r, 3, 12, [14, 18, 11, 16], ink, gap=2.4, thick=0.9)
    r.rect_((3, r.h - 7, 9, r.h - 4.5), ink)  # dosage box
    r.done()
    # long sides: band continued, small print
    r = Region(tex, rects["side"], base)
    r.rect_((0, 0, r.w, 4.5), accent)
    text_lines(r, 3, 7, [20, 12], ink, gap=2.4)
    r.rect_((r.w - 12, 7, r.w - 3, r.h - 2), shade(base, 0.88), ink, 0.25)  # barcode panel
    for i in range(7):
        r.rect_((r.w - 11 + i * 1.2, 7.8, r.w - 10.5 + i * 1.2, r.h - 2.8), ink)
    r.done()
    # ends: accent with the flap edge
    r = Region(tex, rects["end"], accent)
    r.rect_((0, r.h * 0.55, r.w, r.h), shade(accent, 0.85))
    r.rect_((3, 3, r.w - 3, 5), shade(accent, 1.6))
    r.done()
    return tex


def paint_case(tex, spec):
    """AntibodyTestKit: a dark rugged case with a screen (uses the carton mesh, scaled up)."""
    rects = M.CARTON["rects"]
    base, trim, screen = spec["base"], spec["accent"], spec["mark"]
    r = Region(tex, rects["top"], base)
    r.rect_((0, 0, r.w, r.h), base, trim, 1.2)
    r.rrect((4, 4, 27, 20), 1.5, shade(base, 0.6), trim, 0.6)
    r.rect_((5.5, 5.5, 25.5, 18.5), screen)
    for i in range(3):
        r.rect_((7, 7.5 + i * 3.4, 7 + (14, 9, 12)[i], 8.7 + i * 3.4), shade(screen, 0.45))
    r.circle(34, 8, 2.4, (190, 50, 44), shade(base, 0.5), 0.3)
    r.circle(41, 8, 2.4, (226, 226, 220), shade(base, 0.5), 0.3)
    for i in range(3):
        r.rect_((31, 14 + i * 3, 44, 15.2 + i * 3), shade(trim, 1.2))
    r.rect_((4, 23, 44, 25), trim)
    r.done()
    r = Region(tex, rects["side"], base)
    r.rect_((0, 0, r.w, 2), trim)
    for x in (6, 40):
        r.rect_((x, 4, x + 4, 11), shade(trim, 0.8))
    r.done()
    r = Region(tex, rects["end"], base)
    r.rect_((0, 0, r.w, 2), trim)
    r.rect_((8, 5, r.w - 8, 11), shade(base, 0.7), trim, 0.4)
    r.done()
    return tex


def lathe_bands(spec, mesh, extra=None):
    """A lathe strip texture: each profile segment a band of its key's colour, then extra(region, u_px) decals."""
    tw, th = mesh["tex"]
    tex = Image.new("RGB", (tw, th))
    u = M.lathe_u(mesh)
    r = Region(tex, (0, 0, tw, th), (0, 0, 0))
    for i, key in enumerate(mesh["keys"]):
        r.rect_((u[i] * tw, 0, max(u[i + 1] * tw, u[i] * tw + 1 / SS), th), spec[key])
    upx = {}  # key -> (start, end) in px of its first..last segment
    for i, key in enumerate(mesh["keys"]):
        s, e = upx.get(key, (u[i] * tw, u[i + 1] * tw))
        upx[key] = (min(s, u[i] * tw), max(e, u[i + 1] * tw))
    if extra:
        extra(r, upx)
    r.done()
    return tex


def paint_pen(spec):
    def decals(r, upx):
        x0, x1 = upx["window"]
        if "logo" in spec:  # epinephrine: a red ring logo and printing on the white body
            r.circle((x0 + x1) / 2, 8, 3.2, None, spec["logo"], 1.3)
            r.circle((x0 + x1) / 2, 8, 1.0, spec["logo"])
            text_lines(r, x0 + 4, 6, [10, 7], shade(spec["logo"], 0.8), gap=2.5)
            text_lines(r, x1 - 16, 6, [12, 8], shade(spec["logo"], 0.8), gap=2.5)
        else:  # a glass window: glare line and dose marks
            r.rect_((x0, 2, x1, 3.3), shade(spec["window"], 1.45))
            for k in range(5):
                xx = x0 + 5 + k * (x1 - x0 - 10) / 4
                r.rect_((xx, 11, xx + 0.8, 14), shade(spec["window"], 0.55))
        a0, a1 = upx["lower"]
        for k in range(3):  # grip ridges
            xx = a0 + 3 + k * 2.4
            r.rect_((xx, 0, xx + 0.9, r.h), shade(spec["lower"], 0.78))
        c0, c1 = upx["cap"]
        r.rect_((c0 + 2, 0, c0 + 3, r.h), shade(spec["cap"], 0.75))

    return lathe_bands(spec, M.PEN, decals)


def paint_syringe(spec):
    def decals(r, upx):
        x0, x1 = upx["barrel"]
        for k in range(9):
            xx = x0 + 4 + k * (x1 - x0 - 8) / 8
            r.rect_((xx, 1, xx + 0.7, 4 if k % 2 else 6), spec["ticks"])
        r.rect_((x0, 9, x1, 10), shade(spec["barrel"], 1.4))

    return lathe_bands(spec, M.SYRINGE, decals)


def paint_tablets(spec):
    col = spec["colour"]
    keys = {"bottom": shade(col, 0.9), "bevel": shade(col, 0.88), "edge": shade(col, 0.8), "top": col}

    def decals(r, upx):
        x0, x1 = upx["top"]
        r.rect_((x0 + (x1 - x0) * 0.45, 0, x0 + (x1 - x0) * 0.55, r.h), shade(col, 0.82))  # imprint ring

    return lathe_bands(keys, M.TABLET, decals)


def paint_gun(spec):
    tw, th = M.GUN["tex"]
    rc = M.GUN["rects"]
    tex = Image.new("RGB", (tw, th), rgb(spec["dark"]))
    body = spec["body"]
    r = Region(tex, rc["body"], body)
    r.rect_((0, 0, r.w, 3), shade(body, 1.25))
    r.rect_((0, r.h - 3, r.w, r.h), shade(body, 0.7))
    r.line([(4, 6), (4, 26)], shade(body, 0.65), 0.6)
    r.line([(18, 6), (18, 26)], shade(body, 0.65), 0.6)
    r.rrect((21, 10, 29, 22), 1, spec["dark"], spec["metal"], 0.5)
    r.rect_((22.5, 11.5, 27.5, 14), spec["vial"])
    r.circle(9, 16, 2, spec["accent"])
    r.circle(13, 16, 1.2, spec["vial"])
    r.done()
    for key in ("top", "grip", "metal", "vialcap", "accent", "dark"):
        r = Region(tex, rc[key], spec[key])
        if key == "grip":
            for k in range(4):
                r.rect_((0, 3 + k * 3.2, r.w, 4 + k * 3.2), shade(spec["grip"], 0.6))
        if key == "metal":
            r.rect_((0, 0, r.w, r.h * 0.4), shade(spec["metal"], 1.3))
        if key == "top":
            r.rect_((0, r.h * 0.4, r.w, r.h * 0.6), shade(spec["top"], 0.75))
        r.done()
    r = Region(tex, rc["vial"], spec["vial"])  # strip: s along the vial, t around
    r.rect_((0, 0, r.w, r.h * 0.18), shade(spec["vial"], 1.5))
    r.rect_((0, r.h * 0.5, r.w, r.h * 0.56), shade(spec["vial"], 1.3))
    r.done()
    return tex


def paint_ivbag(spec):
    tw, th = M.IVBAG["tex"]
    rc = M.IVBAG["rects"]
    tex = Image.new("RGB", (tw, th), rgb(spec["rim"]))
    r = Region(tex, rc["face"], spec["bag"])
    r.rect_((0, 0, r.w, r.h), spec["bag"], spec["rim"], 1.6)
    r.rect_((3, 3, r.w - 3, 6), shade(spec["bag"], 1.35))  # sheen
    r.rect_((14, 9, 46, 31), spec["label"], shade(spec["lines"], 1.2), 0.4)
    text_lines(r, 17, 12, [18, 12, 22, 9, 15], spec["lines"], gap=3.2, thick=1.1)
    for k in range(6):  # volume marks along the edge
        r.rect_((50, 8 + k * 4, 54 if k % 2 else 56, 8.8 + k * 4), spec["lines"])
    r.done()
    for key in ("port", "drip", "tube", "clamp"):
        r = Region(tex, rc[key], spec[key])
        if key == "drip":
            r.rect_((0, 0, r.w, 3), shade(spec["drip"], 1.3))
        r.done()
    return tex


def paint_strips(spec):
    tw, th = M.STRIPS["tex"]
    tex = Image.new("RGB", (tw, th))
    r = Region(tex, M.STRIPS["rects"]["strip"], spec["colour"])
    for k in range(0, 16, 4):
        r.rect_((0, k, 16, k + 1.2), shade(spec["colour"], 1.25))
    r.rect_((0, 14, 16, 16), shade(spec["colour"], 0.85))
    r.done()
    return tex


# ---- vanilla meshes (UV layouts measured from the vanilla .fbx) -----------------------------------------------------

def paint_sachet(spec):
    """WorldItems/ColdPack, 64x128: both faces share x 0-50 (rows run along the pack), x 50-64 is the side seam,
    the crimped seals are the end rows."""
    tex = Image.new("RGB", (64, 128), rgb(spec["base"]))
    base, accent, mark = spec["base"], spec["accent"], spec["mark"]
    r = Region(tex, (0, 0, 50, 128), base)
    for y0, y1 in ((0, 10), (118, 128)):
        r.rect_((0, y0, 50, y1), shade(base, 0.86))
        for x in range(0, 50, 3):
            r.rect_((x, y0, x + 1, y1), shade(base, 0.76))
    r.rect_((0, 22, 50, 46), accent)
    text_lines(r, 6, 27, [30, 22, 26], shade(accent, 1.7), gap=5, thick=2.2)
    symbol(r, spec["symbol"], 13, 56, 24, mark, accent, base)
    text_lines(r, 6, 88, [34, 24, 30, 18], shade(mark, 1.1), gap=4.5, thick=1.6)
    r.rect_((0, 106, 50, 110), accent)
    r.done()
    r = Region(tex, (50, 0, 64, 128), shade(base, 0.9))
    r.done()
    return tex


def paint_jar(spec):
    """WorldItems/PowderedJar, 64x64: the side wraps the full width, rows top to bottom; rows 0-10 are the lid, which
    also holds the lid's top disc (x 0-14, y 1-8)."""
    tex = Image.new("RGB", (64, 64), rgb(spec["body"]))
    r = Region(tex, (0, 0, 64, 64), spec["body"])
    lid = spec["lid"]
    r.rect_((0, 0, 64, 10), lid)
    for x in range(16, 64, 3):
        r.rect_((x, 1, x + 1, 9), shade(lid, 0.75))  # grip ridges, kept off the top disc
    r.rect_((0, 10, 64, 11.5), shade(lid, 0.6))
    r.rect_((0, 18, 64, 52), spec["label"])
    r.rect_((0, 22, 64, 28), spec["accent"])
    text_lines(r, 4, 32, [18, 12, 15, 9], shade(spec["label"], 0.45), gap=3.4, thick=1.4)
    text_lines(r, 36, 32, [16, 20, 10], shade(spec["label"], 0.45), gap=3.4, thick=1.4)
    r.rect_((0, 58, 64, 64), shade(spec["body"], 0.85))
    if spec is M.ITEMS["FootPowder"]:  # shaker holes in the lid's top disc
        for cx, cy in ((5, 3), (8, 3), (6.5, 5.5), (9.5, 5.5)):
            r.circle(cx, cy, 0.7, shade(lid, 0.5))
    r.done()
    return tex


def paint_bottle(spec):
    """WorldItems/Disinfectant, 128x128: the side wraps the full width, rows top to bottom (0-16 cap, 16-32
    shoulder); the cap's top disc is x 1-21, y 1-21."""
    tex = Image.new("RGB", (128, 128), rgb(spec["glass"]))
    glass = spec["glass"]
    r = Region(tex, (0, 0, 128, 128), glass)
    r.rect_((0, 0, 128, 16), spec["cap"])
    for x in range(24, 128, 4):
        r.rect_((x, 1, x + 1.2, 15), shade(spec["cap"], 0.78))
    r.rect_((0, 16, 128, 18), shade(glass, 0.7))
    for x in (20, 52, 84, 116):  # glass highlights
        r.rect_((x, 18, x + 3, 112), shade(glass, 1.35))
    r.rect_((0, 46, 128, 98), spec["label"])
    r.rect_((0, 50, 128, 60), spec["accent"])
    text_lines(r, 8, 64, [40, 28, 34, 20], shade(spec["label"], 0.4), gap=6, thick=2.4)
    text_lines(r, 70, 64, [36, 44, 24], shade(spec["label"], 0.4), gap=6, thick=2.4)
    r.rect_((0, 112, 128, 128), shade(glass, 0.75))
    r.done()
    return tex


def paint_tub(spec):
    """WorldItems/SourCream, 64x64: lid disc x 0-32, y 0-32; bottom disc x 2-31, y 33-62; the side wraps x 33-63
    (height runs along x)."""
    tex = Image.new("RGB", (64, 64), rgb(spec["side"]))
    r = Region(tex, (0, 0, 32, 32), spec["side"])
    r.circle(16, 16, 14.5, spec["cream"], shade(spec["side"], 0.8), 1.4)
    for k, rad in enumerate((10, 6.5, 3)):  # swirl of the open cream
        r.ellipse((16 - rad, 16 - rad * 0.8, 16 + rad, 16 + rad * 0.8), None, shade(spec["cream"], 1.25), 0.8)
    r.circle(19, 12, 1.5, shade(spec["cream"], 1.35))
    r.done()
    r = Region(tex, (33, 0, 64, 64), spec["side"])
    r.rect_((10, 0, 21, 64), spec["label"])
    r.rect_((14, 0, 16, 64), spec["accent"])
    for y in range(4, 60, 7):
        r.rect_((18, y, 19.2, y + 4), shade(spec["label"], 0.5))
    r.rect_((0, 0, 2, 64), shade(spec["side"], 0.8))
    r.done()
    return tex


def paint_poultice(spec):
    """WorldItems/Poultice, 64x64: one planar island for each side."""
    tex = Image.new("RGB", (64, 64))
    r = Region(tex, (0, 0, 64, 64), spec["cloth"])
    for k in range(0, 64, 2):
        r.rect_((k, 0, k + 0.6, 64), spec["weave"])
        r.rect_((0, k, 64, k + 0.6), spec["weave"])
    cream = spec["cream"]
    r.ellipse((16, 18, 48, 44), cream)
    r.ellipse((24, 12, 42, 30), cream)
    r.ellipse((20, 22, 34, 32), shade(cream, 1.4))
    r.ellipse((36, 30, 44, 37), shade(cream, 0.92))
    r.done()
    return tex


PAINTERS = {"carton": paint_carton, "pen": paint_pen, "syringe": paint_syringe, "tablets": paint_tablets,
            "gun": paint_gun, "ivbag": paint_ivbag, "strips": paint_strips, "sachet": paint_sachet,
            "jar": paint_jar, "bottle": paint_bottle, "tub": paint_tub, "poultice": paint_poultice}


def model_script():
    out = ["module ExtensiveHealth", "{",
           "    /** World models (items dropped on the floor). Generated by tools/models/paint-textures.py from",
           "        tools/models/ehr_models.py: edit those and re-run, don't edit this file by hand. **/", ""]
    for item, spec in M.ITEMS.items():
        if spec["kind"] == "vanilla":
            continue
        mesh, scale = M.item_mesh(item)
        out +=["    model %s" % M.model_name(item), "    {", "        mesh = %s," % mesh,
                "        texture = EHR/World_%s," % item]
        if scale != 1.0:
            out.append("        scale = %g," % scale)
        out += ["    }", ""]
    out[-1:] = ["}", ""]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", help="write under this directory instead of the mod")
    a = ap.parse_args()
    tex_dir = os.path.join(a.out, "textures") if a.out else M.TEX_DIR
    script = os.path.join(a.out, os.path.basename(M.SCRIPT_FILE)) if a.out else M.SCRIPT_FILE
    os.makedirs(tex_dir, exist_ok=True)
    n = 0
    for item, spec in M.ITEMS.items():
        if spec["kind"] == "vanilla":
            continue
        PAINTERS[spec["kind"]](spec).save(os.path.join(tex_dir, "World_%s.png" % item), optimize=True)
        n += 1
    with open(script, "w", newline="\n") as f:
        f.write(model_script())
    print("wrote %d textures to %s and %s" % (n, tex_dir, script))


if __name__ == "__main__":
    main()
