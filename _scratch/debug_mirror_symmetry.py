"""Debug the mirror-symmetry comparison: compare the two halves as multisets.

The pairwise comparison in the derivation reported 911 mismatches whose z values
differed by metres, which cannot be float noise.  Either the mirrored half really
differs in (x, z) from the source half, or the sort key is not aligning equal rows.
This script separates the two possibilities by comparing multisets instead of
sorted lists.

Run:
    blender --factory-startup --background --python _scratch/debug_mirror_symmetry.py
"""

import bmesh
import bpy
from collections import Counter
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
DERIVED = (
    PROJECT
    / "assets/art/environments/tower_descent_3d/source/wall_height12"
    / "env_tower_wall_door_5m_source_v004.blend"
)
OBJECT_NAME = "ENV_TOWER_WALL_DOOR_5M"
STRUCTURAL_BACK_Y_M = 0.15
CUT_GUARD_M = 0.002
SIDE_TOLERANCE_M = 0.0005


def cut_plane_y():
    return -(STRUCTURAL_BACK_Y_M + CUT_GUARD_M)


def face_side(mesh, face):
    cut = cut_plane_y()
    ys = [mesh.vertices[i].co.y for i in face.vertices]
    if min(ys) >= -cut - SIDE_TOLERANCE_M:
        return 1
    if max(ys) <= cut + SIDE_TOLERANCE_M:
        return -1
    return 0


bpy.ops.wm.open_mainfile(filepath=str(DERIVED))
obj = bpy.data.objects[OBJECT_NAME]
mesh = obj.data

decor = bpy.data.objects.new("DECOR_COPY", mesh.copy())
bpy.context.scene.collection.objects.link(decor)
decor.matrix_world = obj.matrix_world.copy()
bm = bmesh.new()
bm.from_mesh(decor.data)
bm.faces.ensure_lookup_table()
drop = [f for f in bm.faces if max(v.co.y for v in f.verts) > cut_plane_y()]
bmesh.ops.delete(bm, geom=drop, context="FACES")
bm.to_mesh(decor.data)
bm.free()
decor.data.update()

bpy.ops.object.select_all(action="DESELECT")
decor.select_set(True)
bpy.context.view_layer.objects.active = decor
modifier = decor.modifiers.new(name="decor_mirror", type="MIRROR")
modifier.use_axis = (False, True, False)
modifier.use_mirror_merge = False
modifier.use_clip = False
bpy.ops.object.modifier_apply(modifier=modifier.name)
print("decor faces after mirror = %d" % len(decor.data.polygons))

plus_mesh = decor.data
minus = []
plus = []
for face in plus_mesh.polygons:
    side = face_side(plus_mesh, face)
    center = face.center
    normal = face.normal.normalized()
    row = (
        round(center.x, 5), round(abs(center.y), 5), round(center.z, 5),
        round(normal.x, 3), round(abs(normal.y), 3), round(normal.z, 3),
    )
    if side > 0:
        plus.append(row)
    elif side < 0:
        minus.append(row)

print("minus=%d plus=%d" % (len(minus), len(plus)))

m_counter = Counter(minus)
p_counter = Counter(plus)
only_minus = m_counter - p_counter
only_plus = p_counter - m_counter
print("distinct rows: minus=%d plus=%d" % (len(m_counter), len(p_counter)))
print("rows only on the original side = %d (total extra %d)" % (len(only_minus), sum(only_minus.values())))
for row, count in list(only_minus.items())[:8]:
    print("   -Y only x%d  %s" % (count, row))
print("rows only on the mirrored side = %d (total extra %d)" % (len(only_plus), sum(only_plus.values())))
for row, count in list(only_plus.items())[:8]:
    print("   +Y only x%d  %s" % (count, row))

# Position-only comparison, ignoring normals entirely: this tells whether the
# mirrored half is geometrically in the wrong place or only has wrong normals.
m_pos = Counter((r[0], r[1], r[2]) for r in minus)
p_pos = Counter((r[0], r[1], r[2]) for r in plus)
print("POSITION-only: rows only on -Y = %d, only on +Y = %d" % (
    len(m_pos - p_pos), len(p_pos - m_pos)
))
for row, count in list((m_pos - p_pos).items())[:6]:
    print("   pos -Y only x%d %s" % (count, row))
for row, count in list((p_pos - m_pos).items())[:6]:
    print("   pos +Y only x%d %s" % (count, row))

print("DEBUG_DONE")
