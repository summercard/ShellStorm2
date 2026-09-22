import bpy
import json
from pathlib import Path

TARGETS = [
    Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments\tower_zones\battle\source\common_components\v006\env_battle_common_components_source_v006.blend"),
    Path(r"I:\工作项目\shellstrom2\ShellStorm2\source\art\blender\base_facility_layout\component_packages\architecture\base_corner_l_5m\base_corner_l_5m_source_v024.blend"),
]

def inspect(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    result = {"file": str(path), "scenes": [s.name for s in bpy.data.scenes], "collections": []}
    for c in bpy.data.collections:
        meshes = [o for o in c.all_objects if o.type == "MESH"]
        if meshes:
            result["collections"].append({
                "name": c.name,
                "objects": [o.name for o in meshes],
                "roots": [o.name for o in c.objects if o.type == "EMPTY" or o.name.startswith("ROOT")],
                "bounds": [list(min((o.matrix_world @ v.co)[i] for o in meshes for v in o.data.vertices) for i in range(3)), list(max((o.matrix_world @ v.co)[i] for o in meshes for v in o.data.vertices) for i in range(3))],
                "materials": sorted({m.name for o in meshes for m in o.data.materials if m}),
                "uv_layers": sorted({layer.name for o in meshes for layer in o.data.uv_layers}),
                "props": {k: c[k] for k in c.keys()},
                "object_transforms": [{"name": o.name, "location": list(o.location), "matrix_world": [list(row) for row in o.matrix_world], "parent": o.parent.name if o.parent else None, "props": {k: o[k] for k in o.keys()}} for o in meshes[:8]],
            })
    return result

OUT = Path(r"I:\工作项目\shellstrom2\ShellStorm2\_scratch\probe_generic_sources_v001.json")
rows = []
for target in TARGETS:
    rows.append(inspect(target))
OUT.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
print("PROBE_WRITTEN", OUT)
