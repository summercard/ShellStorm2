# -*- coding: utf-8 -*-
"""步骤3c：把 Basic Human metarig 摆到四足几何上（不生成、不蒙皮）。

坐标系约定（实测）：模型**头朝 -Y**（= 契约前向的反方向，后续 S3 要整体转 180°）；
左手侧 = +X；脚底 z = 0；body y∈[-0.50,0.50]，肚皮 z≈0.05，背脊 z≈0.55（尖刺 0.71）。
前脚中心 (±0.294/-0.298, -0.2898)、后脚 (±0.2556/-0.2566, +0.2162)。

映射：upper_arm/forearm/hand → **前腿**；thigh/shin/foot → **后腿**；脊柱沿体轴水平。
"""
import json

import bpy
from mathutils import Vector

TORSO_Z = 0.30          # 躯干中轴高度（低伏扁平体腔的中部）
HIP_Y = 0.26            # 髋（后腿根）所在 Y
CHEST_Y = -0.26         # 胸（前腿根）所在 Y

# name -> (head, tail, use_deform, roll_align_vector|None)
# 只在左/中侧写一条，右半由 X 取反镜像（.L -> .R）
SPEC = {
    "spine":      ((0.00,  0.260, 0.290), (0.00,  0.130, 0.300), True,  (0, 0, 1)),
    "spine.001":  ((0.00,  0.130, 0.300), (0.00,  0.000, 0.310), True,  (0, 0, 1)),
    "spine.002":  ((0.00,  0.000, 0.310), (0.00, -0.130, 0.310), True,  (0, 0, 1)),
    "spine.003":  ((0.00, -0.130, 0.310), (0.00, -0.260, 0.310), True,  (0, 0, 1)),
    "spine.004":  ((0.00, -0.260, 0.310), (0.00, -0.320, 0.330), True,  (0, 0, 1)),
    "spine.005":  ((0.00, -0.320, 0.330), (0.00, -0.370, 0.370), True,  (0, 0, 1)),
    "spine.006":  ((0.00, -0.370, 0.370), (0.00, -0.440, 0.400), True,  (0, 0, 1)),

    # 前腿：锁骨从胸侧伸到肩，手臂链向下当腿，肘向后弯
    "shoulder.L":  ((0.050, -0.200, 0.320), (0.200, -0.260, 0.300), True, (0, 0, 1)),
    "upper_arm.L": ((0.200, -0.260, 0.300), (0.270, -0.235, 0.170), True, (0, 1, 0)),
    "forearm.L":   ((0.270, -0.235, 0.170), (0.294, -0.290, 0.065), True, (0, 1, 0)),
    "hand.L":      ((0.294, -0.290, 0.065), (0.294, -0.350, 0.020), True, (0, 0, 1)),

    # 后腿：膝向前（同人腿），脚掌朝前
    "thigh.L":     ((0.120,  0.230, 0.270), (0.205,  0.200, 0.160), True, (0, -1, 0)),
    "shin.L":      ((0.205,  0.200, 0.160), (0.256,  0.216, 0.055), True, (0, -1, 0)),
    "foot.L":      ((0.256,  0.216, 0.055), (0.256,  0.194, 0.046), True, (0, 0, 1)),
    "toe.L":       ((0.256,  0.194, 0.046), (0.256,  0.182, 0.046), True, (0, 0, 1)),
    "heel.02.L":   ((0.220,  0.270, 0.005), (0.290,  0.270, 0.005), True, (0, 0, 1)),

    # 无意义骨：塞进体腔，且关掉 deform（不生成顶点组）
    "breast.L":    ((0.070, -0.120, 0.120), (0.070, -0.160, 0.120), False, None),
    "pelvis.L":    ((0.060,  0.260, 0.290), (0.120,  0.200, 0.240), False, None),
}

# 这些骨在 Basic Human 里不存在（记录下来，供后续补手指时用）
ABSENT = ["palm.01.L", "f_index.01.L", "thumb.01.L"]


def mirror(v):
    return (-v[0], v[1], v[2])


def apply_spec(rig, name, head, tail, deform, align):
    eb = rig.data.edit_bones.get(name)
    if eb is None:
        return None
    eb.use_connect = False           # 先断开，避免改 head 时被父级拉走
    eb.head = Vector(head)
    eb.tail = Vector(tail)
    eb.use_deform = deform
    if align:
        eb.align_roll(Vector(align))
    return {"name": name, "head": [round(c, 4) for c in eb.head],
            "tail": [round(c, 4) for c in eb.tail],
            "roll": round(eb.roll, 4), "deform": deform}


if bpy.context.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")

rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
assert rig is not None, "没有 metarig"

bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")

applied = []
missing = []
for name, (h, t, deform, align) in SPEC.items():
    r = apply_spec(rig, name, h, t, deform, align)
    if r is None:
        missing.append(name)
        continue
    applied.append(r)
    if name.endswith(".L"):
        rn = name[:-2] + ".R"
        r2 = apply_spec(rig, rn, mirror(h), mirror(t), deform,
                        None if align is None else (-align[0], align[1], align[2]))
        if r2 is None:
            missing.append(rn)
        else:
            applied.append(r2)

# 恢复父子连接：把本来 connected 的链重新连上
# ⚠️ 漏连会让 Rigify 报「Input to rig type must be a chain of at least 3 bones」——
# 手臂链必须是 upper_arm -> forearm -> hand 三根连通，腿链是 shin -> foot -> toe。
RECONNECT = ["spine.001", "spine.002", "spine.003", "spine.005",
             "forearm.L", "forearm.R", "hand.L", "hand.R",
             "shin.L", "shin.R", "foot.L", "foot.R", "toe.L", "toe.R"]
for n in RECONNECT:
    eb = rig.data.edit_bones.get(n)
    if eb and eb.parent:
        eb.use_connect = True

bpy.ops.object.mode_set(mode="OBJECT")

print(json.dumps({
    "metarig": rig.name,
    "applied_count": len(applied),
    "missing": missing,
    "absent_not_in_metarig": ABSENT,
    "applied": applied,
}, ensure_ascii=False, indent=2))
