# -*- coding: utf-8 -*-
"""步骤4d：决定性蒙皮测试 —— 转 ORG 骨（经约束驱动 DEF），量顶点位移。

同时对比 IK 控制骨（foot_ik）与 FK 骨（thigh_fk）是否也能带动网格，
判清 Rigify 默认是 IK 还是 FK 生效。
"""
import json
import math

import bpy
from mathutils import Vector

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and not o.name.startswith("metarig"))
mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.name == "tripo_node_29629715")


def snapshot():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    return [mesh.matrix_world @ v.co.copy() for v in ev.data.vertices]


def clear_pose():
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def test(bone_name, axis, deg):
    clear_pose()
    base = snapshot()
    pb = rig.pose.bones.get(bone_name)
    if pb is None:
        return {"bone": bone_name, "missing": True}
    before_head = (rig.matrix_world @ pb.head).copy()
    pb.rotation_mode = "XYZ"
    setattr(pb.rotation_euler, axis.lower(), math.radians(deg))
    bpy.context.view_layer.update()
    after = snapshot()
    d = [(a - b).length for a, b in zip(after, base)]
    moved = sum(1 for x in d if x > 1e-4)
    return {
        "bone": bone_name, "deg": deg, "axis": axis,
        "pose_head_moved_m": round((rig.matrix_world @ pb.head - before_head).length, 5),
        "verts_moved": moved,
        "max_disp_m": round(max(d), 5),
        "mean_disp_m": round(sum(d) / len(d), 6),
    }


results = [
    test("ORG-thigh.L", "X", 35),
    test("ORG-upper_arm.L", "X", 35),
    test("ORG-spine.002", "X", 20),
    test("thigh_fk.L", "X", 35),
    test("upper_arm_fk.L", "X", 35),
    test("thigh_ik.L", "X", 35),
    test("foot_ik.L", "X", 35),
    test("hips", "X", 20),
]

clear_pose()
print(json.dumps(results, ensure_ascii=False, indent=1))
