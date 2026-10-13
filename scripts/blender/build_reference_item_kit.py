"""参考图 31 件低模道具总母版构建器（v003：饱满体块版）。

本版造型规则（相对 v002 的迭代）：
- 去掉全部"细小图案"几何：兔标、星星、闪电、心形挂件、蓝图细线稿一律不再建面。
- 三角面全部投到大轮廓上：用倒角体块、多边圆柱/圆锥、粗拱件把形体做饱满。
- 禁止薄边：任何几何的最小尺寸不小于 MIN_THICKNESS，标识类不再用薄贴片。

其他约束：
- 每个独立资产 <= 100 triangles（最终求值网格 loop_triangles）。
- 每件资产独立 Collection + 独立 ItemRoot，按 9x4 阵列摆放；网格顶点在各自 ItemRoot 局部居中。
- tier_0_static：无骨架、无动画、无碰撞、无玩法脚本。
- 颜色统一走项目公共色盘，PaletteUV + Closest。
"""
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[2]
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
OUT_DIR = ROOT / "art_source/items_weapons/props/reference_kit/source"
OUT = OUT_DIR / "prp_reference_item_kit_source_v001.blend"
MANIFEST = OUT_DIR / "reference_item_kit_source_manifest.json"
CONTRACT = OUT_DIR / "asset_contract.json"
REFERENCE_IMAGE = "C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-10-13T10-34-36-193Z-1dc7482b.jpg"

TRIANGLE_BUDGET = 100
MIN_THICKNESS = 0.025  # 任何几何的最小尺寸下限，用于杜绝薄边

ROOT_NAME = "PRP_参考物品套件_中文资产管理"
COL_AUTHOR = "01_制作组件_已统一材质"
COL_OUTPUT = "02_游戏输出_整合模型"
COL_RIG = "10_骨骼与动画"
COL_SOCKET = "80_挂点_交互接口"
COL_STAGE = "90_展示环境_灯光相机"
ROLES = [COL_AUTHOR, COL_OUTPUT, COL_RIG, COL_SOCKET]

PROP_ROLES = {
    "metal": "01_精工金属_道具骨架",
    "matte": "02_细腻哑光_道具大面",
    "gloss": "03_清漆反光_道具点缀",
    "glow": "04_柔和自发光_道具UI",
}
BAG_ROLES = {
    "metal": "01_精工金属_紫色骨架",
    "matte": "02_细腻哑光_青绿大面",
    "gloss": "03_清漆反光_紫粉点缀",
    "glow": "04_柔和自发光_UI灯光",
}

CELL_HEX = {
    "pink":         (5, 0, "#B25C7B"),
    "pink_light":   (7, 8, "#AE7B98"),
    "plum":         (1, 8, "#7A407D"),
    "magenta":      (4, 8, "#9C4AA3"),
    "blue":         (8, 0, "#5C83AF"),
    "blue_dark":    (0, 6, "#2B4A6E"),
    "blue_light":   (7, 6, "#8A9EB1"),
    "purple":       (2, 0, "#785CB2"),
    "purple_light": (7, 7, "#9287B0"),
    "purple_deep":  (1, 7, "#5C2274"),
    "teal":         (1, 0, "#009C93"),
    "teal_light":   (6, 5, "#46A3AC"),
    "green":        (3, 4, "#38825C"),
    "green_light":  (6, 4, "#65A782"),
    "yellow":       (6, 0, "#B2A42B"),
    "gold":         (4, 0, "#B27F00"),
    "amber":        (4, 3, "#A0861C"),
    "wood":         (1, 2, "#805035"),
    "wood_dark":    (0, 2, "#6F4A1C"),
    "white":        (9, 9, "#E3E7EC"),
    "paper":        (9, 8, "#D1D9E1"),
    "gray_light":   (9, 4, "#94A2B1"),
    "gray":         (9, 3, "#8796A5"),
    "gray_dark":    (9, 2, "#7A8898"),
    "dark":         (0, 9, "#2B2B40"),
    "red":          (4, 1, "#A74263"),
    "deep_red":     (0, 1, "#6F3244"),
    "cyan":         (3, 0, "#46A3B1"),
    "steel":        (8, 0, "#5C83AF"),
}


def cell(name):
    entry = CELL_HEX[name]
    return (entry[0], entry[1])


def cell_hex(name):
    return CELL_HEX[name][2]


# ---------------------------------------------------------------- 底座图元

def _uv_mesh(mesh, cell_pair):
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    uv = mesh.uv_layers.new(name="PaletteUV")
    uv.active = True
    uv.active_render = True
    cx = (cell_pair[0] + 0.5) / 10.0
    cy = 1.0 - (cell_pair[1] + 0.5) / 10.0
    for poly in mesh.polygons:
        n = max(3, len(poly.loop_indices))
        for i, loop_index in enumerate(poly.loop_indices):
            a = (i / n) * math.tau
            uv.data[loop_index].uv = (cx + 0.024 * math.cos(a), cy + 0.024 * math.sin(a))


def _finish(name, verts, faces, material, collection, cell_name, center, rot):
    origin = Vector(center)
    if rot:
        matrix = Euler(rot, "XYZ").to_matrix()
        verts = [tuple(matrix @ Vector(v) + origin) for v in verts]
    else:
        verts = [tuple(Vector(v) + origin) for v in verts]
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.validate(verbose=False)
    mesh.update(calc_edges=True)
    _uv_mesh(mesh, cell(cell_name))
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj["palette_uv"] = "PaletteUV"
    obj["palette_cell"] = list(cell(cell_name))
    obj["palette_cell_hex"] = cell_hex(cell_name)
    return obj


def box(name, size, center, material, collection, cell_name, rot=None):
    x, y, z = [v * 0.5 for v in size]
    verts = [(sx * x, sy * y, sz * z) for sx, sy, sz in
             [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
              (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7)]
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def _beveled_box(name, size, center, material, collection, cell_name, cham,
                 vertical_only=False, rot=None):
    """倒角体块：segments=1 全边倒角 44 三角面，仅竖边倒角 28 三角面。"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for vert in bm.verts:
        vert.co.x *= size[0]
        vert.co.y *= size[1]
        vert.co.z *= size[2]
    edges = list(bm.edges)
    if vertical_only:
        edges = [e for e in edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-6]
    bmesh.ops.bevel(bm, geom=edges, offset=cham, offset_type="OFFSET", segments=1,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    bm.verts.index_update()
    bm.faces.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def cham_box(name, size, center, material, collection, cell_name, cham=None, rot=None):
    """全边倒角体块：饱满、无尖锐棱、无薄边。"""
    cham = cham if cham else min(size) * 0.22
    return _beveled_box(name, size, center, material, collection, cell_name, cham, False, rot)


def round_box(name, size, center, material, collection, cell_name, cham=None, rot=None):
    """仅竖边倒角体块：更省面，仍无尖锐竖棱。"""
    cham = cham if cham else min(size[0], size[1]) * 0.24
    return _beveled_box(name, size, center, material, collection, cell_name, cham, True, rot)


def _axis_map(p, axis):
    if axis == "x":
        return (p[2], p[0], p[1])
    if axis == "y":
        return (p[0], p[2], p[1])
    return p


def cyl(name, radius, depth, center, material, collection, cell_name, sides=8, axis="z", rot=None):
    verts = []
    for z in (-depth * 0.5, depth * 0.5):
        for i in range(sides):
            a = math.tau * i / sides
            verts.append(_axis_map((radius * math.cos(a), radius * math.sin(a), z), axis))
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i) for i in range(sides)]
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides, sides * 2)))
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def cone(name, r1, r2, depth, center, material, collection, cell_name, sides=8, axis="z", rot=None):
    verts = []
    for z, r in ((-depth * 0.5, r1), (depth * 0.5, r2)):
        for i in range(sides):
            a = math.tau * i / sides
            verts.append(_axis_map((r * math.cos(a), r * math.sin(a), z), axis))
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i) for i in range(sides)]
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides, sides * 2)))
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def barrel(name, r1, r2, r3, depth, center, material, collection, cell_name, sides=8, axis="z", rot=None):
    """三段圆桶（下段 → 中段鼓起 → 上段收缩），一次做出饱满腰身。"""
    verts = []
    levels = ((-depth * 0.5, r1), (0.0, r2), (depth * 0.5, r3))
    for z, r in levels:
        for i in range(sides):
            a = math.tau * i / sides
            verts.append(_axis_map((r * math.cos(a), r * math.sin(a), z), axis))
    faces = []
    for layer in (0, 1):
        base = layer * sides
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((base + i, base + j, base + sides + j, base + sides + i))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides * 2, sides * 3)))
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def prism(name, points, depth, center, material, collection, cell_name, axis="z", rot=None):
    n = len(points)
    verts = []
    for d in (-depth * 0.5, depth * 0.5):
        for px, py in points:
            if axis == "z":
                verts.append((px, py, d))
            elif axis == "y":
                verts.append((px, d, py))
            else:
                verts.append((d, px, py))
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def ring(name, r_out, r_in, depth, center, material, collection, cell_name, sides=8, axis="z"):
    verts = []
    for d in (-depth * 0.5, depth * 0.5):
        for r in (r_out, r_in):
            for i in range(sides):
                a = math.tau * i / sides
                verts.append(_axis_map((r * math.cos(a), r * math.sin(a), d), axis))
    faces = []
    for layer in (0, 1):
        base = layer * sides * 2
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((base + i, base + j, base + sides + j, base + sides + i))
    return _finish(name, verts, faces, material, collection, cell_name, center, None)


def hex_profile(scale, squash=0.86):
    pts = [(-1.0, 0.0), (-0.62, 0.86), (0.62, 0.86), (1.0, 0.0), (0.62, -0.86), (-0.62, -0.86)]
    return [(x * scale, y * scale * squash) for x, y in pts]


def heart_profile(scale):
    return [(0.0, -1.0 * scale), (0.92 * scale, -0.06 * scale), (0.52 * scale, 0.88 * scale),
            (0.0, 0.44 * scale), (-0.52 * scale, 0.88 * scale), (-0.92 * scale, -0.06 * scale)]


# ---------------------------------------------------------------- 材质

def make_material(name, metallic, roughness, emission=0.0, coat=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    image = bpy.data.images.get(PALETTE.name) or bpy.data.images.load(str(PALETTE))
    image.filepath = str(PALETTE)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    tex = nodes.new("ShaderNodeTexImage")
    tex.name = "SharedPalette_Closest"
    tex.image = image
    tex.interpolation = "Closest"
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    links.new(uv.outputs["UV"], tex.inputs["Vector"])
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emission > 0:
        if "Emission Color" in bsdf.inputs:
            links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission
    material["palette_source"] = "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
    material["interpolation"] = "Closest"
    return material


def build_material_sets():
    sets = {}
    for key, roles in (("prop", PROP_ROLES), ("bag", BAG_ROLES)):
        sets[key] = {
            "metal": make_material(roles["metal"], 0.85, 0.28),
            "matte": make_material(roles["matte"], 0.0, 0.66),
            "gloss": make_material(roles["gloss"], 0.20, 0.16, 0.0, 0.20),
            "glow": make_material(roles["glow"], 0.0, 0.38, 1.5),
        }
    return sets


def handle_three(name, width, height, bar_y, depth, top_z, material, collection, cell_name):
    """三段粗拱提手：两根方柱 + 一根横梁，全部厚实无薄边（36 三角面）。"""
    post = width * 0.16
    box(name + "_左柱", (post, depth, height), (-width * 0.5 + post * 0.5, bar_y, top_z + height * 0.5),
        material, collection, cell_name)
    box(name + "_右柱", (post, depth, height), (width * 0.5 - post * 0.5, bar_y, top_z + height * 0.5),
        material, collection, cell_name)
    box(name + "_横梁", (width, depth, height * 0.42), (0, bar_y, top_z + height * 0.79),
        material, collection, cell_name)


# ---------------------------------------------------------------- 造型

def build_potion(out, m):
    body_h = 0.24
    cyl("药瓶瓶身", 0.130, body_h, (0, 0, -0.06), m["matte"], out, "pink", 8)
    cone("药瓶肩部", 0.130, 0.062, 0.075, (0, 0, 0.098), m["matte"], out, "pink", 8)
    cyl("药瓶瓶口", 0.062, 0.045, (0, 0, 0.158), m["metal"], out, "gray_light", 6)
    # 心形瓶颈盖属于大轮廓的一部分，厚度 0.085 保持厚实。
    prism("心形瓶盖", heart_profile(0.085), 0.085, (0, 0, 0.222), m["gloss"], out, "red", axis="y")


def build_ammo(out, m):
    cham_box("弹药木箱", (0.40, 0.21, 0.20), (0, 0, -0.035), m["matte"], out, "wood", 0.030)
    for i, x in enumerate((-0.135, -0.045, 0.045, 0.135)):
        cyl("弹药_%d" % i, 0.030, 0.105, (x, 0, 0.115), m["metal"], out, "gold", 4)


def build_battery_small(out, m):
    barrel("电池瓶身", 0.072, 0.086, 0.072, 0.245, (0, 0, -0.02), m["matte"], out, "purple", 8)
    cone("电池正极凸头", 0.045, 0.020, 0.060, (0, 0, 0.132), m["gloss"], out, "gold", 6)
    cyl("电池顶环", 0.082, 0.032, (0, 0, 0.090), m["metal"], out, "blue", 6)
    cyl("电池底盖", 0.078, 0.030, (0, 0, -0.146), m["metal"], out, "blue", 4)


def build_battery_large(out, m):
    barrel("电池瓶身", 0.096, 0.112, 0.096, 0.285, (0, 0, -0.035), m["matte"], out, "blue", 6)
    cyl("电池顶盖", 0.100, 0.048, (0, 0, 0.130), m["metal"], out, "gold", 8)
    handle_three("电池提手", 0.19, 0.055, 0.0, 0.052, 0.154, m["metal"], out, "gold")


def build_cell_pack(out, m):
    cham_box("电芯包箱体", (0.31, 0.21, 0.185), (0, 0, -0.040), m["matte"], out, "purple", 0.032)
    handle_three("电芯包提手", 0.16, 0.052, 0.0, 0.048, 0.055, m["metal"], out, "gold")
    box("电芯包卡扣", (0.070, 0.050, 0.060), (0.098, -0.098, -0.062), m["metal"], out, "gold")


def build_beacon(out, m):
    cyl("信标底座", 0.138, 0.052, (0, 0, -0.140), m["metal"], out, "blue", 6)
    round_box("信标机身", (0.215, 0.215, 0.072), (0, 0, -0.079), m["matte"], out, "white", 0.028)
    cone("信标灯罩", 0.104, 0.054, 0.120, (0, 0, 0.016), m["glow"], out, "cyan", 8)
    cone("信标顶灯", 0.054, 0.024, 0.055, (0, 0, 0.104), m["glow"], out, "red", 6)


def build_key(out, m):
    ring("钥匙环", 0.072, 0.038, 0.042, (-0.115, 0, 0), m["metal"], out, "steel", 8)
    box("钥匙杆", (0.185, 0.048, 0.042), (0.030, 0, 0), m["metal"], out, "gold")
    box("钥匙牌", (0.070, 0.052, 0.075), (-0.020, 0, 0), m["metal"], out, "gold")
    box("钥匙齿一", (0.048, 0.086, 0.042), (0.108, -0.028, 0), m["metal"], out, "gold")
    box("钥匙齿二", (0.048, 0.062, 0.042), (0.040, -0.020, 0), m["metal"], out, "gold")


def build_backpack(out, m, slots, w, d, h):
    body_cell = "pink" if slots == 2 else "blue" if slots == 4 else "teal"
    if slots == 2:
        round_box("背包主体", (w * 0.84, d * 0.76, h * 0.66), (0, 0, -h * 0.05),
                  m["matte"], out, body_cell)
        cham_box("前袋", (w * 0.50, d * 0.30, h * 0.30), (0, -d * 0.40, -h * 0.10),
                 m["gloss"], out, "pink_light", 0.030)
        box("左侧袋", (w * 0.19, d * 0.44, h * 0.26), (-w * 0.47, 0, -h * 0.05), m["gloss"], out, "white")
        box("右侧袋", (w * 0.19, d * 0.44, h * 0.26), (w * 0.47, 0, -h * 0.05), m["gloss"], out, "white")
    elif slots == 4:
        round_box("背包主体", (w * 0.84, d * 0.76, h * 0.66), (0, 0, -h * 0.05),
                  m["matte"], out, body_cell)
        cham_box("前袋", (w * 0.48, d * 0.30, h * 0.30), (0, -d * 0.40, -h * 0.10),
                 m["gloss"], out, "pink_light", 0.030)
        box("顶部提手", (w * 0.40, d * 0.16, h * 0.085), (0, 0, h * 0.385), m["metal"], out, "gold")
    else:
        cham_box("背包主体", (w * 0.84, d * 0.76, h * 0.62), (0, 0, -h * 0.06),
                 m["matte"], out, body_cell, 0.040)
        round_box("前袋", (w * 0.46, d * 0.28, h * 0.28), (0, -d * 0.40, -h * 0.11),
                  m["gloss"], out, "pink_light", 0.030)
        cyl("顶部卷铺盖", w * 0.235, w * 0.40, (0, 0, h * 0.40), m["matte"], out, "teal_light", 6, axis="x")


def build_flashlight(out, m, variant):
    body_cell = {"basic": "gray_dark", "efficient": "blue", "advanced": "purple_deep"}[variant]
    barrel("手电筒身", 0.044, 0.052, 0.044, 0.215, (-0.020, 0, 0),
           m["metal"], out, body_cell, 6, axis="x")
    cone("手电头锥", 0.078, 0.060, 0.062, (0.116, 0, 0), m["metal"], out, "dark", 8, axis="x")
    cyl("手电镜片", 0.068, 0.024, (0.155, 0, 0), m["glow"], out, "cyan", 6, axis="x")
    cyl("手电尾盖", 0.050, 0.034, (-0.145, 0, 0), m["metal"], out, "gray", 4, axis="x")


def build_bullet(out, m, variant):
    spec = {
        "standard":  ("steel", "gold", "paper"),
        "sticky":    ("green", "green_light", "green"),
        "bounce":    ("pink", "pink_light", "steel"),
        "piercing":  ("gray_dark", "purple_deep", "white"),
        "explosive": ("red", "deep_red", "amber"),
        "balloon":   ("pink_light", "pink", "white"),
    }[variant]
    if variant == "explosive":
        cyl("弹体", 0.062, 0.155, (-0.060, 0, 0), m["matte"], out, spec[0], 8, axis="x")
        cone("尖锥弹头", 0.062, 0.020, 0.115, (0.075, 0, 0), m["matte"], out, spec[1], 8, axis="x")
        cyl("弹体环带", 0.070, 0.030, (-0.010, 0, 0), m["metal"], out, "amber", 6, axis="x")
        cyl("弹底缘", 0.070, 0.028, (-0.132, 0, 0), m["metal"], out, "dark", 6, axis="x")
        return
    if variant == "balloon":
        cyl("气球球体", 0.076, 0.105, (0.080, 0, 0), m["matte"], out, "pink", 8, axis="x")
        cone("气球气嘴", 0.030, 0.046, 0.045, (0.014, 0, 0), m["metal"], out, "pink_light", 4, axis="x")
        cyl("弹壳", 0.050, 0.095, (-0.058, 0, 0), m["metal"], out, "steel", 8, axis="x")
        cyl("弹底缘", 0.058, 0.028, (-0.112, 0, 0), m["metal"], out, "dark", 6, axis="x")
        return
    cyl("弹壳", 0.056, 0.135, (-0.058, 0, 0), m["metal"], out, spec[0], 8, axis="x")
    if variant == "piercing":
        cone("穿甲长锥", 0.056, 0.014, 0.165, (0.080, 0, 0), m["matte"], out, spec[1], 8, axis="x")
        cyl("弹底缘", 0.062, 0.028, (-0.122, 0, 0), m["metal"], out, "dark", 6, axis="x")
        cyl("弹壳环带", 0.064, 0.026, (-0.006, 0, 0), m["metal"], out, "paper", 6, axis="x")
        return
    cone("弹头", 0.056, 0.014, 0.125, (0.072, 0, 0), m["matte"], out, spec[1], 8, axis="x")
    if variant == "bounce":
        ring("回旋尾环", 0.078, 0.056, 0.058, (-0.108, 0, 0), m["gloss"], out, spec[2], 6, axis="x")
        cyl("弹体", 0.058, 0.075, (-0.046, 0, 0), m["metal"], out, "dark", 4, axis="x")
    elif variant == "sticky":
        cyl("黏液体环", 0.074, 0.038, (0.012, 0, 0), m["gloss"], out, "green_light", 4, axis="x")
        cyl("弹底缘", 0.062, 0.028, (-0.122, 0, 0), m["metal"], out, "dark", 4, axis="x")
        cyl("黏液滴", 0.030, 0.062, (0.046, 0, 0), m["gloss"], out, "green", 4, axis="x")
    else:
        cyl("弹壳环带", 0.064, 0.026, (-0.006, 0, 0), m["gloss"], out, "paper", 6, axis="x")
        cyl("弹底缘", 0.062, 0.028, (-0.122, 0, 0), m["metal"], out, "dark", 6, axis="x")


def build_attachment(out, m, variant):
    if variant == "triple_muzzle":
        round_box("三叉底座", (0.128, 0.200, 0.190), (-0.071, 0, 0), m["metal"], out, "dark", 0.038)
        for i, (y, z) in enumerate(((-0.062, 0.052), (0.0, 0.0), (0.062, -0.052))):
            cyl("三叉枪管_%d" % i, 0.036, 0.150, (0.050, y, z), m["metal"], out, "pink", 5, axis="x")
        cyl("三叉口环", 0.048, 0.032, (0.122, 0.0, 0.0), m["gloss"], out, "gold", 6, axis="x")
    elif variant == "rubber_stock":
        cham_box("枪托主体", (0.235, 0.158, 0.162), (0.020, 0, -0.005), m["matte"], out, "purple", 0.032)
        round_box("枪托尾盖", (0.058, 0.185, 0.195), (-0.134, 0, 0), m["gloss"], out, "pink", 0.036)
        box("枪托上沿", (0.215, 0.130, 0.048), (0.020, 0, 0.090), m["matte"], out, "purple_deep")
    elif variant == "scope":
        cyl("瞄具镜筒", 0.056, 0.185, (0, 0, 0.010), m["metal"], out, "steel", 8, axis="x")
        cyl("瞄具前镜圈", 0.072, 0.034, (0.092, 0, 0.010), m["metal"], out, "pink", 6, axis="x")
        cyl("瞄具后镜圈", 0.064, 0.030, (-0.090, 0, 0.010), m["metal"], out, "pink", 6, axis="x")
        round_box("瞄具支架", (0.085, 0.100, 0.070), (0, 0, -0.062), m["metal"], out, "dark", 0.032)
    elif variant == "big_mag":
        cham_box("弹匣主体", (0.170, 0.140, 0.275), (0, 0, 0), m["matte"], out, "purple", 0.034)
        round_box("弹匣底板", (0.202, 0.165, 0.052), (0, 0, -0.152), m["metal"], out, "dark", 0.026)
        box("弹匣顶盖", (0.185, 0.150, 0.048), (0, 0, 0.150), m["metal"], out, "pink")
    elif variant == "fan":
        # 风扇朝向 -Y：八边厚底板 + 三片厚叶片 + 中央厚轮毂，整体饱满不留空心薄环。
        cyl("风扇底板", 0.106, 0.070, (0, 0.016, 0), m["metal"], out, "dark", 8, axis="y")
        for i in range(3):
            a = math.tau * i / 3
            box("风扇叶片_%d" % i, (0.062, 0.056, 0.036),
                (0.052 * math.cos(a), -0.024, 0.052 * math.sin(a)),
                m["gloss"], out, "cyan", rot=(0.0, -a, 0.0))
        cone("风扇轮毂", 0.048, 0.026, 0.055, (0, -0.032, 0), m["gloss"], out, "pink", 8, axis="y")
    else:
        cham_box("贴纸底板", (0.212, 0.070, 0.242), (0, 0.006, 0), m["gloss"], out, "purple", 0.030)
        cham_box("贴纸面板", (0.176, 0.062, 0.204), (0.012, -0.036, 0.006), m["gloss"], out, "pink", 0.026)


def build_blueprint(out, m, variant):
    """厚六边牌：外框 + 凸起内板 + 变体粗浮雕。牌体本身加厚，不出现薄片。"""
    card_cell = {"pistol": "blue", "shotgun": "purple_light", "rifle": "pink",
                 "machinegun": "blue_dark", "sniper": "purple", "launcher": "deep_red"}[variant]
    prism("蓝图外框", hex_profile(0.158), 0.090, (0, 0, 0), m["metal"], out, "paper", axis="y")
    prism("蓝图内板", hex_profile(0.132), 0.076, (0, -0.022, 0), m["matte"], out, card_cell, axis="y")
    # 变体浮雕：粗块，最小边 0.032，全部落在内板正面。
    box("浮雕机匣", (0.066, 0.032, 0.036), (-0.014, -0.070, 0.026), m["gloss"], out, "white")
    if variant == "shotgun":
        box("浮雕双管", (0.084, 0.032, 0.028), (0.082, -0.070, 0.030), m["gloss"], out, "white")
        box("浮雕副管", (0.084, 0.032, 0.028), (0.082, -0.070, -0.006), m["gloss"], out, "white")
    elif variant == "machinegun":
        cyl("浮雕弹鼓", 0.040, 0.032, (-0.014, -0.070, -0.038), m["gloss"], out, "white", 4, axis="y")
        box("浮雕枪管", (0.084, 0.032, 0.028), (0.082, -0.070, 0.030), m["gloss"], out, "white")
    elif variant == "sniper":
        box("浮雕长管", (0.092, 0.032, 0.026), (0.086, -0.070, 0.030), m["gloss"], out, "white")
        cyl("浮雕瞄具", 0.030, 0.032, (-0.014, -0.070, 0.072), m["gloss"], out, "white", 4, axis="y")
    elif variant == "launcher":
        cyl("浮雕粗管", 0.048, 0.032, (0.078, -0.070, 0.028), m["gloss"], out, "white", 4, axis="y")
        box("浮雕握把", (0.030, 0.032, 0.056), (-0.078, -0.070, -0.038), m["gloss"], out, "white")
    else:
        box("浮雕枪管", (0.084, 0.032, 0.028), (0.082, -0.070, 0.030), m["gloss"], out, "white")
        box("浮雕握把", (0.030, 0.032, 0.056), (-0.078, -0.070, -0.038), m["gloss"], out, "white")


# ---------------------------------------------------------------- 清单与阵列

CATALOG = [
    ("item_health_potion", "治疗药水", "消耗品", "", (0.34, 0.22, 0.44), (0, 0), "potion"),
    ("item_ammo_pack", "通用弹药", "消耗品", "", (0.42, 0.22, 0.28), (1, 0), "ammo"),
    ("item_battery_s", "小型电池", "消耗品", "", (0.18, 0.18, 0.34), (2, 0), "battery_s"),
    ("item_battery_l", "大型电池", "消耗品", "", (0.26, 0.24, 0.42), (0, 1), "battery_l"),
    ("item_cell_pack", "电芯包", "消耗品", "", (0.34, 0.22, 0.28), (1, 1), "cell_pack"),
    ("item_beacon", "撤离信标", "消耗品", "ITM-CONSUMABLE-ITEM-BEACON", (0.36, 0.30, 0.34), (2, 1), "beacon"),

    ("item_room_key", "房间钥匙", "钥匙与背包", "ITM-KEY-ITEM-ROOM-KEY", (0.38, 0.14, 0.10), (3, 0), "key"),
    ("equipment_backpack_2", "轻型腰包(+2格)", "钥匙与背包", "ITM-EQUIPMENT-BACKPACK-SMALL-3D", (0.56, 0.28, 0.60), (4, 0), "backpack"),
    ("equipment_backpack_4", "战术背包(+4格)", "钥匙与背包", "ITM-EQUIPMENT-BACKPACK-MEDIUM-3D", (0.66, 0.33, 0.74), (5, 0), "backpack"),
    ("equipment_backpack_8", "远征背包(+8格)", "钥匙与背包", "ITM-EQUIPMENT-BACKPACK-LARGE-3D", (0.76, 0.38, 0.88), (4, 1), "backpack"),

    ("item_flashlight_basic", "基础手电模块", "手电配件", "", (0.36, 0.17, 0.17), (6, 0), "flashlight:basic"),
    ("item_flashlight_efficient", "节能手电模块", "手电配件", "", (0.36, 0.17, 0.17), (7, 0), "flashlight:efficient"),
    ("item_flashlight_advanced", "加强模块", "手电配件", "", (0.36, 0.17, 0.17), (8, 0), "flashlight:advanced"),

    ("mod_bullet_standard", "标准子弹模块", "子弹模块", "", (0.30, 0.13, 0.13), (0, 2), "bullet:standard"),
    ("mod_bullet_sticky", "黏黏弹模块", "子弹模块", "", (0.30, 0.14, 0.16), (1, 2), "bullet:sticky"),
    ("mod_bullet_bounce", "回旋镖弹模块", "子弹模块", "", (0.30, 0.16, 0.16), (2, 2), "bullet:bounce"),
    ("mod_bullet_piercing", "穿甲弹模块", "子弹模块", "", (0.30, 0.13, 0.13), (0, 3), "bullet:piercing"),
    ("mod_bullet_explosive", "爆炸弹模块", "子弹模块", "", (0.30, 0.15, 0.15), (1, 3), "bullet:explosive"),
    ("mod_bullet_balloon", "气球弹模块", "子弹模块", "", (0.28, 0.16, 0.16), (2, 3), "bullet:balloon"),

    ("attach_triple_muzzle", "三叉枪口", "配件", "", (0.28, 0.21, 0.19), (3, 2), "attachment:triple_muzzle"),
    ("attach_rubber_stock", "橡皮枪托", "配件", "", (0.32, 0.17, 0.19), (4, 2), "attachment:rubber_stock"),
    ("attach_scope", "放大镜瞄具", "配件", "", (0.24, 0.15, 0.19), (5, 2), "attachment:scope"),
    ("attach_big_mag", "肉质弹匣", "配件", "", (0.21, 0.15, 0.32), (3, 3), "attachment:big_mag"),
    ("attach_fan", "小风扇", "配件", "", (0.23, 0.13, 0.23), (4, 3), "attachment:fan"),
    ("attach_copy_sticker", "复制贴纸", "配件", "", (0.22, 0.07, 0.25), (5, 3), "attachment:copy_sticker"),

    ("bp_pistol", "豌豆手枪蓝图碎片", "蓝图碎片", "WPN-GUN-BP-PISTOL", (0.34, 0.13, 0.28), (6, 2), "blueprint:pistol"),
    ("bp_shotgun", "散射喷壶蓝图碎片", "蓝图碎片", "WPN-GUN-BP-SHOTGUN", (0.34, 0.13, 0.28), (7, 2), "blueprint:shotgun"),
    ("bp_rifle", "步枪蓝图碎片", "蓝图碎片", "WPN-GUN-BP-RIFLE", (0.34, 0.13, 0.28), (8, 2), "blueprint:rifle"),
    ("bp_machinegun", "蜂窝机枪蓝图碎片", "蓝图碎片", "WPN-GUN-BP-MACHINEGUN", (0.34, 0.13, 0.28), (6, 3), "blueprint:machinegun"),
    ("bp_sniper", "弹弓狙击蓝图碎片", "蓝图碎片", "WPN-GUN-BP-SNIPER", (0.34, 0.13, 0.28), (7, 3), "blueprint:sniper"),
    ("bp_launcher", "反胃榴弹筒蓝图碎片", "蓝图碎片", "WPN-GUN-BP-LAUNCHER", (0.34, 0.13, 0.28), (8, 3), "blueprint:launcher"),
]

COL_PITCH = 1.35
ROW_Y = {0: 2.45, 1: 1.15, 2: -0.95, 3: -2.25}
PANEL_SHIFT = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.62, 4: 0.62, 5: 0.62, 6: 1.24, 7: 1.24, 8: 1.24}


def array_position(col, row, dims):
    x = (col - 4) * COL_PITCH + PANEL_SHIFT[col]
    y = ROW_Y[row]
    z = dims[2] * 0.5
    return (round(x, 5), round(y, 5), round(z, 5))


# ---------------------------------------------------------------- 组装

def make_asset_collections(slug, cn):
    holder = bpy.data.collections.new("%s_%s_资产包" % (slug, cn))
    holder["content_id"] = slug
    bpy.data.collections[ROOT_NAME].children.link(holder)
    made = {}
    for role in ROLES:
        child = bpy.data.collections.new("%s__%s" % (slug, role))
        child["collection_role"] = role
        child["asset_content_id"] = slug
        holder.children.link(child)
        made[role] = child
    return holder, made


def make_item_root(slug, cn, asset_id, dims, position, slot):
    holder, colls = make_asset_collections(slug, cn)
    item_root = bpy.data.objects.new("%s__ItemRoot" % slug, None)
    item_root.empty_display_type = "PLAIN_AXES"
    item_root.empty_display_size = 0.12
    item_root.location = position
    colls[COL_SOCKET].objects.link(item_root)
    item_root["semantic_name"] = "ItemRoot"
    item_root["asset_id"] = asset_id or "UNREGISTERED_CONTENT_ONLY"
    item_root["content_id"] = slug
    item_root["display_name_zh"] = cn
    item_root["asset_version"] = "v001"
    item_root["animation_tier"] = "tier_0_static"
    item_root["triangle_budget"] = TRIANGLE_BUDGET
    item_root["dimensions_m"] = list(dims)
    item_root["front_axis"] = "+Z"
    item_root["array_slot"] = [slot[0], slot[1]]
    item_root["array_position_m"] = list(position)
    item_root["style_rule"] = "v003 饱满体块：无细小图案几何、无薄边、三角面投在大轮廓上"
    item_root["export_note"] = "导出前把 ItemRoot.location 归零，或按局部变换导出；阵列坐标不属于资产契约。"
    item_root["style_reference"] = REFERENCE_IMAGE
    return holder, colls, item_root


def normalize_to_contract(output, target_dims):
    meshes = [o for o in output.objects if o.type == "MESH"]
    points = [v.co for o in meshes for v in o.data.vertices]
    if not points:
        raise RuntimeError("资产没有几何：%s" % output.name)
    low = Vector((min(p[i] for p in points) for i in range(3)))
    high = Vector((max(p[i] for p in points) for i in range(3)))
    actual = high - low
    if min(actual) <= 0.0:
        raise RuntimeError("资产存在零尺寸轴：%s" % output.name)
    center = (low + high) * 0.5
    scale = Vector((target_dims[i] / actual[i] for i in range(3)))
    for obj in meshes:
        for vertex in obj.data.vertices:
            vertex.co = Vector(((vertex.co[i] - center[i]) * scale[i] for i in range(3)))
        obj.data.update()


def duplicate_for_authoring(output, author):
    for obj in list(output.objects):
        if obj.type != "MESH":
            continue
        clone = obj.copy()
        clone.data = obj.data.copy()
        clone.name = obj.name + "_制作组件"
        clone["authoring_copy_of"] = obj.name
        author.objects.link(clone)
    author.hide_viewport = True
    author.hide_render = True


def build_asset(entry, materials):
    slug, cn, group, asset_id, dims, slot, shape = entry
    position = array_position(slot[0], slot[1], dims)
    holder, colls, item_root = make_item_root(slug, cn, asset_id, dims, position, slot)
    out = colls[COL_OUTPUT]
    m = materials["bag"] if shape == "backpack" else materials["prop"]
    if shape == "potion":
        build_potion(out, m)
    elif shape == "ammo":
        build_ammo(out, m)
    elif shape == "battery_s":
        build_battery_small(out, m)
    elif shape == "battery_l":
        build_battery_large(out, m)
    elif shape == "cell_pack":
        build_cell_pack(out, m)
    elif shape == "beacon":
        build_beacon(out, m)
    elif shape == "key":
        build_key(out, m)
    elif shape == "backpack":
        build_backpack(out, m, int(slug[-1]), dims[0], dims[1], dims[2])
    elif shape.startswith("flashlight:"):
        build_flashlight(out, m, shape.split(":")[1])
    elif shape.startswith("bullet:"):
        build_bullet(out, m, shape.split(":")[1])
    elif shape.startswith("attachment:"):
        build_attachment(out, m, shape.split(":")[1])
    elif shape.startswith("blueprint:"):
        build_blueprint(out, m, shape.split(":")[1])
    else:
        raise RuntimeError("未知造型：%s" % shape)
    normalize_to_contract(out, dims)
    for obj in out.objects:
        if obj.type == "MESH":
            obj.parent = item_root
    duplicate_for_authoring(out, colls[COL_AUTHOR])
    return holder, colls, item_root, out


def audit(root):
    """按修改器求值后的网格统计三角面，并检查薄边与 UV 契约。"""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    records = {}
    errors = []
    for holder in [c for c in root.children if c.get("content_id")]:
        out = next((c for c in holder.children if c.get("collection_role") == COL_OUTPUT), None)
        sockets = next((c for c in holder.children if c.get("collection_role") == COL_SOCKET), None)
        if out is None or sockets is None:
            errors.append([holder.name, "collection_missing", 0])
            continue
        triangles = 0
        meshes = 0
        uv_bad = []
        thin = []
        roles = set()
        for obj in out.objects:
            if obj.type != "MESH":
                continue
            meshes += 1
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
            local = [v.co for v in mesh.vertices]
            size = [max(p[i] for p in local) - min(p[i] for p in local) for i in range(3)]
            if min(size) < MIN_THICKNESS * 0.9:
                thin.append([obj.name, [round(v, 4) for v in size]])
            evaluated.to_mesh_clear()
            names = [layer.name for layer in obj.data.uv_layers]
            active = obj.data.uv_layers.active.name if obj.data.uv_layers.active else ""
            if names != ["PaletteUV"] or active != "PaletteUV":
                uv_bad.append([obj.name, names])
            for material in obj.data.materials:
                roles.add(material.name)
        item_root = next((o for o in sockets.objects if o.get("semantic_name") == "ItemRoot"), None)
        if item_root is None:
            errors.append([holder.name, "item_root_missing", 0])
        if triangles > TRIANGLE_BUDGET:
            errors.append([holder.name, "triangle_budget", triangles])
        if uv_bad:
            errors.append([holder.name, "uv_layers", uv_bad])
        if thin:
            errors.append([holder.name, "thin_geometry", thin])
        records[holder.name] = {
            "content_id": holder.get("content_id"),
            "triangles": triangles,
            "mesh_parts": meshes,
            "material_roles_used": sorted(roles),
            "array_position_m": list(item_root.location) if item_root else None,
        }
    return records, errors


def build_stage():
    stage = bpy.data.collections.new(COL_STAGE)
    bpy.data.collections[ROOT_NAME].children.link(stage)
    ground = bpy.data.meshes.new("展示地面_Mesh")
    ground.from_pydata([(-8.5, -4.8, 0), (8.5, -4.8, 0), (8.5, 4.8, 0), (-8.5, 4.8, 0)],
                       [], [(0, 1, 2, 3)])
    ground.update()
    ground_obj = bpy.data.objects.new("展示地面", ground)
    ground_obj["stage_only"] = True
    stage.objects.link(ground_obj)

    camera_data = bpy.data.cameras.new("展示相机")
    camera_data.lens = 42
    camera = bpy.data.objects.new("展示相机", camera_data)
    camera.location = (0.6, -11.5, 7.4)
    camera.rotation_euler = (Vector((0.6, 0.1, 0.9)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera["stage_only"] = True
    stage.objects.link(camera)
    bpy.context.scene.camera = camera

    for name, loc, energy, size in (
        ("展示主光", (-4.5, -5.5, 6.5), 1400.0, 6.0),
        ("展示补光", (5.5, -3.0, 4.0), 700.0, 6.0),
        ("展示背光", (0.0, 6.0, 5.0), 900.0, 6.0),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = loc
        light.rotation_euler = (Vector((0.0, 0.0, 0.6)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        light["stage_only"] = True
        stage.objects.link(light)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene["reference_image"] = REFERENCE_IMAGE
    scene["style_contract"] = "饱满体块：无细小图案几何、无薄边；三角面投在大轮廓上；每件 <= 100 三角面"
    scene["array_contract"] = "31 件资产按参考图 6 面板 9 列 x 4 行阵列排布；网格顶点在各 ItemRoot 局部居中"
    scene["runtime_note"] = "仅 Blender 源；GLB/PackedScene/碰撞/玩法属于后续独立阶段"

    root = bpy.data.collections.new(ROOT_NAME)
    scene.collection.children.link(root)
    root["pipeline"] = "game-prop-model-pipeline"
    root["source_version"] = "v001"
    root["style_rule"] = "no_decal_geometry; no_thin_edges; plump_silhouette"
    root["min_geometry_thickness_m"] = MIN_THICKNESS
    root["triangle_budget_per_asset"] = TRIANGLE_BUDGET
    root["asset_count"] = len(CATALOG)
    root["array_layout"] = "9 columns x 4 rows (reference sheet panel layout)"
    root["palette"] = "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

    materials = build_material_sets()

    holders = {}
    for entry in CATALOG:
        holder, colls, item_root, out = build_asset(entry, materials)
        holders[entry[0]] = holder

    records, errors = audit(root)
    build_stage()
    bpy.context.view_layer.update()

    assets = []
    for slug, cn, group, asset_id, dims, slot, shape in CATALOG:
        holder = holders[slug]
        record = records[holder.name]
        assets.append({
            "content_id": slug,
            "display_name_zh": cn,
            "group": group,
            "asset_id": asset_id or None,
            "dimensions_m": {"width": dims[0], "depth": dims[1], "height": dims[2]},
            "triangles": record["triangles"],
            "mesh_parts": record["mesh_parts"],
            "material_roles_used": record["material_roles_used"],
            "animation_tier": "tier_0_static",
            "front_axis": "+Z",
            "source_collection": holder.name,
            "item_root": "%s__ItemRoot" % slug,
            "output_collection_role": COL_OUTPUT,
            "authoring_collection_role": COL_AUTHOR,
            "socket_collection_role": COL_SOCKET,
            "array_slot": {"column": slot[0], "row": slot[1]},
            "array_position_m": {
                "x": record["array_position_m"][0],
                "y": record["array_position_m"][1],
                "z": record["array_position_m"][2],
            },
            "palette": "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
            "uv_layers": ["PaletteUV"],
            "source_version": "v001",
        })

    manifest = {
        "schema": "shellstorm2.reference_item_kit.source_manifest",
        "schema_version": 3,
        "source_blend": "art_source/items_weapons/props/reference_kit/source/prp_reference_item_kit_source_v001.blend",
        "reference_image": REFERENCE_IMAGE,
        "asset_count": len(CATALOG),
        "triangle_budget_per_asset": TRIANGLE_BUDGET,
        "max_triangles_used": max(a["triangles"] for a in assets),
        "style_rule": {
            "decal_geometry": "removed",
            "thin_edges": "forbidden",
            "min_geometry_thickness_m": MIN_THICKNESS,
            "note": "无兔标/星形/闪电/心形挂件等细小图案几何；三角面投入到倒角体块、多边圆柱与粗拱件等大轮廓。",
        },
        "array_layout": {
            "columns": 9,
            "rows": 4,
            "column_pitch_m": COL_PITCH,
            "row_y_m": ROW_Y,
            "panel_shift_m": PANEL_SHIFT,
            "pattern": "参考图 6 个面板按 3 列 x 2 行排布，每面板内含 3 列 x 2 行槽位",
            "rule": "ItemRoot 承担阵列坐标；网格顶点在各自的 ItemRoot 局部居中，母版不叠在同一坐标",
        },
        "assets": assets,
        "unregistered_content_only": [a["content_id"] for a in assets if not a["asset_id"]],
        "errors": errors,
        "notes": [
            "全部资产为 tier_0_static：无骨架、无动画、无碰撞、无玩法脚本。",
            "缺失 AssetID 的内容不擅自编造；账本登记属于独立事务。",
            "三款背包沿用既有稳定 AssetID 与尺寸；本总母版取代其旧单件源，等待导出与导入验收。",
            "展示集合（地面/相机/灯光）只用于审阅，绝不参与导出。",
            "导出前必须把 ItemRoot.location 归零或按局部变换导出，阵列坐标不属于资产契约。",
        ],
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    contract = {
        "schema": "shellstorm2.reference_item_kit.asset_contract",
        "schema_version": 3,
        "display_name_zh": "参考图 31 件低模道具总母版",
        "source_blend": "art_source/items_weapons/props/reference_kit/source/prp_reference_item_kit_source_v001.blend",
        "source_manifest": "art_source/items_weapons/props/reference_kit/source/reference_item_kit_source_manifest.json",
        "reference_image": REFERENCE_IMAGE,
        "asset_count": len(CATALOG),
        "triangle_budget_per_asset": TRIANGLE_BUDGET,
        "min_geometry_thickness_m": MIN_THICKNESS,
        "style_rule": "饱满体块：去掉细小图案几何与薄边，三角面投在大轮廓上",
        "animation_tier": "tier_0_static",
        "array_layout": "9 columns x 4 rows; ItemRoot carries the array position; mesh vertices stay centered on their own ItemRoot",
        "collision_and_gameplay_owner": "Godot runtime / gameplay pipeline",
        "palette": "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
        "palette_interpolation": "Closest",
        "uv_layers": ["PaletteUV"],
        "collection_contract": ROLES,
        "presentation_collection": COL_STAGE,
        "material_role_sets": {"prop": list(PROP_ROLES.values()), "backpack": list(BAG_ROLES.values())},
        "export_recovery": "Zero ItemRoot.location (or export local transforms) before GLB export; array position is presentation-only.",
        "status": "source_verified_pending_glb_and_godot_import",
        "notes": [
            "既有三款背包稳定 AssetID 与尺寸已保留在总源内。",
            "未登记 AssetID 的内容保持未登记，未编造稳定 ID。",
            "展示集合不是导出源。",
            "本契约不宣称任何运行时 GLB、PackedScene、碰撞、账本状态或 Godot 正式验收。",
        ],
    }
    CONTRACT.write_text(json.dumps(contract, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT))
    print("REFERENCE_ITEM_KIT_SOURCE_OK", len(CATALOG), manifest["max_triangles_used"], OUT)
    print("ERRORS", json.dumps(errors, ensure_ascii=False))
    print(json.dumps({a["content_id"]: a["triangles"] for a in assets}, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
