"""Dry-run the door-wall double-siding mirror on the real v004 mesh.

Why a dry run: the wall body is not a plain slab.  7799 of its 7935 triangles live
strictly in front of the structural plane at Blender y = -0.15; the rest is the
back shell plus the door tunnel that bores the full thickness.  So the mirror has
to copy ONLY the decoration, and the cut has to be exact -- copying a face that
straddles the plane would produce a coplanar twin against the back plate and the
wall would flicker.

This script performs the exact operation the derivation will use (partition by the
plane -> Mirror modifier on the decoration object -> apply -> join) in memory and
prints what would come out.  Nothing is saved.

Run:
    blender --factory-startup --background --python _scratch/simulate_door_wall_mirror.py
"""

from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[1]
DERIVED = (
    PROJECT
    / "assets/art/environments/tower_descent_3d/source/wall_height12"
    / "env_tower_wall_door_5m_source_v004.blend"
)
OBJECT_NAME = "ENV_TOWER_WALL_DOOR_5M"

# The wall's reference plane: the structural slab is +-0.15 thick, so the mirror
# has to run about its mid-plane, y = 0.
MIRROR_PLANE_Y_M = 0.0
STRUCTURAL_FACE_Y_M = 0.15
# Only faces entirely in front of the structural face are decoration.  The 2mm
# guard keeps a face that merely touches the plane out of the copy.
CUT_GUARD_M = 0.002
DOWN_FACE_NORMAL_Z = -0.5
GROUND_BAND_M = 0.05


def bounds(obj):
    points = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return (
        [min(p[i] for p in points) for i in range(3)],
        [max(p[i] for p in points) for i in range(3)],
    )


def face_stats(obj, label):
    mesh = obj.data
    matrix = obj.matrix_world
    down_ground = 0
    down_above = 0
    for face in mesh.polygons:
        normal = face.normal.normalized()
        if normal.z >= DOWN_FACE_NORMAL_Z:
            continue
        if abs((matrix @ face.center).z) <= GROUND_BAND_M:
            down_ground += 1
        else:
            down_above += 1

    edge_use = {}
    for face in mesh.polygons:
        verts = list(face.vertices)
        for i in range(len(verts)):
            key = tuple(sorted((verts[i], verts[(i + 1) % len(verts)])))
            edge_use[key] = edge_use.get(key, 0) + 1
    boundary = sum(1 for v in edge_use.values() if v == 1)
    nonmanifold = sum(1 for v in edge_use.values() if v > 2)

    # Coplanar twins: same vertex-position set on two different faces.  This is the
    # z-fighting signature, and the thing the cut plane exists to avoid.
    seen = {}
    for face in mesh.polygons:
        key = frozenset(
            tuple(round(v, 4) for v in (matrix @ mesh.vertices[i].co))
            for i in face.vertices
        )
        seen.setdefault(key, []).append(face.index)
    twins = {k: v for k, v in seen.items() if len(v) > 1}

    lows, highs = bounds(obj)
    print("  [%s] faces=%d verts=%d" % (label, len(mesh.polygons), len(mesh.vertices)))
    print("        bounds min=%s max=%s" % ([round(v, 5) for v in lows], [round(v, 5) for v in highs]))
    print("        downward: floor_band=%d above_band=%d" % (down_ground, down_above))
    print("        edges: boundary(open)=%d nonmanifold=%d" % (boundary, nonmanifold))
    print("        coincident-face twins=%d (groups)" % len(twins))
    for key, idx in list(twins.items())[:5]:
        print("          %s -> faces %s" % (sorted(list(key))[:2], idx))
    return twins


bpy.ops.wm.open_mainfile(filepath=str(DERIVED))
obj = bpy.data.objects[OBJECT_NAME]
mesh = obj.data

print("=" * 78)
print("BEFORE")
face_stats(obj, "v004 as shipped")

# --- measure the straddling set, which the cut has to exclude -----------------
matrix = obj.matrix_world
straddle = []
for face in mesh.polygons:
    ys = [(matrix @ mesh.vertices[i].co).y for i in face.vertices]
    if min(ys) < -(STRUCTURAL_FACE_Y_M + CUT_GUARD_M) < max(ys):
        straddle.append((face.index, round(min(ys), 4), round(max(ys), 4)))
print("  straddling faces=%d" % len(straddle))
for row in sorted(straddle, key=lambda r: -r[2])[:12]:
    print("    face %5d  y=%.4f..%.4f" % row)
if straddle:
    print(
        "    straddle y limits: min %.4f  max %.4f"
        % (min(r[1] for r in straddle), max(r[2] for r in straddle))
    )

# --- the operation itself ----------------------------------------------------
decor = bpy.data.objects.new("DECOR_COPY", mesh.copy())
bpy.context.scene.collection.objects.link(decor)
decor.matrix_world = obj.matrix_world.copy()

decor_bm = bmesh.new()
decor_bm.from_mesh(decor.data)
drop = [
    f
    for f in decor_bm.faces
    if max(v.co.y for v in f.verts) > -(STRUCTURAL_FACE_Y_M + CUT_GUARD_M)
]
bmesh.ops.delete(decor_bm, geom=drop, context="FACES")
decor_bm.to_mesh(decor.data)
decor_bm.free()
decor.data.update()
print("  decor partition: kept=%d dropped=%d" % (len(decor.data.polygons), len(drop)))

main_bm = bmesh.new()
main_bm.from_mesh(mesh)
drop_main = [
    f
    for f in main_bm.faces
    if max(v.co.y for v in f.verts) <= -(STRUCTURAL_FACE_Y_M + CUT_GUARD_M)
]
bmesh.ops.delete(main_bm, geom=drop_main, context="FACES")
main_bm.to_mesh(mesh)
main_bm.free()
mesh.update()
print("  main partition: kept=%d dropped=%d" % (len(mesh.polygons), len(drop_main)))

bpy.ops.object.select_all(action="DESELECT")
decor.select_set(True)
bpy.context.view_layer.objects.active = decor
modifier = decor.modifiers.new(name="decor_mirror", type="MIRROR")
modifier.use_axis = (False, True, False)
modifier.use_mirror_merge = False
modifier.use_clip = False
bpy.ops.object.modifier_apply(modifier=modifier.name)
print("  decor after mirror: faces=%d modifiers=%d" % (len(decor.data.polygons), len(decor.modifiers)))

uv_check = sorted(set(round(value, 4) for value in decor.data.uv_layers["PaletteUV"].data[0].uv))
print("  decor PaletteUV preserved: layer=%s sample=%s" % (
    [l.name for l in decor.data.uv_layers], uv_check
))

bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
decor.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.join()
merged = bpy.context.view_layer.objects.active
print("=" * 78)
print("AFTER join -> object=%s slots=%s" % (merged.name, [s.material.name for s in merged.material_slots]))
face_stats(merged, "double-sided")

mirrored = []
kept = []
for face in merged.data.polygons:
    ys = [(merged.matrix_world @ merged.data.vertices[i].co).y for i in face.vertices]
    if min(ys) >= STRUCTURAL_FACE_Y_M + CUT_GUARD_M - 1e-6:
        mirrored.append(face.index)
    else:
        kept.append(face.index)
print("  faces on the new +Y side = %d   (all other faces = %d)" % (len(mirrored), len(kept)))
if mirrored:
    pts = [
        merged.matrix_world @ merged.data.vertices[i].co
        for fi in mirrored
        for i in merged.data.polygons[fi].vertices
    ]
    print(
        "  +Y side extent y=%.5f..%.5f  x=%.5f..%.5f  z=%.5f..%.5f"
        % (
            min(p.y for p in pts),
            max(p.y for p in pts),
            min(p.x for p in pts),
            max(p.x for p in pts),
            min(p.z for p in pts),
            max(p.z for p in pts),
        )
    )
print("SIMULATE_DONE (nothing saved)")
