"""Rebuild the rooftop parapet (straight run + outer corner) at 0.80 m total height
with the project owner's chosen "plan A" elevation.

Plan A (owner decision, 2026-09-20)
----------------------------------
Plain recessed panel framed by a base band and a coping band. No intermediate
vertical tile seams and no divider band -- the 10 x 0.5 m vertical tiles of the v002
kit read as a dense, busy grid and were explicitly rejected.

    base band    5.00 x 0.50 x 0.10   z 0.00 .. 0.10   cell (9,6)
    panel        5.00 x 0.43 x 0.64   z 0.08 .. 0.72   cell (9,7)   (recessed 0.035/side)
    coping band  5.00 x 0.50 x 0.10   z 0.70 .. 0.80   cell (9,8)

Total height 0.80 m INCLUDING the coping (owner decision). The 0.50 m thickness is
deliberately unchanged so TowerFloorStage3D.ROOFTOP_PARAPET_THICKNESS -- and therefore
the boundary inset -- does not move. The panel overlaps each band by 0.02 m so the
joint shows a shadow line instead of the bevel gap that two exactly-abutting beveled
boxes would leave.

How this fits the pipeline
--------------------------
The v002 reference library is the art truth and is opened READ-ONLY; nothing is ever
written back to it. This script rebuilds the two package meshes in memory, asserts the
geometry contracts, and saves the result to a separate WORK blend. The damage author
and the exporter are then pointed at that work blend.

Full reproduction chain (all inputs are tracked; no work blend is committed)
---------------------------------------------------------------------------
  1. blender.exe --background \\
       source/reference_components/v002/天台区块_参考组件库_v002.blend \\
       --python source/author_env_rooftop_parapet_v003.py
       -> source/parapet_v003_work.blend            (straight + outer corner rebuilt)
  2. blender.exe --background source/parapet_v003_work.blend \\
       --python source/export_env_rooftop_parapet_v001.py
       -> components/env_rooftop_ref_parapet_top3d.glb          (intact straight run)
       -> components/env_rooftop_ref_parapet_outer_top3d.glb    (intact outer corner)
  3. blender.exe --background source/parapet_v003_work.blend \\
       --python source/author_env_rooftop_parapet_damage_v003.py
       -> components/env_rooftop_ref_parapet_dmg_{a,b,c}_top3d.glb

Contracts re-asserted here (same ones the v002 exporter relies on)
-----------------------------------------------------------------
origin   : XY-centred, base face at local Z=0
envelope : straight 5.00 x 0.50 x 0.80, outer corner 2.50 x 2.50 x 0.80
palette  : every loop UV sits on its palette cell's ring (radius .027 at cell centre),
           so the whole piece stays inside the concrete swatch
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy

HEIGHT = 0.80
THICKNESS = 0.50
PANEL_THICKNESS = 0.43
BAND_HEIGHT = 0.10
BAND_OVERLAP = 0.02
BEVEL = 0.025
ROLE = 1

CELL_BASE = (9, 6)
CELL_PANEL = (9, 7)
CELL_COPING = (9, 8)

STRAIGHT_LENGTH = 5.0
CORNER_LEGS = ((0.0, -1.0, 2.5, 0.0), (-1.0, 0.25, 2.0, math.pi / 2))

PANEL_Z0 = BAND_HEIGHT - BAND_OVERLAP
PANEL_Z1 = HEIGHT - BAND_HEIGHT + BAND_OVERLAP
PANEL_HEIGHT = PANEL_Z1 - PANEL_Z0

STRAIGHT_TARGET = ("女儿墙直段_水泥结构_制作", "女儿墙直段_主体")
CORNER_TARGET = ("女儿墙外角_水泥结构_制作", "女儿墙外角_主体")

# One shell per box: the straight run is 3 bands, the outer corner is 2 legs x 3 bands.
STRAIGHT_SHELLS = 3
CORNER_SHELLS = len(CORNER_LEGS) * 3


def _require(condition, message):
    if not condition:
        raise RuntimeError(message)


class Bag(object):
    """Vertex / face / per-face-palette-cell accumulator, mirroring build_rooftop.py."""

    def __init__(self):
        self.v = []
        self.f = []
        self.style = []

    def add_box(self, center, dims, cell, bev=BEVEL, rot=0.0):
        vs, fs = _beveled_box(dims, bev)
        co, si = math.cos(rot), math.sin(rot)
        base = len(self.v)
        for x, y, z in vs:
            self.v.append(
                (center[0] + x * co - y * si, center[1] + x * si + y * co, center[2] + z)
            )
        for face in fs:
            self.f.append(tuple(base + i for i in face))
            self.style.append((cell, ROLE))

    def recentre(self):
        """XY centre -> 0, base face -> Z=0. This IS the package origin contract."""
        xs = [p[0] for p in self.v]
        ys = [p[1] for p in self.v]
        zs = [p[2] for p in self.v]
        ax = (min(xs) + max(xs)) * 0.5
        ay = (min(ys) + max(ys)) * 0.5
        az = min(zs)
        self.v = [(x - ax, y - ay, z - az) for x, y, z in self.v]

    def bounds(self):
        xs = [p[0] for p in self.v]
        ys = [p[1] for p in self.v]
        zs = [p[2] for p in self.v]
        return (
            min(xs), max(xs),
            min(ys), max(ys),
            min(zs), max(zs),
        )


def _beveled_box(dims, bev):
    """Exactly build_rooftop.py's primitive: unit cube -> scale -> bevel all edges."""
    effective = min(bev, min(dims) * 0.22)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for vert in bm.verts:
        vert.co.x *= dims[0]
        vert.co.y *= dims[1]
        vert.co.z *= dims[2]
    if effective > 0.0:
        bmesh.ops.bevel(
            bm, geom=list(bm.edges), offset=effective, segments=1, affect="EDGES"
        )
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return verts, faces


def build_straight():
    bag = Bag()
    bag.add_box(
        (0.0, 0.0, BAND_HEIGHT * 0.5),
        (STRAIGHT_LENGTH, THICKNESS, BAND_HEIGHT),
        CELL_BASE,
    )
    bag.add_box(
        (0.0, 0.0, (PANEL_Z0 + PANEL_Z1) * 0.5),
        (STRAIGHT_LENGTH, PANEL_THICKNESS, PANEL_HEIGHT),
        CELL_PANEL,
    )
    bag.add_box(
        (0.0, 0.0, HEIGHT - BAND_HEIGHT * 0.5),
        (STRAIGHT_LENGTH, THICKNESS, BAND_HEIGHT),
        CELL_COPING,
    )
    bag.recentre()
    return bag


def build_corner():
    bag = Bag()
    for cx, cy, length, rot in CORNER_LEGS:
        bag.add_box((cx, cy, BAND_HEIGHT * 0.5), (length, THICKNESS, BAND_HEIGHT), CELL_BASE, rot=rot)
        bag.add_box(
            (cx, cy, (PANEL_Z0 + PANEL_Z1) * 0.5),
            (length, PANEL_THICKNESS, PANEL_HEIGHT),
            CELL_PANEL,
            rot=rot,
        )
        bag.add_box(
            (cx, cy, HEIGHT - BAND_HEIGHT * 0.5),
            (length, THICKNESS, BAND_HEIGHT),
            CELL_COPING,
            rot=rot,
        )
    bag.recentre()
    return bag


def make_mesh(name, bag, material):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(bag.v, [], bag.f)
    mesh.update()
    mesh.materials.append(material)
    uv = mesh.uv_layers.new(name="PaletteUV")
    uv.active_render = True
    mesh.uv_layers.active = uv
    _require(
        len(mesh.polygons) == len(bag.style),
        "%s: 生成的面数 %d 与色盘样式记录 %d 不一致"
        % (name, len(mesh.polygons), len(bag.style)),
    )
    for poly, ((col, row), role) in zip(mesh.polygons, bag.style):
        poly.material_index = 0
        for j, li in enumerate(poly.loop_indices):
            angle = j * math.tau / poly.loop_total
            uv.data[li].uv = (
                (col + 0.5) / 10.0 + 0.027 * math.cos(angle),
                (9 - row + 0.5) / 10.0 + 0.027 * math.sin(angle),
            )
    for poly in mesh.polygons:
        poly.use_smooth = False
    mesh.validate()
    mesh.update()
    return mesh


def shell_count(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    seen = set()
    shells = 0
    for face in bm.faces:
        if face.index in seen:
            continue
        shells += 1
        stack = [face]
        while stack:
            current = stack.pop()
            if current.index in seen:
                continue
            seen.add(current.index)
            for edge in current.edges:
                for neighbour in edge.link_faces:
                    if neighbour.index not in seen:
                        stack.append(neighbour)
    bm.free()
    return shells


def uv_bounds(mesh):
    layer = mesh.uv_layers.get("PaletteUV")
    us = [loop.uv.x for loop in layer.data]
    vs = [loop.uv.y for loop in layer.data]
    return min(us), max(us), min(vs), max(vs)


def rebuild(source_name, package_name, builder, mesh_name, expected, expected_shells):
    source = bpy.data.objects.get(source_name)
    package = bpy.data.objects.get(package_name)
    _require(source is not None, "缺少制作件对象：%s" % source_name)
    _require(package is not None, "缺少输出件对象：%s" % package_name)
    _require(source.type == "MESH" and package.type == "MESH", "%s / %s 必须是网格" % (source_name, package_name))

    shared = source.data is package.data
    material = source.data.materials[0]
    old = (source.data.name, package.data.name, shared)

    bag = builder()
    mesh = make_mesh(mesh_name, bag, material)
    source.data = mesh
    package.data = mesh

    lo_x, hi_x, lo_y, hi_y, lo_z, hi_z = bag.bounds()
    size = (hi_x - lo_x, hi_y - lo_y, hi_z - lo_z)
    _require(abs(lo_z) < 1e-6, "%s: 底面没有落在 Z=0（min=%.6f）" % (mesh_name, lo_z))
    for index, axis in enumerate("XYZ"):
        _require(
            abs(size[index] - expected[index]) < 1e-4,
            "%s: %s 包络 %.4f 与预期 %.4f 不符" % (mesh_name, axis, size[index], expected[index]),
        )
    shells = shell_count(mesh)
    _require(
        shells == expected_shells,
        "%s: 拆出 %d 个独立壳体，与方案A预期的 %d 个不符" % (mesh_name, shells, expected_shells),
    )
    u_min, u_max, v_min, v_max = uv_bounds(mesh)
    _require(
        u_min >= 0.923 - 1e-6 and u_max <= 0.977 + 1e-6,
        "%s: UV 的 U 越出混凝土色块 [0.923, 0.977] -> [%.4f, %.4f]" % (mesh_name, u_min, u_max),
    )
    _require(
        v_min >= 0.123 - 1e-6 and v_max <= 0.477 + 1e-6,
        "%s: UV 的 V 越出混凝土色块 [0.123, 0.477] -> [%.4f, %.4f]" % (mesh_name, v_min, v_max),
    )

    print(
        "REBUILT %-24s mesh=%-22s verts=%-5d faces=%-5d shells=%d "
        "size=%.3f x %.3f x %.3f z=[%.3f, %.3f] uv=[%.4f..%.4f]x[%.4f..%.4f] shared=%s"
        % (
            source_name,
            mesh.name,
            len(mesh.vertices),
            len(mesh.polygons),
            shells,
            size[0], size[1], size[2], lo_z, hi_z,
            u_min, u_max, v_min, v_max,
            shared,
        )
    )
    print(
        "   was mesh=%s / %s shared=%s -> now both point at %s"
        % (old[0], old[1], old[2], mesh.name)
    )
    return mesh


bpy.context.view_layer.update()

MATERIAL_TAG = "02_"
probe = bpy.data.objects.get(STRAIGHT_TARGET[0])
_require(probe is not None and probe.data.materials, "找不到女儿墙材质来源")
_require(
    probe.data.materials[0].name.startswith(MATERIAL_TAG),
    "女儿墙材质不是预期的 %s...（实际 %s）" % (MATERIAL_TAG, probe.data.materials[0].name),
)

straight_mesh = rebuild(
    STRAIGHT_TARGET[0],
    STRAIGHT_TARGET[1],
    build_straight,
    "女儿墙直段_v003_水泥结构",
    (STRAIGHT_LENGTH, THICKNESS, HEIGHT),
    STRAIGHT_SHELLS,
)
corner_mesh = rebuild(
    CORNER_TARGET[0],
    CORNER_TARGET[1],
    build_corner,
    "女儿墙外角_v003_水泥结构",
    (2.5, 2.5, HEIGHT),
    CORNER_SHELLS,
)

WORK_BLEND = Path(__file__).resolve().parent / "parapet_v003_work.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(WORK_BLEND))
print("WORK_BLEND %s" % WORK_BLEND)
print(
    "PARAPET_V003_AUTHOR_OK height=%.2f straight=%d verts corner=%d verts"
    % (HEIGHT, len(straight_mesh.vertices), len(corner_mesh.vertices))
)
