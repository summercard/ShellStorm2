"""参考图 31 件低模道具总母版构建器。

设计约束：
- 每个独立资产 <= 100 triangles（最终求值网格 loop_triangles）。
- 每件资产独立 Collection + 独立 ItemRoot；ItemRoot 按 9x4 阵列摆放，
  网格顶点在各自 ItemRoot 局部居中，母版中不允许所有资产叠在同一坐标。
- tier_0_static：无骨架、无动画、无碰撞、无玩法脚本。
- 造型、配色以参考图为准；颜色统一走项目公共色盘，PaletteUV + Closest。
"""
import json
import math
from pathlib import Path

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

ROOT_NAME = "PRP_参考物品套件_中文资产管理"
COL_AUTHOR = "01_制作组件_已统一材质"
COL_OUTPUT = "02_游戏输出_整合模型"
COL_RIG = "10_骨骼与动画"
COL_SOCKET = "80_挂点_交互接口"
COL_STAGE = "90_展示环境_灯光相机"
ROLES = [COL_AUTHOR, COL_OUTPUT, COL_RIG, COL_SOCKET]

# 道具分支材质角色（06 规范）
PROP_ROLES = {
    "metal": "01_精工金属_道具骨架",
    "matte": "02_细腻哑光_道具大面",
    "gloss": "03_清漆反光_道具点缀",
    "glow": "04_柔和自发光_道具UI",
}
# 三款背包沿用账本已冻结的场景四材质标准名
BAG_ROLES = {
    "metal": "01_精工金属_紫色骨架",
    "matte": "02_细腻哑光_青绿大面",
    "gloss": "03_清漆反光_紫粉点缀",
    "glow": "04_柔和自发光_UI灯光",
}

# 公共色盘 10x10 实测色格：(col, row_from_top) -> 采样十六进制（用于清单核对）
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


# ---------------------------------------------------------------- 图元

def _finish(name, verts, faces, material, collection, cell_name, center, rot):
    origin = Vector(center)
    if rot:
        mat = Euler(rot, "XYZ").to_matrix()
        verts = [tuple(mat @ Vector(v) + origin) for v in verts]
    else:
        verts = [tuple(Vector(v) + origin) for v in verts]
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update(calc_edges=True)
    uv_mesh(mesh, cell(cell_name))
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj["palette_uv"] = "PaletteUV"
    obj["palette_cell"] = list(cell(cell_name))
    obj["palette_cell_hex"] = cell_hex(cell_name)
    return obj


def uv_mesh(mesh, cell_pair):
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


def box(name, size, center, material, collection, cell_name, rot=None):
    x, y, z = [v * 0.5 for v in size]
    verts = [(sx * x, sy * y, sz * z) for sx, sy, sz in
             [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
              (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7)]
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def _axis_map(p, axis):
    if axis == "x":
        return (p[2], p[0], p[1])
    if axis == "y":
        return (p[0], p[2], p[1])
    return p


def cyl(name, radius, depth, center, material, collection, cell_name, sides=6, axis="z", rot=None):
    verts = []
    for z in (-depth * 0.5, depth * 0.5):
        for i in range(sides):
            a = math.tau * i / sides
            verts.append(_axis_map((radius * math.cos(a), radius * math.sin(a), z), axis))
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i) for i in range(sides)]
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides, sides * 2)))
    return _finish(name, verts, faces, material, collection, cell_name, center, rot)


def cone(name, r1, r2, depth, center, material, collection, cell_name, sides=6, axis="z", rot=None):
    verts = []
    for z, r in ((-depth * 0.5, r1), (depth * 0.5, r2)):
        for i in range(sides):
            a = math.tau * i / sides
            verts.append(_axis_map((r * math.cos(a), r * math.sin(a), z), axis))
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i) for i in range(sides)]
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides, sides * 2)))
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


def ring(name, r_out, r_in, depth, center, material, collection, cell_name, sides=6):
    verts = []
    for d in (-depth * 0.5, depth * 0.5):
        for r in (r_out, r_in):
            for i in range(sides):
                a = math.tau * i / sides
                verts.append((r * math.cos(a), r * math.sin(a), d))
    faces = []
    for layer in (0, 1):
        base = layer * sides * 2
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((base + i, base + j, base + sides + j, base + sides + i))
    return _finish(name, verts, faces, material, collection, cell_name, center, None)


# ---------------------------------------------------------------- 识别标识

# 标识贴片使用绝对厚度，保证一定穿透宿主表面而不是被埋进主体。
DECAL_THICKNESS = 0.03


def bunny(name, center, scale, material, collection, cell_name, axis="y"):
    """七顶点兔子剪影：两耳 + 头 + 下颌。"""
    s = scale
    pts = [(-0.84 * s, -0.70 * s), (0.84 * s, -0.70 * s), (0.78 * s, 0.26 * s),
           (0.40 * s, 1.45 * s), (0.06 * s, 0.40 * s), (-0.40 * s, 1.45 * s), (-0.78 * s, 0.26 * s)]
    return prism(name, pts, DECAL_THICKNESS, center, material, collection, cell_name, axis)


def heart(name, center, scale, material, collection, cell_name, axis="y"):
    s = scale
    pts = [(0.0, -1.0 * s), (0.92 * s, -0.06 * s), (0.52 * s, 0.88 * s),
           (0.0, 0.44 * s), (-0.52 * s, 0.88 * s), (-0.92 * s, -0.06 * s)]
    return prism(name, pts, DECAL_THICKNESS, center, material, collection, cell_name, axis)


def star(name, center, scale, material, collection, cell_name, axis="y"):
    """十顶点五角星（+36 三角面）：只在预算充裕且识别性最强的位置使用。"""
    pts = []
    for i in range(10):
        a = math.pi * 0.5 + math.tau * i / 10
        r = scale if i % 2 == 0 else scale * 0.44
        pts.append((r * math.cos(a), r * math.sin(a)))
    return prism(name, pts, DECAL_THICKNESS, center, material, collection, cell_name, axis)


def spark(name, center, scale, material, collection, cell_name, axis="y"):
    """六顶点三星尖（+20 三角面）：低预算位置的星形替代。"""
    pts = []
    for i in range(6):
        a = math.pi * 0.5 + math.tau * i / 6
        r = scale if i % 2 == 0 else scale * 0.34
        pts.append((r * math.cos(a), r * math.sin(a)))
    return prism(name, pts, DECAL_THICKNESS, center, material, collection, cell_name, axis)


def lightning(name, center, scale, material, collection, cell_name, axis="y"):
    s = scale
    pts = [(-0.22 * s, 1.0 * s), (0.38 * s, 0.14 * s), (0.06 * s, 0.14 * s),
           (0.30 * s, -1.0 * s), (-0.38 * s, -0.04 * s), (-0.06 * s, -0.04 * s)]
    return prism(name, pts, DECAL_THICKNESS, center, material, collection, cell_name, axis)


def cross_mark(name, center, size, material, collection, cell_name):
    a, b, c = size
    box(name + "_横", (a, b, c), center, material, collection, cell_name)
    box(name + "_竖", (b, a, c), center, material, collection, cell_name)


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


# ---------------------------------------------------------------- 造型

def build_potion(out, m):
    cyl("药瓶主体", 0.145, 0.24, (0, 0, -0.02), m["matte"], out, "pink", 5)
    cyl("药瓶瓶颈", 0.052, 0.06, (0, 0, 0.14), m["metal"], out, "gray_light", 4)
    heart("瓶盖心形", (0, 0, 0.19), 0.058, m["gloss"], out, "red")
    cross_mark("治疗十字", (0, -0.117, 0.03), (0.115, 0.028, 0.028), m["metal"], out, "white")
    bunny("兔子标识", (0, -0.117, -0.075), 0.072, m["metal"], out, "white")


def build_ammo(out, m):
    box("弹药木箱", (0.40, 0.20, 0.19), (0, 0, -0.02), m["matte"], out, "wood")
    box("弹药木箱盖沿", (0.42, 0.22, 0.035), (0, 0, 0.075), m["matte"], out, "wood_dark")
    for i, x in enumerate((-0.135, -0.045, 0.045, 0.135)):
        cyl("弹药_%d" % i, 0.028, 0.14, (x, 0, 0.13), m["metal"], out, "gold", 4)
    bunny("兔子标识", (0, -0.100, -0.02), 0.058, m["gloss"], out, "blue")


def build_battery_small(out, m):
    cyl("电池主体", 0.082, 0.26, (0, 0, -0.01), m["matte"], out, "purple", 6)
    cyl("电池正极凸头", 0.040, 0.045, (0, 0, 0.145), m["gloss"], out, "gold", 4)
    cyl("电池正极环", 0.072, 0.03, (0, 0, 0.112), m["metal"], out, "blue", 6)
    cyl("电池负极环", 0.076, 0.028, (0, 0, -0.132), m["metal"], out, "blue", 6)
    lightning("闪电标识", (0, -0.072, 0.0), 0.075, m["glow"], out, "yellow")


def build_battery_large(out, m):
    cyl("电池主体", 0.104, 0.30, (0, 0, -0.02), m["matte"], out, "blue", 6)
    cyl("电池顶盖", 0.114, 0.05, (0, 0, 0.155), m["metal"], out, "gold", 6)
    box("电池提手横梁", (0.20, 0.045, 0.035), (0, 0, 0.215), m["metal"], out, "gold")
    box("电池提手左柱", (0.032, 0.042, 0.05), (-0.084, 0, 0.182), m["metal"], out, "gold")
    box("电池提手右柱", (0.032, 0.042, 0.05), (0.084, 0, 0.182), m["metal"], out, "gold")
    lightning("闪电标识", (0, -0.092, -0.02), 0.098, m["glow"], out, "yellow")


def build_cell_pack(out, m):
    box("电芯包主体", (0.30, 0.20, 0.17), (0, 0, -0.03), m["matte"], out, "purple")
    box("电芯包前面板", (0.32, 0.03, 0.15), (0, -0.102, -0.02), m["gloss"], out, "teal")
    box("电芯包提手横梁", (0.15, 0.035, 0.03), (0, 0, 0.078), m["metal"], out, "gold")
    box("电芯包提手左柱", (0.028, 0.034, 0.045), (-0.06, 0, 0.05), m["metal"], out, "gold")
    box("电芯包提手右柱", (0.028, 0.034, 0.045), (0.06, 0, 0.05), m["metal"], out, "gold")
    box("电芯包卡扣", (0.055, 0.045, 0.055), (0.10, -0.10, -0.055), m["metal"], out, "gold")
    bunny("电芯包兔子标识", (0, -0.117, -0.02), 0.062, m["gloss"], out, "white")


def build_beacon(out, m):
    cyl("信标底座", 0.14, 0.05, (0, 0, -0.135), m["metal"], out, "blue", 6)
    cyl("信标白色台", 0.115, 0.05, (0, 0, -0.085), m["matte"], out, "white", 6)
    cone("信标灯罩", 0.105, 0.052, 0.11, (0, 0, -0.005), m["glow"], out, "cyan", 6)
    cyl("信标顶部灯球", 0.042, 0.05, (0, 0, 0.075), m["glow"], out, "red", 4)
    heart("信标心形标", (0, -0.100, -0.085), 0.05, m["gloss"], out, "pink")


def build_key(out, m):
    ring("钥匙环", 0.072, 0.038, 0.036, (-0.115, 0, 0), m["metal"], out, "steel", 6)
    box("钥匙杆", (0.19, 0.042, 0.034), (0.028, 0, 0), m["metal"], out, "gold")
    box("钥匙齿", (0.042, 0.078, 0.034), (0.108, -0.026, 0), m["metal"], out, "gold")
    heart("钥匙链心形", (-0.115, 0.055, 0), 0.048, m["gloss"], out, "pink", axis="z")
    bunny("钥匙兔挂件", (0.075, 0, 0), 0.052, m["gloss"], out, "white", axis="z")


def build_backpack(out, m, slots, w, d, h):
    body_cell = "pink" if slots == 2 else "blue" if slots == 4 else "teal"
    box("背包主体", (w * 0.80, d * 0.74, h * 0.64), (0, 0, -h * 0.05), m["matte"], out, body_cell)
    box("前袋", (w * 0.52, d * 0.14, h * 0.30), (0, -d * 0.43, -h * 0.10), m["gloss"], out, "pink_light")
    if slots == 2:
        box("顶部提手", (w * 0.34, d * 0.14, h * 0.07), (0, 0, h * 0.36), m["metal"], out, "gold")
        box("左侧袋", (w * 0.14, d * 0.50, h * 0.24), (-w * 0.46, 0, -h * 0.05), m["gloss"], out, "white")
        box("右侧袋", (w * 0.14, d * 0.50, h * 0.24), (w * 0.46, 0, -h * 0.05), m["gloss"], out, "white")
        bunny("背包兔子标识", (0, -d * 0.50, -h * 0.08), w * 0.16, m["metal"], out, "white")
    elif slots == 4:
        box("顶部提手", (w * 0.34, d * 0.14, h * 0.07), (0, 0, h * 0.36), m["metal"], out, "gold")
        box("前盖扣带", (w * 0.09, d * 0.16, h * 0.34), (0, -d * 0.50, 0), m["metal"], out, "gold")
        bunny("背包兔子标识", (-w * 0.19, -d * 0.50, -h * 0.05), w * 0.13, m["metal"], out, "white")
        spark("背包星形标识", (w * 0.20, -d * 0.50, -h * 0.05), w * 0.085, m["metal"], out, "yellow")
    else:
        # 远征背包以顶部卷铺盖代替提手，把预算让给双扣带与兔标。
        box("前盖扣带左", (w * 0.08, d * 0.16, h * 0.36), (-w * 0.24, -d * 0.50, 0), m["metal"], out, "gold")
        box("前盖扣带右", (w * 0.08, d * 0.16, h * 0.36), (w * 0.24, -d * 0.50, 0), m["metal"], out, "gold")
        cyl("顶部卷铺盖", w * 0.26, w * 0.42, (0, 0, h * 0.44), m["matte"], out, "teal_light", 4, axis="x")
        bunny("背包兔子标识", (0, -d * 0.50, -h * 0.06), w * 0.15, m["metal"], out, "white")


def build_flashlight(out, m, variant):
    body_cell = {"basic": "gray_dark", "efficient": "blue", "advanced": "purple_deep"}[variant]
    cyl("手电主体", 0.05, 0.25, (-0.015, 0, 0), m["metal"], out, body_cell, 6, axis="x")
    cone("手电头锥", 0.078, 0.052, 0.06, (0.13, 0, 0), m["metal"], out, "dark", 6, axis="x")
    cyl("手电镜片", 0.064, 0.02, (0.163, 0, 0), m["glow"], out, "cyan", 6, axis="x")
    cyl("手电尾盖", 0.046, 0.03, (-0.155, 0, 0), m["metal"], out, "gray", 4, axis="x")
    if variant == "basic":
        cyl("手电开关环", 0.056, 0.018, (0.055, 0, 0), m["gloss"], out, "red", 4, axis="x")
        box("手电开关", (0.05, 0.032, 0.035), (0.0, -0.05, 0), m["gloss"], out, "paper")
    elif variant == "efficient":
        lightning("手电闪电标识", (0.0, -0.046, 0), 0.062, m["glow"], out, "yellow")
    else:
        bunny("手电兔子标识", (0.0, -0.046, 0), 0.058, m["gloss"], out, "pink")


def build_bullet(out, m, variant):
    spec = {
        "standard":  ("steel", "gold", "blue"),
        "sticky":    ("green", "green", "green"),
        "bounce":    ("pink", "pink", "steel"),
        "piercing":  ("gray_dark", "purple_deep", "white"),
        "explosive": ("red", "deep_red", "yellow"),
        "balloon":   ("pink_light", "pink_light", "white"),
    }[variant]
    if variant == "explosive":
        cyl("弹体", 0.062, 0.16, (-0.055, 0, 0), m["matte"], out, spec[0], 6, axis="x")
        cone("弹头", 0.062, 0.018, 0.13, (0.085, 0, 0), m["matte"], out, spec[1], 6, axis="x")
        cyl("底缘环", 0.066, 0.022, (-0.135, 0, 0), m["metal"], out, "dark", 4, axis="x")
        star("爆炸星标", (0.045, -0.052, 0), 0.055, m["glow"], out, "yellow")
        return
    if variant == "balloon":
        cyl("气球球体", 0.072, 0.10, (0.075, 0, 0), m["matte"], out, "pink", 6, axis="x")
        cyl("气球气嘴", 0.018, 0.04, (0.012, 0, 0), m["metal"], out, "pink_light", 4, axis="x")
        cyl("弹壳", 0.05, 0.09, (-0.06, 0, 0), m["metal"], out, "steel", 6, axis="x")
        cyl("底缘环", 0.056, 0.022, (-0.11, 0, 0), m["metal"], out, "dark", 4, axis="x")
        bunny("弹壳兔子标识", (-0.06, -0.044, 0), 0.05, m["gloss"], out, "white")
        return
    cyl("弹壳", 0.055, 0.13, (-0.06, 0, 0), m["metal"], out, spec[0], 6, axis="x")
    cone("弹头", 0.055, 0.012, 0.13, (0.07, 0, 0), m["matte"], out, spec[1], 6, axis="x")
    if variant != "bounce":
        # 回旋镖型把预算让给三片尾翼，不再单独做底缘环。
        cyl("底缘环", 0.061, 0.022, (-0.125, 0, 0), m["metal"], out, "dark", 4, axis="x")
    if variant == "sticky":
        cyl("黏液滴左", 0.019, 0.07, (0.02, -0.052, 0), m["gloss"], out, "green_light", 4, axis="x")
        cyl("黏液滴右", 0.019, 0.07, (0.02, 0.052, 0), m["gloss"], out, "green_light", 4, axis="x")
        spark("黏黏星标", (0.02, 0, -0.052), 0.05, m["glow"], out, "yellow")
    elif variant == "bounce":
        box("尾翼左", (0.09, 0.022, 0.055), (-0.09, -0.048, 0.048), m["metal"], out, "steel")
        box("尾翼右", (0.09, 0.022, 0.055), (-0.09, 0.048, 0.048), m["metal"], out, "steel")
        box("尾翼下", (0.09, 0.022, 0.055), (-0.09, 0, -0.055), m["metal"], out, "steel")
        spark("回旋星标", (0.02, 0, -0.05), 0.052, m["glow"], out, "yellow")
    else:
        cyl("饰环", 0.058, 0.018, (0.005, 0, 0), m["gloss"], out, "paper", 4, axis="x")
        bunny("弹壳兔子标识", (-0.06, -0.048, 0), 0.05, m["gloss"], out, spec[2])


def build_attachment(out, m, variant):
    if variant == "triple_muzzle":
        box("三叉底座", (0.11, 0.18, 0.17), (-0.075, 0, 0), m["metal"], out, "dark")
        for i, (y, z) in enumerate(((-0.06, 0.05), (0.0, 0.0), (0.06, -0.05))):
            cyl("三叉枪管_%d" % i, 0.032, 0.17, (0.055, y, z), m["metal"], out, "pink", 4, axis="x")
        for i, (y, z) in enumerate(((-0.06, 0.05), (0.06, -0.05))):
            cyl("三叉管口环_%d" % i, 0.040, 0.022, (0.13, y, z), m["gloss"], out, "gold", 4, axis="x")
        spark("三叉星标", (-0.07, -0.090, -0.02), 0.055, m["gloss"], out, "gold")
    elif variant == "rubber_stock":
        box("枪托主体", (0.26, 0.15, 0.15), (0.01, 0, 0), m["matte"], out, "purple")
        box("枪托尾盖", (0.045, 0.17, 0.175), (-0.135, 0, 0), m["gloss"], out, "pink")
        box("枪托上沿", (0.24, 0.12, 0.035), (0.01, 0, 0.088), m["matte"], out, "purple_deep")
        box("枪托连接块", (0.07, 0.09, 0.075), (0.145, 0, -0.02), m["metal"], out, "dark")
        bunny("枪托兔子标识", (0.01, -0.075, 0.0), 0.058, m["gloss"], out, "pink")
    elif variant == "scope":
        cyl("瞄具镜筒", 0.056, 0.19, (0, 0, 0.008), m["metal"], out, "steel", 6, axis="x")
        cyl("瞄具前镜圈", 0.068, 0.03, (0.09, 0, 0.008), m["metal"], out, "pink", 4, axis="x")
        cyl("瞄具后镜圈", 0.06, 0.026, (-0.088, 0, 0.008), m["metal"], out, "pink", 4, axis="x")
        cyl("瞄具镜片", 0.05, 0.014, (0.104, 0, 0.008), m["glow"], out, "cyan", 6, axis="x")
        box("瞄具支架", (0.075, 0.09, 0.045), (0, 0, -0.055), m["metal"], out, "dark")
        cyl("瞄具旋钮", 0.018, 0.035, (0.0, 0, 0.052), m["gloss"], out, "gold", 4)
    elif variant == "big_mag":
        box("弹匣主体", (0.17, 0.13, 0.28), (0, 0, 0), m["matte"], out, "purple")
        box("弹匣面板", (0.185, 0.028, 0.20), (0, -0.078, 0.01), m["gloss"], out, "pink")
        box("弹匣底板", (0.20, 0.15, 0.035), (0, 0, -0.145), m["metal"], out, "dark")
        box("弹匣侧棱左", (0.028, 0.13, 0.26), (-0.086, 0, 0), m["metal"], out, "dark")
        box("弹匣侧棱右", (0.028, 0.13, 0.26), (0.086, 0, 0), m["metal"], out, "dark")
        bunny("弹匣兔子标识", (0, -0.092, 0.02), 0.058, m["gloss"], out, "white")
    elif variant == "fan":
        # 正面朝向 -Y：六边实心底板 + 三片粉叶片 + 轴心兔标，轮廓干净且兔标不被遮挡。
        cyl("风扇底板", 0.105, 0.030, (0, 0.020, 0), m["metal"], out, "dark", 6, axis="y")
        for i in range(3):
            a = math.tau * i / 3
            box("风扇叶片_%d" % i, (0.060, 0.016, 0.030),
                (0.055 * math.cos(a), 0.0, 0.055 * math.sin(a)),
                m["gloss"], out, "pink", rot=(0.0, -a, 0.0))
        bunny("风扇兔子标识", (0, -0.028, 0), 0.046, m["gloss"], out, "pink")
    else:
        for i, (x, y, cell_name) in enumerate(((0.0, 0.014, "purple"), (0.012, 0.0, "pink"),
                                               (-0.012, -0.014, "steel"), (0.006, -0.026, "blue"))):
            box("贴纸卡_%d" % i, (0.185, 0.006, 0.225), (x, y, 0), m["gloss"], out, cell_name)
        spark("贴纸星标", (0.0, -0.029, 0.055), 0.058, m["metal"], out, "paper")
        bunny("贴纸兔子标", (-0.02, -0.029, -0.045), 0.066, m["metal"], out, "paper")


def build_blueprint(out, m, variant):
    """六边形蓝图碎片：外框 + 内板 + 枪械线稿。线稿几何互不重叠，保证读得清轮廓。"""
    card_cell = {"pistol": "blue", "shotgun": "purple_light", "rifle": "pink",
                 "machinegun": "blue_dark", "sniper": "purple", "launcher": "deep_red"}[variant]
    hexp = [(-1.0, 0.0), (-0.62, 0.86), (0.62, 0.86), (1.0, 0.0), (0.62, -0.86), (-0.62, -0.86)]
    s = 0.155
    prism("蓝图外框", [(x * s, y * s * 0.86) for x, y in hexp], 0.034,
          (0, 0.004, 0), m["metal"], out, "paper", axis="y")
    prism("蓝图内板", [(x * s * 0.86, y * s * 0.74) for x, y in hexp], 0.02,
          (0, -0.014, 0), m["matte"], out, card_cell, axis="y")
    # 线稿：机匣（中间）→ 枪管（右侧）→ 握把/弹匣（左侧），三者 x 区间互不重叠。
    box("线稿机匣", (0.062, 0.014, 0.032), (-0.014, -0.028, 0.026), m["gloss"], out, "white")
    if variant == "launcher":
        box("线稿粗管", (0.078, 0.014, 0.050), (0.082, -0.028, 0.026), m["gloss"], out, "white")
    else:
        box("线稿枪管", (0.078, 0.014, 0.022), (0.082, -0.028, 0.030), m["gloss"], out, "white")
    if variant == "shotgun":
        box("线稿副管", (0.078, 0.014, 0.022), (0.082, -0.028, -0.002), m["gloss"], out, "white")
    elif variant == "machinegun":
        cyl("线稿弹鼓", 0.036, 0.014, (-0.014, -0.028, -0.030), m["gloss"], out, "white", 4, axis="y")
    elif variant == "sniper":
        cyl("线稿瞄具", 0.020, 0.014, (-0.014, -0.028, 0.066), m["gloss"], out, "white", 4, axis="y")
    elif variant == "launcher":
        box("线稿握把", (0.024, 0.014, 0.052), (-0.078, -0.028, -0.028), m["gloss"], out, "white")
    else:
        box("线稿握把", (0.024, 0.014, 0.052), (-0.078, -0.028, -0.028), m["gloss"], out, "white")
    # 星标使各型号保持同一识别语言；实测整件仍在 100 三角预算内（含星标 96）。
    spark("蓝图星标", (0.075, -0.028, -0.062), 0.042, m["metal"], out, "gold")


# ---------------------------------------------------------------- 清单与阵列

# (content_id, 中文名, 分组, asset_id, (X 宽, Y 深, Z 高), (列, 行), 造型)
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

    ("bp_pistol", "豌豆手枪蓝图碎片", "蓝图碎片", "WPN-GUN-BP-PISTOL", (0.34, 0.05, 0.28), (6, 2), "blueprint:pistol"),
    ("bp_shotgun", "散射喷壶蓝图碎片", "蓝图碎片", "WPN-GUN-BP-SHOTGUN", (0.34, 0.05, 0.28), (7, 2), "blueprint:shotgun"),
    ("bp_rifle", "步枪蓝图碎片", "蓝图碎片", "WPN-GUN-BP-RIFLE", (0.34, 0.05, 0.28), (8, 2), "blueprint:rifle"),
    ("bp_machinegun", "蜂窝机枪蓝图碎片", "蓝图碎片", "WPN-GUN-BP-MACHINEGUN", (0.34, 0.05, 0.28), (6, 3), "blueprint:machinegun"),
    ("bp_sniper", "弹弓狙击蓝图碎片", "蓝图碎片", "WPN-GUN-BP-SNIPER", (0.34, 0.05, 0.28), (7, 3), "blueprint:sniper"),
    ("bp_launcher", "反胃榴弹筒蓝图碎片", "蓝图碎片", "WPN-GUN-BP-LAUNCHER", (0.34, 0.05, 0.28), (8, 3), "blueprint:launcher"),
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
    bpy.context.view_layer.update()
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
        roles = set()
        for obj in out.objects:
            if obj.type != "MESH":
                continue
            meshes += 1
            mesh = obj.data
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
            names = [layer.name for layer in mesh.uv_layers]
            active = mesh.uv_layers.active.name if mesh.uv_layers.active else ""
            if names != ["PaletteUV"] or active != "PaletteUV":
                uv_bad.append([obj.name, names])
            for material in mesh.materials:
                roles.add(material.name)
        item_root = next((o for o in sockets.objects if o.get("semantic_name") == "ItemRoot"), None)
        if item_root is None:
            errors.append([holder.name, "item_root_missing", 0])
        if triangles > TRIANGLE_BUDGET:
            errors.append([holder.name, "triangle_budget", triangles])
        if uv_bad:
            errors.append([holder.name, "uv_layers", uv_bad])
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
    scene["style_contract"] = "粉蓝紫兔标 + 星形/闪电识别点；低多边形；每件独立资产最终求值网格 <= 100 三角面"
    scene["array_contract"] = "31 件资产按参考图 6 面板 9 列 x 4 行阵列排布；网格顶点在各 ItemRoot 局部居中，母版不叠在同一坐标"
    scene["runtime_note"] = "仅 Blender 源；GLB/PackedScene/碰撞/玩法属于后续独立阶段"

    root = bpy.data.collections.new(ROOT_NAME)
    scene.collection.children.link(root)
    root["pipeline"] = "game-prop-model-pipeline"
    root["source_version"] = "v001"
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
        "schema_version": 2,
        "source_blend": "art_source/items_weapons/props/reference_kit/source/prp_reference_item_kit_source_v001.blend",
        "reference_image": REFERENCE_IMAGE,
        "asset_count": len(CATALOG),
        "triangle_budget_per_asset": TRIANGLE_BUDGET,
        "max_triangles_used": max(a["triangles"] for a in assets),
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
        "schema_version": 2,
        "display_name_zh": "参考图 31 件低模道具总母版",
        "source_blend": "art_source/items_weapons/props/reference_kit/source/prp_reference_item_kit_source_v001.blend",
        "source_manifest": "art_source/items_weapons/props/reference_kit/source/reference_item_kit_source_manifest.json",
        "reference_image": REFERENCE_IMAGE,
        "asset_count": len(CATALOG),
        "triangle_budget_per_asset": TRIANGLE_BUDGET,
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
