"""只读：列出 v002 blend 中地面系统 / 外墙系统的资产包集合、根对象与包围盒。"""
import bpy
from mathutils import Vector

BLEND = "/dummy"

TARGET_KEYS = ["地砖", "外墙"]


def aabb(objects):
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                mins[axis] = min(mins[axis], world[axis])
                maxs[axis] = max(maxs[axis], world[axis])
    return mins, maxs


def collect(collection):
    result = list(collection.objects)
    for child in collection.children:
        result.extend(collect(child))
    return result


print("LIST_BEGIN")
for collection in sorted(bpy.data.collections, key=lambda c: c.name):
    if not any(key in collection.name for key in TARGET_KEYS):
        continue
    meshes = [o for o in collect(collection) if o.type == "MESH"]
    roots = [o for o in collection.objects if o.type != "MESH"]
    mins, maxs = aabb(meshes) if meshes else ([0, 0, 0], [0, 0, 0])
    print(
        "PKG %-28s meshes=%d roots=%s origin=%s\n"
        "     AABB min=[%.4f, %.4f, %.4f] max=[%.4f, %.4f, %.4f] size=[%.4f, %.4f, %.4f]\n"
        "     mesh_names=%s"
        % (
            collection.name,
            len(meshes),
            [r.name for r in roots],
            [tuple(round(v, 4) for v in r.location) for r in roots],
            mins[0],
            mins[1],
            mins[2],
            maxs[0],
            maxs[1],
            maxs[2],
            maxs[0] - mins[0],
            maxs[1] - mins[1],
            maxs[2] - mins[2],
            [m.name for m in meshes],
        )
    )
print("LIST_END")
