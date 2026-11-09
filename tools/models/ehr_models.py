"""Shared data for the mod's 3D world models: which mesh each item uses, the UV layouts of our own meshes, and the
colours each texture is painted in (taken from the item's inventory icon).

Imported by the three tools in this folder:
    blender -b --factory-startup --python tools/models/build-meshes.py      builds our meshes, writes the .fbx files
    python3 tools/models/paint-textures.py                                  paints every texture, writes the model
                                                                            script EHR_WorldModels.txt
    blender -b --factory-startup --python tools/models/render-previews.py -- OUT_DIR
                                                                            renders each item's model (a dev check)

Run them from the repo root. Pure Python, no imports, so it loads both in Blender's Python and in the system one.

Units: metres. Project Zomboid sizes a model as its FBX vertices x node scale x the script's `scale`, in metres
(vanilla's carton comes out at about 8 cm, its cold pack at 11 cm). build-meshes.py exports with "FBX Units Scale"
so the vertices are plain metres and the script scale is 1. Every mesh lies on the floor: Z up, bottom at Z=0,
centred on X and Y.
"""

MOD = "Contents/mods/ExtensiveHealthRedone"
MESH_DIR = MOD + "/common/media/models_X/EHR"   # script: mesh = EHR/<name>
TEX_DIR = MOD + "/common/media/textures/EHR"    # script: texture = EHR/World_<Item>
SCRIPT_FILE = MOD + "/42/media/scripts/EHR_WorldModels.txt"
VANILLA_MEDIA = "/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid/media"  # previews only

# ---------------------------------------------------------------------------------------------------------------
# Our own meshes. Rects are (x0, y0, x1, y1) in texture pixels, origin top left.
# ---------------------------------------------------------------------------------------------------------------

# Medicine carton, lying flat. Vanilla's SleepingTablets carton has the right shape, but its UV islands overlap
# (top, bottom and sides share pixels), so it can't be repainted cleanly.
CARTON = {
    "size": (0.090, 0.055, 0.026),
    "tex": (64, 64),
    "rects": {"top": (0, 0, 48, 29), "side": (0, 29, 48, 43), "end": (0, 43, 29, 57)},  # bottom reuses top
}

# Lathe meshes: a profile of (x, radius) points turned around the X axis (the Z axis for tablets). A radius of 0
# closes an end. Each segment between two points has a colour key; the texture is a strip whose u runs along the
# profile (by length) and whose v runs around, so a segment paints as a band and an end face as rings.
PEN = {
    "points": [(0.000, 0.0), (0.000, 0.0045), (0.007, 0.0060), (0.012, 0.0095), (0.050, 0.0100), (0.053, 0.0100),
               (0.118, 0.0100), (0.121, 0.0110), (0.146, 0.0110), (0.150, 0.0080), (0.150, 0.0032),
               (0.1505, 0.0)],
    "keys": ["tipend", "tip", "tip", "lower", "ring", "window", "ring", "cap", "cap", "capend", "button"],
    "segments": 14,
    "tex": (128, 16),
}

SYRINGE = {
    "points": [(0.000, 0.0), (0.000, 0.0007), (0.024, 0.0007), (0.024, 0.0022), (0.030, 0.0045), (0.034, 0.0080),
               (0.104, 0.0080), (0.104, 0.0125), (0.107, 0.0125), (0.107, 0.0030), (0.133, 0.0030),
               (0.133, 0.0095), (0.137, 0.0095), (0.137, 0.0)],
    "keys": ["needle", "needle", "hub", "hub", "shoulder", "barrel", "flange", "flange", "flange", "rod", "thumb",
             "thumb", "thumb"],
    "segments": 12,
    "tex": (128, 16),
}

TABLET = {  # one tablet, turned around Z; TABLETS places three
    "points": [(0.0, 0.0), (0.0, 0.0085), (0.0012, 0.0105), (0.0058, 0.0105), (0.0070, 0.0085), (0.0070, 0.0)],
    "keys": ["bottom", "bevel", "edge", "bevel", "top"],
    "segments": 16,
    "tex": (32, 8),
    "placements": [(-0.012, -0.007, 0.0), (0.011, -0.005, 0.0), (0.000, 0.012, 0.0)],
}

# Injector gun (GeneTherapyKit, ImmunoboosterShot), built from boxes and cylinders. Each part maps into one rect.
GUN = {
    "tex": (64, 64),
    "rects": {"body": (0, 0, 32, 32), "top": (32, 0, 64, 16), "grip": (32, 16, 48, 32), "metal": (48, 16, 64, 32),
              "vial": (0, 32, 16, 48), "vialcap": (16, 32, 32, 48), "accent": (32, 32, 48, 48),
              "dark": (48, 32, 64, 48)},
}

# IV bag lying flat, with a drip chamber and a coiled tube.
IVBAG = {
    "size": (0.150, 0.100, 0.028),
    "tex": (64, 64),
    "rects": {"face": (0, 0, 60, 40), "rim": (0, 48, 8, 56), "port": (8, 48, 16, 56), "drip": (16, 48, 24, 56),
              "tube": (24, 48, 32, 56), "clamp": (32, 48, 40, 56)},
}

STRIPS = {"tex": (16, 16), "rects": {"strip": (0, 0, 16, 16)}}

MESHES = {"Carton": CARTON, "Pen": PEN, "Syringe": SYRINGE, "Tablets": TABLET, "InjectorGun": GUN,
          "IVBag": IVBAG, "PlasticStrips": STRIPS}

# Vanilla meshes we only repaint: mesh path, vanilla script scale, texture size.
VANILLA_MESHES = {
    "sachet": ("WorldItems/ColdPack", 0.2, (64, 128)),
    "jar": ("WorldItems/PowderedJar", 0.15, (64, 64)),
    "bottle": ("WorldItems/Disinfectant", 0.4, (128, 128)),
    "tub": ("WorldItems/SourCream", 0.4, (64, 64)),
    "poultice": ("WorldItems/Poultice", 0.6, (64, 64)),
}

# ---------------------------------------------------------------------------------------------------------------
# Items. kind picks the mesh and the painter; the rest are colours from the icon. No red cross anywhere: a red
# cross on white is the protected Red Cross emblem (see tools/make-release-art.py).
# ---------------------------------------------------------------------------------------------------------------

def carton(base, accent, mark, symbol, scale=1.0):
    """symbol: tablets, capsule, drop, vial, syringe, patch, inhaler, powder, tube, mask, leaf"""
    return {"kind": "carton", "base": base, "accent": accent, "mark": mark, "symbol": symbol, "scale": scale}


def pen(**colours):
    return {"kind": "pen", **colours}


def iv_pen(liquid, button):
    return pen(tipend="#d9dcdf", tip="#b9bec3", lower="#ece6da", ring="#8f969c", window=liquid, cap="#f2eee6",
               capend="#f2eee6", button=button)


EPI = pen(tipend="#2a2626", tip="#2a2626", lower="#c0362e", ring="#7e1e1a", window="#efe9e2", cap="#b52a24",
          capend="#b52a24", button="#8c1d18", logo="#c0362e")

ITEMS = {
    # Cartons
    "IVKit": carton("#ebe1d6", "#a8352f", "#8e524a", "drop"),
    "Syringe": carton("#ece6da", "#5f8a87", "#6f7a76", "syringe"),
    "AntipyreticTablets": carton("#e3eef4", "#4f86bd", "#e08a5a", "tablets"),
    "ElectrolytePowder": carton("#f2e9dd", "#3f8f96", "#84bec0", "powder"),
    "BronchodilatorInhaler": carton("#eef0ec", "#3f7f8c", "#6a9da7", "inhaler"),
    "AntiNauseaTablets": carton("#ece9df", "#5f9474", "#83a490", "tablets"),
    "AntiInflammatory": carton("#f1ebe3", "#c47426", "#e1a86a", "tablets"),
    "AntiDiarrheal": carton("#eee8da", "#5f7f69", "#9fb4a6", "tablets"),
    "MuscleRelaxants": carton("#eee7dc", "#55606a", "#a3a5a5", "tablets"),
    "CoughSuppressant": carton("#ebe4da", "#56527a", "#8e899b", "tablets"),
    "AntisepticCream": carton("#f0e9df", "#4a7a69", "#98b1a7", "tube"),
    "BlisterPatches": carton("#f4efe6", "#d0782a", "#dda879", "patch"),
    "AntiviralCapsules": carton("#ece6dc", "#2f6260", "#3a8fd0", "capsule"),
    "PrescriptionAntibiotics": carton("#f0e8dc", "#4a6d65", "#92aaa2", "capsule"),
    "AntifungalTablets": carton("#f4f1ec", "#6a5a86", "#9c8bb5", "tablets"),
    "AntiparasiticPills": carton("#e9e0d0", "#7a1f27", "#c0442f", "capsule"),
    "TopicalPermethrin": carton("#f5efe3", "#b8383b", "#e1c0b7", "tube"),
    "Furosemide": carton("#f2ece3", "#62786c", "#aeb9b2", "tablets"),
    "Antipsychotics": carton("#ede4d9", "#64506c", "#a79b9e", "tablets"),
    "DualOrexinReceptor": carton("#ede2d7", "#56578a", "#aeaaae", "tablets"),
    "Buprenorphine": carton("#e2f2f6", "#a84d68", "#9c7881", "tablets"),
    "TetanusAntitoxin": carton("#f2eee6", "#335c2e", "#9fbf9a", "vial"),
    "BroadSpectrumAntibiotics": carton("#f4ead6", "#bd9a32", "#7e7954", "capsule"),
    "RespiratorySupportKit": carton("#e6e4da", "#4f5b53", "#a3b8b3", "mask", scale=1.25),
    "ChelationKit": carton("#f2c14a", "#222a5c", "#851734", "vial", scale=1.25),
    "TetanusImmunoglobulin": carton("#f6f0ea", "#8a7a40", "#c2b79b", "vial"),
    "EmergencySepsisKit": carton("#e3e0d0", "#4e5a36", "#97957c", "vial", scale=1.25),
    "AntibodyTestKit": carton("#2e2c2a", "#6b5a42", "#7fb5a8", "screen", scale=1.3),
    # Pen injectors
    "Epinephrine": EPI,
    "LastChanceEpinephrine": EPI,
    "CorticosteroidInjection": iv_pen("#a51b25", "#3f9a5a"),
    "IVAntibiotics": iv_pen("#3d74a4", "#c8302c"),
    "IVMetronidazole": iv_pen("#2c2624", "#c8302c"),
    "IVAmphotericin": iv_pen("#3f884b", "#c8302c"),
    "AlbendazoleInjection": iv_pen("#a2328f", "#d9d0e0"),
    "IVCiprofloxacin": iv_pen("#8a5a2e", "#3fa6a6"),
    "IVVancomycin": iv_pen("#c2b62f", "#e08a2a"),
    # Injector guns
    "GeneTherapyKit": {"kind": "gun", "body": "#2f5d9a", "top": "#24497a", "grip": "#2b2c30", "metal": "#8b8995",
                       "vial": "#c42a26", "vialcap": "#5a1a18", "accent": "#e0e6ef", "dark": "#191f28"},
    "ImmunoboosterShot": {"kind": "gun", "body": "#7a3a8f", "top": "#5c2a6c", "grip": "#2b2c30", "metal": "#8b8995",
                          "vial": "#2f3fb0", "vialcap": "#1a1f5a", "accent": "#e6dcef", "dark": "#191922"},
    # Other own meshes
    "HomemadeSyringe": {"kind": "syringe", "needle": "#b8bcc0", "hub": "#3f5a8a", "shoulder": "#d9dee2",
                        "barrel": "#dde3e8", "ticks": "#3f4d6a", "flange": "#e8ecef", "rod": "#c8ccd2",
                        "thumb": "#3f5a8a"},
    "HomemadeIVKit": {"kind": "ivbag", "bag": "#d2e0e6", "label": "#f4f2ea", "lines": "#8a8f92", "rim": "#c9cfd0",
                      "port": "#9a9a94", "drip": "#d0d6d8", "tube": "#cfd3d2", "clamp": "#4f9a5a"},
    "HomemadeMuscleRelaxant": {"kind": "tablets", "colour": "#9a7a74", "scale": 1.6},
    "HomemadePainkillers": {"kind": "tablets", "colour": "#d6cfca", "scale": 1.6},
    "HomemadeSleepingPills": {"kind": "tablets", "colour": "#6f86a0", "scale": 1.6},
    "PlantBasedAntibiotics": {"kind": "tablets", "colour": "#aba048", "scale": 1.6},
    "PlasticStrips": {"kind": "strips", "colour": "#e2ddd6"},
    # Vanilla meshes, our texture
    "ColdFluTablets": {"kind": "sachet", "symbol": "tablets", "base": "#f6f8f6", "accent": "#3fb851",
                       "mark": "#276a6d"},
    "OralRehydrationKit": {"kind": "sachet", "symbol": "drop", "base": "#ebe9e1", "accent": "#4f9a96",
                           "mark": "#85897c"},
    "InstantIcePack": {"kind": "sachet", "symbol": "snow", "base": "#d6dee8", "accent": "#4f78a8", "mark": "#2f4f78"},
    "WarmingPack": {"kind": "sachet", "symbol": "sun", "base": "#f6e9d4", "accent": "#c8702f", "mark": "#8a4a1f"},
    "NitricOxideBooster": {"kind": "jar", "body": "#4a1f5c", "lid": "#2c1238", "label": "#e6dccf",
                           "accent": "#8a5a9a"},
    "CombatStimulants": {"kind": "jar", "body": "#2b2519", "lid": "#1a1814", "label": "#c6b19a", "accent": "#8a2a1d"},
    "FootPowder": {"kind": "jar", "body": "#e8edf3", "lid": "#b9c0c8", "label": "#3f69a8", "accent": "#f4f6f9"},
    "CoughSyrup": {"kind": "bottle", "glass": "#6a2a1c", "cap": "#dcc8b4", "label": "#ede1cf", "accent": "#9c3a2c",
                   "scale": 0.28},
    "HomemadeCoughSyrup": {"kind": "bottle", "glass": "#4a2a1a", "cap": "#a88c6c", "label": "#d8c4aa",
                           "accent": "#6a4a30", "scale": 0.28},
    "HomemadeTopicalPermethrin": {"kind": "tub", "cream": "#e4cc98", "side": "#b8a888", "label": "#d9cba8",
                                  "accent": "#938264"},
    "HomemadeAntisepticCream": {"kind": "poultice", "cloth": "#d6cbb0", "weave": "#c2b594", "cream": "#fbf8ee",
                                "scale": 0.45},
    # Vanilla model as is: the item uses vanilla's caffeine pill icon
    "PhalanxPills": {"kind": "vanilla", "model": "CaffeinePills"},
}

# Which of our meshes each kind uses (kinds missing here use a vanilla mesh).
KIND_MESH = {"carton": "Carton", "pen": "Pen", "gun": "InjectorGun", "syringe": "Syringe", "ivbag": "IVBag",
             "tablets": "Tablets", "strips": "PlasticStrips"}


def model_name(item):
    return "EHR_World_" + item


def item_mesh(item):
    """(mesh as the model script names it, script scale) of an item that has a model block. An item's own "scale"
    overrides the default (1 for our meshes, vanilla's own scale for a vanilla mesh)."""
    spec = ITEMS[item]
    kind = spec["kind"]
    if kind in KIND_MESH:
        return "EHR/" + KIND_MESH[kind], spec.get("scale", 1.0)
    mesh, scale, _ = VANILLA_MESHES[kind]
    return mesh, spec.get("scale", scale)


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lathe_u(spec):
    """Cumulative profile length at each point, scaled 0..1: the u of each ring of the lathe strip."""
    pts = spec["points"]
    d = [0.0]
    for (x0, r0), (x1, r1) in zip(pts, pts[1:]):
        d.append(d[-1] + ((x1 - x0) ** 2 + (r1 - r0) ** 2) ** 0.5)
    return [v / d[-1] for v in d]
