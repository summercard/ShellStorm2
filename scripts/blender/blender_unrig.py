# -*- coding: utf-8 -*-
"""去掉骨骼绑定（第一步：清空旧 rig）。

用途
    把一个已绑骨骼的模型还原成「干净的静态网格」，方便重新绑定与蒙皮。
    会做四件事：
      1. 删除所有 Armature 物体，并清除它们留下的 armature 数据块 / 动作；
      2. 删除网格上的 Armature 修改器；
      3. 清空网格的全部顶点组（vertex groups）；
      4. 把原本挂在骨架上的网格解除父子关系，且保持世界坐标不变。

怎么用
    Blender -> Scripting -> 打开本文件 -> Run Script（或 Text Editor 里粘贴运行）。
    脚本会先把当前状况打印出来，再动手；REPORT_ONLY = True 时只看不动。

注意
    · 删除 Armature 后，网格会回到 **rest（静止）形状**。如果你当前看到的是某个
      pose，那部分形变会消失 —— 这正是重新绑定时想要的干净状态。
    · 想保留当前 pose 的形状（非重绑定场景），把 BAKE_CURRENT_POSE 改成 True。
    · 全程一次 Undo（Ctrl+Z）可整体撤销。
"""

# --------------------------------------------------------------------------
# 参数
# --------------------------------------------------------------------------
# 支持外部覆盖：调用方在本脚本 exec 之前，把 {"REPORT_ONLY": True, ...} 放进同名
# 全局变量 _UNRIG_OVERRIDES，即可不改文件做干跑 / 换档。
_OVR = globals().get("_UNRIG_OVERRIDES", {})

REPORT_ONLY = _OVR.get("REPORT_ONLY", False)            # True = 只盘点打印，不改任何东西
CLEAR_VERTEX_GROUPS = _OVR.get("CLEAR_VERTEX_GROUPS", True)   # 清空顶点组（重新蒙皮必须清）
REMOVE_ARMATURE_MODIFIERS = _OVR.get("REMOVE_ARMATURE_MODIFIERS", True)
CLEAR_ANIMATION_DATA = _OVR.get("CLEAR_ANIMATION_DATA", True)  # 清骨架动作/NLA 与网格动画数据
UNPARENT_KEEP_TRANSFORM = _OVR.get("UNPARENT_KEEP_TRANSFORM", True)
BAKE_CURRENT_POSE = _OVR.get("BAKE_CURRENT_POSE", False)  # True = 先用当前 pose 烘成静态形状
PURGE_ORPHAN_ACTIONS = _OVR.get("PURGE_ORPHAN_ACTIONS", True)  # 回收只剩骨架在用的 action

import json

import bpy

# --------------------------------------------------------------------------
# 1. 盘点
# --------------------------------------------------------------------------
armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
meshes = [o for o in bpy.data.objects if o.type == "MESH"]

report = {
    "armatures": [
        {
            "name": a.name,
            "bones": len(a.data.bones),
            "children": [c.name for c in a.children],
            "parent": a.parent.name if a.parent else None,
            "matrix_world_translation": [round(v, 5) for v in a.matrix_world.translation],
        }
        for a in armatures
    ],
    "meshes": [
        {
            "name": m.name,
            "parent": m.parent.name if m.parent else None,
            "parent_type": m.parent_type,
            "parent_bone": m.parent_bone or None,
            "vertex_groups": len(m.vertex_groups),
            "armature_modifiers": [mo.name for mo in m.modifiers if mo.type == "ARMATURE"],
            "modifiers": [f"{mo.name}:{mo.type}" for mo in m.modifiers],
            "shape_keys": bool(m.data.shape_keys),
            "verts": len(m.data.vertices),
        }
        for m in meshes
    ],
}

print("[unrig] 盘点 / inventory")
print(json.dumps(report, ensure_ascii=False, indent=2))

if not armatures:
    print("[unrig] 场景里没有 Armature 物体，无需处理。")
if REPORT_ONLY:
    print("[unrig] REPORT_ONLY = True，盘点结束，未做任何修改。")

# --------------------------------------------------------------------------
# 2. 动手
# --------------------------------------------------------------------------
if not REPORT_ONLY and armatures:

    # ---- 2a. 可选：把当前 pose 烘成静态形状 --------------------------------
    if BAKE_CURRENT_POSE:
        if bpy.context.mode != "OBJECT":
            bpy.ops.object.mode_set(mode="OBJECT")
        for m in meshes:
            for mo in [x for x in m.modifiers if x.type == "ARMATURE"]:
                try:
                    bpy.ops.object.select_all(action="DESELECT")
                    m.select_set(True)
                    bpy.context.view_layer.objects.active = m
                    bpy.ops.object.modifier_apply(modifier=mo.name)
                    print(f"[unrig] 已烘焙 pose -> {m.name} / {mo.name}")
                except Exception as exc:
                    print(f"[unrig] 烘焙失败（跳过）: {m.name} / {mo.name}: {exc}")

    # ---- 2b. 网格：记世界矩阵、去修改器、清顶点组、解父子 ------------------
    unparented = []
    for m in meshes:
        mw = m.matrix_world.copy()

        if REMOVE_ARMATURE_MODIFIERS:
            for mo in [x for x in m.modifiers if x.type == "ARMATURE"]:
                mo_name = mo.name          # 必须先取名字：remove 之后 StructRNA 失效
                m.modifiers.remove(mo)
                print(f"[unrig] 删除修改器 {m.name} / {mo_name}")

        if CLEAR_VERTEX_GROUPS and len(m.vertex_groups):
            n = len(m.vertex_groups)
            m.vertex_groups.clear()
            print(f"[unrig] 清空顶点组 {m.name}（{n} 个）")

        if CLEAR_ANIMATION_DATA:
            if m.data.shape_keys and m.data.shape_keys.animation_data:
                m.data.shape_keys.animation_data_clear()
            if m.animation_data:
                m.animation_data_clear()

        # 挂在骨架上的网格：解父子但保住世界坐标
        attached = m.parent in armatures or bool(m.parent_bone)
        if attached:
            m.parent = None
            m.parent_type = "OBJECT"
            m.parent_bone = ""
            if UNPARENT_KEEP_TRANSFORM:
                m.matrix_world = mw
            unparented.append(m.name)
            print(f"[unrig] 解除父子 {m.name}（世界坐标已保持）")

    # ---- 2c. 收集骨架用到的 action，然后删骨架 -----------------------------
    orphan_actions = set()
    for a in armatures:
        ad = a.animation_data
        if not ad:
            continue
        if ad.action:
            orphan_actions.add(ad.action)
        for track in getattr(ad, "nla_tracks", []):
            for strip in track.strips:
                if getattr(strip, "action", None):
                    orphan_actions.add(strip.action)
        if CLEAR_ANIMATION_DATA:
            a.animation_data_clear()

    arm_data = {}
    for a in armatures:
        if a.data:
            arm_data[a.data] = a.data.name    # 先记名字，删完不能再读 .name
        name = a.name
        bpy.data.objects.remove(a, do_unlink=True)
        print(f"[unrig] 删除骨架物体 {name}")

    for d, dname in arm_data.items():
        try:
            bpy.data.armatures.remove(d)
            print(f"[unrig] 清除 armature 数据块 {dname}")
        except Exception as exc:
            print(f"[unrig] armature 数据块未能清除 {dname}: {exc}")

    # ---- 2d. 回收孤立 action -----------------------------------------------
    if PURGE_ORPHAN_ACTIONS:
        for act in sorted(orphan_actions, key=lambda x: x.name):
            if act.users == 0:
                try:
                    name = act.name
                    bpy.data.actions.remove(act)
                    print(f"[unrig] 回收动作 {name}")
                except Exception as exc:
                    print(f"[unrig] 动作回收失败 {act.name}: {exc}")
            else:
                act.use_fake_user = False
                print(f"[unrig] 动作仍被 {act.users} 处引用，保留：{act.name}")

    # ---- 2e. 清选择/激活，避免残留骨架子物体引用 ---------------------------
    for ob in bpy.data.objects:
        ob.select_set(False)

# --------------------------------------------------------------------------
# 3. 校验
# --------------------------------------------------------------------------
left_arm = [o.name for o in bpy.data.objects if o.type == "ARMATURE"]
left_mod = [f"{o.name}/{mo.name}" for o in bpy.data.objects
            if o.type == "MESH" for mo in o.modifiers if mo.type == "ARMATURE"]
left_vg = [f"{o.name}:{len(o.vertex_groups)}" for o in bpy.data.objects
           if o.type == "MESH" and len(o.vertex_groups)]
left_data = [d.name for d in bpy.data.armatures]

verify = {
    "armature_objects_left": left_arm,
    "armature_modifiers_left": left_mod,
    "meshes_with_vertex_groups_left": left_vg,
    "armature_datablocks_left": left_data,
    "mesh_world_translations": {
        o.name: [round(v, 5) for v in o.matrix_world.translation]
        for o in bpy.data.objects if o.type == "MESH"
    },
    "ok": not (left_arm or left_mod or left_vg or left_data),
}
print("[unrig] 校验 / verify")
print(json.dumps(verify, ensure_ascii=False, indent=2))

result = {"inventory": report, "verify": verify}
