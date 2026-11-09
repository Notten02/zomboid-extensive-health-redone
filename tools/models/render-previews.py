"""Renders the world models for a visual check (a dev tool; nothing here ships).

    blender -b --factory-startup --python tools/models/render-previews.py -- OUT_DIR [MESH_DIR TEX_DIR]
    blender -b --factory-startup --python tools/models/render-previews.py -- --showcase OUT.png [MESH_DIR TEX_DIR]

Run from the repo root. Writes OUT_DIR/item_<Item>.png (each model alone, framed to fit) and OUT_DIR/lineup.png
(every model at its in-game size, next to a few vanilla items for reference), seen from Project Zomboid's camera
angle. MESH_DIR and TEX_DIR default to the mod's; vanilla meshes come from ehr_models.VANILLA_MEDIA. Blender's
renderer is not the game's: lighting and filtering differ, so check the result in game too.

--showcase instead drops every model onto a table with Blender's physics and renders the heap in Cycles at 1920x1080,
for the Steam Workshop page (a few minutes on a CPU). The heap is the same on every run (fixed random seed).
"""
import importlib
import math
import os
import random
import sys

import addon_utils
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ehr_models as M  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
SHOWCASE = bool(argv) and argv[0] == "--showcase"
if SHOWCASE:
    argv = argv[1:]
OUT = argv[0]
MESH_DIR = argv[1] if len(argv) > 1 else M.MESH_DIR
TEX_DIR = argv[2] if len(argv) > 2 else M.TEX_DIR
V = M.VANILLA_MEDIA

parse_fbx = importlib.import_module(
    [m.__name__ for m in addon_utils.modules() if m.__name__.endswith("io_scene_fbx")][0] + ".parse_fbx")


def unit_scale(path):
    root, _ = parse_fbx.parse(path)
    gs = [e for e in root.elems if e.id == b"GlobalSettings"][0]
    for p in [e for e in gs.elems if e.id == b"Properties70"][0].elems:
        if p.props[0] == b"UnitScaleFactor":
            return p.props[4]
    return 1.0


def load(fbx, tex, script_scale, interpolation="Closest"):
    """Imports fbx at its in-game size (vertices x node scale x script scale, in metres) with tex on it."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    obs = [o for o in bpy.data.objects if o not in before]
    for o in [o for o in obs if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    obs = [o for o in obs if o.name in bpy.data.objects and o.type == "MESH"]
    k = script_scale * 100.0 / unit_scale(fbx)  # Blender applies UnitScaleFactor/100; the game doesn't
    img = bpy.data.images.load(tex, check_existing=True)
    mat = bpy.data.materials.new("m")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    ti = nt.nodes.new("ShaderNodeTexImage")
    ti.image = img
    ti.interpolation = interpolation
    nt.links.new(ti.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    for o in obs:
        o.scale = o.scale * k
        o.data.materials.clear()
        o.data.materials.append(mat)
    bpy.context.view_layer.update()
    return obs


def item_source(item):
    spec = M.ITEMS[item]
    kind = spec["kind"]
    if kind == "vanilla":
        return V + "/models_X/CaffinePills.fbx", V + "/textures/CaffeinePills.png", 0.1
    tex = os.path.join(TEX_DIR, "World_%s.png" % item)
    mesh, scale = M.item_mesh(item)
    if kind in M.KIND_MESH:
        return os.path.join(MESH_DIR, M.KIND_MESH[kind] + ".fbx"), tex, scale
    return "%s/models_X/%s.fbx" % (V, mesh), tex, scale


def bounds(obs):
    pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


def setup_scene(res_x, res_y):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = res_x, res_y
    sc.view_settings.view_transform = "Standard"
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.5, 0.5, 0.5, 1)
    bg.inputs[1].default_value = 0.9
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.0
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(40), math.radians(10), math.radians(30))
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    return sc, co, cam


def aim(co, cam, lo, hi, margin):
    """PZ's camera: looking down at about 30 degrees, rotated 45 degrees."""
    ctr, rad = (lo + hi) / 2, (hi - lo).length / 2
    el, yaw = math.radians(30), math.radians(45)
    d = Vector((math.cos(el) * math.sin(yaw), -math.cos(el) * math.cos(yaw), math.sin(el)))
    co.location = ctr + d * rad * 10
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam.ortho_scale = rad * 2 * margin
    cam.clip_end = rad * 40


def floor(size):
    bpy.ops.mesh.primitive_plane_add(size=size)
    p = bpy.context.active_object
    mat = bpy.data.materials.new("floor")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.33, 0.3, 0.27, 1)
    p.data.materials.append(mat)


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    items = list(M.ITEMS)
    for item in items:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        sc, co, cam = setup_scene(256, 256)
        obs = load(*item_source(item))
        aim(co, cam, *bounds(obs), 1.2)
        render(os.path.join(OUT, "item_%s.png" % item))
    # line-up at in-game size, with vanilla references in the first row
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc, co, cam = setup_scene(1800, 1200)
    refs = [(V + "/models_X/WorldItems/SleepingTablets.fbx", V + "/textures/WorldItems/SleepingTablets.png", 0.4),
            (V + "/models_X/WorldItems/Marker.fbx", V + "/textures/WorldItems/Marker_Red.png", 1.0),
            (V + "/models_X/WorldItems/Disinfectant.fbx", V + "/textures/WorldItems/BottleOfDisinfectant.png", 0.4),
            (V + "/models_X/WorldItems/ColdPack.fbx", V + "/textures/WorldItems/Icepack.png", 0.2)]
    sources = refs + [item_source(i) for i in items]
    cols, step = 10, 0.2
    for n, src in enumerate(sources):
        obs = load(*src)
        row, col = divmod(n + (6 if n >= len(refs) else 0), cols)
        lo, hi = bounds(obs)
        off = Vector((col * step, -row * step, 0)) - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0))
        for o in obs:
            o.location += off
    allobs = [o for o in bpy.data.objects if o.type == "MESH"]
    lo, hi = bounds(allobs)
    floor(10)
    bpy.context.active_object.location = ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0)
    aim(co, cam, lo, hi, 0.95)
    render(os.path.join(OUT, "lineup.png"))
    print("RENDERED", len(items), "items to", OUT)


def showcase(path):
    """Every model dropped onto a table with rigid-body physics, rendered in Cycles."""
    k = 10.0  # the physics engine is unreliable at centimetre scale, so the whole scene is built 10x larger
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    rng = random.Random(42)
    bpy.ops.rigidbody.world_add()
    sc.rigidbody_world.substeps_per_frame = 20
    sc.rigidbody_world.solver_iterations = 30
    sc.frame_end = sc.rigidbody_world.point_cache.frame_end = 260
    items = list(M.ITEMS)
    rng.shuffle(items)
    items.sort(key=lambda i: M.ITEMS[i]["kind"] in ("carton", "ivbag", "sachet", "poultice"), reverse=True)
    for n, item in enumerate(items):  # flat things first, so they end up underneath
        obs = load(*item_source(item), interpolation="Linear")
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.scale = o.scale * k
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        a, rad = rng.uniform(0, 2 * math.pi), 0.9 * math.sqrt(rng.random())
        ob.location = (rad * math.cos(a), rad * math.sin(a), 0.8 + n * 0.45)  # spaced apart: overlaps explode
        ob.rotation_euler = Euler((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, 2 * math.pi)))
        bpy.ops.rigidbody.object_add(type="ACTIVE")
        rb = ob.rigid_body
        rb.collision_shape = "CONVEX_HULL"
        rb.collision_margin = 0.005
        rb.mass = max(0.05, ob.dimensions.x * ob.dimensions.y * ob.dimensions.z)
        rb.friction, rb.restitution = 0.9, 0.0
        rb.linear_damping, rb.angular_damping = 0.4, 0.6
    bpy.ops.mesh.primitive_plane_add(size=60)
    table = bpy.context.active_object
    bpy.ops.rigidbody.object_add(type="PASSIVE")
    table.rigid_body.friction = 1.0
    tm = bpy.data.materials.new("table")
    tm.use_nodes = True
    tb = tm.node_tree.nodes["Principled BSDF"]
    tb.inputs["Base Color"].default_value = (0.028, 0.032, 0.04, 1)
    tb.inputs["Roughness"].default_value = 0.55
    table.data.materials.append(tm)
    # an invisible cup holds the items while they fall, then lifts away so the stack slumps into a heap
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=1.6, depth=30, end_fill_type="NOTHING",
                                        location=(0, 0, 15))
    cup = bpy.context.active_object
    cup.hide_render = True
    bpy.ops.rigidbody.object_add(type="PASSIVE")
    cup.rigid_body.collision_shape = "MESH"
    cup.rigid_body.kinematic = True
    cup.rigid_body.friction = 0.0
    for frame, z in ((130, 15), (175, 45)):
        cup.location.z = z
        cup.keyframe_insert("location", index=2, frame=frame)
    for f in range(1, sc.frame_end + 1):
        sc.frame_set(f)
    heap = [o for o in sc.objects if o.type == "MESH" and o not in (table, cup)]
    heap = [o for o in heap if o.matrix_world.translation.xy.length < 3.5]  # ignore strays for framing
    lo, hi = bounds(heap)
    ctr = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (hi.z - lo.z) * 0.3))
    size = max(hi.x - lo.x, hi.y - lo.y)
    # camera, in front and a little above
    cam = bpy.data.cameras.new("cam")
    cam.lens = 70
    cam.dof.use_dof = True
    cam.dof.aperture_fstop = 16.0
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    d = Vector((0.15, -1.0, 0.62)).normalized()
    co.location = ctr + d * size * 2.6
    co.rotation_euler = (ctr - co.location).to_track_quat("-Z", "Y").to_euler()
    cam.dof.focus_distance = (ctr - co.location).length
    # studio lights: a large soft key, a cool fill, a warm rim from behind
    for name, loc, energy, colour, sz in (("key", (-1.2, -1.4, 2.0), 1800, (1.0, 0.97, 0.92), 3.0),
                                          ("fill", (1.8, -0.8, 0.9), 450, (0.8, 0.88, 1.0), 3.0),
                                          ("rim", (0.4, 1.8, 1.6), 1500, (1.0, 0.85, 0.7), 2.0)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.color, light.size = energy * (size / 4) ** 2, colour, sz * size / 4
        lo_ = bpy.data.objects.new(name, light)
        sc.collection.objects.link(lo_)
        lo_.location = ctr + Vector(loc) * size
        lo_.rotation_euler = (ctr - lo_.location).to_track_quat("-Z", "Y").to_euler()
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.014, 0.018, 1)
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 160
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED showcase to", path)


showcase(OUT) if SHOWCASE else main()
