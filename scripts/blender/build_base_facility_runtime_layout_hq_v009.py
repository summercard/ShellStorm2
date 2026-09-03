#!/usr/bin/env python3
"""Build Base 99 HQ v009: east facility-zone high-fidelity detailing only.

The v008 wall, floor, mezzanine, railing, architecture and non-scope facility
geometry stay locked. This pass corrects the east wall personnel-door reading,
rebuilds the reference east facilities, and preserves one Collection/directory
per independently managed facility.
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
INPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v008.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v009.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v009"
VERIFY_ROOT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v009"
HERO_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v009.png"
TOP_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v009_top.png"
DETAIL_RENDER = VERIFY_ROOT / "base_facility_runtime_layout_hq_v009_east_facilities.png"
CATALOG_JSON = VERIFY_ROOT / "base_facility_component_catalog_v009.json"
TREE_TXT = VERIFY_ROOT / "base_facility_component_tree_v009.txt"
LOCK_REPORT = VERIFY_ROOT / "base_facility_locked_scope_v008_v009.json"

V008_SCRIPT = PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v008.py"
spec = importlib.util.spec_from_file_location("base_facility_hq_v008_helpers", V008_SCRIPT)
v008 = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(v008)
base = v008.base

ROOT_NAME = "基地99层高品质微缩模型_中文资产管理"
INPUT_OUTPUT_NAME = "02_游戏输出_独立资产包_v008"
OUTPUT_NAME = "02_游戏输出_独立资产包_v009"
EAST_CATEGORY_NAME = "70_东面设施区域"
TARGET_OLD_SLUGS = {
    "supply_vending_station",
    "east_power_box",
    "sorting_bin_group",
    "maintenance_workstation",
}


def setup_helpers():
    v008.OUTPUT_NAME = INPUT_OUTPUT_NAME
    v008.setup_helpers()


def ensure_child(parent, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def move_collection(collection, new_parent):
    for parent in bpy.data.collections:
        if collection.name in parent.children:
            parent.children.unlink(collection)
    if collection.name not in new_parent.children:
        new_parent.children.link(collection)


def package_meta(collection, slug, category="east_facilities"):
    collection["资产包"] = True
    collection["资产包键"] = slug
    collection["资产类别"] = category
    collection["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
    collection["未来导出目录"] = str((PACKAGE_ROOT / category / slug).relative_to(PROJECT))
    collection["组织版本"] = "v009"
    collection["当前状态"] = "已深化归类_待独立导出"
    collection["本批次范围"] = "参考图东面设施区域"
    return collection


def add_package(parent, name, slug):
    return package_meta(ensure_child(parent, name), slug)


def clear_package_objects(package):
    names = [obj.name for obj in package.objects]
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)
        src = bpy.data.objects.get(name + "__源")
        if src:
            bpy.data.objects.remove(src, do_unlink=True)


def add_box(name, loc, size, role, color, target, bevel=0.035, obstacle=False, rotation=(0, 0, 0)):
    obj = base.add_box(name, loc, size, role, color, bevel, target, obstacle, rotation)
    obj["v009_scope"] = "east_facility_detail"
    return obj


def add_cylinder(name, loc, radius, depth, role, color, target, vertices=16, obstacle=False, rotation=(0, 0, 0)):
    obj = base.add_cylinder(name, loc, radius, depth, role, color, vertices, target, obstacle, rotation)
    obj["v009_scope"] = "east_facility_detail"
    return obj


def add_sphere(name, loc, radius, role, color, target):
    obj = base.add_sphere(name, loc, radius, role, color, target)
    obj["v009_scope"] = "east_facility_detail"
    return obj


def add_beam(name, start, end, thickness, role, color, target):
    obj = base.add_beam(name, start, end, thickness, role, color, target)
    obj["v009_scope"] = "east_facility_detail"
    return obj


def add_text_east(name, body, loc, size, role, color, target, extrude=0.02, align="CENTER"):
    bpy.ops.object.select_all(action="DESELECT")
    # East-wall labels face the room (-X).  Using +PI/2 here exposes the
    # back face to the locked inspection camera and mirrors every label.
    obj = base.add_text(name, body, loc, size, role, color, extrude, align, (math.pi / 2, 0, -math.pi / 2), target)
    obj["v009_scope"] = "east_facility_detail"
    return obj


def add_text_south(name, body, loc, size, role, color, target, extrude=0.02, align="CENTER"):
    bpy.ops.object.select_all(action="DESELECT")
    obj = base.add_text(name, body, loc, size, role, color, extrude, align, (math.pi / 2, 0, 0), target)
    obj["v009_scope"] = "east_facility_detail"
    return obj


def add_torus(name, loc, major_radius, minor_radius, role, color, target, major_segments=32, minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(
        align="WORLD", major_segments=major_segments, minor_segments=minor_segments,
        location=loc, major_radius=major_radius, minor_radius=minor_radius,
    )
    src = bpy.context.object
    base.link_only(src, base.SOURCE)
    src.name = name + "__源"
    base.assign_material(src, role, base.COLORS[color])
    obj = base.publish(src, target, name)
    obj["v009_scope"] = "east_facility_detail"
    return obj


def add_point_light(name, loc, energy, color, target, radius=0.8):
    data = bpy.data.lights.new(name, "POINT")
    data.energy = energy
    data.color = color
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data)
    target.objects.link(obj)
    obj.location = loc
    obj["v009_scope"] = "east_facility_detail"
    return obj


def pulse_scale(obj, phase=0, low=0.90, high=1.05):
    original = obj.scale.copy()
    for frame, factor in ((1 + phase, low), (61 + phase, high), (121 + phase, 0.96), (181 + phase, 1.02), (241 + phase, low)):
        obj.scale = (original.x, original.y, original.z * factor)
        obj.keyframe_insert("scale", frame=frame)
    if obj.animation_data and obj.animation_data.action:
        for curve in obj.animation_data.action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = "BEZIER"
            curve.modifiers.new("CYCLES")


def pulse_light(light, phase=0, low=12, high=80):
    for frame, energy in ((1 + phase, low), (61 + phase, high), (121 + phase, low * 1.3), (181 + phase, high * 0.75), (241 + phase, low)):
        light.data.energy = energy
        light.data.keyframe_insert("energy", frame=frame)
    if light.data.animation_data and light.data.animation_data.action:
        for curve in light.data.animation_data.action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = "BEZIER"
            curve.modifiers.new("CYCLES")


def build_personnel_door(package):
    # Existing wall module opening marker is 2.2 x 2.5 m at x=15, y=-2.5.
    x, y = 14.22, -2.50
    add_box("东墙人员门_厚重外门框", (14.38, y, 1.32), (0.46, 2.42, 2.64), "metal", "dark_gray", package, 0.11)
    add_box("东墙人员门_内嵌主门板", (14.08, y, 1.28), (0.24, 2.08, 2.42), "matte", "mid_gray", package, 0.09)
    add_box("东墙人员门_二级装甲板", (13.91, y, 1.43), (0.10, 1.62, 1.78), "metal", "dark_gray", package, 0.08)
    for offset, width in ((-0.62, 0.46), (0.0, 0.76), (0.62, 0.46)):
        add_box(f"东墙人员门_装甲分区_{offset:+.2f}", (13.84, y + offset, 1.43), (0.055, width, 1.34), "matte", "purple", package, 0.05)
    for z in (0.52, 1.28, 2.04):
        add_box(f"东墙人员门_横向拼接缝_{z:.2f}", (13.825, y, z), (0.035, 1.70, 0.055), "metal", "black", package, 0.01)
    for side in (-1, 1):
        add_box(f"东墙人员门_门框侧柱_{side:+d}", (14.05, y + side * 1.09, 1.32), (0.34, 0.22, 2.64), "metal", "purple", package, 0.055)
        for z in (0.28, 0.86, 1.44, 2.02, 2.42):
            add_cylinder(f"东墙人员门_门框固定螺丝_{side:+d}_{z:.2f}", (13.82, y + side * 1.09, z), 0.035, 0.035, "metal", "light_gray", package, 10, rotation=(0, math.pi / 2, 0))
    add_box("东墙人员门_顶部横梁", (14.03, y, 2.58), (0.36, 2.42, 0.22), "metal", "dark_gray", package, 0.05)
    add_box("东墙人员门_底部金属门槛", (13.94, y, 0.10), (0.32, 2.18, 0.20), "metal", "light_gray", package, 0.035)
    add_box("东墙人员门_机械锁定横杆", (13.73, y + 0.16, 1.36), (0.18, 1.14, 0.16), "metal", "dark_gray", package, 0.035)
    add_cylinder("东墙人员门_机械开门手轮", (13.61, y - 0.48, 1.30), 0.22, 0.10, "metal", "light_gray", package, 20, rotation=(0, math.pi / 2, 0))
    add_cylinder("东墙人员门_手轮内轴", (13.54, y - 0.48, 1.30), 0.08, 0.14, "gloss", "orange", package, 16, rotation=(0, math.pi / 2, 0))
    add_box("东墙人员门_门侧控制面板", (13.86, y + 1.38, 1.48), (0.24, 0.54, 1.08), "metal", "dark_gray", package, 0.07)
    screen = add_box("东墙人员门_门禁屏幕_自发光", (13.70, y + 1.38, 1.72), (0.035, 0.38, 0.30), "emit", "cyan", package, 0.025)
    add_box("东墙人员门_读卡器", (13.68, y + 1.38, 1.38), (0.04, 0.34, 0.20), "gloss", "black", package, 0.025)
    for row in range(3):
        for col in range(3):
            add_cylinder(f"东墙人员门_数字键_{row+1}_{col+1}", (13.64, y + 1.23 + col * 0.14, 1.12 - row * 0.14), 0.028, 0.025, "gloss", "mid_gray", package, 8, rotation=(0, math.pi / 2, 0))
    add_cylinder("东墙人员门_紧急开门按钮", (13.61, y + 1.38, 0.58), 0.11, 0.08, "gloss", "orange", package, 16, rotation=(0, math.pi / 2, 0))
    top_light = add_box("东墙人员门_顶部状态灯_自发光", (13.78, y, 2.76), (0.08, 0.68, 0.14), "emit", "cyan", package, 0.025)
    add_box("东墙人员门_橙色待机灯_自发光", (13.76, y + 1.38, 2.10), (0.05, 0.18, 0.15), "emit", "orange", package, 0.025)
    add_text_east("东墙人员门_ACCESS文字_自发光", "ACCESS", (13.70, y + 1.38, 1.74), 0.085, "emit", "light_gray", package, 0.006)
    add_text_east("东墙人员门_EXIT标牌_自发光", "EXIT", (13.73, y, 2.95), 0.18, "emit", "cyan", package, 0.009)
    add_text_east("东墙人员门_安全标签", "AUTHORIZED", (13.72, y + 0.30, 0.32), 0.09, "matte", "yellow", package, 0.006)
    pulse_scale(screen, 12, 0.95, 1.03)
    pulse_scale(top_light, 0, 0.88, 1.07)
    light = add_point_light("东墙人员门_状态照明", (13.2, y, 2.7), 55, (0.02, 0.55, 1.0), package, 0.7)
    pulse_light(light, 0, 18, 65)


def build_supply_machine(package):
    # Adjacent to, but outside, the locked door opening and facing the room (-X).
    x, y = 13.52, 1.55
    add_box("SUPPLY24H_主体外壳", (x, y, 1.78), (1.82, 2.18, 3.56), "matte", "purple", package, 0.16, True)
    add_box("SUPPLY24H_加厚顶部模块", (x - 0.02, y, 3.48), (1.94, 2.28, 0.34), "metal", "dark_gray", package, 0.10)
    add_box("SUPPLY24H_前面板凹槽", (12.55, y, 2.10), (0.14, 1.82, 2.22), "metal", "dark_gray", package, 0.06)
    add_box("SUPPLY24H_大型屏幕外框", (12.43, y + 0.18, 2.40), (0.12, 1.34, 1.42), "metal", "purple", package, 0.08)
    screen = add_box("SUPPLY24H_青绿显示屏_自发光", (12.35, y + 0.18, 2.40), (0.035, 1.16, 1.22), "emit", "teal", package, 0.045)
    # Simple friendly mascot face.
    add_box("SUPPLY24H_吉祥物脸框_自发光", (12.31, y + 0.18, 2.42), (0.018, 0.58, 0.48), "emit", "cyan", package, 0.10)
    for dy in (-0.16, 0.16):
        add_cylinder(f"SUPPLY24H_吉祥物眼睛_{dy:+.2f}_自发光", (12.28, y + 0.18 + dy, 2.49), 0.055, 0.02, "emit", "light_gray", package, 12, rotation=(0, math.pi / 2, 0))
    add_box("SUPPLY24H_吉祥物嘴_自发光", (12.27, y + 0.18, 2.30), (0.015, 0.25, 0.035), "emit", "light_gray", package, 0.01)
    add_text_east("SUPPLY24H_顶部标识_自发光", "SUPPLY 24H", (12.31, y, 3.49), 0.20, "emit", "light_gray", package, 0.010)
    # Product window with readable bottles, cans, food, battery and med boxes.
    add_box("SUPPLY24H_产品展示窗框", (12.40, y - 0.62, 1.37), (0.13, 0.62, 1.34), "metal", "dark_gray", package, 0.06)
    add_box("SUPPLY24H_产品展示玻璃", (12.32, y - 0.62, 1.37), (0.025, 0.50, 1.18), "gloss", "blue", package, 0.025)
    for idx, z in enumerate((1.00, 1.36, 1.72)):
        add_box(f"SUPPLY24H_商品层板_{idx+1:02d}", (12.25, y - 0.62, z), (0.10, 0.48, 0.045), "metal", "light_gray", package, 0.01)
    products = [
        ("水瓶", y - 0.78, 1.18, "cyan", "bottle"),
        ("能量罐", y - 0.50, 1.18, "orange", "can"),
        ("压缩食品", y - 0.76, 1.53, "yellow", "box"),
        ("电池盒", y - 0.50, 1.53, "teal", "box"),
        ("医疗包", y - 0.64, 1.87, "red", "box"),
    ]
    for name, py, pz, color, kind in products:
        if kind == "bottle":
            add_cylinder(f"SUPPLY24H_商品_{name}_瓶身", (12.20, py, pz), 0.075, 0.24, "gloss", color, package, 12)
            add_cylinder(f"SUPPLY24H_商品_{name}_瓶盖", (12.20, py, pz + 0.15), 0.045, 0.06, "metal", "light_gray", package, 10)
        elif kind == "can":
            add_cylinder(f"SUPPLY24H_商品_{name}", (12.20, py, pz), 0.08, 0.23, "gloss", color, package, 14)
        else:
            add_box(f"SUPPLY24H_商品_{name}", (12.20, py, pz), (0.12, 0.20, 0.20), "matte", color, package, 0.025)
    add_box("SUPPLY24H_操作模块", (12.38, y + 0.74, 1.55), (0.20, 0.46, 1.18), "metal", "dark_gray", package, 0.07)
    add_box("SUPPLY24H_身份识别屏_自发光", (12.24, y + 0.74, 1.86), (0.035, 0.30, 0.24), "emit", "cyan", package, 0.025)
    for row in range(4):
        for col in range(3):
            add_cylinder(f"SUPPLY24H_数字键_{row+1}_{col+1}", (12.22, y + 0.62 + col * 0.12, 1.56 - row * 0.12), 0.025, 0.025, "gloss", "mid_gray", package, 8, rotation=(0, math.pi / 2, 0))
    add_box("SUPPLY24H_出货口边框", (12.40, y + 0.12, 0.55), (0.16, 1.18, 0.42), "metal", "dark_gray", package, 0.07)
    add_box("SUPPLY24H_出货挡板", (12.29, y + 0.12, 0.55), (0.04, 0.98, 0.26), "gloss", "black", package, 0.04)
    add_box("SUPPLY24H_侧面维护面板", (13.55, y - 1.12, 1.65), (1.10, 0.08, 1.26), "metal", "mid_gray", package, 0.06)
    for z in (1.25, 1.48, 1.71, 1.94):
        add_box(f"SUPPLY24H_侧面散热口_{z:.2f}", (13.55, y - 1.17, z), (0.72, 0.035, 0.08), "metal", "black", package, 0.01)
    add_box("SUPPLY24H_底部设备座", (13.52, y, 0.14), (1.94, 2.30, 0.28), "metal", "dark_gray", package, 0.08)
    for py in (y - 0.88, y + 0.88):
        for z in (0.34, 3.22):
            add_cylinder(f"SUPPLY24H_固定螺丝_{py:.2f}_{z:.2f}", (12.49, py, z), 0.035, 0.035, "metal", "light_gray", package, 10, rotation=(0, math.pi / 2, 0))
    status = add_box("SUPPLY24H_状态灯_自发光", (12.22, y + 0.77, 2.18), (0.04, 0.20, 0.08), "emit", "orange", package, 0.018)
    add_box("SUPPLY24H_后部电源接口", (14.50, y - 0.72, 0.72), (0.20, 0.32, 0.36), "metal", "dark_gray", package, 0.045)
    add_beam("SUPPLY24H_后部电源线", (14.50, y - 0.72, 0.75), (14.50, y - 0.72, 4.72), 0.055, "metal", "black", package)
    pulse_scale(screen, 18, 0.96, 1.025)
    pulse_scale(status, 42, 0.80, 1.10)


def build_power_cabinet(package):
    x, y = 14.15, -5.55
    add_box("东墙POWER配电柜_主箱体", (x, y, 2.35), (0.34, 1.55, 2.15), "metal", "dark_gray", package, 0.08)
    add_box("东墙POWER配电柜_厚重柜门", (13.91, y, 2.35), (0.18, 1.36, 1.96), "matte", "black", package, 0.075)
    for side in (-1, 1):
        add_box(f"东墙POWER配电柜_柜门边框_{side:+d}", (13.78, y + side * 0.65, 2.35), (0.08, 0.10, 1.98), "metal", "purple", package, 0.02)
    for z in (1.56, 3.14):
        add_cylinder(f"东墙POWER配电柜_重型铰链_{z:.2f}", (13.75, y - 0.58, z), 0.055, 0.14, "metal", "light_gray", package, 12, rotation=(0, math.pi / 2, 0))
    add_box("东墙POWER配电柜_机械拉手", (13.69, y + 0.48, 2.20), (0.08, 0.12, 0.68), "metal", "light_gray", package, 0.03)
    add_cylinder("东墙POWER配电柜_机械锁", (13.65, y + 0.47, 2.68), 0.07, 0.05, "gloss", "orange", package, 12, rotation=(0, math.pi / 2, 0))
    add_text_east("东墙POWER配电柜_POWER文字_自发光", "POWER", (13.64, y, 2.86), 0.23, "emit", "red", package, 0.010)
    # Stylized lightning symbol.
    add_beam("东墙POWER配电柜_闪电上段_自发光", (13.60, y - 0.18, 2.58), (13.60, y + 0.08, 2.18), 0.055, "emit", "orange", package)
    add_beam("东墙POWER配电柜_闪电下段_自发光", (13.60, y + 0.08, 2.18), (13.60, y - 0.12, 1.70), 0.055, "emit", "orange", package)
    for idx, py in enumerate((y - 0.30, y, y + 0.30)):
        lamp = add_cylinder(f"东墙POWER配电柜_状态灯_{idx+1:02d}_自发光", (13.62, py, 1.45), 0.045, 0.035, "emit", "cyan" if idx < 2 else "orange", package, 10, rotation=(0, math.pi / 2, 0))
        pulse_scale(lamp, idx * 18, 0.82, 1.08)
    add_box("东墙POWER配电柜_顶部进线接口", (14.18, y, 3.56), (0.36, 0.48, 0.28), "metal", "purple", package, 0.05)
    add_box("东墙POWER配电柜_底部出线接口", (14.18, y, 1.14), (0.34, 0.44, 0.26), "metal", "purple", package, 0.05)
    for idx, z in enumerate((1.75, 2.05, 2.35, 2.65)):
        add_box(f"东墙POWER配电柜_侧面散热结构_{idx+1:02d}", (14.36, y + 0.66, z), (0.08, 0.22, 0.09), "metal", "black", package, 0.015)
    for py in (y - 0.58, y + 0.58):
        for z in (1.48, 3.22):
            add_cylinder(f"东墙POWER配电柜_固定螺丝_{py:.2f}_{z:.2f}", (13.62, py, z), 0.032, 0.03, "metal", "light_gray", package, 8, rotation=(0, math.pi / 2, 0))
    add_text_east("东墙POWER配电柜_检修标签", "HIGH VOLTAGE", (13.62, y, 1.20), 0.10, "matte", "yellow", package, 0.006)


def build_east_pipeline(package):
    x = 14.48
    # Three upper trunks retain a clean horizontal rhythm.
    for idx, (z, thickness) in enumerate(((7.05, 0.16), (6.65, 0.12), (6.28, 0.085))):
        add_beam(f"东墙管线_顶部主干_{idx+1:02d}", (x, -13.8, z), (x, 3.8, z), thickness, "metal", "dark_gray" if idx < 2 else "purple", package)
        for py in (-12.5, -9.5, -6.5, -3.5, -0.5, 2.5):
            add_box(f"东墙管线_主干固定管卡_{idx+1:02d}_{py:.1f}", (14.35, py, z), (0.24, 0.22, thickness + 0.10), "metal", "mid_gray", package, 0.025)
    # Junctions and logical branches: door, SUPPLY, POWER, workbench.
    junctions = ((-11.8, 6.65, "WORK"), (-5.55, 6.65, "POWER"), (-2.5, 6.65, "ACCESS"), (1.55, 6.65, "SUPPLY"))
    for py, z, label in junctions:
        add_box(f"东墙管线_{label}_接线盒", (14.25, py, z), (0.42, 0.74, 0.54), "metal", "purple", package, 0.065)
        add_text_east(f"东墙管线_{label}_接线盒标签_自发光", label, (13.99, py, z), 0.09, "emit", "cyan" if label != "POWER" else "orange", package, 0.006)
    branches = ((-11.8, 1.85, "WORK"), (-5.55, 3.58, "POWER"), (-2.5, 2.88, "ACCESS"), (1.55, 4.72, "SUPPLY"))
    for py, low_z, label in branches:
        add_beam(f"东墙管线_{label}_垂直支线", (14.36, py, 6.42), (14.36, py, low_z), 0.08, "metal", "dark_gray", package)
        for z in [low_z + (6.42 - low_z) * t for t in (0.22, 0.48, 0.74)]:
            add_box(f"东墙管线_{label}_支线固定座_{z:.2f}", (14.24, py, z), (0.24, 0.22, 0.10), "metal", "mid_gray", package, 0.02)
        add_cylinder(f"东墙管线_{label}_设备接口", (14.20, py, low_z), 0.13, 0.16, "metal", "light_gray", package, 16, rotation=(0, math.pi / 2, 0))
    # Rounded-looking elbows/T joints at branch tops.
    for py, _, label in branches:
        add_sphere(f"东墙管线_{label}_圆弧弯头", (14.36, py, 6.42), 0.13, "metal", "dark_gray", package)
        add_cylinder(f"东墙管线_{label}_T型接头", (14.36, py, 6.65), 0.15, 0.26, "metal", "purple", package, 16, rotation=(0, math.pi / 2, 0))


def build_bin(package, label, center_y, accent):
    x = 10.80
    add_box(f"分类垃圾设施_{label}_主体", (x, center_y, 0.70), (1.05, 1.05, 1.30), "matte", "dark_gray", package, 0.10, True)
    add_box(f"分类垃圾设施_{label}_顶部盖板", (x, center_y, 1.34), (1.10, 1.10, 0.16), "metal", "mid_gray", package, 0.06)
    add_box(f"分类垃圾设施_{label}_投入口", (10.22, center_y, 1.15), (0.10, 0.62, 0.24), "gloss", "black", package, 0.04)
    add_box(f"分类垃圾设施_{label}_功能面板", (10.18, center_y, 0.77), (0.10, 0.74, 0.58), "matte", accent, package, 0.04)
    add_text_east(f"分类垃圾设施_{label}_文字_自发光", label, (10.11, center_y, 0.91), 0.13, "emit", "light_gray", package, 0.007)
    add_box(f"分类垃圾设施_{label}_门缝", (10.10, center_y, 0.52), (0.025, 0.70, 0.035), "metal", "black", package, 0.005)
    add_box(f"分类垃圾设施_{label}_拉手", (10.07, center_y + 0.25, 0.48), (0.035, 0.22, 0.08), "metal", "light_gray", package, 0.015)
    add_box(f"分类垃圾设施_{label}_底座", (x, center_y, 0.08), (1.02, 1.02, 0.16), "metal", "black", package, 0.04)
    for py in (center_y - 0.34, center_y + 0.34):
        add_cylinder(f"分类垃圾设施_{label}_脚轮_{py:.2f}", (10.55, py, 0.09), 0.07, 0.10, "metal", "black", package, 12, rotation=(0, math.pi / 2, 0))
    add_box(f"分类垃圾设施_{label}_识别灯_自发光", (10.16, center_y, 1.42), (0.05, 0.30, 0.08), "emit", accent if label != "WASTE" else "cyan", package, 0.018)
    if label == "FLAMMABLE":
        add_text_east("分类垃圾设施_FLAMMABLE_火焰警告_自发光", "!", (10.10, center_y, 0.62), 0.24, "emit", "orange", package, 0.008)
    elif label == "RECYCLE":
        add_text_east("分类垃圾设施_RECYCLE_回收标志_自发光", "R", (10.10, center_y, 0.62), 0.22, "emit", "green", package, 0.008)


def build_maintenance(package):
    # Existing footprint and orientation are preserved at the south/east-visible edge.
    x, y = 6.20, -13.25
    add_box("东面维修工作台_主柜体", (x, y, 0.92), (4.70, 1.15, 1.50), "matte", "dark_gray", package, 0.10, True)
    add_box("东面维修工作台_耐磨钢台面", (x, -12.62, 1.72), (5.00, 1.42, 0.18), "metal", "mid_gray", package, 0.06)
    # Drawers, doors and handles face north (+Y).
    for idx, px in enumerate((4.25, 5.25, 6.25, 7.25, 8.15)):
        add_box(f"东面维修工作台_抽屉_{idx+1:02d}", (px, -12.61, 1.18), (0.82, 0.08, 0.42), "matte", "purple" if idx % 2 else "mid_gray", package, 0.035)
        add_box(f"东面维修工作台_抽屉拉手_{idx+1:02d}", (px, -12.54, 1.25), (0.36, 0.06, 0.08), "metal", "light_gray", package, 0.02)
    for idx, px in enumerate((4.65, 6.20, 7.75)):
        add_box(f"东面维修工作台_下柜门_{idx+1:02d}", (px, -12.60, 0.62), (1.28, 0.08, 0.58), "matte", "dark_gray", package, 0.035)
        add_box(f"东面维修工作台_柜门拉手_{idx+1:02d}", (px + 0.42, -12.53, 0.72), (0.08, 0.06, 0.28), "metal", "light_gray", package, 0.02)
    for px in (3.85, 8.55):
        add_box(f"东面维修工作台_承重侧腿_{px:.2f}", (px, -13.25, 0.80), (0.24, 1.12, 1.42), "metal", "purple", package, 0.045)
    add_box("东面维修工作台_工具挂板", (x, -14.40, 3.05), (5.00, 0.14, 2.10), "metal", "dark_gray", package, 0.07)
    for row in range(5):
        for col in range(12):
            add_cylinder(f"东面维修工作台_挂板孔_{row+1:02d}_{col+1:02d}", (3.95 + col * 0.41, -14.30, 2.30 + row * 0.36), 0.020, 0.025, "metal", "light_gray", package, 8, rotation=(math.pi / 2, 0, 0))
    # Real simplified 3D tools.
    for idx, px in enumerate((4.20, 4.70, 5.20, 5.70)):
        add_beam(f"东面维修工作台_立体扳手_{idx+1:02d}_柄", (px, -14.24, 2.48), (px + 0.10, -14.24, 3.12), 0.055, "metal", "light_gray", package)
        add_cylinder(f"东面维修工作台_立体扳手_{idx+1:02d}_头", (px + 0.11, -14.24, 3.17), 0.10, 0.05, "metal", "light_gray", package, 12, rotation=(math.pi / 2, 0, 0))
    for idx, px in enumerate((6.25, 6.65, 7.05, 7.45)):
        add_beam(f"东面维修工作台_螺丝刀_{idx+1:02d}_杆", (px, -14.24, 2.42), (px, -14.24, 2.98), 0.035, "metal", "light_gray", package)
        add_cylinder(f"东面维修工作台_螺丝刀_{idx+1:02d}_柄", (px, -14.24, 3.08), 0.065, 0.22, "gloss", "orange" if idx % 2 else "teal", package, 12)
    add_beam("东面维修工作台_锤子_柄", (8.00, -14.24, 2.42), (8.00, -14.24, 3.06), 0.055, "matte", "rust", package)
    add_box("东面维修工作台_锤子_头", (8.00, -14.24, 3.12), (0.38, 0.12, 0.15), "metal", "light_gray", package, 0.035)
    for idx, px in enumerate((4.5, 5.0)):
        add_beam(f"东面维修工作台_钳子_{idx+1:02d}_左柄", (px - 0.07, -14.22, 3.46), (px, -14.22, 3.10), 0.035, "gloss", "teal", package)
        add_beam(f"东面维修工作台_钳子_{idx+1:02d}_右柄", (px + 0.07, -14.22, 3.46), (px, -14.22, 3.10), 0.035, "gloss", "teal", package)
    add_box("东面维修工作台_六角工具组", (5.90, -14.21, 3.54), (0.66, 0.08, 0.34), "metal", "mid_gray", package, 0.04)
    add_cylinder("东面维修工作台_卷尺", (6.72, -14.21, 3.52), 0.18, 0.08, "gloss", "yellow", package, 16, rotation=(math.pi / 2, 0, 0))
    add_box("东面维修工作台_小型电钻机身", (7.55, -14.18, 3.52), (0.52, 0.16, 0.28), "matte", "teal", package, 0.06)
    add_box("东面维修工作台_小型电钻握把", (7.45, -14.18, 3.28), (0.18, 0.14, 0.38), "matte", "dark_gray", package, 0.04)
    add_box("东面维修工作台_套筒工具盒", (8.15, -14.18, 3.52), (0.56, 0.16, 0.34), "matte", "purple", package, 0.05)
    add_box("东面维修工作台_顶部照明灯_自发光", (x, -14.18, 4.26), (3.40, 0.10, 0.10), "emit", "cyan", package, 0.02)
    add_box("东面维修工作台_电源插座", (3.95, -14.20, 1.92), (0.50, 0.10, 0.30), "metal", "dark_gray", package, 0.04)
    monitor = add_box("东面维修工作台_小显示器_自发光", (7.75, -12.36, 2.10), (0.58, 0.12, 0.44), "emit", "cyan", package, 0.05, rotation=(0.12, 0, 0))
    add_box("东面维修工作台_平板电脑", (6.65, -12.33, 1.88), (0.62, 0.36, 0.08), "gloss", "blue", package, 0.04, rotation=(0, 0, -0.10))
    add_box("东面维修工作台_工具盒", (4.50, -12.32, 1.98), (0.78, 0.44, 0.36), "matte", "teal", package, 0.05)
    add_box("东面维修工作台_螺丝盒", (5.35, -12.30, 1.90), (0.48, 0.38, 0.20), "matte", "orange", package, 0.04)
    add_cylinder("东面维修工作台_水杯", (8.20, -12.28, 1.94), 0.11, 0.30, "matte", "light_gray", package, 16)
    pulse_scale(monitor, 28, 0.96, 1.025)


def build_low_storage(package):
    # Low profile at the right/lower edge, outside the central lane.
    x, y = 10.85, -14.10
    add_box("东面低矮储物区_主柜体", (x, y, 0.62), (2.90, 1.10, 1.10), "matte", "dark_gray", package, 0.10, True)
    add_box("东面低矮储物区_顶部软垫", (x, -13.98, 1.23), (2.76, 0.86, 0.22), "matte", "blue", package, 0.09)
    for idx, px in enumerate((9.95, 10.85, 11.75)):
        add_box(f"东面低矮储物区_柜门_{idx+1:02d}", (px, -13.51, 0.66), (0.76, 0.08, 0.72), "matte", "mid_gray" if idx != 1 else "purple", package, 0.035)
        add_box(f"东面低矮储物区_柜门拉手_{idx+1:02d}", (px, -13.45, 0.83), (0.30, 0.05, 0.08), "metal", "light_gray", package, 0.018)
    add_box("东面低矮储物区_小型收纳箱", (10.05, -13.92, 1.55), (0.78, 0.56, 0.42), "matte", "teal", package, 0.06)
    add_cylinder("东面低矮储物区_水杯", (11.72, -13.82, 1.48), 0.10, 0.28, "matte", "light_gray", package, 16)


def build_poster(package):
    x, y, z = 14.32, -8.45, 4.72
    add_box("东墙团结海报_实体底板", (x, y, z), (0.18, 2.35, 1.55), "matte", "dark_gray", package, 0.06)
    for py in (y - 1.12, y + 1.12):
        add_box(f"东墙团结海报_金属侧框_{py:.2f}", (13.99, py, z), (0.10, 0.12, 1.60), "metal", "light_gray", package, 0.025)
    for pz in (z - 0.75, z + 0.75):
        add_box(f"东墙团结海报_金属横框_{pz:.2f}", (13.99, y, pz), (0.10, 2.35, 0.12), "metal", "light_gray", package, 0.025)
    add_text_east("东墙团结海报_WORK文字_自发光", "WORK", (13.91, y, 5.08), 0.22, "emit", "light_gray", package, 0.008)
    add_text_east("东墙团结海报_TOGETHER文字", "TOGETHER", (13.91, y, 4.70), 0.17, "matte", "yellow", package, 0.006)
    add_text_east("东墙团结海报_STAY_STRONG文字_自发光", "STAY STRONG", (13.91, y, 4.31), 0.14, "emit", "cyan", package, 0.006)
    for py in (y - 1.02, y + 1.02):
        for pz in (z - 0.65, z + 0.65):
            add_cylinder(f"东墙团结海报_固定螺丝_{py:.2f}_{pz:.2f}", (13.91, py, pz), 0.035, 0.03, "metal", "light_gray", package, 8, rotation=(0, math.pi / 2, 0))
    for idx, pz in enumerate((4.15, 4.30, 5.24)):
        add_box(f"东墙团结海报_轻微磨损_{idx+1:02d}", (13.88, y + (-0.65 + idx * 0.52), pz), (0.025, 0.32, 0.035), "matte", "warm_gray", package, 0.005, rotation=(0.0, 0.12, 0.0))


def build_small_devices(package):
    # Devices occupy only free wall bays and do not cover the door or major equipment.
    devices = [
        ("东墙小型设备_门禁状态面板", -0.55, 4.45, "cyan"),
        ("东墙小型设备_安全指示器", -4.35, 4.55, "orange"),
        ("东墙小型设备_分线箱", -10.20, 4.15, "teal"),
        ("东墙小型设备_维修标签盒", -12.30, 3.65, "yellow"),
    ]
    for idx, (name, py, pz, accent) in enumerate(devices):
        add_box(name + "_主体", (14.30, py, pz), (0.22, 0.72, 0.56), "metal", "dark_gray", package, 0.055)
        add_box(name + "_状态窗_自发光", (14.15, py, pz + 0.05), (0.035, 0.44, 0.20), "emit", accent, package, 0.025)
        for oy in (-0.25, 0.25):
            for oz in (-0.19, 0.19):
                add_cylinder(f"{name}_固定螺丝_{oy:+.2f}_{oz:+.2f}", (14.11, py + oy, pz + oz), 0.026, 0.025, "metal", "light_gray", package, 8, rotation=(0, math.pi / 2, 0))
    add_text_east("东墙小型设备_EXIT标牌_自发光", "EXIT", (13.99, -2.50, 3.35), 0.20, "emit", "cyan", package, 0.008)
    add_text_east("东墙小型设备_消防提示", "FIRE", (13.99, -6.75, 3.85), 0.15, "matte", "red", package, 0.006)
    add_box("东墙小型设备_应急灯_自发光", (14.05, -6.75, 4.18), (0.08, 0.42, 0.18), "emit", "orange", package, 0.03)
    add_box("东墙小型设备_双联插座", (14.18, -11.20, 1.20), (0.18, 0.54, 0.32), "metal", "dark_gray", package, 0.045)


def build_plants(package):
    placements = ((12.65, 3.20, 0.32), (12.00, -7.95, 0.30), (11.85, -13.35, 1.55))
    for idx, (x, y, z) in enumerate(placements):
        add_cylinder(f"东面植物_{idx+1:02d}_深色花盆", (x, y, z), 0.20, 0.38, "matte", "dark_gray", package, 16)
        for leaf, (dx, dy, dz) in enumerate(((0, 0, 0.24), (-0.13, 0.02, 0.30), (0.13, -0.02, 0.31), (0.0, 0.12, 0.36))):
            obj = add_sphere(f"东面植物_{idx+1:02d}_叶片_{leaf+1:02d}", (x + dx, y + dy, z + dz), 0.16, "matte", "green", package)
            obj.scale.z = 1.25


def build_lamp_details(package):
    # Existing x=10,y=-3.4 circular lamp geometry remains in place; add only structure.
    x, y = 10.0, -3.4
    add_cylinder("东面圆形吊灯_顶部连接座", (x, y, 8.22), 0.25, 0.18, "metal", "dark_gray", package, 20)
    for idx, (dx, dy) in enumerate(((-0.22, 0), (0.22, 0), (0, -0.22), (0, 0.22))):
        add_beam(f"东面圆形吊灯_四点吊线_{idx+1:02d}", (x + dx, y + dy, 8.15), (x + dx * 1.8, y + dy * 1.8, 7.34), 0.028, "metal", "black", package)
    add_torus("东面圆形吊灯_外围青蓝灯圈_自发光", (x, y, 6.98), 0.55, 0.035, "emit", "cyan", package, 32, 8)
    add_cylinder("东面圆形吊灯_底部冷白发光面_自发光", (x, y, 6.94), 0.46, 0.08, "emit", "light_gray", package, 28)
    light = add_point_light("东面圆形吊灯_局部冷白光", (x, y, 6.75), 185, (0.62, 0.82, 1.0), package, 1.4)
    light.data.use_shadow = True


def reclassify_target_packages(output, east_category):
    by_slug = {}
    for category in output.children:
        for package in category.children:
            slug = package.get("资产包键")
            if slug:
                by_slug[slug] = package

    supply = by_slug["supply_vending_station"]
    clear_package_objects(supply)
    supply.name = "72_SUPPLY24H自动补给机_资产包"
    move_collection(supply, east_category)
    package_meta(supply, "east_supply_24h_station")

    power = by_slug["east_power_box"]
    clear_package_objects(power)
    power.name = "73_POWER工业配电系统_资产包"
    move_collection(power, east_category)
    package_meta(power, "east_power_distribution")

    maintenance = by_slug["maintenance_workstation"]
    clear_package_objects(maintenance)
    maintenance.name = "78_维修工作台与工具墙_资产包"
    move_collection(maintenance, east_category)
    package_meta(maintenance, "east_maintenance_workstation")

    old_bins = by_slug["sorting_bin_group"]
    clear_package_objects(old_bins)
    bpy.data.collections.remove(old_bins)

    return supply, power, maintenance


def move_existing_east_lamp(output, lamp_package):
    support = next(category for category in output.children if category.name == "60_共享照明与环境动效")
    group = next(package for package in support.children if package.get("资产包键") == "warehouse_pendant_light_group")
    moved = []
    for obj in list(group.objects):
        if obj.name.endswith("_2_0") or obj.name.endswith("_2_0_自发光"):
            group.objects.unlink(obj)
            lamp_package.objects.link(obj)
            moved.append(obj.name)
    lamp_package["沿用v008灯体对象"] = ";".join(sorted(moved))


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


def object_signature(obj):
    data = None
    if obj.type == "MESH":
        verts = tuple(round(float(v), 6) for vertex in obj.data.vertices for v in vertex.co)
        data = {
            "vertices": len(obj.data.vertices),
            "polygons": len(obj.data.polygons),
            "vertex_hash": hashlib.sha256(repr(verts).encode()).hexdigest(),
            "materials": [mat.name if mat else None for mat in obj.data.materials],
            "material_indices": hashlib.sha256(bytes([poly.material_index % 256 for poly in obj.data.polygons])).hexdigest(),
        }
    animation = []
    if obj.animation_data and obj.animation_data.action:
        for curve in obj.animation_data.action.fcurves:
            animation.append((curve.data_path, curve.array_index, tuple((round(p.co.x, 4), round(p.co.y, 6)) for p in curve.keyframe_points)))
    return {
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "matrix": [round(float(v), 7) for row in obj.matrix_world for v in row],
        "dimensions": [round(float(v), 7) for v in obj.dimensions],
        "data": data,
        "animation": animation,
    }


def locked_payload(output):
    payload = {}
    for package in all_leaf_packages(output):
        if package.get("资产包键") in TARGET_OLD_SLUGS:
            continue
        for obj in package.objects:
            if obj.get("v009_scope"):
                continue
            payload[obj.name] = object_signature(obj)
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode()
    return payload, hashlib.sha256(encoded).hexdigest()


def bbox_for_objects(objects):
    points = []
    for obj in objects:
        if getattr(obj, "bound_box", None):
            points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
        else:
            points.append(obj.matrix_world.translation.copy())
    if not points:
        return {"center_m": [0, 0, 0], "size_m": [0, 0, 0]}
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return {
        "center_m": [round((lo[i] + hi[i]) * 0.5, 5) for i in range(3)],
        "size_m": [round(hi[i] - lo[i], 5) for i in range(3)],
    }


def write_catalog(output):
    VERIFY_ROOT.mkdir(parents=True, exist_ok=True)
    entries = []
    for package in sorted(all_leaf_packages(output), key=collection_path):
        category = package.get("资产类别", "uncategorized")
        slug = package.get("资产包键", package.name)
        package["资产包"] = True
        package["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
        package["未来导出目录"] = str((PACKAGE_ROOT / category / slug).relative_to(PROJECT))
        package["组织版本"] = "v009"
        export_dir = PROJECT / package["未来导出目录"]
        export_dir.mkdir(parents=True, exist_ok=True)
        objects = sorted(package.objects, key=lambda obj: obj.name)
        bbox = bbox_for_objects(objects)
        entry = {
            "asset_id": "ENV-BASE99-ART-LAYOUT-3D",
            "package_id": f"ENV-BASE99-ART-LAYOUT-3D::{slug}",
            "display_name": package.name,
            "asset_slug": slug,
            "category": category,
            "version": "v009",
            "collection_path": collection_path(package),
            "future_export_directory": package["未来导出目录"],
            "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
            "status": package.get("当前状态", "已归类_待独立导出"),
            "object_count": len(objects),
            "mesh_count": sum(obj.type == "MESH" for obj in objects),
            "light_count": sum(obj.type == "LIGHT" for obj in objects),
            "object_names": [obj.name for obj in objects],
            "world_center_m": bbox["center_m"],
            "bounding_size_m": bbox["size_m"],
            "local_origin": "preserve scene master world placement; export pivot to be authored at independent-export stage",
            "forward_axis": "scene master world orientation; Blender +Y north",
            "material_roles": sorted({obj.get("material_role") for obj in objects if obj.get("material_role")}),
            "has_animation": any(obj.animation_data and obj.animation_data.action for obj in objects),
            "dependencies": [],
            "expected_export": f"{slug}_visual_top3d_v001.glb",
            "collision_status": "not_authored_in_this_partial_blender_pass",
            "export_status": "not_exported",
        }
        manifest = dict(entry)
        manifest["note"] = "v009独立设施资产包；Collection与目录一一对应，后续独立导出GLB、碰撞与PackedScene。"
        (export_dir / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        entries.append(entry)
    catalog = {
        "schema": "shellstorm2.base_facility.component_catalog.v2",
        "organization_version": "v009",
        "source_asset_id": "ENV-BASE99-ART-LAYOUT-3D",
        "source_blend": str(INPUT_BLEND.relative_to(PROJECT)),
        "organized_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "scope": "reference east facility zone only",
        "package_count": len(entries),
        "floor_tile_package_count": sum(e["category"] == "floor" for e in entries),
        "packages": entries,
    }
    CATALOG_JSON.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["基地场景独立资产包树 v009", "源资产ID: ENV-BASE99-ART-LAYOUT-3D", f"独立资产包数量: {len(entries)}", ""]
    for category in output.children:
        lines.append(category.name + "/")
        for package in category.children:
            lines.append(f"  {package.name}/ [{package['资产包键']}] objects={len(package.objects)} -> {package['未来导出目录']}")
        lines.append("")
    TREE_TXT.write_text("\n".join(lines), encoding="utf-8")
    return catalog


def create_detail_camera():
    preview = bpy.data.collections["90_展示环境_灯光相机"]
    source = bpy.data.objects["基地微缩模型_英雄相机"]
    camera = source.copy()
    camera.data = source.data.copy()
    camera.name = "基地微缩模型_东面设施验收相机"
    camera.data.name = camera.name
    preview.objects.link(camera)
    camera.location = (1.5, -15.5, 11.2)
    target = Vector((13.4, -4.5, 2.6))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 20.0
    return camera


def render(camera, path):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = str(path)
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    bpy.ops.render.render(write_still=True)


def main():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        raise RuntimeError(f"必须以v008为输入: {bpy.data.filepath}")
    if OUTPUT_BLEND.exists():
        raise RuntimeError(f"目标文件已存在，禁止覆盖: {OUTPUT_BLEND}")
    setup_helpers()
    root = bpy.data.collections[ROOT_NAME]
    output = bpy.data.collections[INPUT_OUTPUT_NAME]
    before_payload, before_hash = locked_payload(output)

    output.name = OUTPUT_NAME
    base.OUTPUT = output
    east_category = ensure_child(output, EAST_CATEGORY_NAME)
    supply, power, maintenance = reclassify_target_packages(output, east_category)

    door = add_package(east_category, "71_正式人员安全门_资产包", "east_personnel_security_door")
    pipes = add_package(east_category, "74_东墙工业管线系统_资产包", "east_industrial_pipeline_system")
    waste = add_package(east_category, "75_WASTE普通垃圾设施_资产包", "east_waste_bin")
    flammable = add_package(east_category, "76_FLAMMABLE可燃垃圾设施_资产包", "east_flammable_bin")
    recycle = add_package(east_category, "77_RECYCLE回收垃圾设施_资产包", "east_recycle_bin")
    low_storage = add_package(east_category, "80_低矮储物收纳区_资产包", "east_low_storage_bench")
    poster = add_package(east_category, "81_WORK_TOGETHER工业海报_资产包", "east_work_together_poster")
    small_devices = add_package(east_category, "82_东墙小型安全设备_资产包", "east_small_safety_devices")
    plants = add_package(east_category, "83_东面植物点缀组_资产包", "east_plant_group")
    lamp = add_package(east_category, "84_东面圆形工业吊灯_资产包", "east_round_pendant_light")
    move_existing_east_lamp(output, lamp)

    build_personnel_door(door)
    build_supply_machine(supply)
    build_power_cabinet(power)
    build_east_pipeline(pipes)
    build_bin(waste, "WASTE", -5.20, "mid_gray")
    build_bin(flammable, "FLAMMABLE", -6.65, "red")
    build_bin(recycle, "RECYCLE", -8.10, "green")
    build_maintenance(maintenance)
    build_low_storage(low_storage)
    build_poster(poster)
    build_small_devices(small_devices)
    build_plants(plants)
    build_lamp_details(lamp)

    after_payload, after_hash = locked_payload(output)
    if before_hash != after_hash:
        before_names, after_names = set(before_payload), set(after_payload)
        changed = sorted(name for name in before_names & after_names if before_payload[name] != after_payload[name])
        raise RuntimeError(f"锁定范围发生变化 added={sorted(after_names-before_names)[:8]} removed={sorted(before_names-after_names)[:8]} changed={changed[:8]}")

    source = bpy.data.collections["01_制作组件_已统一材质"]
    source.hide_viewport = True
    source.hide_render = True
    VERIFY_ROOT.mkdir(parents=True, exist_ok=True)
    catalog = write_catalog(output)
    lock_report = {
        "input": str(INPUT_BLEND.relative_to(PROJECT)),
        "output": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "locked_object_count": len(before_payload),
        "locked_signature_v008": before_hash,
        "locked_signature_v009": after_hash,
        "locked_match": before_hash == after_hash,
        "target_old_slugs": sorted(TARGET_OLD_SLUGS),
        "package_count": catalog["package_count"],
    }
    LOCK_REPORT.write_text(json.dumps(lock_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    detail_camera = create_detail_camera()
    bpy.context.scene["v009_scope"] = "东面设施区域局部高还原深化"
    bpy.context.scene["v009_locked_signature"] = after_hash
    bpy.context.scene["v009_package_count"] = catalog["package_count"]
    bpy.context.scene["v009_floor_tile_package_count"] = catalog["floor_tile_package_count"]
    bpy.context.scene["v009_personnel_door_contract"] = "east wall x=15; opening center y=-2.5; clear marker 2.2x2.5m unchanged"
    bpy.context.scene["v009_supply_contract"] = "adjacent to door; does not overlap y[-3.6,-1.4] door clearance"
    bpy.context.scene["v009_runtime_note"] = "Blender source/package pass only; no GLB/collision/PackedScene export"

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    render(bpy.data.objects["基地微缩模型_英雄相机"], HERO_RENDER)
    render(bpy.data.objects["基地微缩模型_顶视相机"], TOP_RENDER)
    render(detail_camera, DETAIL_RENDER)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"BASE_FACILITY_V009_BUILT {OUTPUT_BLEND}")
    print(f"locked_signature={after_hash} packages={catalog['package_count']} floor_tiles={catalog['floor_tile_package_count']}")


if __name__ == "__main__":
    main()
