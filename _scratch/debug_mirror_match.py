"""Second-pass debug: why do 29 faces per side fail the tolerance match?

The mirror is exact to ~1e-5, so 29 unpaired faces are either (a) real geometric
differences, (b) degenerate triangles whose normal/centre is numerically unstable, or
(c) a defect in the matching.  Distinguish by comparing raw vertex position
multisets (which do not depend on normals at all) and by measuring the nearest
neighbour distance of every unmatched face.

Run:
    blender --factory-startup --background --python _scratch/debug_mirror_match.py
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
CUT_Y = -(0.15 + 0.002)
SIDE_TOL = 0.0005
MATCH_TOL = 0.004


def face_side(mesh, face):
    ys = [mesh.vertices[i].co.y for i in face.vertices]
    if min(ys) >= -CUT_Y - SIDE_TOL:
        return 1
    if max(ys) <= CUT_Y + SIDE_TOL:
        return -1
    return 0


def row_of(face):
    c = face.center
    n = face.normal.normalized()
    return (c.x, c.y, c.z, n.x, n.y, n.z)


bpy.ops.wm.open_mainfile(filepath=str(DERIVED))
obj = bpy.data.objects[OBJECT_NAME]
mesh = obj.data

decor = bpy.data.objects.new("DECOR_COPY", mesh.copy())
bpy.context.scene.collection.objects.link(decor)
decor.matrix_world = obj.matrix_world.copy()
bm = bmesh.new()
bm.from_mesh(decor.data)
bm.faces.ensure_lookup_table()
drop = [f for f in bm.faces if max(v.co.y for v in f.verts) > CUT_Y]
bmesh.ops.delete(bm, geom=drop, context="FACES")
bm.to_mesh(decor.data)
bm.free()
decor.data.update()
bpy.ops.object.select_all(action="DESELECT")
decor.select_set(True)
bpy.context.view_layer.objects.active = decor
mod = decor.modifiers.new(name="m", type="MIRROR")
mod.use_axis = (False, True, False)
mod.use_mirror_merge = False
mod.use_clip = False
bpy.ops.object.modifier_apply(modifier=mod.name)

data = decor.data
minus = []
plus = []
for face in data.polygons:
    side = face_side(data, face)
    if side == 0:
        continue
    row = row_of(face)
    if side > 0:
        plus.append(row)
    else:
        minus.append((row[0], -row[1], row[2], row[3], -row[4], row[5]))

print("minus=%d plus=%d" % (len(minus), len(plus)))

# --- vertex position multiset, normal-free ------------------------------------
# `decor` holds both halves; classify against its own data
vm = Counter()
vp = Counter()
for face in data.polygons:
    side = face_side(data, face)
    if side == 0:
        continue
    target = vm if side < 0 else vp
    for i in face.vertices:
        co = data.vertices[i].co
        target[(round(co.x, 4), round(abs(co.y), 4), round(co.z, 4))] += 1
print("VERTEX positions: -Y only=%d  +Y only=%d  (distinct -Y=%d, +Y=%d)" % (
    sum((vm - vp).values()), sum((vp - vm).values()), len(vm), len(vp)
))
for key, count in list((vm - vp).items())[:6]:
    print("   vert -Y only x%d %s" % (count, key))
for key, count in list((vp - vm).items())[:6]:
    print("   vert +Y only x%d %s" % (count, key))

# --- degenerate faces --------------------------------------------------------
def degenerate_rows(rows_mesh):
    bad = 0
    for face in rows_mesh.polygons:
        if face_side(rows_mesh, face) == 0:
            continue
        if face.area < 1e-9:
            bad += 1
    return bad


print("degenerate faces (area < 1e-9) = %d" % degenerate_rows(data))

# --- nearest neighbour for unmatched rows ------------------------------------
def cell(row):
    return tuple(int(r // MATCH_TOL) for r in row[:3])


buckets = {}
for idx, row in enumerate(minus):
    buckets.setdefault(cell(row), []).append([idx, row, False])

unmatched_plus = []
for row in plus:
    c = cell(row)
    match = None
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for entry in buckets.get((c[0] + dx, c[1] + dy, c[2] + dz), ()):
                    if entry[2]:
                        continue
                    other = entry[1]
                    if all(abs(row[i] - other[i]) <= MATCH_TOL for i in range(6)):
                        match = entry
                        break
                if match:
                    break
            if match:
                break
        if match:
            break
    if match is None:
        unmatched_plus.append(row)
    else:
        match[2] = True
leftover_minus = [
    entry[1] for entries in buckets.values() for entry in entries if not entry[2]
]

print("unmatched plus=%d  leftover minus=%d" % (len(unmatched_plus), len(leftover_minus)))
all_minus = [entry[1] for entries in buckets.values() for entry in entries]
areas = {}
for face in data.polygons:
    c = face.center
    areas[(round(c.x, 4), round(abs(c.y), 4), round(c.z, 4))] = face.area
for row in unmatched_plus[:6]:
    key = (round(row[0], 4), round(row[1], 4), round(row[2], 4))
    best = None
    for other in all_minus:
        dp = max(abs(row[i] - other[i]) for i in range(3))
        dn = max(abs(row[i] - other[i]) for i in range(3, 6))
        score = (dp, dn)
        if best is None or score < best[0]:
            best = (score, dp, dn, other)
    print("   +Y row %s  area=%.3e" % ([round(v, 4) for v in row], areas.get(key, -1.0)))
    print("      nearest -Y row %s   dpos=%.6f dnormal=%.6f"
          % ([round(v, 4) for v in best[3]], best[1], best[2]))
print("DEBUG2_DONE")
