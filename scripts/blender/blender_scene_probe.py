# -*- coding: utf-8 -*-
"""独立复核：不依赖 blender_unrig.py 的逻辑，直接查 Blender 真实状态。"""
import json

import bpy

obs = []
for o in bpy.data.objects:
    obs.append({
        "name": o.name,
        "type": o.type,
        "parent": o.parent.name if o.parent else None,
        "parent_type": o.parent_type,
        "parent_bone": o.parent_bone or None,
        "loc": [round(v, 6) for v in o.location],
        "world": [round(v, 6) for v in o.matrix_world.translation],
    })

meshes = {}
for m in [o for o in bpy.data.objects if o.type == "MESH"]:
    meshes[m.name] = {
        "verts": len(m.data.vertices),
        "polys": len(m.data.polygons),
        "materials": [ms.material.name if ms.material else None for ms in m.material_slots],
        "uv_layers": [uv.name for uv in m.data.uv_layers],
        "color_attrs": [c.name for c in m.data.color_attributes],
        "vertex_groups": len(m.vertex_groups),
        "modifiers": [f"{mo.name}:{mo.type}" for mo in m.modifiers],
        "shape_keys": bool(m.data.shape_keys),
        "anim_data": bool(m.animation_data),
        "skin_vertices_modifier": [mo.name for mo in m.modifiers if mo.type == "VERTEX_WEIGHT_MIX"],
        "scale": [round(v, 6) for v in m.scale],
        "dimensions": [round(v, 6) for v in m.dimensions],
    }

out = {
    "objects": obs,
    "object_count": len(bpy.data.objects),
    "meshes": meshes,
    "data_blocks": {
        "armatures": [a.name for a in bpy.data.armatures],
        "armature_count": len(bpy.data.armatures),
        "actions": [a.name for a in bpy.data.actions],
        "action_count": len(bpy.data.actions),
        "materials": [mt.name for mt in bpy.data.materials],
        "images": len(bpy.data.images),
    },
    "file": {
        "path": bpy.data.filepath,
        "is_saved": bpy.data.is_saved,
        "is_dirty": bpy.data.is_dirty,
    },
}

print(json.dumps(out, ensure_ascii=False, indent=2))
