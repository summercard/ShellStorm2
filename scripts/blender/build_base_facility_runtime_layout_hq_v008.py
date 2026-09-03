#!/usr/bin/env python3
"""Build Base 99 HQ v008: south visual-center facility detailing only.

Input is the organized v007 scene. Locked architecture, floor, mezzanine,
railing, stair and non-scope facilities are not modified. The former TV-like
panel is rebuilt in-place as the reference roll-up main door, and all new
facility details remain in independent export-package Collections.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path("/Users/summercards/ShellStorm2")
INPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v007.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v008.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v008"
VERIFY_ROOT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v008"
HERO_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v008.png"
TOP_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v008_top.png"
DETAIL_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v008_south_facilities.png"
CATALOG_JSON = VERIFY_ROOT / "base_facility_component_catalog_v008.json"
TREE_TXT = VERIFY_ROOT / "base_facility_component_tree_v008.txt"

V006_SCRIPT = PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v006.py"
spec = importlib.util.spec_from_file_location("base_facility_hq_v006_helpers", V006_SCRIPT)
v006 = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(v006)
base = v006.base

ROOT_NAME = "基地99层高品质微缩模型_中文资产管理"
OUTPUT_NAME = "02_游戏输出_独立资产包_v007"
UNDERLOFT_CATEGORY = "40_阁楼外侧视觉中心设施"


def setup_helpers():
    base.SOURCE = bpy.data.collections["01_制作组件_已统一材质"]
    base.SOURCE.hide_viewport = False
    base.SOURCE.hide_render = True
    base.OUTPUT = bpy.data.collections[OUTPUT_NAME]
    base.MATS.clear()
    base.MATS.update({
        "metal": bpy.data.materials["01_精工金属_紫色骨架"],
        "matte": bpy.data.materials["02_细腻哑光_青绿大面"],
        "gloss": bpy.data.materials["03_清漆反光_紫粉点缀"],
        "emit": bpy.data.materials["04_柔和自发光_UI灯光"],
    })


def ensure_child(parent, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def package_meta(collection, slug, category="underloft"):
    collection["资产包"] = True
    collection["资产包键"] = slug
    collection["资产类别"] = category
    collection["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
    collection["未来导出目录"] = str((PACKAGE_ROOT / category / slug).relative_to(PROJECT))
    collection["组织版本"] = "v008"
    collection["当前状态"] = "已深化归类_待独立导出"
    collection["本批次范围"] = "南面视觉中心设施区域"
    return collection


def rename_package(old_name, new_name, slug):
    collection = bpy.data.collections[old_name]
    collection.name = new_name
    return package_meta(collection, slug)


def add_package(parent, name, slug):
    return package_meta(ensure_child(parent, name), slug)


def add_box(name, loc, size, role, color, target, bevel=0.035, obstacle=False, rotation=(0, 0, 0)):
    obj = base.add_box(name, loc, size, role, color, bevel, target, obstacle, rotation)
    obj["v008_scope"] = "south_facility_detail"
    return obj


def add_cylinder(name, loc, radius, depth, role, color, target, vertices=16, obstacle=False, rotation=(0, 0, 0)):
    obj = base.add_cylinder(name, loc, radius, depth, role, color, vertices, target, obstacle, rotation)
    obj["v008_scope"] = "south_facility_detail"
    return obj


def add_beam(name, start, end, thickness, role, color, target):
    obj = base.add_beam(name, start, end, thickness, role, color, target)
    obj["v008_scope"] = "south_facility_detail"
    return obj


def add_text(name, body, loc, size, role, color, target, extrude=0.025, align="CENTER"):
    bpy.ops.object.select_all(action="DESELECT")
    obj = base.add_text(name, body, loc, size, role, color, extrude, align, (math.pi / 2, 0, 0), target)
    obj["v008_scope"] = "south_facility_detail"
    return obj


def add_torus(name, loc, major_radius, minor_radius, role, color, target, major_segments=36, minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(
        align="WORLD", major_segments=major_segments, minor_segments=minor_segments,
        location=loc, major_radius=major_radius, minor_radius=minor_radius,
    )
    src = bpy.context.object
    base.link_only(src, base.SOURCE)
    src.name = name + "__源"
    base.assign_material(src, role, base.COLORS[color])
    obj = base.publish(src, target, name)
    obj["v008_scope"] = "south_facility_detail"
    return obj


def add_point_light(name, loc, energy, color, target, radius=1.0):
    data = bpy.data.lights.new(name, "POINT")
    data.energy = energy
    data.color = color
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data)
    target.objects.link(obj)
    obj.location = loc
    obj["v008_scope"] = "south_facility_detail"
    return obj


def animate_scale(obj, frames, axis="z"):
    index = {"x": 0, "y": 1, "z": 2}[axis]
    original = list(obj.scale)
    for frame, value in frames:
        scale = original.copy()
        scale[index] = value
        obj.scale = scale
        obj.keyframe_insert("scale", frame=frame)
    if obj.animation_data and obj.animation_data.action:
        for curve in obj.animation_data.action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = "BEZIER"
            curve.modifiers.new("CYCLES")


def animate_light(light, frames):
    for frame, energy in frames:
        light.data.energy = energy
        light.data.keyframe_insert("energy", frame=frame)
    if light.data.animation_data and light.data.animation_data.action:
        for curve in light.data.animation_data.action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = "BEZIER"
            curve.modifiers.new("CYCLES")


def locked_signature(collection_names):
    payload = {}
    for collection_name in collection_names:
        collection = bpy.data.collections[collection_name]
        for obj in collection.all_objects:
            data = None
            if obj.type == "MESH":
                data = (obj.data.name, len(obj.data.vertices), len(obj.data.polygons), tuple(mat.name if mat else None for mat in obj.data.materials))
            payload[obj.name] = {
                "type": obj.type,
                "parent": obj.parent.name if obj.parent else None,
                "matrix": tuple(round(float(v), 8) for row in obj.matrix_world for v in row),
                "dimensions": tuple(round(float(v), 8) for v in obj.dimensions),
                "data": data,
            }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return payload, hashlib.sha256(encoded).hexdigest()


def delete_old_door_misread():
    prefixes = ("工业电视墙_", "电视扫描线_")
    for obj in list(bpy.data.objects):
        is_low_cabinet = obj.name in {"工业电视墙_下方储物柜", "工业电视墙_下方储物柜__源"}
        if obj.name.startswith(prefixes) and not is_low_cabinet:
            bpy.data.objects.remove(obj, do_unlink=True)


def rename_pair(old, new):
    obj = bpy.data.objects.get(old)
    if obj:
        obj.name = new
    src = bpy.data.objects.get(old + "__源")
    if src:
        src.name = new + "__源"


def relabel_existing_objects():
    replacements = {
        "电视背景墙_钢板左": "南墙工业墙板_左装甲板",
        "电视背景墙_旧木板中": "南墙工业墙板_中复合板",
        "电视背景墙_水泥板右": "南墙工业墙板_右修补板",
        "电视背景墙_钢包边_1.8": "南墙工业墙板_竖向加强筋_1.8",
        "电视背景墙_钢包边_3.4": "南墙工业墙板_竖向加强筋_3.4",
        "电视背景墙_钢包边_5.0": "南墙工业墙板_竖向加强筋_5.0",
        "电视背景墙_钢包边_6.6": "南墙工业墙板_竖向加强筋_6.6",
        "电视背景墙_钢包边_8.2": "南墙工业墙板_竖向加强筋_8.2",
        "工业电视墙_下方储物柜": "主门下方低矮设备柜_主体",
        "电视低柜门_2.7": "主门低柜_柜门_01",
        "电视低柜门_4.25": "主门低柜_柜门_02",
        "电视低柜门_5.75": "主门低柜_柜门_03",
        "电视低柜门_7.3": "主门低柜_柜门_04",
    }
    for old, new in replacements.items():
        rename_pair(old, new)


def build_south_wall_details(package):
    # Attachment-only ribs and pillars; the locked wall meshes remain untouched.
    for idx, z in enumerate((0.48, 3.82, 4.94)):
        add_box(f"南墙工业附着横向加强筋_{idx+1:02d}", (5.0, 4.79, z), (19.35, 0.12, 0.14), "metal", "dark_gray", package, 0.025)
    for idx, x in enumerate((-4.62, -0.35, 9.72, 14.58)):
        add_box(f"南墙工业附着竖向结构柱_{idx+1:02d}", (x, 4.78, 2.70), (0.24, 0.16, 4.55), "metal", "purple", package, 0.035)
        for z in (0.62, 1.72, 2.82, 3.92, 4.78):
            add_cylinder(f"南墙结构柱固定螺栓_{idx+1:02d}_{z:.2f}", (x, 4.675, z), 0.045, 0.035, "metal", "mid_gray", package, 10, rotation=(math.pi / 2, 0, 0))
    # Two restrained service plates in empty wall bays.
    for idx, (x, z, w, h) in enumerate(((-0.75, 3.15, 1.05, 0.72), (10.25, 3.25, 0.95, 0.62))):
        add_box(f"南墙小型检修板_{idx+1:02d}", (x, 4.68, z), (w, 0.08, h), "matte", "mid_gray", package, 0.06)
        for sx in (-w * 0.40, w * 0.40):
            for sz in (-h * 0.36, h * 0.36):
                add_cylinder(f"南墙检修板螺钉_{idx+1:02d}_{sx:.2f}_{sz:.2f}", (x + sx, 4.62, z + sz), 0.025, 0.025, "metal", "dark_gray", package, 8, rotation=(math.pi / 2, 0, 0))
    # Cyan edge lights and small orange service lamps follow the reference hierarchy.
    for idx, x in enumerate((-3.7, 0.4, 9.4, 13.55)):
        add_box(f"南墙青蓝边缘灯_{idx+1:02d}_自发光", (x, 4.65, 4.85), (2.2, 0.05, 0.07), "emit", "cyan", package, 0.012)
    for idx, x in enumerate((-4.2, -0.1, 9.85, 14.05)):
        add_box(f"南墙橙色维护灯_{idx+1:02d}_自发光", (x, 4.62, 4.27), (0.22, 0.08, 0.22), "emit", "orange", package, 0.045)


def build_rollup_door(package):
    # Locked opening envelope: X[2.10,7.90], Z[0.925,3.475].
    add_box("BASE主门_外围门框底衬", (5.0, 4.64, 2.20), (5.80, 0.40, 2.55), "metal", "dark_gray", package, 0.09)
    add_box("BASE主门_左厚重导轨", (2.28, 4.37, 2.20), (0.34, 0.20, 2.46), "metal", "purple", package, 0.055)
    add_box("BASE主门_右厚重导轨", (7.72, 4.37, 2.20), (0.34, 0.20, 2.46), "metal", "purple", package, 0.055)
    add_box("BASE主门_顶部卷门机械箱", (5.0, 4.36, 3.34), (5.18, 0.26, 0.28), "metal", "dark_gray", package, 0.065)
    for index in range(12):
        z = 1.06 + index * 0.19
        color = "teal" if index % 3 else "green"
        add_box(f"BASE主门_青绿色卷帘板_{index+1:02d}", (5.0, 4.205, z), (5.12, 0.10, 0.165), "matte", color, package, 0.025)
        add_box(f"BASE主门_卷帘机械接缝_{index+1:02d}", (5.0, 4.14, z - 0.088), (5.02, 0.025, 0.025), "metal", "dark_gray", package, 0.006)
    add_box("BASE主门_底部导向轨", (5.0, 4.16, 0.97), (5.16, 0.16, 0.18), "metal", "mid_gray", package, 0.035)
    # Motor, axle housings and drive chain cover.
    add_cylinder("BASE主门_顶部电机主壳", (6.85, 4.18, 3.55), 0.25, 0.62, "metal", "purple", package, 20, rotation=(0, math.pi / 2, 0))
    add_cylinder("BASE主门_电机端盖", (7.18, 4.18, 3.55), 0.18, 0.08, "gloss", "teal", package, 16, rotation=(0, math.pi / 2, 0))
    add_box("BASE主门_驱动链保护罩", (7.48, 4.19, 3.23), (0.26, 0.16, 0.56), "metal", "dark_gray", package, 0.07)
    for idx, x in enumerate((2.25, 2.43, 7.57, 7.75)):
        for z in (1.10, 1.72, 2.34, 2.96, 3.34):
            add_cylinder(f"BASE主门_门框固定螺丝_{idx+1:02d}_{z:.2f}", (x, 4.08, z), 0.035, 0.025, "metal", "light_gray", package, 8, rotation=(math.pi / 2, 0, 0))
    # White central Base logo, restrained to the central third.
    logo_y = 4.10
    add_beam("BASE主门_白色Logo_左边_自发光", (4.45, logo_y, 2.48), (5.00, logo_y, 1.78), 0.075, "emit", "light_gray", package)
    add_beam("BASE主门_白色Logo_右边_自发光", (5.00, logo_y, 1.78), (5.55, logo_y, 2.48), 0.075, "emit", "light_gray", package)
    add_beam("BASE主门_白色Logo_顶边_自发光", (4.45, logo_y, 2.48), (5.55, logo_y, 2.48), 0.075, "emit", "light_gray", package)
    add_beam("BASE主门_白色Logo_内标_自发光", (4.74, logo_y - 0.015, 2.24), (5.26, logo_y - 0.015, 2.24), 0.045, "emit", "cyan", package)
    # Controls and safety hardware stay small and outside the opening.
    add_box("BASE主门_右侧开门控制面板", (8.08, 4.34, 2.08), (0.42, 0.18, 0.92), "metal", "dark_gray", package, 0.065)
    add_box("BASE主门_控制面板屏幕_自发光", (8.08, 4.23, 2.31), (0.29, 0.035, 0.27), "emit", "cyan", package, 0.025)
    for idx, z in enumerate((1.98, 1.82, 1.66)):
        add_cylinder(f"BASE主门_控制实体按键_{idx+1:02d}", (8.08, 4.22, z), 0.045, 0.035, "gloss", "orange" if idx == 0 else "mid_gray", package, 12, rotation=(math.pi / 2, 0, 0))
    add_box("BASE主门_左安全传感器", (1.94, 4.30, 1.45), (0.18, 0.16, 0.62), "metal", "dark_gray", package, 0.04)
    add_box("BASE主门_左安全传感器镜片_自发光", (1.94, 4.20, 1.55), (0.10, 0.025, 0.18), "emit", "cyan", package, 0.02)
    add_cylinder("BASE主门_紧急停止按钮", (8.12, 4.18, 1.34), 0.13, 0.09, "gloss", "red", package, 16, rotation=(math.pi / 2, 0, 0))
    add_text("BASE主门_安全标识", "CAUTION", (7.12, 4.08, 1.15), 0.16, "matte", "yellow", package, 0.010)
    # Controlled wear at bottom and frame edges.
    for idx, x in enumerate((3.05, 3.75, 6.25, 6.95)):
        add_box(f"BASE主门_底部轻微摩擦痕_{idx+1:02d}", (x, 4.08, 1.02), (0.34, 0.018, 0.045), "matte", "warm_gray", package, 0.004, rotation=(0, 0, (-0.12 if idx % 2 else 0.10)))
    warning = add_point_light("BASE主门_橙色警示灯光", (7.92, 4.00, 3.58), 90, (1.0, 0.18, 0.02), package, 0.45)
    lamp = add_box("BASE主门_橙色警示灯_自发光", (7.92, 4.20, 3.58), (0.24, 0.12, 0.26), "emit", "orange", package, 0.05)
    animate_light(warning, ((1, 10), (52, 105), (70, 18), (150, 12), (190, 90), (210, 10), (241, 10)))
    animate_scale(lamp, ((1, 0.78), (52, 1.08), (70, 0.82), (150, 0.78), (190, 1.05), (210, 0.78), (241, 0.78)), "z")


def build_sign_details(package):
    # Existing sign location/ratio is untouched; additions hug its original envelope.
    for z in (4.00, 4.86):
        add_box(f"BASE_CAMP标牌_加厚外框_{z:.2f}", (5.0, 4.68, z), (7.72, 0.18, 0.12), "metal", "purple", package, 0.03)
    for x in (1.16, 8.84):
        add_box(f"BASE_CAMP标牌_侧框_{x:.2f}", (x, 4.68, 4.43), (0.12, 0.18, 0.92), "metal", "dark_gray", package, 0.025)
    for idx, x in enumerate((1.55, 3.25, 5.0, 6.75, 8.45)):
        add_box(f"BASE_CAMP标牌_背部固定支架_{idx+1:02d}", (x, 4.90, 4.43), (0.12, 0.25, 0.62), "metal", "dark_gray", package, 0.025)
        add_cylinder(f"BASE_CAMP标牌_连接螺钉_{idx+1:02d}", (x, 4.56, 4.43), 0.038, 0.025, "metal", "light_gray", package, 10, rotation=(math.pi / 2, 0, 0))
    add_box("BASE_CAMP标牌_上沿青蓝泛光条_自发光", (5.0, 4.55, 4.91), (7.20, 0.04, 0.055), "emit", "cyan", package, 0.012)


def recolor_existing(obj_name, role, color):
    obj = bpy.data.objects.get(obj_name)
    if obj and obj.type == "MESH":
        base.assign_material(obj, role, base.COLORS[color])


def cabinet_frame(prefix, x, package, accent, label, variant):
    # Existing body/door dimensions and positions remain fixed.
    recolor_existing(f"工业储物柜_{variant:02d}_柜体", "matte", "dark_gray")
    recolor_existing(f"工业储物柜_{variant:02d}_柜门", "matte", "mid_gray")
    add_box(f"{prefix}_顶部装甲帽", (x, 4.42, 2.91), (1.58, 0.78, 0.18), "metal", "dark_gray", package, 0.06)
    add_box(f"{prefix}_底部承重座", (x, 4.42, 0.13), (1.58, 0.78, 0.22), "metal", "purple", package, 0.05)
    for sx in (-0.68, 0.68):
        add_box(f"{prefix}_门框_{sx:+.2f}", (x + sx, 4.00, 1.46), (0.10, 0.10, 2.52), "metal", "dark_gray", package, 0.022)
    add_box(f"{prefix}_功能色标题板", (x, 3.94, 2.45), (1.05, 0.045, 0.34), "matte", accent, package, 0.045)
    add_text(f"{prefix}_{label}文字_自发光", label, (x, 3.905, 2.46), 0.20, "emit", "light_gray", package, 0.012)
    # Hinges, handle, lock and label frame.
    for z in (0.78, 2.07):
        add_cylinder(f"{prefix}_重型合页_{z:.2f}", (x - 0.58, 3.91, z), 0.055, 0.12, "metal", "dark_gray", package, 12, rotation=(math.pi / 2, 0, 0))
    add_box(f"{prefix}_独立拉手", (x + 0.46, 3.89, 1.48), (0.10, 0.07, 0.58), "metal", "light_gray", package, 0.035)
    add_cylinder(f"{prefix}_锁具", (x + 0.45, 3.87, 1.13), 0.065, 0.045, "gloss", "orange", package, 12, rotation=(math.pi / 2, 0, 0))
    add_box(f"{prefix}_下部维修盖", (x, 3.92, 0.55), (0.82, 0.045, 0.38), "metal", "dark_gray", package, 0.045)
    for idx, sx in enumerate((-0.29, -0.10, 0.10, 0.29)):
        add_box(f"{prefix}_底部通风缝_{idx+1:02d}", (x + sx, 3.885, 0.55), (0.08, 0.025, 0.22), "matte", "black", package, 0.008)


def build_medical_cabinet(package):
    x = -3.65
    cabinet_frame("MEDICAL医疗柜", x, package, "red", "MEDICAL", 1)
    # Red is limited to the header and recognizable cross.
    add_box("MEDICAL医疗柜_十字竖", (x, 3.875, 1.79), (0.18, 0.035, 0.62), "matte", "red", package, 0.025)
    add_box("MEDICAL医疗柜_十字横", (x, 3.875, 1.79), (0.56, 0.035, 0.18), "matte", "red", package, 0.025)
    for idx, z in enumerate((2.17, 2.04, 1.91)):
        add_cylinder(f"MEDICAL医疗柜_状态灯_{idx+1:02d}_自发光", (x + 0.47, 3.86, z), 0.032, 0.026, "emit", "cyan" if idx < 2 else "orange", package, 10, rotation=(math.pi / 2, 0, 0))
    add_box("MEDICAL医疗柜_柜顶医疗箱", (x, 4.28, 3.18), (0.92, 0.42, 0.34), "matte", "mid_gray", package, 0.055)
    add_box("MEDICAL医疗柜_柜顶医疗箱红十字_自发光", (x, 4.045, 3.18), (0.34, 0.025, 0.10), "emit", "red", package, 0.018)
    add_box("MEDICAL医疗柜_柜顶医疗箱红十字竖_自发光", (x, 4.045, 3.18), (0.10, 0.025, 0.30), "emit", "red", package, 0.018)


def build_tools_cabinet(package):
    x = -1.85
    cabinet_frame("TOOLS工具柜", x, package, "teal", "TOOLS", 2)
    # Distinct two-zone door and simple wrench-like icon.
    add_box("TOOLS工具柜_门板分区横梁", (x, 3.88, 1.58), (1.05, 0.035, 0.08), "metal", "dark_gray", package, 0.015)
    add_beam("TOOLS工具柜_扳手图标柄_自发光", (x - 0.20, 3.84, 1.10), (x + 0.20, 3.84, 1.88), 0.07, "emit", "teal", package)
    add_cylinder("TOOLS工具柜_扳手图标端_自发光", (x + 0.23, 3.84, 1.94), 0.14, 0.035, "emit", "teal", package, 14, rotation=(math.pi / 2, 0, 0))
    add_box("TOOLS工具柜_侧挂维修盒", (x + 0.94, 4.24, 1.00), (0.48, 0.52, 0.68), "matte", "teal", package, 0.08)
    add_box("TOOLS工具柜_侧挂盒卡扣", (x + 0.94, 3.96, 1.12), (0.22, 0.05, 0.12), "metal", "orange", package, 0.025)


def build_narrow_cabinet(package, index, x, label, accent, style):
    prefix = f"南墙窄柜_{label}"
    cabinet_frame(prefix, x, package, accent, label, index)
    if style == "split":
        for z in (1.08, 1.72):
            add_box(f"{prefix}_门板分区_{z:.2f}", (x, 3.885, z), (1.02, 0.035, 0.07), "metal", "dark_gray", package, 0.015)
        add_box(f"{prefix}_电池状态窗_自发光", (x, 3.85, 1.88), (0.54, 0.025, 0.18), "emit", "cyan", package, 0.025)
    else:
        add_box(f"{prefix}_竖向功能槽", (x - 0.25, 3.88, 1.45), (0.16, 0.035, 1.25), "matte", accent, package, 0.025)
        for idx, z in enumerate((1.05, 1.45, 1.85)):
            add_cylinder(f"{prefix}_状态节点_{idx+1:02d}_自发光", (x + 0.30, 3.85, z), 0.045, 0.03, "emit", "cyan" if idx < 2 else "orange", package, 10, rotation=(math.pi / 2, 0, 0))


def build_low_cabinet(package):
    add_box("主门低柜_加厚工作台面", (5.0, 3.77, 1.30), (6.28, 0.86, 0.16), "metal", "dark_gray", package, 0.055)
    add_box("主门低柜_连续承重底座", (5.0, 4.18, 0.12), (6.18, 0.76, 0.20), "metal", "purple", package, 0.05)
    for index, x in enumerate((2.7, 4.25, 5.75, 7.3)):
        add_box(f"主门低柜_柜门上沿_{index+1:02d}", (x, 3.72, 1.05), (1.22, 0.05, 0.08), "metal", "dark_gray", package, 0.015)
        add_box(f"主门低柜_独立拉手_{index+1:02d}", (x, 3.69, 0.78), (0.48, 0.06, 0.10), "metal", "light_gray", package, 0.025)
        for sx in (-0.52, 0.52):
            add_cylinder(f"主门低柜_合页_{index+1:02d}_{sx:+.2f}", (x + sx, 3.69, 0.53), 0.035, 0.04, "metal", "dark_gray", package, 10, rotation=(math.pi / 2, 0, 0))
    for x in (2.15, 7.85):
        add_box(f"主门低柜_金属包角_{x:.2f}", (x, 3.77, 0.70), (0.14, 0.10, 1.02), "metal", "purple", package, 0.025)
    # Sparse life props: a plant and one repair box only.
    add_cylinder("主门低柜_小植物花盆", (3.0, 3.68, 1.52), 0.18, 0.34, "matte", "rust", package, 16)
    for idx, (dx, dz) in enumerate(((0.0, 0.25), (-0.12, 0.30), (0.12, 0.30))):
        add_s = base.add_sphere(f"主门低柜_植物叶片_{idx+1:02d}", (3.0 + dx, 3.68, 1.62 + dz), 0.16, "matte", "green", package)
        add_s["v008_scope"] = "south_facility_detail"
    add_box("主门低柜_小维修盒", (7.10, 3.69, 1.50), (0.66, 0.42, 0.28), "matte", "teal", package, 0.05)
    add_box("主门低柜_维修盒卡扣", (7.10, 3.44, 1.52), (0.18, 0.05, 0.10), "metal", "orange", package, 0.02)


def build_hologram_platform(package):
    x, y = 5.0, 1.72
    add_cylinder("全息终端平台_深灰主底座", (x, y, 0.22), 1.14, 0.36, "metal", "dark_gray", package, 40, True)
    add_torus("全息终端平台_外圈机械环", (x, y, 0.43), 0.98, 0.12, "metal", "purple", package, 40, 10)
    middle = add_torus("全息终端平台_中层旋转环", (x, y, 0.51), 0.73, 0.08, "metal", "mid_gray", package, 36, 8)
    glow = add_torus("全息终端平台_青蓝数据灯带_自发光", (x, y, 0.58), 0.84, 0.035, "emit", "cyan", package, 40, 8)
    add_cylinder("全息终端平台_内部核心座", (x, y, 0.52), 0.48, 0.28, "gloss", "teal", package, 32)
    add_cylinder("全息终端平台_中央发光核心_自发光", (x, y, 0.69), 0.24, 0.12, "emit", "cyan", package, 28)
    for idx in range(8):
        angle = math.tau * idx / 8
        nx, ny = x + math.cos(angle) * 0.93, y + math.sin(angle) * 0.93
        add_box(f"全息终端平台_分布式节点座_{idx+1:02d}", (nx, ny, 0.52), (0.22, 0.18, 0.16), "metal", "dark_gray", package, 0.035, rotation=(0, 0, angle))
        node = add_box(f"全息终端平台_节点灯_{idx+1:02d}_自发光", (nx, ny, 0.62), (0.12, 0.10, 0.05), "emit", "cyan" if idx % 2 == 0 else "blue", package, 0.018, rotation=(0, 0, angle))
        animate_scale(node, ((1 + idx * 3, 0.75), (61 + idx * 3, 1.08), (121 + idx * 3, 0.82), (181 + idx * 3, 1.02), (241 + idx * 3, 0.75)), "z")
    for idx in range(8):
        angle = math.tau * idx / 8
        add_cylinder(f"全息终端平台_固定螺栓_{idx+1:02d}", (x + math.cos(angle) * 0.72, y + math.sin(angle) * 0.72, 0.64), 0.04, 0.035, "metal", "light_gray", package, 8)
    add_box("全息终端平台_数据接口盒", (x + 0.58, y - 0.52, 0.47), (0.34, 0.26, 0.20), "metal", "dark_gray", package, 0.04, rotation=(0, 0, -0.7))
    add_box("全息终端平台_数据接口灯_自发光", (x + 0.61, y - 0.56, 0.58), (0.15, 0.08, 0.05), "emit", "orange", package, 0.012, rotation=(0, 0, -0.7))
    # Simple floating shield mark, no complex UI text.
    symbol_y = y - 0.04
    shield_points = [
        ((x - 0.34, symbol_y, 1.55), (x, symbol_y, 1.78)),
        ((x, symbol_y, 1.78), (x + 0.34, symbol_y, 1.55)),
        ((x + 0.34, symbol_y, 1.55), (x + 0.24, symbol_y, 1.08)),
        ((x + 0.24, symbol_y, 1.08), (x, symbol_y, 0.90)),
        ((x, symbol_y, 0.90), (x - 0.24, symbol_y, 1.08)),
        ((x - 0.24, symbol_y, 1.08), (x - 0.34, symbol_y, 1.55)),
    ]
    symbol_parts = []
    for idx, (start, end) in enumerate(shield_points):
        symbol_parts.append(add_beam(f"全息终端平台_悬浮盾牌_{idx+1:02d}_自发光", start, end, 0.035, "emit", "cyan", package))
    for obj in symbol_parts:
        base_location = obj.location.copy()
        for frame, offset in ((1, 0.0), (61, 0.08), (121, 0.0), (181, -0.05), (241, 0.0)):
            obj.location = base_location + Vector((0.0, 0.0, offset))
            obj.keyframe_insert("location", frame=frame)
    for obj, speed in ((middle, math.tau), (glow, -math.tau * 0.45)):
        obj.rotation_euler.z = 0
        obj.keyframe_insert("rotation_euler", frame=1)
        obj.rotation_euler.z = speed
        obj.keyframe_insert("rotation_euler", frame=241)
        if obj.animation_data and obj.animation_data.action:
            for curve in obj.animation_data.action.fcurves:
                for point in curve.keyframe_points:
                    point.interpolation = "LINEAR"
                curve.modifiers.new("CYCLES")
    light = add_point_light("全息终端平台_青蓝核心光", (x, y, 1.05), 150, (0.02, 0.70, 1.0), package, 1.2)
    animate_light(light, ((1, 115), (61, 165), (121, 125), (181, 155), (241, 115)))


def build_terminal(package, prefix, loc, label, accent="cyan", wall=True):
    x, y, z = loc
    if wall:
        add_box(f"{prefix}_墙挂支架", (x, y + 0.12, z), (0.56, 0.18, 0.92), "metal", "dark_gray", package, 0.07)
    else:
        add_box(f"{prefix}_金属底座", (x, y, z - 0.38), (0.62, 0.52, 0.16), "metal", "dark_gray", package, 0.05)
        add_box(f"{prefix}_立柱", (x, y, z - 0.12), (0.16, 0.16, 0.52), "metal", "purple", package, 0.035)
    add_box(f"{prefix}_屏幕边框", (x, y - 0.04, z + 0.14), (0.52, 0.16, 0.46), "metal", "purple", package, 0.055)
    screen = add_box(f"{prefix}_屏幕_自发光", (x, y - 0.13, z + 0.15), (0.40, 0.025, 0.32), "emit", accent, package, 0.03)
    add_text(f"{prefix}_{label}文字_自发光", label, (x, y - 0.155, z + 0.15), 0.085, "emit", "light_gray", package, 0.006)
    for idx, dx in enumerate((-0.16, 0.0, 0.16)):
        add_cylinder(f"{prefix}_实体按键_{idx+1:02d}", (x + dx, y - 0.13, z - 0.18), 0.035, 0.025, "gloss", "orange" if idx == 2 else "mid_gray", package, 10, rotation=(math.pi / 2, 0, 0))
    add_box(f"{prefix}_读卡器", (x + 0.22, y - 0.13, z - 0.02), (0.10, 0.035, 0.14), "gloss", "black", package, 0.018)
    add_box(f"{prefix}_后部数据线", (x - 0.24, y + 0.18, z - 0.28), (0.07, 0.08, 0.58), "metal", "black", package, 0.02)
    animate_scale(screen, ((1, 0.94), (71, 1.02), (141, 0.96), (211, 1.01), (241, 0.94)), "z")


def build_wall_pipes(package):
    # Logical route A: upper trunk -> junction box -> door controller.
    add_beam("南墙管线_A_顶部主管", (-4.3, 4.70, 5.18), (14.3, 4.70, 5.18), 0.10, "metal", "dark_gray", package)
    add_box("南墙管线_A_门控接线盒", (9.15, 4.62, 4.62), (0.64, 0.20, 0.52), "metal", "purple", package, 0.07)
    add_beam("南墙管线_A_门控垂直支线", (9.15, 4.66, 5.18), (9.15, 4.66, 2.20), 0.065, "metal", "dark_gray", package)
    add_beam("南墙管线_A_门控终端线", (9.15, 4.66, 2.20), (8.30, 4.66, 2.20), 0.055, "metal", "dark_gray", package)
    # Logical route B: device service box -> floor direction -> hologram interface.
    add_box("南墙管线_B_设备分线盒", (1.15, 4.62, 3.70), (0.58, 0.20, 0.48), "metal", "dark_gray", package, 0.065)
    add_beam("南墙管线_B_全息供能垂直线", (1.15, 4.66, 3.70), (1.15, 4.66, 0.58), 0.07, "metal", "purple", package)
    add_box("南墙管线_B_地面接口保护座", (1.15, 4.40, 0.58), (0.34, 0.46, 0.42), "metal", "dark_gray", package, 0.07)
    for idx, x in enumerate((-3.5, -1.0, 1.5, 4.0, 6.5, 9.0, 11.5, 14.0)):
        add_cylinder(f"南墙管线_主管固定卡扣_{idx+1:02d}", (x, 4.70, 5.18), 0.14, 0.06, "metal", "mid_gray", package, 12, rotation=(math.pi / 2, 0, 0))
    for idx, z in enumerate((1.0, 1.7, 2.4, 3.1, 3.8, 4.5)):
        add_box(f"南墙管线_垂直线固定卡扣_{idx+1:02d}", (9.15, 4.60, z), (0.22, 0.10, 0.08), "metal", "mid_gray", package, 0.018)


def build_upper_railing_details(package):
    # Existing railing geometry remains locked; only visible base shoes and edge lamps are added.
    for idx, x in enumerate((-4.7, -2.7, -0.7, 1.3, 3.3, 5.3, 7.3, 9.3, 11.3, 13.3)):
        add_box(f"南侧栏杆固定底座_{idx+1:02d}", (x, 5.15, 6.14), (0.22, 0.28, 0.10), "metal", "dark_gray", package, 0.025)
        add_cylinder(f"南侧栏杆连接螺丝_{idx+1:02d}", (x, 4.98, 6.18), 0.035, 0.025, "metal", "light_gray", package, 8, rotation=(math.pi / 2, 0, 0))
    for idx, x in enumerate((-3.7, 0.3, 4.3, 8.3, 12.3)):
        add_box(f"二层边缘青蓝灯_{idx+1:02d}_自发光", (x, 4.92, 6.03), (1.35, 0.05, 0.055), "emit", "cyan", package, 0.012)
    add_text("二层栏杆安全编号", "S-02", (13.55, 4.86, 6.72), 0.16, "matte", "yellow", package, 0.010)


def create_detail_camera():
    preview = bpy.data.collections["90_展示环境_灯光相机"]
    source = bpy.data.objects["基地微缩模型_英雄相机"]
    camera = source.copy()
    camera.data = source.data.copy()
    camera.name = "基地微缩模型_南面设施验收相机"
    camera.data.name = camera.name
    preview.objects.link(camera)
    camera.location = (-9.5, -10.5, 10.8)
    target = Vector((5.0, 4.3, 2.45))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 16.8
    return camera


def all_leaf_packages(output):
    return [leaf for category in output.children for leaf in category.children]


def collection_path(collection):
    parents = {}
    for parent in bpy.data.collections:
        for child in parent.children:
            parents[child.name] = parent
    path = [collection.name]
    while path[-1] in parents:
        path.append(parents[path[-1]].name)
    return list(reversed(path))


def write_catalog(output):
    VERIFY_ROOT.mkdir(parents=True, exist_ok=True)
    entries = []
    for package in sorted(all_leaf_packages(output), key=collection_path):
        category = package.get("资产类别", "uncategorized")
        slug = package.get("资产包键", package.name)
        package["资产包"] = True
        package["资产包键"] = slug
        package["资产类别"] = category
        package["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
        package["未来导出目录"] = str((PACKAGE_ROOT / category / slug).relative_to(PROJECT))
        package["组织版本"] = "v008"
        if "当前状态" not in package:
            package["当前状态"] = "已归类_待独立导出"
        export_dir = PROJECT / package["未来导出目录"]
        export_dir.mkdir(parents=True, exist_ok=True)
        objects = sorted(package.objects, key=lambda obj: obj.name)
        entry = {
            "asset_slug": slug,
            "category": category,
            "collection_path": collection_path(package),
            "future_export_directory": package["未来导出目录"],
            "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
            "source_asset_id": "ENV-BASE99-ART-LAYOUT-3D",
            "status": package["当前状态"],
            "object_count": len(objects),
            "mesh_count": sum(obj.type == "MESH" for obj in objects),
            "light_count": sum(obj.type == "LIGHT" for obj in objects),
            "object_names": [obj.name for obj in objects],
        }
        manifest = dict(entry)
        manifest["note"] = "v008独立设施资产包；后续按此Collection独立导出GLB、碰撞与PackedScene。"
        (export_dir / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        entries.append(entry)
    catalog = {
        "schema": "shellstorm2.base_facility.component_catalog.v1",
        "organization_version": "v008",
        "source_asset_id": "ENV-BASE99-ART-LAYOUT-3D",
        "source_blend": str(INPUT_BLEND.relative_to(PROJECT)),
        "organized_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "scope": "south visual-center facility zone only",
        "package_count": len(entries),
        "floor_tile_package_count": sum(e["category"] == "floor" for e in entries),
        "packages": entries,
    }
    CATALOG_JSON.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["基地场景独立资产包树 v008", "源资产ID: ENV-BASE99-ART-LAYOUT-3D", f"独立资产包数量: {len(entries)}", ""]
    for category in output.children:
        lines.append(category.name + "/")
        for package in category.children:
            lines.append(f"  {package.name}/ [{package['资产包键']}] objects={len(package.objects)} -> {package['未来导出目录']}")
        lines.append("")
    TREE_TXT.write_text("\n".join(lines), encoding="utf-8")
    return catalog


def render(camera, path):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        raise RuntimeError(f"必须以v007为输入: {bpy.data.filepath}")
    if OUTPUT_BLEND.exists():
        raise RuntimeError(f"目标文件已存在，禁止覆盖: {OUTPUT_BLEND}")
    setup_helpers()
    root = bpy.data.collections[ROOT_NAME]
    output = bpy.data.collections[OUTPUT_NAME]
    locked_names = (
        "20_统一地面系统_36块独立地砖",
        "12_东墙阁楼主体结构_资产包",
        "13_阁楼下方铁皮封闭体_资产包",
        "14_西北贴墙L型楼梯_资产包",
        "30_阁楼生活设施",
        "50_仓库与辅助设施",
    )
    before_locked, before_hash = locked_signature(locked_names)

    output.name = "02_游戏输出_独立资产包_v008"
    base.OUTPUT = output
    underloft = bpy.data.collections[UNDERLOFT_CATEGORY]
    wall_package = rename_package("41_电视复合背景墙_资产包", "41_南墙工业墙板附着结构_资产包", "south_industrial_wall_details")
    door_package = rename_package("42_工业电视与扫描线_资产包", "42_BASE_CAMP大型卷帘主门_资产包", "base_camp_rollup_main_door")
    low_cabinet = rename_package("43_电视低柜_资产包", "43_主门下方低矮设备柜_资产包", "main_door_low_storage_cabinet")
    sign_package = package_meta(bpy.data.collections["44_BASE_CAMP立体霓虹标识_资产包"], "base_camp_neon_sign")
    medical = package_meta(bpy.data.collections["45_工业储物柜01_资产包"], "medical_cabinet")
    medical.name = "45_MEDICAL医疗柜_资产包"
    tools = package_meta(bpy.data.collections["46_工业储物柜02_资产包"], "tools_cabinet")
    tools.name = "46_TOOLS工具柜_资产包"
    battery = package_meta(bpy.data.collections["47_工业储物柜03_资产包"], "narrow_battery_cabinet")
    battery.name = "47_窄型电池柜_资产包"
    emergency = package_meta(bpy.data.collections["48_工业储物柜04_资产包"], "narrow_emergency_cabinet")
    emergency.name = "48_窄型应急柜_资产包"
    holo = add_package(underloft, "51_圆形全息设备平台_资产包", "hologram_terminal_platform")
    terminal_access = add_package(underloft, "52_ACCESS门禁终端_资产包", "access_terminal")
    terminal_status = add_package(underloft, "53_BASE_STATUS状态终端_资产包", "base_status_terminal")
    terminal_storage = add_package(underloft, "54_STORAGE储物终端_资产包", "storage_terminal")
    pipes = add_package(underloft, "55_南墙工业管线系统_资产包", "south_wall_pipeline_system")
    railing_detail = add_package(underloft, "56_二层栏杆附着细节_资产包", "south_upper_railing_details")

    delete_old_door_misread()
    relabel_existing_objects()
    build_south_wall_details(wall_package)
    build_rollup_door(door_package)
    build_sign_details(sign_package)
    build_low_cabinet(low_cabinet)
    build_medical_cabinet(medical)
    build_tools_cabinet(tools)
    build_narrow_cabinet(battery, 3, 11.85, "BATTERY", "teal", "split")
    build_narrow_cabinet(emergency, 4, 13.65, "EMERGENCY", "orange", "nodes")
    build_hologram_platform(holo)
    build_terminal(terminal_access, "ACCESS门禁终端", (1.35, 4.28, 2.10), "ACCESS", "cyan", True)
    build_terminal(terminal_status, "BASE_STATUS状态终端", (8.38, 3.58, 1.72), "BASE STATUS", "cyan", False)
    build_terminal(terminal_storage, "STORAGE储物终端", (-0.62, 4.25, 1.82), "STORAGE", "teal", True)
    build_wall_pipes(pipes)
    build_upper_railing_details(railing_detail)

    bpy.context.view_layer.update()
    after_locked, after_hash = locked_signature(locked_names)
    if before_locked != after_locked or before_hash != after_hash:
        changed = sorted(name for name, value in before_locked.items() if after_locked.get(name) != value)
        raise RuntimeError(f"锁定范围发生修改: {changed[:20]}")

    root["version"] = "v008"
    root["v008_scope"] = "south visual-center facilities only"
    root["v008_reference_priority"] = "user reference image is visual truth"
    root["v008_locked"] = "floor, wall base, mezzanine dimensions, railing positions, stair, non-scope facilities"
    root["v008_asset_id"] = "ENV-BASE99-ART-LAYOUT-3D"
    output["资产组织版本"] = "v008"
    output["本批次制作范围"] = "BASE CAMP主门、标牌、低柜、MEDICAL、TOOLS、窄柜、全息平台、终端、管线、灯光与栏杆附着细节"
    output["禁止改动范围"] = "地板、墙体基础规格、二层平台规格、栏杆位置、楼梯、文档外设施"

    detail_camera = create_detail_camera()
    catalog = write_catalog(output)
    if catalog["package_count"] != 82 or catalog["floor_tile_package_count"] != 36:
        raise RuntimeError(f"资产包数量异常: {catalog['package_count']}, floor={catalog['floor_tile_package_count']}")

    VERIFY_ROOT.mkdir(parents=True, exist_ok=True)
    base.SOURCE.hide_viewport = True
    base.SOURCE.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
    render(bpy.data.objects["基地微缩模型_英雄相机"], HERO_RENDER)
    render(bpy.data.objects["基地微缩模型_顶视相机"], TOP_RENDER)
    render(detail_camera, DETAIL_RENDER)
    bpy.context.scene.camera = bpy.data.objects["基地微缩模型_英雄相机"]
    bpy.context.scene.render.filepath = str(HERO_RENDER)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
    print("BASE_FACILITY_V008_BUILD_COMPLETE")
    print(f"blend={OUTPUT_BLEND}")
    print(f"packages={catalog['package_count']} floor_tiles={catalog['floor_tile_package_count']}")
    print(f"locked_signature={after_hash} match={before_hash == after_hash}")
    print(f"objects={len(bpy.data.objects)} meshes={sum(o.type == 'MESH' for o in bpy.data.objects)} materials={len(bpy.data.materials)}")


if __name__ == "__main__":
    main()
