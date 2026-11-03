# -*- coding: utf-8 -*-
"""把 18 条状态动作 GLB 合并进单一动画母版 GLB。

规格对齐现有普通怪（fat_zombie03 13 剪辑 / melee_chaser 6 剪辑）：
产物是**一份** `<slug>_visual_top3d.glb`，内含 网格 + 41 骨骼 + 18 个 animation clip。
不新建并行 GLB，运行时会按剪辑名播放。

做法：
1. 起一个空场景，导入基础视觉模型（mesh + skeleton，无动画）；
2. 逐条导入 18 个动作 GLB，取出其 Action（改名成状态名）后删掉临时对象，
   Action 用 fake_user 钉住不被回收；
3. 把 18 个 Action 逐个 stash 进基础骨架的 NLA 轨；
4. 导出为 GLB，`export_animation_mode='ACTIONS'` ⇒ 每条 Action 一个 clip。

骨架一致性由脚本自己断言：18 条动作的 joints 名与基础模型必须逐位相同，
不一致就 NotImplementedError 退出，避免把错骨架的动作烘进母版。
"""
import os
import sys
import json
import struct

import bpy

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
SLUG = "enm_elite_arms_taker"
ASSET_DIR = os.path.join(ROOT, "assets/art/enemies/elite_3d", SLUG)
COMPONENT_DIR = os.path.join(ASSET_DIR, "components", SLUG)
BASE_GLB = os.path.join(COMPONENT_DIR, SLUG + "_visual_top3d.glb")
ANIM_DIR = os.path.join(ROOT, "art_source/enemies/elite_3d", SLUG, "source/animations")
OUT_GLB = BASE_GLB

# 导出顺序 = 状态机动画清单顺序；slam 的源 clip 名不规范，这里统一改成 slam。
CLIP_SOURCES = [
    ("tvone_idle.glb", "idle"),
    ("tvone_walk.glb", "walk"),
    ("tvone_run.glb", "run"),
    ("tvone_turn_left.glb", "turn_left"),
    ("tvone_turn_right.glb", "turn_right"),
    ("tvone_attack_light.glb", "attack_light"),
    ("tvone_attack_heavy.glb", "attack_heavy"),
    ("tvone_attack_jump.glb", "attack_jump"),
    ("tvone_block.glb", "block"),
    ("tvone_dodge.glb", "dodge"),
    ("tvone_hit.glb", "hit"),
    ("tvone_stagger.glb", "stagger"),
    ("tvone_stunned.glb", "stunned"),
    ("tvone_death.glb", "death"),
    ("tvone_spawn_standup.glb", "spawn_standup"),
    ("tvone_roar.glb", "roar"),
    ("tvone_kneel.glb", "kneel"),
    ("tvone_slam.glb", "slam"),
]


def log(msg):
    print("[merge] " + str(msg), flush=True)


def gltf_json(path):
    """读 GLB 的 JSON chunk，用来做骨架断言（不依赖 Blender 的导入结果）。"""
    with open(path, "rb") as handle:
        data = handle.read()
    total = struct.unpack("<III", data[:12])[2]
    offset = 12
    while offset < total:
        chunk_len, chunk_type = struct.unpack("<II", data[offset:offset + 8])
        if struct.pack("<I", chunk_type).decode("ascii", "replace").strip() == "JSON":
            return json.loads(data[offset + 8:offset + 8 + chunk_len].decode("utf-8"))
        offset += 8 + chunk_len
    raise RuntimeError("no JSON chunk: " + path)


def joint_names(doc):
    skins = doc.get("skins") or []
    if not skins:
        return []
    return [doc["nodes"][index].get("name") for index in skins[0]["joints"]]


def wipe_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def action_frame_count(action):
    """兼容 Blender 4.x（fcurves）与 5.x（layered）两种 Action 结构。"""
    curves = getattr(action, "fcurves", None)
    if curves:
        try:
            return len(curves[0].keyframe_points)
        except Exception:
            return 0
    total = 0
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for channelbag in getattr(strip, "channelbags", []):
                total += len(getattr(channelbag, "fcurves", []))
    return total


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [obj for obj in bpy.data.objects if obj not in before]


def main():
    base_doc = gltf_json(BASE_GLB)
    base_joints = joint_names(base_doc)
    log("基础模型 joints=%d" % len(base_joints))
    if len(base_joints) != 41:
        raise RuntimeError("基础模型骨骼数异常：%d" % len(base_joints))

    # —— 先做骨架一致性断言，任何一条不一致就整体不跑 ——
    for filename, clip_name in CLIP_SOURCES:
        path = os.path.join(ANIM_DIR, filename)
        if not os.path.isfile(path):
            raise RuntimeError("缺动作文件：" + path)
        doc = gltf_json(path)
        names = joint_names(doc)
        if names != base_joints:
            raise NotImplementedError(
                "骨架与基础模型不一致：%s（joints=%d）" % (filename, len(names))
            )
    log("18 条动作骨架一致性断言通过")

    # —— 基础模型 ——
    wipe_scene()
    base_objects = import_glb(BASE_GLB)
    base_armature = next((o for o in base_objects if o.type == "ARMATURE"), None)
    if base_armature is None:
        raise RuntimeError("基础模型里找不到 Armature")
    log("基础骨架对象：%s（%d 骨）" % (base_armature.name, len(base_armature.data.bones)))

    # —— 逐条抽 Action ——
    #
    # Blender 5.x 的 Action 是 layered 结构（`layers/strips/channelbags`），
    # **没有** `fcurves` 这个旧属性 —— 直接读会 AttributeError。
    # 因此帧数一律走兼容取法，取不到就记 0（帧数只用于日志，不参与门禁）。
    actions = []
    for filename, clip_name in CLIP_SOURCES:
        path = os.path.join(ANIM_DIR, filename)
        before_actions = set(bpy.data.actions)
        added = import_glb(path)
        armature = next((o for o in added if o.type == "ARMATURE"), None)
        if armature is None:
            raise RuntimeError("动作里找不到 Armature：" + filename)
        action = None
        if armature.animation_data is not None:
            action = armature.animation_data.action
        if action is None:
            # 兜底：取这次导入新出现的 Action（新版可能不挂到 animation_data.action 上）
            fresh = [a for a in bpy.data.actions if a not in before_actions]
            if len(fresh) == 1:
                action = fresh[0]
        if action is None:
            raise RuntimeError("动作里没有 Action：" + filename)
        action.name = clip_name
        action.use_fake_user = True
        actions.append({
            "clip": clip_name,
            "action": action,
            "frames": action_frame_count(action),
            "range": [float(action.frame_range[0]), float(action.frame_range[1])],
        })
        log("  抽到 %-14s <- %-24s range=%s" % (clip_name, filename, action.frame_range[:]))
        # 删掉这条动作带进来的临时对象；Action 已 fake_user，不会被回收
        for obj in added:
            bpy.data.objects.remove(obj, do_unlink=True)

    # —— 把 18 个 Action stash 进基础骨架的 NLA ——
    if base_armature.animation_data is None:
        base_armature.animation_data_create()
    base_armature.animation_data.action = None
    for track in list(base_armature.animation_data.nla_tracks):
        base_armature.animation_data.nla_tracks.remove(track)
    for entry in actions:
        action = entry["action"]
        track = base_armature.animation_data.nla_tracks.new()
        track.name = entry["clip"]
        strip = track.strips.new(entry["clip"], int(action.frame_range[0]), action)
        strip.name = entry["clip"]
        track.mute = True
    log("已 stash %d 条 Action 到 NLA" % len(base_armature.animation_data.nla_tracks))

    # —— 导出 ——
    #
    # 两处刻意的设置，都是实测踩出来的：
    #
    # ① `export_force_sampling=False`：强制采样会按**整数帧**重采样，
    #    而源时间是 1/24 秒的整数倍但**不一定是整数帧**（idle = 127.2 帧 = 5.300s）。
    #    强制采样后变成 127 帧 = 5.292s，run 更是 20.8 → 20 帧（0.867 → 0.833s），
    #    逐条对不上源清单。关掉采样直接导出关键帧，时间戳原样保留。
    # ② 导出前清掉不在名单里的 Action：slam.glb 内含**两条** clip
    #    （`Armature.001|mixamo.com|Layer0` + `ArmatureAction`），导入时只有一条
    #    会挂到 `animation_data.action`，另一条留在 `bpy.data.actions` 里，
    #    被 `ACTIONS` 模式一并导出 ⇒ 产物多出一个 `ArmatureAction`（7.542s）。
    keep = {entry["action"].name for entry in actions}
    for action in list(bpy.data.actions):
        if action.name not in keep:
            log("  清理残留 Action：%s" % action.name)
            bpy.data.actions.remove(action)
    if os.path.isfile(OUT_GLB):
        os.remove(OUT_GLB)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_nla_strips=False,
        export_frame_range=False,
        export_force_sampling=False,
        export_optimize_animation_size=False,
        export_anim_single_armature=True,
        export_reset_pose_bones=True,
        export_yup=True,
        export_materials="EXPORT",
        export_skins=True,
    )
    log("已导出：" + OUT_GLB)

    # —— 自检：读回产物，核对 clip 数与名字 ——
    out_doc = gltf_json(OUT_GLB)
    names = [a.get("name") for a in out_doc.get("animations", [])]
    log("产物 animations=%d" % len(names))
    log("产物 clip 名：" + ", ".join(names))
    expected = [clip for _, clip in CLIP_SOURCES]
    missing = [clip for clip in expected if clip not in names]
    if missing:
        raise RuntimeError("产物缺 clip：%s" % missing)
    extra = [name for name in names if name not in expected]
    if extra:
        raise RuntimeError("产物有多余 clip（源里的脏 Action 没清干净）：%s" % extra)
    if len(names) != len(expected):
        raise RuntimeError("产物 clip 数 %d != 期望 %d" % (len(names), len(expected)))

    # 时长逐条对源清单（1/24 秒量化，容差 1 帧）
    reference = {
        "idle": 5.300, "walk": 1.433, "run": 0.867, "turn_left": 1.333,
        "turn_right": 1.333, "attack_light": 2.667, "attack_heavy": 1.100,
        "attack_jump": 3.700, "block": 1.333, "dodge": 1.633, "hit": 2.000,
        "stagger": 4.933, "stunned": 2.133, "death": 4.600,
        "spawn_standup": 3.100, "roar": 5.400, "kneel": 4.267, "slam": 7.567,
    }
    drifted = []
    for anim in out_doc.get("animations", []):
        name = anim.get("name")
        longest = 0.0
        for sampler in anim.get("samplers", []):
            accessor = out_doc["accessors"][sampler["input"]]
            if "max" in accessor:
                longest = max(longest, accessor["max"][0])
        want = reference.get(name)
        if want is None:
            continue
        if abs(longest - want) > 1.0 / 24.0 + 1e-4:
            drifted.append("%s: %.3f vs %.3f" % (name, longest, want))
    if drifted:
        raise RuntimeError("产物时长漂移超过 1 帧：%s" % drifted)
    log("自检通过：18 条 clip 全部就位、无多余 clip、时长误差均在 1 帧内")


main()
