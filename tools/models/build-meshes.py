"""Builds the mod's own world-model meshes from code and exports them as FBX for Project Zomboid.

    blender -b --factory-startup --python tools/models/build-meshes.py [-- OUT_DIR]

Run from the repo root. Writes Carton, Pen, Syringe, Tablets, InjectorGun, IVBag and PlasticStrips .fbx to
ehr_models.MESH_DIR (or OUT_DIR). Shapes, sizes and UV layouts come from ehr_models.py, which paint-textures.py
reads too, so a mesh and its textures always agree. Blender 4.2 or later.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ehr_models as M  # noqa: E402

INSET = 0.3  # px kept clear at rect edges so nearest-pixel sampling and mipmaps don't bleed in the neighbour


class Builder:
    """Collects parts into one bmesh with one UV layer. Rects are texture pixels (origin top left)."""

    def __init__(self, tex):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.tw, self.th = tex

    def to_uv(self, rect, s, t):
        """s, t in 0..1 across the rect; t=0 is the rect's top row."""
        x0, y0, x1, y1 = rect
        x0, y0, x1, y1 = x0 + INSET, y0 + INSET, x1 - INSET, y1 - INSET
        return Vector(((x0 + s * (x1 - x0)) / self.tw, 1.0 - (y0 + t * (y1 - y0)) / self.th))

    def face(self, coords, uvs, smooth=False):
        verts = [self.bm.verts.new(c) for c in coords]
        f = self.bm.faces.new(verts)
        f.smooth = smooth
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def box(self, corners, rects):
        """corners: 8 points in order (x0y0z0, x1y0z0, x1y1z0, x0y1z0, then the same at z1). rects: per face
        direction ('+X', '-X', '+Y', '-Y', '+Z', '-Z') a rect; each face is planar-projected into its rect."""
        c = [Vector(p) for p in corners]
        quads = {"-Z": (0, 3, 2, 1), "+Z": (4, 5, 6, 7), "-Y": (0, 1, 5, 4), "+Y": (2, 3, 7, 6),
                 "-X": (3, 0, 4, 7), "+X": (1, 2, 6, 5)}
        for d, idx in quads.items():
            pts = [c[i] for i in idx]
            self.face(pts, self.project(pts, d, rects[d]))

    def project(self, pts, d, rect):
        ax = "XYZ".index(d[1])
        a, b = {0: (1, 2), 1: (0, 2), 2: (0, 1)}[ax]  # (u axis, v axis); v up = image up
        flip_u = d in ("-Z", "+Y", "-X")  # so the image reads unmirrored when that face is seen from outside
        us = [p[a] for p in pts]
        vs = [p[b] for p in pts]
        u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
        out = []
        for p in pts:
            s = (p[a] - u0) / ((u1 - u0) or 1)
            t = 1 - (p[b] - v0) / ((v1 - v0) or 1)
            out.append(self.to_uv(rect, 1 - s if flip_u else s, t))
        return out

    def lathe(self, points, segments, rect, axis="X", origin=(0, 0, 0), u_of=None):
        """Turns (along, radius) points around axis. The rect is a strip: s runs along the profile (by length), t
        around. A radius of 0 makes a pole."""
        u_of = u_of or M.lathe_u({"points": points})
        o = Vector(origin)

        def pos(along, r, ang):
            ca, sa = math.cos(ang) * r, math.sin(ang) * r
            if axis == "X":
                return o + Vector((along, ca, sa))
            return o + Vector((ca, sa, along))

        for i in range(len(points) - 1):
            (a0, r0), (a1, r1) = points[i], points[i + 1]
            s0, s1 = u_of[i], u_of[i + 1]
            for j in range(segments):
                t0, t1 = j / segments, (j + 1) / segments
                g0, g1 = 2 * math.pi * t0, 2 * math.pi * t1
                if r0 == 0 and r1 == 0:
                    continue
                if r0 == 0:
                    tm = (t0 + t1) / 2
                    self.face([pos(a0, 0, 0), pos(a1, r1, g1), pos(a1, r1, g0)],
                              [self.to_uv(rect, s0, tm), self.to_uv(rect, s1, t1), self.to_uv(rect, s1, t0)], True)
                elif r1 == 0:
                    tm = (t0 + t1) / 2
                    self.face([pos(a0, r0, g0), pos(a0, r0, g1), pos(a1, 0, 0)],
                              [self.to_uv(rect, s0, t0), self.to_uv(rect, s0, t1), self.to_uv(rect, s1, tm)], True)
                else:
                    self.face([pos(a0, r0, g0), pos(a0, r0, g1), pos(a1, r1, g1), pos(a1, r1, g0)],
                              [self.to_uv(rect, s0, t0), self.to_uv(rect, s0, t1), self.to_uv(rect, s1, t1),
                               self.to_uv(rect, s1, t0)], True)

    def tube(self, path, radius, segments, rect):
        """Sweeps a circle along a polyline (closed ends)."""
        rings = []
        for i, p in enumerate(path):
            p = Vector(p)
            a = Vector(path[max(i - 1, 0)])
            b = Vector(path[min(i + 1, len(path) - 1)])
            tan = (b - a).normalized()
            ref = Vector((0, 0, 1)) if abs(tan.z) < 0.9 else Vector((1, 0, 0))
            n1 = tan.cross(ref).normalized()
            n2 = tan.cross(n1).normalized()
            rings.append([p + radius * (math.cos(2 * math.pi * j / segments) * n1 +
                                        math.sin(2 * math.pi * j / segments) * n2) for j in range(segments)])
        n = len(rings) - 1
        for i in range(n):
            for j in range(segments):
                k = (j + 1) % segments
                self.face([rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]],
                          [self.to_uv(rect, i / n, j / segments), self.to_uv(rect, i / n, (j + 1) / segments),
                           self.to_uv(rect, (i + 1) / n, (j + 1) / segments),
                           self.to_uv(rect, (i + 1) / n, j / segments)], True)
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            pts = list(reversed(ring)) if rev else ring
            self.face(pts, [self.to_uv(rect, 0.5, 0.5)] * len(pts))

    def finish(self, name):
        """Lays the result on the floor (bottom at Z=0, centred on X and Y) and returns a new object."""
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        zs = [v.co.z for v in bm.verts]
        shift = Vector((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, -min(zs)))
        bmesh.ops.translate(bm, verts=bm.verts, vec=shift)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.set_sharp_from_angle(angle=math.radians(40))
        mat = bpy.data.materials.get("EHR_" + name) or bpy.data.materials.new("EHR_" + name)
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def box_corners(x0, x1, y0, y1, z0, z1):
    return [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]


def build_carton():
    s = M.CARTON
    lx, ly, lz = s["size"]
    r = s["rects"]
    b = Builder(s["tex"])
    b.box(box_corners(-lx / 2, lx / 2, -ly / 2, ly / 2, 0, lz),
          {"+Z": r["top"], "-Z": r["top"], "+Y": r["side"], "-Y": r["side"], "+X": r["end"], "-X": r["end"]})
    return b.finish("Carton")


def build_lathe(name, spec):
    b = Builder(spec["tex"])
    w, h = spec["tex"]
    b.lathe(spec["points"], spec["segments"], (0, 0, w, h), axis="X", u_of=M.lathe_u(spec))
    return b.finish(name)


def build_tablets():
    s = M.TABLET
    w, h = s["tex"]
    b = Builder(s["tex"])
    for x, y, _ in s["placements"]:
        b.lathe(s["points"], s["segments"], (0, 0, w, h), axis="Z", origin=(x, y, 0), u_of=M.lathe_u(s))
    return b.finish("Tablets")


def build_gun():
    """Modelled upright (X forward, Z up, Y across), then laid on its side."""
    r = M.GUN["rects"]
    b = Builder(M.GUN["tex"])

    def all_dirs(rect, **over):
        d = {k: rect for k in ("+X", "-X", "+Y", "-Y", "+Z", "-Z")}
        d.update({k.replace("p", "+").replace("m", "-"): r[v] for k, v in over.items()})
        return d

    b.box(box_corners(-0.050, 0.055, -0.016, 0.016, 0.040, 0.072), all_dirs(r["top"], pY="body", mY="body"))
    b.lathe([(0.055, 0.0), (0.055, 0.010), (0.080, 0.010), (0.080, 0.007), (0.092, 0.005), (0.092, 0.0)], 12,
            r["metal"], axis="X", origin=(0, 0, 0.056))
    b.box([(-0.048, -0.013, 0.0), (-0.020, -0.013, 0.0), (-0.020, 0.013, 0.0), (-0.048, 0.013, 0.0),
           (-0.040, -0.013, 0.040), (-0.012, -0.013, 0.040), (-0.012, 0.013, 0.040), (-0.040, 0.013, 0.040)],
          all_dirs(r["grip"]))
    b.box(box_corners(-0.006, 0.0, -0.004, 0.004, 0.022, 0.040), all_dirs(r["dark"]))
    b.box(box_corners(-0.022, 0.012, -0.012, 0.012, 0.072, 0.078), all_dirs(r["dark"]))
    b.lathe([(0.078, 0.0), (0.078, 0.0095), (0.106, 0.0095), (0.106, 0.0)], 12, r["vial"], axis="Z",
            origin=(-0.005, 0, 0))
    b.lathe([(0.106, 0.0), (0.106, 0.0105), (0.114, 0.0105), (0.114, 0.0)], 12, r["vialcap"], axis="Z",
            origin=(-0.005, 0, 0))
    for y0, y1 in ((0.016, 0.0175), (-0.0175, -0.016)):
        b.box(box_corners(0.020, 0.036, y0, y1, 0.050, 0.060), all_dirs(r["accent"]))
    bmesh.ops.rotate(b.bm, verts=b.bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    return b.finish("InjectorGun")


def build_ivbag():
    s = M.IVBAG
    lx, ly, lz = s["size"]
    r = s["rects"]
    b = Builder(s["tex"])
    nx, ny = 12, 8

    def bulge(i, j):
        u, v = 2 * i / nx - 1, 2 * j / ny - 1
        return (1 - u ** 4) * (1 - v ** 4)

    def p(i, j, sign):
        return Vector((-lx / 2 + lx * i / nx, -ly / 2 + ly * j / ny, lz / 2 + sign * lz / 2 * bulge(i, j)))

    for sign in (1, -1):
        for i in range(nx):
            for j in range(ny):
                q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                if sign < 0:
                    q.reverse()
                b.face([p(a, c, sign) for a, c in q],
                       [b.to_uv(r["face"], a / nx, 1 - c / ny) for a, c in q], True)
    z = lz / 2
    x = -lx / 2
    b.lathe([(x, 0.0), (x, 0.005), (x - 0.012, 0.005), (x - 0.012, 0.0)], 10, r["port"], origin=(0, 0, z))
    b.lathe([(x - 0.012, 0.0), (x - 0.012, 0.0075), (x - 0.036, 0.0075), (x - 0.040, 0.004), (x - 0.040, 0.0)], 10,
            r["drip"], origin=(0, 0, z))
    tr = 0.0022
    cx, cy, rad = x - 0.068, 0.0, 0.026
    path = [(x - 0.040, 0, z), (x - 0.042, 0, tr + 0.003)]
    for k in range(25):
        a = math.pi * 2 * 0.92 * k / 24
        path.append((cx + rad * math.cos(a), cy + rad * math.sin(a), tr))
    b.tube(path, tr, 8, r["tube"])
    ex, ey, _ = path[-1]
    b.box(box_corners(ex - 0.005, ex + 0.005, ey - 0.006, ey + 0.002, 0, 0.006),
          {k: r["clamp"] for k in ("+X", "-X", "+Y", "-Y", "+Z", "-Z")})
    return b.finish("IVBag")


def build_strips():
    r = M.STRIPS["rects"]["strip"]
    b = Builder(M.STRIPS["tex"])
    for k, (ang, dy) in enumerate(((0, 0.0), (8, 0.010), (-6, -0.012))):
        z0 = k * 0.0016
        corners = box_corners(-0.065, 0.065, -0.008, 0.008, z0, z0 + 0.0015)
        rot = Matrix.Rotation(math.radians(ang), 3, "Z")
        corners = [tuple(rot @ Vector(c) + Vector((0, dy, 0))) for c in corners]
        b.box(corners, {d: r for d in ("+X", "-X", "+Y", "-Y", "+Z", "-Z")})
    return b.finish("PlasticStrips")


def export(ob, out_dir):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(out_dir, ob.name + ".fbx")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="OFF", add_leaf_bones=False,
                             bake_anim=False, path_mode="STRIP")
    dims = ob.dimensions
    print("EXPORTED %-14s %4d tris  %.3f x %.3f x %.3f m  -> %s" % (
        ob.name, len(ob.data.polygons), dims.x, dims.y, dims.z, path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else M.MESH_DIR
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for ob in (build_carton(), build_lathe("Pen", M.PEN), build_lathe("Syringe", M.SYRINGE), build_tablets(),
               build_gun(), build_ivbag(), build_strips()):
        export(ob, out_dir)


main()
