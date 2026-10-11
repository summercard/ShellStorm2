# -*- coding: utf-8 -*-
"""headless 读一个 .blend 的骨架结构（只读，不保存）。"""
import json

import bpy

out = {"file": bpy.data.filepath, "armatures": [], "meshes": []}

for a in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    bones = []
    for b in a.data.bones:
        bones.append({
            "name": b.name,
            "parent": b.parent.name if b.parent else None,
            "use_deform": b.use_deform,
            "head_world": [round(v, 4) for v in (a.matrix_world @ b.head_local)],
            "len": round(b.length, 4),
        })
    out["armatures"].append({
        "object": a.name,
        "data": a.data.name,
        "bone_count": len(a.data.bones),
        "deform_bone_count": sum(1 for b in a.data.bones if b.use_deform),
        "bones": bones,
    })

for m in [o for o in bpy.data.objects if o.type == "MESH"]:
    out["meshes"].append({
        "name": m.name,
        "verts": len(m.data.vertices),
        "vertex_groups": len(m.vertex_groups),
        "vertex_group_names": [g.name for g in m.vertex_groups],
        "modifiers": [f"{mo.name}:{mo.type}" for mo in m.modifiers],
        "parent": m.parent.name if m.parent else None,
        "dims": [round(v, 4) for v in m.dimensions],
    })

print("===RIG_DUMP_BEGIN===")
print(json.dumps(out, ensure_ascii=False))
print("===RIG_DUMP_END===")
