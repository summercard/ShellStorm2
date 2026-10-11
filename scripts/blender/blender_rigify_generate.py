# -*- coding: utf-8 -*-
"""步骤4a：生成 Rigify 骨架（幂等：已有生成结果先删）。"""
import json
import traceback

import bpy

if bpy.context.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.select_all(action="DESELECT")

metarig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name.startswith("metarig"))
# 清掉上一次的生成结果
for o in [x for x in bpy.data.objects if x.type == "ARMATURE" and x is not metarig]:
    print("REMOVE old rig:", o.name)
    bpy.data.objects.remove(o, do_unlink=True)

bpy.context.view_layer.objects.active = metarig
metarig.select_set(True)

err = None
try:
    bpy.ops.pose.rigify_generate()
except Exception:
    err = traceback.format_exc()

rigs = [o for o in bpy.data.objects if o.type == "ARMATURE" and o is not metarig]
res = {
    "error": err,
    "objects": [o.name for o in bpy.data.objects],
    "generated": [{"name": r.name, "bones": len(r.data.bones),
                   "deform_bones": sum(1 for b in r.data.bones if b.use_deform)} for r in rigs],
}
if rigs:
    r = rigs[0]
    groups = {}
    for b in r.data.bones:
        p = b.name.split("-")[0] if "-" in b.name else ("DEF" if b.use_deform else "OTHER")
        groups[p] = groups.get(p, 0) + 1
    res["bone_prefixes"] = groups
    res["def_names"] = sorted(b.name for b in r.data.bones if b.use_deform)[:80]
print(json.dumps(res, ensure_ascii=False, indent=1))
