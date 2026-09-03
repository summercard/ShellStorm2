#!/usr/bin/env python3
"""Build Base 99 HQ v011: high-fidelity loft/stair iteration from v010."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
INPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v010.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v011.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v011"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v011"
CATALOG = VERIFY / "base_facility_component_catalog_v011.json"
TREE = VERIFY / "base_facility_component_tree_v011.txt"
LOCK_REPORT = VERIFY / "base_facility_locked_scope_v010_v011.json"
SCOPE_REPORT = VERIFY / "base_facility_v011_visual_acceptance.json"
OUT10 = "02_游戏输出_独立资产包_v010"
OUT11 = "02_游戏输出_独立资产包_v011"

spec = importlib.util.spec_from_file_location("base_v010", PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v010.py")
v010 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v010)
base = v010.base


def setup():
    base.SOURCE = bpy.data.collections["01_制作组件_已统一材质"]
    base.SOURCE.hide_viewport = False
    base.SOURCE.hide_render = True
    base.OUTPUT = bpy.data.collections[OUT10]
    base.MATS.clear()
    base.MATS.update({
        "metal": bpy.data.materials["01_精工金属_紫色骨架"],
        "matte": bpy.data.materials["02_细腻哑光_青绿大面"],
        "gloss": bpy.data.materials["03_清漆反光_紫粉点缀"],
        "emit": bpy.data.materials["04_柔和自发光_UI灯光"],
    })


def ensure_child(parent, name):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in parent.children:
        parent.children.link(c)
    return c


def package(parent, number, name, slug, category="loft"):
    c = ensure_child(parent, f"{number:02d}_{name}_资产包")
    c["资产包"] = True
    c["资产包键"] = slug
    c["资产类别"] = category
    c["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
    c["组织版本"] = "v011"
    c["当前状态"] = "参考图高还原深化_待独立导出"
    c["本批次范围"] = "二楼设施与楼梯高还原迭代"
    c["未来导出目录"] = str((PACKAGE_ROOT / category / slug).relative_to(PROJECT))
    return c


def tag(o):
    o["v011_scope"] = "loft_and_stair_high_fidelity"
    return o


def box(n, l, s, role, color, coll, bevel=.035, ob=False, rot=(0, 0, 0)):
    return tag(base.add_box(n, l, s, role, color, bevel, coll, ob, rot))


def cyl(n, l, rad, depth, role, color, coll, verts=16, rot=(0, 0, 0)):
    return tag(base.add_cylinder(n, l, rad, depth, role, color, verts, coll, False, rot))


def sphere(n, l, rad, role, color, coll):
    return tag(base.add_sphere(n, l, rad, role, color, coll))


def beam(n, a, b, thick, role, color, coll):
    return tag(base.add_beam(n, a, b, thick, role, color, coll))


def text_north(n, body, l, size, role, color, coll, extrude=.012):
    bpy.ops.object.select_all(action="DESELECT")
    return tag(base.add_text(n, body, l, size, role, color, extrude, "CENTER", (math.pi / 2, 0, 0), coll))


def text_west(n, body, l, size, role, color, coll, extrude=.012):
    bpy.ops.object.select_all(action="DESELECT")
    return tag(base.add_text(n, body, l, size, role, color, extrude, "CENTER", (math.pi / 2, 0, -math.pi / 2), coll))


def torus(n, l, major, minor, role, color, coll, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(align="WORLD", major_segments=24, minor_segments=8, location=l, major_radius=major, minor_radius=minor, rotation=rot)
    src = bpy.context.object
    base.link_only(src, base.SOURCE)
    src.name = n + "__源"
    base.assign_material(src, role, base.COLORS[color])
    return tag(base.publish(src, coll, n))


def pulse(obj, phase=0, lo=.94, hi=1.03):
    obj.scale = (1, 1, 1)
    obj.keyframe_insert("scale", frame=1 + phase)
    obj.scale = (lo, lo, lo)
    obj.keyframe_insert("scale", frame=32 + phase)
    obj.scale = (hi, hi, hi)
    obj.keyframe_insert("scale", frame=64 + phase)
    obj.scale = (1, 1, 1)
    obj.keyframe_insert("scale", frame=96 + phase)


def add_area_light(name, loc, energy, color, size, coll, target):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "RECTANGLE"
    if isinstance(size, (int, float)):
        data.size = float(size)
        data.size_y = float(size) * .55
    else:
        data.size = size[0]
        data.size_y = size[1]
    obj = bpy.data.objects.new(name, data)
    coll.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    return tag(obj)


def remove_v010_scope(output):
    for obj_name in [o.name for o in bpy.data.objects]:
        obj = bpy.data.objects.get(obj_name)
        if obj is None:
            continue
        if obj.get("v010_scope"):
            src = bpy.data.objects.get(obj.name + "__源")
            bpy.data.objects.remove(obj, do_unlink=True)
            if src:
                bpy.data.objects.remove(src, do_unlink=True)
    for coll in list(bpy.data.collections):
        if coll.get("资产包") and not coll.objects and not coll.children and coll.get("资产包键") != "northwest_l_stair":
            bpy.data.collections.remove(coll)
    for name in ("30_二楼生活工作设施", "15_楼梯深化与过渡结构"):
        coll = bpy.data.collections.get(name)
        if coll and not coll.objects and not coll.children:
            bpy.data.collections.remove(coll)


def rounded_cushion(name, loc, scale, color, coll, rot=(0, 0, 0)):
    obj = box(name, loc, scale, "matte", color, coll, min(scale) * .22, rot=rot)
    return obj


def build_bed(coll):
    x, y = .3, 11.25
    # Reference-like low, thick black frame with visible under-bed structure.
    for py in (10.28, 12.22):
        box(f"床架_长边_{py}", (x, py, 6.49), (4.75, .15, .34), "metal", "dark_gray", coll, .055)
    for px in (-2.0, 2.6):
        box(f"床架_短边_{px}", (px, y, 6.49), (.15, 2.05, .34), "metal", "dark_gray", coll, .055)
    for px in (-1.9, 2.5):
        for py in (10.38, 12.12):
            cyl(f"床架_圆脚_{px}_{py}", (px, py, 6.30), .075, .58, "metal", "black", coll, 12)
    rounded_cushion("床垫_厚软包", (x, y, 6.78), (4.52, 1.86, .38), "light_gray", coll)
    rounded_cushion("床面_墨绿床罩", (.62, y, 7.03), (3.80, 1.78, .20), "green", coll)
    for i, py in enumerate((10.78, 11.62)):
        rounded_cushion(f"枕头_{i+1:02d}", (-1.45, py, 7.19), (.95, .66, .22), "light_gray", coll, (0, .06, .02 if i else -.03))
    # Mattress seam and restrained blanket folds.
    for py in (10.39, 12.11):
        box(f"床垫_滚边_{py}", (x, py, 6.89), (4.20, .035, .055), "matte", "mid_gray", coll, .01)
    for i in range(4):
        box(f"床罩_细褶_{i:02d}", (.35 + i * .65, y, 7.145), (.025, 1.46, .018), "matte", "teal", coll, .004)
    for i, py in enumerate((10.78, 11.72)):
        box(f"床下收纳箱_{i+1:02d}", (.85, py, 6.27), (1.18, .70, .38), "matte", "dark_gray", coll, .07)
        box(f"床下箱_橙色扣_{i+1:02d}", (.85, py - .37, 6.28), (.24, .04, .12), "metal", "orange", coll, .015)


def build_nightstand(coll):
    x, y = -2.75, 11.35
    box("床头柜_主箱体", (x, y, 6.64), (1.02, .92, 1.05), "matte", "dark_gray", coll, .11)
    box("床头柜_顶板", (x, y, 7.20), (1.10, 1.00, .10), "metal", "black", coll, .04)
    for i, z in enumerate((6.48, 6.82)):
        box(f"床头柜_抽屉面_{i+1}", (x, 10.86, z), (.86, .06, .26), "matte", "purple", coll, .035)
        box(f"床头柜_抽屉拉手_{i+1}", (x, 10.81, z), (.28, .04, .055), "metal", "orange", coll, .012)
    box("床头柜_书本", (-2.93, 11.27, 7.30), (.46, .33, .07), "matte", "orange", coll, .022, rot=(0, 0, -.12))
    cyl("床头柜_杯子", (-2.56, 11.10, 7.37), .085, .20, "matte", "light_gray", coll, 16)


def build_bed_lamp(coll):
    x, y = -2.80, 11.67
    cyl("床头灯_底座", (x, y, 7.27), .19, .08, "metal", "dark_gray", coll, 20)
    cyl("床头灯_杆", (x, y, 7.61), .032, .66, "metal", "light_gray", coll, 12)
    shade = box("床头灯_橙色灯罩_自发光", (x, y, 7.96), (.42, .42, .34), "emit", "orange", coll, .095)
    pulse(shade, 9, .96, 1.03)
    light = bpy.data.lights.new("床头灯_暖橙光", "POINT")
    light.color = (1.0, .24, .05)
    light.energy = 85
    light.shadow_soft_size = .75
    obj = bpy.data.objects.new("床头灯_暖橙光", light)
    coll.objects.link(obj)
    obj.location = (x, y, 7.83)
    tag(obj)


def build_rug(coll, name, center, size, color, pattern):
    box(name + "_软质基底", (center[0], center[1], 6.087), (size[0], size[1], .045), "matte", color, coll, .13)
    for i in range(pattern):
        x = center[0] - size[0] * .34 + i * (size[0] * .68 / max(pattern - 1, 1))
        box(f"{name}_低对比编织线_{i+1:02d}", (x, center[1], 6.114), (.025, size[1] * .82, .012), "matte", "purple", coll, .004)


def build_curtain(coll):
    x = 3.55
    cyl("隔断帘_顶部黑色横杆", (x, 12.25, 8.72), .045, 2.75, "metal", "black", coll, 16, (math.pi / 2, 0, 0))
    for py in (10.96, 13.54):
        beam(f"隔断帘_吊杆_{py}", (x, py, 8.72), (x, py, 8.98), .025, "metal", "dark_gray", coll)
    colors = ("rust", "purple", "rust", "orange", "purple", "rust", "purple", "rust")
    for i, color in enumerate(colors):
        py = 11.05 + i * .355
        panel = box(f"隔断帘_布褶片_{i+1:02d}", (x, py, 7.67), (.075, .38, 2.02), "matte", color, coll, .025, rot=(0, .015 * math.sin(i), 0))
        panel.keyframe_insert("rotation_euler", frame=1)
        panel.rotation_euler.y += .025 * (-1 if i % 2 else 1)
        panel.keyframe_insert("rotation_euler", frame=55)
        panel.rotation_euler.y -= .025 * (-1 if i % 2 else 1)
        panel.keyframe_insert("rotation_euler", frame=110)


def build_sofa(coll):
    x, y = 6.25, 12.28
    box("沙发_低矮加厚底座", (x, y, 6.43), (4.05, 1.50, .50), "matte", "dark_gray", coll, .18)
    for i, px in enumerate((4.94, 6.25, 7.56)):
        rounded_cushion(f"沙发_独立座垫_{i+1:02d}", (px, 11.99, 6.79), (1.20, .93, .32), "green", coll)
        rounded_cushion(f"沙发_独立靠垫_{i+1:02d}", (px, 12.77, 7.34), (1.20, .33, 1.16), "teal", coll, (-.10, 0, 0))
        box(f"沙发_座垫压线_{i+1:02d}", (px, 11.51, 6.83), (.90, .025, .028), "matte", "dark_gray", coll, .006)
    for px in (4.02, 8.48):
        rounded_cushion(f"沙发_宽扶手_{px}", (px, 12.23, 6.96), (.36, 1.58, .74), "green", coll)
    for i, (px, pz, color, angle) in enumerate(((5.20, 7.34, "purple", -.10), (6.15, 7.39, "blue", .05), (7.20, 7.32, "red", .12))):
        rounded_cushion(f"沙发_彩色靠枕_{i+1:02d}", (px, 12.28, pz), (.66, .27, .58), color, coll, (-.10, 0, angle))
    # Little feet read clearly in the miniature view.
    for px in (4.35, 8.15):
        for py in (11.72, 12.78):
            cyl(f"沙发_短脚_{px}_{py}", (px, py, 6.20), .055, .22, "metal", "black", coll, 10)


def build_coffee_table(coll):
    x, y = 6.20, 9.38
    box("茶几_红棕圆角台面", (x, y, 6.70), (2.85, 1.28, .17), "matte", "rust", coll, .10)
    box("茶几_台面内嵌边", (x, y, 6.80), (2.50, .94, .035), "gloss", "purple", coll, .025)
    for px in (5.02, 7.38):
        for py in (8.94, 9.82):
            cyl(f"茶几_细腿_{px}_{py}", (px, py, 6.39), .045, .58, "metal", "dark_gray", coll, 10)
    box("茶几_遥控器", (5.83, 9.28, 6.87), (.39, .18, .07), "gloss", "black", coll, .03, rot=(0, 0, .13))
    cyl("茶几_杯子", (6.31, 9.52, 6.91), .09, .20, "matte", "light_gray", coll, 16)
    box("茶几_小碟", (6.78, 9.22, 6.85), (.39, .29, .04), "gloss", "purple", coll, .04)


def build_pouf(coll, index, loc, color):
    cyl(f"坐墩{index:02d}_软包主体", (loc[0], loc[1], 6.47), .44, .54, "matte", color, coll, 24)
    torus(f"坐墩{index:02d}_下包边", (loc[0], loc[1], 6.22), .37, .045, "metal", "dark_gray", coll)
    torus(f"坐墩{index:02d}_坐面滚边", (loc[0], loc[1], 6.72), .35, .025, "matte", "teal", coll)


def build_side_table(coll):
    x, y = 1.80, 9.22
    box("辅助小桌_圆角台面", (x, y, 6.62), (1.12, .76, .14), "matte", "rust", coll, .075)
    for px in (1.36, 2.24):
        for py in (8.95, 9.49):
            cyl(f"辅助小桌_腿_{px}_{py}", (px, py, 6.36), .035, .48, "metal", "dark_gray", coll, 10)
    cyl("辅助小桌_青色杯", (1.61, 9.20, 6.79), .075, .19, "matte", "teal", coll, 14)
    box("辅助小桌_个人终端", (1.97, 9.20, 6.76), (.30, .21, .05), "gloss", "blue", coll, .025)


def build_workstation(coll):
    x, y = 10.45, 13.70
    box("工位_深色桌面", (x, y, 6.84), (3.75, 1.08, .17), "matte", "dark_gray", coll, .085)
    for px in (8.85, 12.05):
        box(f"工位_抽屉支撑柜_{px}", (px, y, 6.42), (.43, 1.00, .76), "metal", "dark_gray", coll, .065)
        for z in (6.26, 6.53):
            box(f"工位_抽屉_{px}_{z}", (px, 13.13, z), (.32, .055, .18), "matte", "purple", coll, .02)
    for i, px in enumerate((9.70, 11.17)):
        box(f"工位_显示器厚框_{i+1:02d}", (px, 14.02, 7.63), (1.24, .15, .86), "metal", "purple", coll, .075)
        screen = box(f"工位_显示屏_{i+1:02d}_自发光", (px, 13.93, 7.63), (1.06, .026, .67), "emit", "cyan" if i == 0 else "blue", coll, .025)
        pulse(screen, i * 13, .97, 1.02)
        cyl(f"工位_显示器立柱_{i+1:02d}", (px, 13.79, 7.15), .045, .34, "metal", "dark_gray", coll, 12)
        box(f"工位_显示器底座_{i+1:02d}", (px, 13.64, 6.99), (.55, .28, .055), "metal", "dark_gray", coll, .025)
        # Readable scan lines rather than a flat cyan tile.
        for row in range(4):
            box(f"工位_屏幕扫描线_{i+1:02d}_{row+1:02d}_自发光", (px, 13.912, 7.41 + row * .14), (.78, .008, .018), "emit", "light_gray", coll, .003)
    box("工位_键盘底板", (10.30, 13.15, 6.98), (1.12, .35, .065), "gloss", "dark_gray", coll, .035)
    for r in range(3):
        for c in range(7):
            box(f"工位_键帽_{r}_{c}", (9.88 + c * .14, 13.03 + r * .10, 7.025), (.095, .065, .026), "matte", "mid_gray", coll, .008)
    box("工位_鼠标", (11.18, 13.10, 7.02), (.22, .31, .08), "gloss", "purple", coll, .06)
    for px in (9.05, 11.87):
        box(f"工位_音箱_{px}", (px, 13.30, 7.29), (.27, .27, .53), "matte", "black", coll, .045)
        cyl(f"工位_音箱单元_{px}", (px, 13.145, 7.30), .075, .022, "gloss", "cyan", coll, 16, (math.pi / 2, 0, 0))
    box("工位_竖置主机", (12.15, 13.65, 7.34), (.47, .66, .88), "metal", "dark_gray", coll, .065)
    box("工位_主机状态灯_自发光", (12.15, 13.28, 7.55), (.08, .025, .07), "emit", "green", coll, .018)
    cyl("工位_白色杯", (9.00, 13.14, 7.06), .085, .21, "matte", "light_gray", coll, 16)
    box("工位_记事板", (11.62, 13.15, 7.00), (.33, .26, .035), "matte", "orange", coll, .018, rot=(0, 0, -.12))


def build_office_chair(coll):
    x, y = 10.45, 12.23
    cyl("办公椅_五星脚中心", (x, y, 6.25), .13, .18, "metal", "dark_gray", coll, 16)
    for i in range(5):
        a = i * 2 * math.pi / 5
        end = (x + .52 * math.cos(a), y + .52 * math.sin(a), 6.18)
        beam(f"办公椅_五星脚_{i+1:02d}", (x, y, 6.22), end, .045, "metal", "dark_gray", coll)
        cyl(f"办公椅_脚轮_{i+1:02d}", end, .06, .08, "metal", "black", coll, 10, (math.pi / 2, 0, 0))
    cyl("办公椅_升降杆", (x, y, 6.55), .055, .61, "metal", "light_gray", coll, 12)
    rounded_cushion("办公椅_坐垫", (x, y, 6.91), (1.02, .91, .25), "teal", coll)
    rounded_cushion("办公椅_靠背", (x, 12.65, 7.54), (1.04, .25, 1.19), "green", coll, (-.08, 0, 0))
    for sx in (-.52, .52):
        beam(f"办公椅_扶手杆_{sx}", (x + sx, y, 6.89), (x + sx, y, 7.28), .035, "metal", "dark_gray", coll)
        box(f"办公椅_扶手垫_{sx}", (x + sx, y - .02, 7.30), (.24, .62, .08), "matte", "dark_gray", coll, .035)


def build_storage(coll, label, loc, color):
    x, y = loc
    # Reference uses compact modular boxes; avoid the prior oversized tall-cabinet silhouette.
    box(f"{label}分类箱_厚实主体", (x, y, 6.50), (1.15, .85, .76), "matte", color, coll, .12)
    box(f"{label}分类箱_深色顶盖", (x, y, 6.91), (1.20, .90, .12), "metal", "dark_gray", coll, .055)
    for sx in (-.49, .49):
        box(f"{label}分类箱_包角_{sx}", (x + sx, y, 6.50), (.11, .87, .74), "metal", "dark_gray", coll, .025)
    box(f"{label}分类箱_正面标签板", (x, y - .46, 6.54), (.84, .045, .28), "gloss", "dark_gray", coll, .025)
    text_north(f"{label}分类箱_文字_自发光", label, (x, y - .49, 6.54), .115, "emit", "light_gray", coll, .006)
    box(f"{label}分类箱_锁扣", (x, y - .50, 6.80), (.20, .035, .10), "metal", "orange", coll, .015)


def build_wall_decor(coll):
    box("EXPLORE海报_深色底板", (-2.12, 14.72, 8.05), (1.22, .07, 1.48), "matte", "dark_gray", coll, .045)
    text_north("EXPLORE海报_标题_自发光", "EXPLORE", (-2.12, 14.67, 8.48), .135, "emit", "orange", coll, .006)
    # Stylised mountain graphic built as geometry.
    beam("EXPLORE海报_山线A", (-2.58, 14.64, 7.72), (-2.18, 14.64, 8.08), .035, "matte", "light_gray", coll)
    beam("EXPLORE海报_山线B", (-2.18, 14.64, 8.08), (-1.74, 14.64, 7.68), .035, "matte", "light_gray", coll)
    box("工具洞洞板_主体", (-.15, 14.72, 8.05), (2.55, .08, 1.34), "metal", "mid_gray", coll, .055)
    for row in range(4):
        for col in range(8):
            cyl(f"工具洞洞板_孔_{row}_{col}", (-1.14 + col * .28, 14.665, 7.58 + row * .29), .022, .018, "metal", "dark_gray", coll, 8, (math.pi / 2, 0, 0))
    for i, x in enumerate((-.78, -.24, .28, .80)):
        beam(f"工具洞洞板_工具_{i+1:02d}", (x, 14.625, 7.72), (x + .10, 14.625, 8.28), .04, "metal", "light_gray", coll)
        box(f"工具洞洞板_橙色挂钩_{i+1:02d}", (x, 14.60, 8.33), (.16, .035, .07), "metal", "orange", coll, .015)


def build_plant(coll):
    x, y = 2.72, 14.15
    cyl("吊挂植物_陶盆", (x, y, 8.23), .22, .34, "matte", "rust", coll, 18)
    for i in range(9):
        a = i * 2 * math.pi / 9
        beam(f"吊挂植物_垂叶_{i+1:02d}", (x, y, 8.15), (x + .28 * math.cos(a), y + .22 * math.sin(a), 7.48 - .08 * (i % 3)), .06, "matte", "green", coll)
    for py in (13.97, 14.33):
        beam(f"吊挂植物_吊绳_{py}", (x, py, 8.38), (x, py, 8.96), .02, "metal", "dark_gray", coll)


def build_neon(coll):
    box("GOOD_VIBES_小型背板", (10.55, 14.72, 8.48), (1.55, .07, .66), "metal", "dark_gray", coll, .055)
    good = text_north("GOOD_VIBES_GOOD_自发光", "GOOD", (10.55, 14.665, 8.62), .18, "emit", "magenta", coll, .008)
    vibes = text_north("GOOD_VIBES_VIBES_自发光", "VIBES", (10.55, 14.665, 8.34), .18, "emit", "magenta", coll, .008)
    pulse(good, 12, .96, 1.035)
    pulse(vibes, 20, .96, 1.035)


def build_loft_lighting(coll):
    # Fixtures are visible, real lights create the reference's cold/warm hierarchy.
    box("二楼西墙_冷白线性灯外壳", (-5.10, 14.66, 7.58), (2.20, .12, .18), "metal", "dark_gray", coll, .045)
    lamp = box("二楼西墙_冷白线性灯_自发光", (-5.10, 14.57, 7.58), (1.88, .035, .085), "emit", "light_gray", coll, .018)
    pulse(lamp, 4, .98, 1.02)
    add_area_light("二楼床区_暖白面光", (-1.4, 11.2, 9.6), 520, (1.0, .58, .28), 4.5, coll, (-.2, 11.0, 6.6))
    add_area_light("二楼休闲区_柔和暖光", (6.3, 10.4, 10.0), 610, (1.0, .42, .20), 5.0, coll, (6.2, 10.8, 6.5))
    add_area_light("二楼工位区_冷色面光", (10.6, 13.0, 10.2), 500, (.12, .48, 1.0), 4.0, coll, (10.5, 13.5, 6.8))
    add_area_light("二楼整体_冷色轮廓光", (-1.0, 7.0, 11.5), 580, (.18, .38, 1.0), 8.0, coll, (3.5, 11.0, 6.0))


def build_l_stair_detail(coll):
    coll["组织版本"] = "v011"
    coll["本批次范围"] = "既有L型楼梯几何锁定，仅表面与节点深化"
    for run, prefix in (("第一跑", "L梯_西墙第一跑踏步_"), ("第二跑", "L梯_北墙第二跑踏步_")):
        for i in range(1, 11):
            step = bpy.data.objects[f"{prefix}{i:02d}"]
            loc, dim = step.location, step.dimensions
            if run == "第一跑":
                box(f"L梯v011_{run}_银色防滑边_{i:02d}", (loc.x, loc.y - dim.y * .46, loc.z + dim.z * .52), (dim.x * .82, .045, .028), "metal", "light_gray", coll, .006)
                light = box(f"L梯v011_{run}_橙色踏步灯_{i:02d}_自发光", (loc.x, loc.y - dim.y * .52, loc.z + dim.z * .17), (dim.x * .74, .022, .038), "emit", "orange", coll, .005)
            else:
                box(f"L梯v011_{run}_银色防滑边_{i:02d}", (loc.x - dim.x * .46, loc.y, loc.z + dim.z * .52), (.045, dim.y * .82, .028), "metal", "light_gray", coll, .006)
                light = box(f"L梯v011_{run}_橙色踏步灯_{i:02d}_自发光", (loc.x - dim.x * .52, loc.y, loc.z + dim.z * .17), (.022, dim.y * .74, .038), "emit", "orange", coll, .005)
            pulse(light, i * 2, .94, 1.03)
    box("L梯v011_转角平台完整防滑板", (-13.8, 13.8, 3.07), (1.76, 1.76, .05), "metal", "mid_gray", coll, .028)
    for y in (13.09, 14.51):
        box(f"L梯v011_转角平台橙色边线_{y}", (-13.8, y, 3.105), (1.55, .07, .02), "matte", "orange", coll, .006)
    box("L梯v011_顶层平台接缝压板", (-4.82, 13.8, 6.103), (.30, 1.76, .05), "metal", "light_gray", coll, .016)
    text_west("L梯v011_STAY_CURIOUS标牌_自发光", "STAY CURIOUS", (-14.65, 11.02, 5.18), .17, "emit", "orange", coll, .008)


def build_east_stair(coll):
    # Compact stair at the northeast edge, matching the reference silhouette and leaving the workstation path clear.
    x, y0, dy, dz = 13.28, 10.56, .39, .25
    for i in range(10):
        y, z = y0 + i * dy, 6.18 + i * dz
        box(f"东侧楼梯_踏步_{i+1:02d}", (x, y, z), (1.72, .40, .25), "metal", "dark_gray", coll, .042)
        box(f"东侧楼梯_银色防滑条_{i+1:02d}", (x, y - .165, z + .142), (1.43, .045, .025), "metal", "light_gray", coll, .006)
        light = box(f"东侧楼梯_橙色踏步灯_{i+1:02d}_自发光", (x, y - .205, z + .035), (1.34, .018, .036), "emit", "orange", coll, .005)
        pulse(light, i * 2, .94, 1.03)
    box("东侧楼梯_底部接缝压板", (x, 10.30, 6.085), (1.72, .26, .045), "metal", "light_gray", coll, .014)
    box("东侧楼梯_顶部接驳平台", (x, 14.52, 8.68), (1.95, .80, .16), "metal", "dark_gray", coll, .045)
    for sx in (12.36, 14.20):
        beam(f"东侧楼梯_侧梁_{sx}", (sx, 10.35, 6.03), (sx, 14.10, 8.45), .08, "metal", "dark_gray", coll)
        for i in range(6):
            y = 10.38 + i * .72
            z = 6.55 + i * .47
            cyl(f"东侧楼梯_栏杆立柱_{sx}_{i:02d}", (sx, y, z), .035, .88, "metal", "dark_gray", coll, 10)
        beam(f"东侧楼梯_连续扶手_{sx}", (sx, 10.35, 7.02), (sx, 14.10, 9.31), .052, "metal", "dark_gray", coll)
    coll["接口契约"] = "bottom seam top Z=6.1075; first tread top Z=6.305; top landing top Z=8.76"


def leaf_packages(root):
    out = []
    def walk(c):
        if c.get("资产包"):
            out.append(c)
        for child in c.children:
            walk(child)
    walk(root)
    return out


def objsig(o):
    data = None
    if o.type == "MESH":
        coords = tuple(round(float(c), 6) for v in o.data.vertices for c in v.co)
        data = (len(o.data.vertices), len(o.data.polygons), hashlib.sha256(repr(coords).encode()).hexdigest(), tuple(m.name if m else None for m in o.data.materials))
    return {
        "type": o.type,
        "parent": o.parent.name if o.parent else None,
        "matrix": [round(float(c), 7) for row in o.matrix_world for c in row],
        "dim": [round(float(c), 7) for c in o.dimensions],
        "data": data,
    }


def locked_signature(output):
    result = {}
    for pkg in leaf_packages(output):
        for obj in pkg.objects:
            if not obj.get("v010_scope") and not obj.get("v011_scope"):
                result[obj.name] = objsig(obj)
    return result


def bbox(objects):
    pts = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box] if objects else []
    if not pts:
        return [0, 0, 0], [0, 0, 0]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return [round((lo[i] + hi[i]) / 2, 4) for i in range(3)], [round(hi[i] - lo[i], 4) for i in range(3)]


def write_catalog(output):
    VERIFY.mkdir(parents=True, exist_ok=True)
    entries = []
    for pkg in sorted(leaf_packages(output), key=lambda c: c.name):
        cat = pkg.get("资产类别", "uncategorized")
        slug = pkg.get("资产包键", pkg.name)
        pkg["组织版本"] = "v011"
        pkg["未来导出目录"] = str((PACKAGE_ROOT / cat / slug).relative_to(PROJECT))
        folder = PROJECT / pkg["未来导出目录"]
        folder.mkdir(parents=True, exist_ok=True)
        objs = sorted(pkg.objects, key=lambda o: o.name)
        center, size = bbox(objs)
        entry = {
            "asset_id": "ENV-BASE99-ART-LAYOUT-3D",
            "package_id": f"ENV-BASE99-ART-LAYOUT-3D::{slug}",
            "display_name": pkg.name,
            "asset_slug": slug,
            "category": cat,
            "version": "v011",
            "collection_path": pkg.name,
            "future_export_directory": pkg["未来导出目录"],
            "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
            "object_count": len(objs),
            "mesh_count": sum(o.type == "MESH" for o in objs),
            "light_count": sum(o.type == "LIGHT" for o in objs),
            "object_names": [o.name for o in objs],
            "world_center_m": center,
            "bounding_size_m": size,
            "local_origin": "preserve scene master world placement",
            "forward_axis": "Blender +Y north",
            "has_animation": any(o.animation_data and o.animation_data.action for o in objs),
            "expected_export": f"{slug}_visual_top3d_v001.glb",
            "collision_status": "not_authored_in_this_partial_blender_pass",
            "export_status": "not_exported",
        }
        (folder / "asset_manifest.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        entries.append(entry)
    doc = {
        "schema": "shellstorm2.base_facility.component_catalog.v2",
        "organization_version": "v011",
        "source_asset_id": "ENV-BASE99-ART-LAYOUT-3D",
        "scope": "loft facilities and stairs high-fidelity iteration only",
        "package_count": len(entries),
        "floor_tile_package_count": sum(e["category"] == "floor" for e in entries),
        "packages": entries,
    }
    CATALOG.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    TREE.write_text("基地场景独立资产包树 v011\n" + "\n".join(f"{e['category']}/{e['asset_slug']} objects={e['object_count']}" for e in entries) + "\n", encoding="utf-8")
    return doc


def make_camera(name, loc, target, scale):
    coll = bpy.data.collections["90_展示环境_灯光相机"]
    src = bpy.data.objects["基地微缩模型_英雄相机"]
    cam = src.copy()
    cam.data = src.data.copy()
    cam.name = name
    cam.data.name = name
    coll.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    return tag(cam)


def render(camera, path, x=1672, y=941):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = str(path)
    scene.render.resolution_x = x
    scene.render.resolution_y = y
    scene.render.resolution_percentage = 100
    bpy.ops.render.render(write_still=True)


def main():
    if Path(bpy.data.filepath).resolve() != INPUT_BLEND.resolve():
        raise RuntimeError("must start from v010")
    if OUTPUT_BLEND.exists():
        raise RuntimeError(f"target exists: {OUTPUT_BLEND}")
    setup()
    output = bpy.data.collections[OUT10]
    before = locked_signature(output)
    remove_v010_scope(output)
    output.name = OUT11
    base.OUTPUT = output
    loft = ensure_child(output, "30_二楼生活工作设施")
    build_bed(package(loft, 31, "参考床架床品与床下收纳", "loft_bed_and_bedding"))
    build_nightstand(package(loft, 32, "参考床头柜与生活物件", "loft_nightstand"))
    build_bed_lamp(package(loft, 33, "暖橙床头灯", "loft_bedside_lamp"))
    build_rug(package(loft, 34, "床边暖灰地毯", "loft_bedside_rug"), "床边暖灰地毯", (.30, 9.82), (4.25, .84), "warm_gray", 5)
    build_curtain(package(loft, 35, "红紫条纹隔断帘", "loft_striped_privacy_curtain"))
    build_sofa(package(loft, 36, "墨绿三人休闲沙发", "loft_lounge_sofa"))
    build_coffee_table(package(loft, 37, "红棕茶几与生活物件", "loft_coffee_table"))
    build_rug(package(loft, 38, "休闲区低饱和地毯", "loft_lounge_rug"), "休闲区低饱和地毯", (6.18, 9.55), (4.90, 2.45), "purple", 6)
    build_pouf(package(loft, 39, "青绿圆形坐墩01", "loft_pouf_01"), 1, (3.78, 8.55), "teal")
    build_pouf(package(loft, 40, "深绿圆形坐墩02", "loft_pouf_02"), 2, (8.72, 8.62), "green")
    build_side_table(package(loft, 41, "床前辅助小桌", "loft_side_table"))
    build_workstation(package(loft, 42, "双屏电脑完整工位", "loft_computer_workstation"))
    build_office_chair(package(loft, 43, "带扶手办公椅", "loft_office_chair"))
    build_neon(package(loft, 44, "GOOD VIBES霓虹", "loft_good_vibes_neon"))
    build_storage(package(loft, 45, "MEDICAL模块收纳箱", "loft_medical_cabinet"), "MEDICAL", (-3.25, 13.92), "red")
    build_storage(package(loft, 46, "BATTERY模块收纳箱", "loft_battery_cabinet"), "BATTERY", (-1.95, 13.92), "teal")
    build_storage(package(loft, 47, "FOOD模块收纳箱", "loft_food_cabinet"), "FOOD", (-.65, 13.92), "orange")
    build_wall_decor(package(loft, 48, "EXPLORE海报与工具洞洞板", "loft_wall_utility_decor"))
    build_plant(package(loft, 49, "后墙吊挂植物", "loft_hanging_plant"))
    build_loft_lighting(package(loft, 50, "二楼分层照明支持", "loft_lighting_support", "support"))

    stair_group = ensure_child(output, "15_楼梯深化与过渡结构")
    l_stair = next(p for p in leaf_packages(output) if p.get("资产包键") == "northwest_l_stair")
    build_l_stair_detail(l_stair)
    east = package(stair_group, 51, "东侧紧凑上行过渡楼梯", "east_upper_transition_stair", "architecture")
    build_east_stair(east)

    after = locked_signature(output)
    if before != after:
        changed = sorted(k for k in before.keys() & after.keys() if before[k] != after[k])
        raise RuntimeError(f"locked scope changed {changed[:8]} added={sorted(after.keys()-before.keys())[:8]} removed={sorted(before.keys()-after.keys())[:8]}")

    doc = write_catalog(output)
    old_hash = hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()
    new_hash = hashlib.sha256(json.dumps(after, sort_keys=True).encode()).hexdigest()
    LOCK_REPORT.write_text(json.dumps({
        "input": str(INPUT_BLEND.relative_to(PROJECT)),
        "output": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "locked_object_count_v010": len(before),
        "locked_object_count_v011": len(after),
        "locked_match": before == after,
        "locked_signature_v010": old_hash,
        "locked_signature_v011": new_hash,
        "package_count": doc["package_count"],
        "floor_tile_package_count": doc["floor_tile_package_count"],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    refcam = make_camera("基地二楼_参考图高还原验收相机_v011", (-24.5, -24.0, 19.5), (0.6, 10.0, 5.8), 27.2)
    detailcam = make_camera("基地二楼_设施细节验收相机_v011", (-16.5, -13.5, 13.5), (3.7, 11.2, 6.7), 20.8)
    staircam = make_camera("基地二楼_双楼梯接口验收相机_v011", (-23.0, -5.5, 13.5), (-5.5, 12.2, 5.2), 24.0)
    bpy.context.scene["v011_scope"] = "二楼设施与楼梯参考图高还原迭代"
    bpy.context.scene["v011_locked_count"] = len(before)
    bpy.context.scene["v011_package_count"] = doc["package_count"]
    base.SOURCE.hide_viewport = True
    base.SOURCE.hide_render = True
    VERIFY.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    render(refcam, VERIFY / "base_facility_runtime_layout_hq_v011_reference_match.png")
    render(detailcam, VERIFY / "base_facility_runtime_layout_hq_v011_loft_detail.png")
    render(staircam, VERIFY / "base_facility_runtime_layout_hq_v011_stair_interfaces.png")
    render(bpy.data.objects["基地微缩模型_顶视相机"], VERIFY / "base_facility_runtime_layout_hq_v011_top.png", 1600, 1000)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

    SCOPE_REPORT.write_text(json.dumps({
        "status": "built_pending_manual_visual_review",
        "reference_truth": "codex-clipboard-07f86f50-f901-48fa-8940-fef41b91b478.png",
        "scope": "second floor facilities and stairs only",
        "locked_match": True,
        "locked_object_count": len(before),
        "package_count": doc["package_count"],
        "floor_tile_package_count": doc["floor_tile_package_count"],
        "required_render": "base_facility_runtime_layout_hq_v011_reference_match.png",
        "visual_acceptance_dimensions": [
            "structure", "silhouette", "scale", "position", "orientation", "spacing",
            "mechanical_detail", "functional_detail", "materials", "color", "roughness",
            "surface_detail", "labels", "icons", "wear", "lighting", "visual_density", "Q-style"
        ],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE_FACILITY_V011_BUILT packages={doc['package_count']} locked={len(before)}")


if __name__ == "__main__":
    main()
