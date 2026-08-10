import bpy
from mathutils import Vector


source = bpy.data.collections.get("01_制作组件_已统一材质")
objects = [obj for obj in source.all_objects if obj.type == "MESH"] if source else []
bpy.context.view_layer.update()
for obj in sorted(objects, key=lambda item: item.name):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = tuple(min(point[axis] for point in points) for axis in range(3))
    maximum = tuple(max(point[axis] for point in points) for axis in range(3))
    if abs(obj.location.x) > 1.2 or abs(obj.location.y) > 1.2:
        print(
            "OUTLIER",
            obj.name,
            "LOC",
            tuple(round(value, 3) for value in obj.location),
            "BOUNDS",
            tuple(round(value, 3) for value in minimum),
            tuple(round(value, 3) for value in maximum),
        )
