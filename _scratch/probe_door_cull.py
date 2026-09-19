"""Where do the downward faces of door_5m_门扇_输出 actually live?

The A-suite wall pipeline culls world-downward faces (a wall module's underside is
hidden by the floor).  For a free-standing door leaf that predicate removed 1631 of
8468 triangles, which is far more than a bottom cap -- so before keeping the cull we
measure the height distribution and area of every removed face.
"""

import bpy
from mathutils import Vector

BLEND = (
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments"
    r"\tower_zones\battle\source\common_components\v006"
    r"\env_battle_common_components_source_v006.blend"
)

bpy.ops.wm.open_mainfile(filepath=str(BLEND))

ROOT = bpy.data.objects["ROOT_door_5m_通用组件"]
origin = ROOT.matrix_world.translation

total = 0
removed = 0
removed_area = 0.0
total_area = 0.0
buckets = {}

for name in ("door_5m_门扇_输出", "door_5m_UI灯光_柔和自发光"):
    obj = bpy.data.objects[name]
    rot = obj.matrix_world.to_3x3()
    for poly in obj.data.polygons:
        local_z = (obj.matrix_world @ poly.center).z - origin.z
        area = poly.area * rot.determinant() ** (2.0 / 3.0)
        total += 1
        total_area += area
        if (rot @ Vector(poly.normal)).normalized().z < -0.5:
            removed += 1
            removed_area += area
            key = round(local_z * 10) / 10.0
            slot = buckets.setdefault(key, [0, 0.0])
            slot[0] += 1
            slot[1] += area

print("TOTAL faces=%d area=%.4f" % (total, total_area))
print("REMOVED faces=%d area=%.4f (%.1f%% of faces, %.1f%% of area)"
      % (removed, removed_area, 100.0 * removed / total, 100.0 * removed_area / total_area))
print("REMOVED_BY_HEIGHT z_m: faces/area_m2")
for key in sorted(buckets):
    print("  %6.1f  %5d  %.4f" % (key, buckets[key][0], buckets[key][1]))
print("PROBE_DONE")
