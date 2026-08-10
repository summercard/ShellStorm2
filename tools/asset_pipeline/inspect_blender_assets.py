import bpy


def bounds_for(objects):
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        return None
    return tuple(min(p[i] for p in points) for i in range(3)), tuple(max(p[i] for p in points) for i in range(3))


from mathutils import Vector

print("FILE", bpy.data.filepath)
for collection in bpy.data.collections:
    mesh_objects = [obj for obj in collection.all_objects if obj.type == "MESH"]
    if mesh_objects:
        print("COLL", collection.name, len(mesh_objects), bounds_for(mesh_objects))
for obj in bpy.data.objects:
    if obj.type == "MESH":
        mats = [slot.material.name if slot.material else "" for slot in obj.material_slots]
        print("OBJ", obj.name, obj.parent.name if obj.parent else "-", tuple(round(v, 4) for v in obj.dimensions), tuple(round(v, 4) for v in obj.location), mats)
