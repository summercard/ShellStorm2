import bpy
from collections import defaultdict
from mathutils import Vector


def bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    if not points:
        return None
    return tuple(round(min(point[i] for point in points), 4) for i in range(3)), tuple(
        round(max(point[i] for point in points), 4) for i in range(3)
    )


source = bpy.data.collections.get("01_制作组件_已统一材质")
objects = [obj for obj in source.all_objects if obj.type == "MESH"] if source else []
groups = defaultdict(list)
for obj in objects:
    groups[obj.name.split("_", 1)[0]].append(obj)

print("FILE", bpy.data.filepath)
print("SOURCE_OBJECTS", len(objects), "BOUNDS", bounds(objects))
for prefix, members in sorted(groups.items()):
    print("PREFIX", prefix, "COUNT", len(members), "BOUNDS", bounds(members))
    for obj in sorted(members, key=lambda item: item.name)[:5]:
        print(" EXAMPLE", obj.name, "LOC", tuple(round(v, 4) for v in obj.location), "DIM", tuple(round(v, 4) for v in obj.dimensions))
