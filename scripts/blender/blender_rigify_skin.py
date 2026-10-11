# -*- coding: utf-8 -*-
"""步骤4b：汇总生成结果 + 用自动权重把网格蒙皮到 rig（幂等）。"""
import json
import traceback

import bpy

if bpy.context.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.select_all(action="DESELECT")

metarig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name.startswith("metarig"))
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o is not metarig)
mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.name == "tripo_node_29629715")

prefix = {}
deform = []
for b in rig.data.bones:
    p = b.name.split("-")[0] if "-" in b.name else "NOPREFIX"
    prefix[p] = prefix.get(p, 0) + 1
    if b.use_deform:
        deform.append(b.name)

# ---- 清掉旧蒙皮 ----
for mo in [m for m in mesh.modifiers if m.type == "ARMATURE"]:
    mesh.modifiers.remove(mo)
mesh.parent = None
prev_vg = len(mesh.vertex_groups)
mesh.vertex_groups.clear()

# ---- 自动权重 ----
err = None
try:
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
except Exception:
    err = traceback.format_exc()

# ---- 复核 ----
groups = sorted(g.name for g in mesh.vertex_groups)
deform_set = set(deform)
# 每个顶点组的权重顶点数
wcount = {g.name: 0 for g in mesh.vertex_groups}
gi = {g.index: g.name for g in mesh.vertex_groups}
weighted_verts = 0
for v in mesh.data.vertices:
    hit = False
    for ge in v.groups:
        n = gi.get(ge.group)
        if n:
            wcount[n] += 1
            hit = True
    if hit:
        weighted_verts += 1

print(json.dumps({
    "rig": rig.name,
    "rig_bones": len(rig.data.bones),
    "bone_prefixes": prefix,
    "deform_bone_count": len(deform),
    "deform_bones": sorted(deform),
    "parent_error": err,
    "mesh": mesh.name,
    "mesh_parent": mesh.parent.name if mesh.parent else None,
    "modifiers": [f"{m.name}:{m.type}" for m in mesh.modifiers],
    "prev_vertex_groups": prev_vg,
    "now_vertex_group_count": len(groups),
    "groups_not_in_deform": [g for g in groups if g not in deform_set][:40],
    "deform_bones_without_group": sorted(deform_set - set(groups))[:40],
    "weighted_verts": weighted_verts,
    "total_verts": len(mesh.data.vertices),
    "zero_weight_groups": sorted([k for k, v in wcount.items() if v == 0]),
}, ensure_ascii=False, indent=1))
