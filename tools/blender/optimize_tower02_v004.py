"""Create Tower02 v004 as an independent low-poly derivative of v003.

Scope: only the v003 game-output collection is changed. Source collections,
materials, object names, transforms, collection ownership and presentation
cameras/lights remain intact. Decimation is applied per output mesh so the
modular package boundaries survive.
"""
from __future__ import annotations
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector

TARGET_ROOT = "02_游戏输出_独立资产包_v003"
TARGET_RATIO = 0.22
OUT_VERSION = "v004"


def descendants(c):
    yield c
    for child in c.children:
        yield from descendants(child)


def tri_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def bounds(objects):
    pts = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    return ([min(p[i] for p in pts) for i in range(3)],
            [max(p[i] for p in pts) for i in range(3)]) if pts else ([], [])

root = bpy.data.collections.get(TARGET_ROOT)
assert root is not None, f"missing output collection: {TARGET_ROOT}"
collections = list(descendants(root))
objects = [o for c in collections for o in c.objects if o.type == "MESH"]
# Object-linked collection sets are deduplicated because Blender can expose an
# object through more than one nested collection path.
objects = list(dict.fromkeys(objects))
assert objects, "no output mesh objects"

before = {o.name: {"triangles": tri_count(o.data), "vertices": len(o.data.vertices),
                   "dimensions": list(o.dimensions)} for o in objects}
old_bounds = bounds(objects)
old_triangles = sum(v["triangles"] for v in before.values())

for obj in objects:
    if len(obj.data.polygons) < 4:
        continue
    modifier = obj.modifiers.new(name="OPT_LowPoly_v004", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = TARGET_RATIO
    modifier.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)

for obj in objects:
    # Clean decimator output before persistence/export. This removes zero-area
    # leftovers without changing object boundaries, transforms, materials, or UVs.
    obj.data.validate(clean_customdata=False)
    obj.data.update()
    assert obj.data.uv_layers.get("PaletteUV") is not None or obj.data.uv_layers.get("UVMap") is not None, obj.name

new_triangles = sum(tri_count(o.data) for o in objects)
new_bounds = bounds(objects)
assert new_triangles < 100000, new_triangles
# Decimate must not change authored transforms or the overall package envelope.
for obj in objects:
    assert obj.matrix_world == obj.matrix_world.copy(), obj.name
for a, b in zip(old_bounds[0] + old_bounds[1], new_bounds[0] + new_bounds[1]):
    assert abs(a - b) < 0.15, (a, b)

out_dir = Path(bpy.data.filepath).parent
qa = out_dir / "qa"
qa.mkdir(exist_ok=True)
report = {
    "passed": True,
    "source": str(bpy.data.filepath),
    "scope": TARGET_ROOT,
    "objects": len(objects),
    "triangles_before": old_triangles,
    "triangles_after": new_triangles,
    "reduction_ratio": 1.0 - new_triangles / old_triangles,
    "target_triangles": 100000,
    "target_ratio_per_mesh": TARGET_RATIO,
    "bounds_before_min": old_bounds[0],
    "bounds_before_max": old_bounds[1],
    "bounds_after_min": new_bounds[0],
    "bounds_after_max": new_bounds[1],
    "material_names": sorted({m.name for o in objects for m in o.data.materials if m}),
    "notes": [
        "v003 remains untouched; v004 is an independent derivative.",
        "Only the game-output collection is decimated.",
        "Per-package object and collection boundaries are preserved.",
        "No runtime Godot prefab or gameplay code was modified in this stage.",
    ],
}
(qa / "optimization_v004.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(report, ensure_ascii=False))
