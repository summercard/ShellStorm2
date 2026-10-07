from __future__ import annotations

import bpy
import json
from pathlib import Path


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def walk_collection(collection):
    yield collection
    for child in collection.children:
        yield from walk_collection(child)

collections = []
for collection in bpy.data.collections:
    if collection.name not in {c.name for c in collection.children_recursive}:
        collections.append(collection)

result = {
    "blend": bpy.data.filepath,
    "collections": [],
    "objects": [],
}
for collection in sorted(bpy.data.collections, key=lambda c: c.name):
    mesh_objects = [o for o in collection.objects if o.type == "MESH"]
    if mesh_objects:
        result["collections"].append({
            "name": collection.name,
            "mesh_objects": len(mesh_objects),
            "objects": [o.name for o in mesh_objects],
            "triangles": sum(tri_count(o) for o in mesh_objects),
        })
for obj in sorted((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: o.name):
    result["objects"].append({
        "name": obj.name,
        "triangles": tri_count(obj),
        "vertices": len(obj.data.vertices),
        "polygons": len(obj.data.polygons),
        "collections": [c.name for c in obj.users_collection],
        "materials": [m.name if m else None for m in obj.data.materials],
    })

out = Path(bpy.data.filepath).with_suffix(".scene_audit.json")
out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"collections": len(result["collections"]), "objects": len(result["objects"]), "output": str(out)}, ensure_ascii=False))
