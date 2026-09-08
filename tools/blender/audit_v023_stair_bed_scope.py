import bpy
import json
from mathutils import Vector
from pathlib import Path

TARGETS = {
    "northwest_l_stair": "14_西北贴墙L型楼梯_资产包",
    "loft_bed_and_bedding": "31__02_游戏输出_整合模型",
}

def all_objects(collection):
    seen = set()
    for obj in collection.all_objects:
        if obj.name not in seen:
            seen.add(obj.name)
            yield obj

def mesh_summary(objects):
    meshes = [obj for obj in objects if obj.type == "MESH"]
    faces = sum(len(obj.data.polygons) for obj in meshes)
    triangles = sum(sum(len(poly.vertices) - 2 for poly in obj.data.polygons) for obj in meshes)
    return {
        "mesh_count": len(meshes),
        "faces": faces,
        "triangles": triangles,
        "materials": sorted({mat.name for obj in meshes for mat in obj.data.materials if mat}),
        "uv_layers": {obj.name: [uv.name for uv in obj.data.uv_layers] for obj in meshes},
        "world_bbox": bbox(meshes),
        "objects": [
            {
                "name": obj.name,
                "type": obj.type,
                "modifiers": [modifier.name for modifier in obj.modifiers],
            }
            for obj in objects
        ],
    }

def bbox(objects):
    points = []
    for obj in objects:
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    if not points:
        return None
    return {
        "min": [min(point[i] for point in points) for i in range(3)],
        "max": [max(point[i] for point in points) for i in range(3)],
    }

report = {
    "file": bpy.data.filepath,
    "targets": {},
}
for slug, collection_name in TARGETS.items():
    collection = bpy.data.collections.get(collection_name)
    assert collection is not None, f"missing target collection: {collection_name}"
    report["targets"][slug] = {
        "collection": collection_name,
        **mesh_summary(list(all_objects(collection))),
    }
print("BASE99_V023_SCOPE_AUDIT=" + json.dumps(report, ensure_ascii=False))
