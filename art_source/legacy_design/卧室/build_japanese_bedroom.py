import bpy
import json
import math
import os
from mathutils import Vector


ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
LAYOUT_PATH = os.path.join(ROOT_DIR, "scene-preview.json")
BLEND_PATH = os.path.join(ROOT_DIR, "日式卧室_微缩场景.blend")
PREVIEW_PATH = os.path.join(ROOT_DIR, "日式卧室_预览.png")
PALETTE_PATH = os.path.join(ROOT_DIR, "日式卧室_色盘_10x10_512.png")
REPORT_PATH = os.path.join(ROOT_DIR, "日式卧室_布局校验.json")

TAU = math.tau

# 0-based palette cells. Column 9 is reserved for the required cool gray ramp.
WOOD_LIGHT = (0, 2)
WOOD_MID = (1, 2)
WOOD_DARK = (2, 2)
RICE = (3, 1)
PAPER = (4, 0)
MATCHA = (5, 3)
MATCHA_DARK = (6, 4)
SAKURA = (7, 2)
ORANGE = (8, 3)
COOL_DARK = (9, 1)
COOL_MID = (9, 5)
COOL_LIGHT = (9, 8)
LEAF = (5, 6)
SOIL = (2, 6)
WHITE = (4, 0)
BLUE_DUSK = (8, 7)


def get_or_create_collection(name, parent=None):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
    if parent:
        if coll.name not in parent.children:
            parent.children.link(coll)
    elif coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    return coll


def move_to_collection(obj, coll):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    coll.objects.link(obj)


def make_palette():
    image = bpy.data.images.get("日式卧室_色盘_10x10_512")
    if image:
        return image
    image = bpy.data.images.new("日式卧室_色盘_10x10_512", width=512, height=512, alpha=True)
    columns = [
        (0.72, 0.48, 0.28), (0.48, 0.27, 0.14), (0.28, 0.13, 0.07),
        (0.91, 0.86, 0.76), (0.98, 0.96, 0.89), (0.48, 0.62, 0.35),
        (0.24, 0.39, 0.22), (0.91, 0.55, 0.58), (0.95, 0.53, 0.22),
    ]
    cool = [
        (0.106, 0.145, 0.200), (0.149, 0.196, 0.259), (0.196, 0.251, 0.322),
        (0.247, 0.310, 0.384), (0.302, 0.369, 0.447), (0.365, 0.431, 0.510),
        (0.443, 0.506, 0.584), (0.537, 0.596, 0.667), (0.647, 0.698, 0.757),
        (0.773, 0.808, 0.847),
    ]
    pixels = [0.0] * (512 * 512 * 4)
    for y in range(512):
        row = min(9, int(y * 10 / 512))
        for x in range(512):
            col = min(9, int(x * 10 / 512))
            if col == 9:
                rgb = cool[row]
            else:
                base = columns[col]
                factor = 1.18 - row * 0.045
                rgb = tuple(min(1.0, max(0.0, c * factor)) for c in base)
            idx = (y * 512 + x) * 4
            pixels[idx:idx + 4] = [rgb[0], rgb[1], rgb[2], 1.0]
    image.pixels.foreach_set(pixels)
    image.filepath_raw = PALETTE_PATH
    image.file_format = 'PNG'
    image.save()
    image.pack()
    return image


def input_socket(node, names):
    for name in names:
        if name in node.inputs:
            return node.inputs[name]
    return None


def make_material(name, role, image):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    out = mat.node_tree.nodes.new("ShaderNodeOutputMaterial")
    shader = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    uv = mat.node_tree.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    tex.image = image
    tex.interpolation = 'Closest'
    mat.node_tree.links.new(uv.outputs['UV'], tex.inputs['Vector'])
    base = input_socket(shader, ["Base Color"])
    mat.node_tree.links.new(tex.outputs['Color'], base)
    rough = input_socket(shader, ["Roughness"])
    metal = input_socket(shader, ["Metallic"])
    if role == "MATTE":
        rough.default_value = 0.68
        metal.default_value = 0.02
    elif role == "GLOSS":
        rough.default_value = 0.2
        metal.default_value = 0.05
        coat = input_socket(shader, ["Coat Weight", "Clearcoat"])
        if coat:
            coat.default_value = 0.55
    elif role == "METAL":
        rough.default_value = 0.28
        metal.default_value = 0.86
    elif role == "EMISSION":
        rough.default_value = 0.4
        emission = input_socket(shader, ["Emission Color", "Emission"])
        strength = input_socket(shader, ["Emission Strength"])
        if emission:
            mat.node_tree.links.new(tex.outputs['Color'], emission)
        if strength:
            strength.default_value = 1.35
    elif role == "GLASS":
        rough.default_value = 0.12
        transmission = input_socket(shader, ["Transmission Weight", "Transmission"])
        alpha = input_socket(shader, ["Alpha"])
        if transmission:
            transmission.default_value = 0.35
        if alpha:
            alpha.default_value = 0.38
        try:
            mat.surface_render_method = 'DITHERED'
        except Exception:
            mat.blend_method = 'BLEND'
        mat.diffuse_color[3] = 0.38
    mat.node_tree.links.new(shader.outputs['BSDF'], out.inputs['Surface'])
    return mat


def setup_materials():
    image = make_palette()
    return {
        "MATTE": make_material("01_细腻哑光_色盘", "MATTE", image),
        "GLOSS": make_material("02_清漆反光_色盘", "GLOSS", image),
        "METAL": make_material("03_精工金属_色盘", "METAL", image),
        "EMISSION": make_material("04_柔和自发光_色盘", "EMISSION", image),
        "GLASS": make_material("05_玻璃_色盘", "GLASS", image),
    }


def assign_palette_uv(obj, cell):
    if obj.type != 'MESH':
        return
    mesh = obj.data
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv = mesh.uv_layers.new(name="PaletteUV")
    col, row = cell
    margin = 0.022
    size = 0.056
    u0 = col / 10 + margin
    v0 = row / 10 + margin
    for poly in mesh.polygons:
        count = len(poly.loop_indices)
        for n, loop_index in enumerate(poly.loop_indices):
            angle = TAU * n / max(3, count) + math.pi / 4
            uv.data[loop_index].uv = (u0 + size / 2 + math.cos(angle) * size / 2,
                                      v0 + size / 2 + math.sin(angle) * size / 2)
    mesh.uv_layers.active = uv
    uv.active_render = True


def finish_mesh(obj, cell, role="MATTE", bevel=0.035):
    obj.data.materials.clear()
    obj.data.materials.append(MATS[role])
    assign_palette_uv(obj, cell)
    if bevel > 0:
        mod = obj.modifiers.new("柔和倒角", 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    for poly in obj.data.polygons:
        poly.use_smooth = False
    obj["palette_cell"] = f"{cell[0]},{cell[1]}"
    obj["material_role"] = role
    return obj


def parent_local(obj, parent, loc=(0, 0, 0), rot=(0, 0, 0)):
    obj.parent = parent
    obj.location = loc
    obj.rotation_euler = rot
    return obj


def box(name, loc, dims, cell, role="MATTE", coll=None, rot=(0, 0, 0), bevel=0.035, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish_mesh(obj, cell, role, min(bevel, min(dims) * 0.22))
    if coll:
        move_to_collection(obj, coll)
    if parent:
        parent_local(obj, parent, loc, rot)
    else:
        obj.location = loc
        obj.rotation_euler = rot
    return obj


def cyl(name, loc, radius, depth, cell, role="MATTE", coll=None, rot=(0, 0, 0), vertices=24, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    finish_mesh(obj, cell, role, min(0.025, radius * 0.18))
    if coll:
        move_to_collection(obj, coll)
    if parent:
        parent_local(obj, parent, loc, rot)
    else:
        obj.location = loc
        obj.rotation_euler = rot
    return obj


def sphere(name, loc, scale, cell, role="MATTE", coll=None, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish_mesh(obj, cell, role, 0)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if coll:
        move_to_collection(obj, coll)
    if parent:
        parent_local(obj, parent, loc)
    else:
        obj.location = loc
    return obj


def torus(name, loc, major, minor, cell, role="MATTE", coll=None, rot=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=24, minor_segments=8, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    finish_mesh(obj, cell, role, 0)
    if coll:
        move_to_collection(obj, coll)
    if parent:
        parent_local(obj, parent, loc, rot)
    else:
        obj.location = loc
        obj.rotation_euler = rot
    return obj


def curve_tube(name, points, radius, cell, role="MATTE", coll=None, cyclic=False):
    curve = bpy.data.curves.new(name + "_曲线", 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    (coll or DECOR).objects.link(obj)
    obj.data.materials.append(MATS[role])
    obj["palette_cell"] = f"{cell[0]},{cell[1]}"
    return obj


def text_obj(name, body, loc, size, cell, coll, extrude=0.008, align='CENTER'):
    curve = bpy.data.curves.new(name + "_字形", 'FONT')
    curve.body = body
    curve.align_x = align
    curve.size = size
    curve.extrude = extrude
    obj = bpy.data.objects.new(name, curve)
    coll.objects.link(obj)
    obj.location = loc
    obj.data.materials.append(MATS["MATTE"])
    obj["palette_cell"] = f"{cell[0]},{cell[1]}"
    return obj


def create_root(record, coll):
    root = bpy.data.objects.new(record["name"], None)
    coll.objects.link(root)
    p = record["position"]
    r = record["rotation"]
    s = record["scale"]
    # Three.js is Y-up; Blender is Z-up. Positive Three.js Y rotation maps to negative Blender Z rotation.
    root.location = (p["x"], p["z"], p["y"])
    root.rotation_euler = (r["x"], r["z"], -r["y"])
    root.scale = (s["x"], s["z"], s["y"])
    root.empty_display_type = 'CUBE'
    root.empty_display_size = 0.18
    root.lock_location = (True, True, True)
    root.lock_rotation = (True, True, True)
    root.lock_scale = (True, True, True)
    root["fixed_component"] = True
    root["layout_type"] = record["type"]
    root["source_position_xyz"] = json.dumps(p, ensure_ascii=False)
    root["source_rotation_xyz"] = json.dumps(r, ensure_ascii=False)
    root["source_scale_xyz"] = json.dumps(s, ensure_ascii=False)
    return root


def build_wall(root, settings, coll):
    box(root.name + "_米白墙体", (0, 0, settings["height"] / 2),
        (settings["width"], settings["thickness"], settings["height"]), PAPER, "MATTE", coll,
        bevel=0.018, parent=root)


def build_floor(root, settings, coll):
    box(root.name + "_浅木地板", (0, 0, settings["thickness"] / 2),
        (settings["length"], settings["width"], settings["thickness"]), WOOD_LIGHT, "MATTE", coll,
        bevel=0.012, parent=root)


def cabinet_frame(root, coll, dark=False, glass=False):
    frame_cell = WOOD_DARK if dark else WOOD_LIGHT
    # Exact local envelope: 1.4 x 0.55 x 1.65.
    box(root.name + "_背板", (0, 0.25, 0.825), (1.4, 0.05, 1.65), frame_cell, "MATTE", coll, bevel=0.018, parent=root)
    for x in (-0.66, 0.66):
        box(root.name + "_侧框", (x, 0, 0.825), (0.08, 0.55, 1.65), frame_cell, "MATTE", coll, bevel=0.018, parent=root)
    for z in (0.04, 1.61):
        box(root.name + "_横框", (0, 0, z), (1.24, 0.55, 0.08), frame_cell, "MATTE", coll, bevel=0.018, parent=root)
    door_role = "GLASS" if glass else "MATTE"
    door_cell = COOL_LIGHT if glass else RICE
    for x in (-0.31, 0.31):
        box(root.name + "_推拉门", (x, -0.255, 0.825), (0.58, 0.04, 1.45), door_cell, door_role, coll, bevel=0.012, parent=root)
        box(root.name + "_门竖格", (x, -0.276 + 0.022, 0.825), (0.025, 0.025, 1.42), frame_cell, "MATTE", coll, bevel=0.006, parent=root)
    for x in (-0.31, 0.31):
        cyl(root.name + "_圆拉手", (x + (0.16 if x < 0 else -0.16), -0.266, 0.82), 0.025, 0.018,
            ORANGE, "METAL", coll, rot=(math.pi / 2, 0, 0), parent=root)
    if glass:
        for z in (0.43, 0.82, 1.21):
            box(root.name + "_层板", (0, 0.08, z), (1.15, 0.39, 0.035), WOOD_LIGHT, "MATTE", coll, bevel=0.008, parent=root)


def build_bed(root, coll):
    # Exact local envelope matches the original Three.js prototype: 2.25 x 1.35 x 1.06.
    for x in (-1.02, 1.02):
        for y in (-0.56, 0.56):
            box(root.name + "_床脚", (x, y, 0.12), (0.12, 0.12, 0.24), WOOD_MID, "MATTE", coll, bevel=0.02, parent=root)
    box(root.name + "_木框", (0, 0, 0.30), (2.25, 1.35, 0.18), WOOD_LIGHT, "MATTE", coll, bevel=0.035, parent=root)
    box(root.name + "_床头板", (-1.085, 0, 0.53), (0.08, 1.35, 1.06), WOOD_LIGHT, "MATTE", coll, bevel=0.025, parent=root)
    for y in (-0.45, 0, 0.45):
        box(root.name + "_床头格栅", (-1.03, y, 0.77), (0.06, 0.06, 0.45), WOOD_DARK, "MATTE", coll, bevel=0.015, parent=root)
    box(root.name + "_床垫", (0.06, 0, 0.48), (2.03, 1.22, 0.25), RICE, "MATTE", coll, bevel=0.10, parent=root)
    box(root.name + "_抹茶被褥", (0.30, 0, 0.66), (1.50, 1.18, 0.12), MATCHA, "MATTE", coll, bevel=0.055, parent=root)
    for y in (-0.31, 0.31):
        box(root.name + "_枕头", (-0.62, y, 0.72), (0.50, 0.48, 0.16), RICE, "MATTE", coll, bevel=0.075, parent=root)
    box(root.name + "_深灰床旗", (0.67, 0, 0.735), (0.40, 1.19, 0.035), COOL_MID, "MATTE", coll, bevel=0.012, parent=root)
    for x in (-0.30, 0.05, 0.40):
        box(root.name + "_格纹", (x, -0.591, 0.728), (0.035, 0.012, 0.135), RICE, "MATTE", coll, bevel=0.002, parent=root)


def build_chair(root, settings, coll):
    w, d = settings["seatWidth"], settings["seatDepth"]
    lh, st, bh = settings["legHeight"], 0.13, settings["backHeight"]
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        for y in (-d / 2 + 0.06, d / 2 - 0.06):
            box(root.name + "_椅腿", (x, y, lh / 2), (0.12, 0.12, lh), WOOD_LIGHT, "MATTE", coll, bevel=0.02, parent=root)
    box(root.name + "_椅座", (0, 0, lh + st / 2), (w, d, st), WOOD_LIGHT, "MATTE", coll, bevel=0.035, parent=root)
    box(root.name + "_坐垫", (0, -0.015, lh + st + 0.055), (w - 0.10, d - 0.10, 0.10), RICE, "MATTE", coll, bevel=0.045, parent=root)
    top = lh + st + bh
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        box(root.name + "_靠背柱", (x, d / 2 - 0.06, lh + st + bh / 2), (0.12, 0.12, bh), WOOD_LIGHT, "MATTE", coll, bevel=0.02, parent=root)
    box(root.name + "_靠背横杆", (0, d / 2 - 0.06, top - 0.06), (w, 0.12, 0.12), WOOD_LIGHT, "MATTE", coll, bevel=0.025, parent=root)
    box(root.name + "_搭毯", (0, d / 2 - 0.125, top - 0.30), (w - 0.16, 0.035, 0.43), SAKURA, "MATTE", coll, bevel=0.018, parent=root)
    for x in (-0.20, 0, 0.20):
        box(root.name + "_搭毯格纹", (x, d / 2 - 0.146, top - 0.30), (0.025, 0.008, 0.42), RICE, "MATTE", coll, bevel=0.002, parent=root)


def build_table(root, settings, coll, low=False):
    w, d = settings["width"], settings["depth"]
    lh, th = settings["legHeight"], settings["topThickness"]
    leg = 0.13
    box(root.name + "_桌面", (0, 0, lh + th / 2), (w, d, th), WOOD_LIGHT, "MATTE", coll, bevel=0.06 if low else 0.035, parent=root)
    for x in (-w / 2 + 0.115, w / 2 - 0.115):
        for y in (-d / 2 + 0.115, d / 2 - 0.115):
            box(root.name + "_桌腿", (x, y, lh / 2), (leg, leg, lh), WOOD_MID, "MATTE", coll, bevel=0.022, parent=root)
    if low:
        box(root.name + "_收纳层", (0, 0, 0.26), (w - 0.25, d - 0.25, 0.07), WOOD_MID, "MATTE", coll, bevel=0.025, parent=root)


def stage_fixed():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    global MASTER, FIXED, WALLS, FLOORS, FURNITURE, DECOR, DYNAMIC, DISPLAY, MATS
    MASTER = get_or_create_collection("日式卧室_中文资产管理")
    FIXED = get_or_create_collection("01_固定元素_布局锁定", MASTER)
    WALLS = get_or_create_collection("01_墙壁", FIXED)
    FLOORS = get_or_create_collection("02_地板", FIXED)
    FURNITURE = get_or_create_collection("03_家具", FIXED)
    DECOR = get_or_create_collection("02_自由装饰_生活化", MASTER)
    DYNAMIC = get_or_create_collection("03_动态元素", MASTER)
    DISPLAY = get_or_create_collection("90_展示环境_灯光相机", MASTER)
    MATS = setup_materials()
    with open(LAYOUT_PATH, "r", encoding="utf-8") as handle:
        layout = json.load(handle)
    bpy.context.scene["layout_source"] = LAYOUT_PATH
    bpy.context.scene["layout_saved_at"] = layout.get("savedAt", "")
    bpy.context.scene["fixed_component_count"] = len(layout["components"])
    for record in layout["components"]:
        kind = record["type"]
        coll = WALLS if kind == "墙壁" else FLOORS if kind == "地板" else FURNITURE
        root = create_root(record, coll)
        if kind == "墙壁":
            build_wall(root, record["surfaceSettings"], coll)
        elif kind == "地板":
            build_floor(root, record["surfaceSettings"], coll)
        elif kind == "柜子":
            cabinet_frame(root, coll, dark=record["name"] == "柜子_1", glass=record["name"] == "柜子_2")
        elif kind == "床":
            build_bed(root, coll)
        elif kind == "椅子":
            build_chair(root, record["chairSettings"], coll)
        elif kind == "桌子":
            build_table(root, record["tableSettings"], coll, low=record["name"] == "桌子_2")


def add_leaf_cluster(base, height=1.1, count=9, coll=None):
    coll = coll or DECOR
    for i in range(count):
        a = TAU * i / count
        end = (base[0] + math.cos(a) * (0.35 + 0.08 * (i % 3)),
               base[1] + math.sin(a) * (0.35 + 0.08 * ((i + 1) % 3)),
               base[2] + height * (0.75 + 0.05 * (i % 4)))
        curve_tube("盆栽_叶柄", [base, end], 0.018, LEAF, "MATTE", coll)
        leaf = sphere("盆栽_叶片", end, (0.10, 0.28, 0.045), LEAF, "MATTE", coll)
        leaf.rotation_euler[2] = a


def stage_environment():
    global MASTER, FIXED, WALLS, FLOORS, FURNITURE, DECOR, DYNAMIC, DISPLAY, MATS
    MASTER = bpy.data.collections["日式卧室_中文资产管理"]
    DECOR = bpy.data.collections["02_自由装饰_生活化"]
    DYNAMIC = bpy.data.collections["03_动态元素"]
    DISPLAY = bpy.data.collections["90_展示环境_灯光相机"]
    MATS = {"MATTE": bpy.data.materials["01_细腻哑光_色盘"], "GLOSS": bpy.data.materials["02_清漆反光_色盘"],
            "METAL": bpy.data.materials["03_精工金属_色盘"], "EMISSION": bpy.data.materials["04_柔和自发光_色盘"],
            "GLASS": bpy.data.materials["05_玻璃_色盘"]}
    # Floor board seams and warm planks sit above, but outside, the locked floor roots.
    for x in [v * 0.75 - 5 for v in range(17)]:
        box("木地板_纵向接缝", (x, -2, 0.112), (0.014, 12, 0.012), WOOD_DARK, "MATTE", DECOR, bevel=0.002)
    for y in range(-8, 5):
        offset = 0.38 if y % 2 else 0
        for x in range(-5, 8, 3):
            box("木地板_错缝", (x + offset, y, 0.114), (0.012, 0.018, 0.014), WOOD_DARK, "MATTE", DECOR, bevel=0.002)
    # Wainscot, skirting and roof beams preserve the two-wall open diorama.
    box("北墙_浅木护墙板", (1, 3.875, 0.70), (12, 0.045, 1.35), WOOD_LIGHT, "MATTE", DECOR, bevel=0.012)
    box("北墙_踢脚线", (1, 3.82, 0.16), (12, 0.12, 0.20), WOOD_DARK, "MATTE", DECOR, bevel=0.018)
    box("西墙_浅木护墙板", (-4.875, -2, 0.70), (0.045, 12, 1.35), WOOD_LIGHT, "MATTE", DECOR, bevel=0.012)
    box("西墙_踢脚线", (-4.82, -2, 0.16), (0.12, 12, 0.20), WOOD_DARK, "MATTE", DECOR, bevel=0.018)
    for x in (-4.6, -1.8, 1.0, 3.8, 6.6):
        box("屋顶_原木横梁", (x, -2, 5.90), (0.14, 12, 0.17), WOOD_DARK, "MATTE", DECOR, bevel=0.022)
    for y in (3.6,):
        box("屋顶_原木主梁", (1, y, 5.94), (12, 0.15, 0.20), WOOD_DARK, "MATTE", DECOR, bevel=0.022)
    # Sunset picture-window on north wall.
    box("落地窗_黄昏光幕_自发光", (3.75, 3.80, 3.08), (5.55, 0.025, 3.75), ORANGE, "EMISSION", DECOR, bevel=0.006)
    box("落地窗_玻璃", (3.75, 3.74, 3.08), (5.55, 0.035, 3.75), BLUE_DUSK, "GLASS", DECOR, bevel=0.008)
    for x in (1.0, 2.82, 4.68, 6.5):
        box("落地窗_竖框", (x, 3.70, 3.08), (0.10, 0.11, 3.82), WOOD_MID, "MATTE", DECOR, bevel=0.016)
    for z in (1.20, 3.05, 4.96):
        box("落地窗_横框", (3.75, 3.70, z), (5.60, 0.11, 0.10), WOOD_MID, "MATTE", DECOR, bevel=0.016)
    box("落地窗_窗台", (3.75, 3.52, 1.16), (5.8, 0.48, 0.14), WOOD_LIGHT, "MATTE", DECOR, bevel=0.035)
    # Shoji door on the west wall.
    box("障子门_纸面_自发光", (-4.78, -4.75, 2.38), (0.045, 2.65, 4.35), PAPER, "EMISSION", DECOR, bevel=0.008)
    for y in (-6.08, -5.41, -4.75, -4.09, -3.42):
        box("障子门_竖格", (-4.73, y, 2.38), (0.095, 0.055, 4.42), WOOD_DARK, "MATTE", DECOR, bevel=0.012)
    for z in (0.20, 1.05, 1.90, 2.75, 3.60, 4.56):
        box("障子门_横格", (-4.73, -4.75, z), (0.095, 2.70, 0.055), WOOD_DARK, "MATTE", DECOR, bevel=0.012)
    # Matcha rug and cushions.
    box("抹茶绿方形地毯", (3.85, -2.35, 0.145), (3.75, 3.20, 0.07), MATCHA, "MATTE", DECOR, bevel=0.075)
    for i in range(12):
        y = -3.78 + i * 0.27
        box("地毯_米白边线", (2.02, y, 0.184), (0.055, 0.16, 0.012), RICE, "MATTE", DECOR, bevel=0.004)
    for loc, cell in [((4.05, 1.25, 0.24), RICE), ((5.95, 1.30, 0.24), SAKURA)]:
        cyl("蒲团坐垫", loc, 0.58, 0.20, cell, "MATTE", DECOR, vertices=32)
        torus("蒲团滚边", (loc[0], loc[1], loc[2] + 0.08), 0.52, 0.025, WOOD_DARK, "MATTE", DECOR)


def add_book_stack(base, count=4, rotation=0):
    colors = [SAKURA, MATCHA, RICE, COOL_MID]
    for i in range(count):
        box("生活摆件_书", (base[0], base[1], base[2] + i * 0.055), (0.38, 0.25, 0.05), colors[i % len(colors)], "MATTE", DECOR,
            rot=(0, 0, rotation + (i % 2) * 0.04), bevel=0.012)


def add_cup(loc, scale=1.0, cell=RICE):
    cup = cyl("陶瓷茶杯", loc, 0.11 * scale, 0.18 * scale, cell, "GLOSS", DECOR, vertices=28)
    torus("陶瓷杯口", (loc[0], loc[1], loc[2] + 0.09 * scale), 0.09 * scale, 0.012 * scale, COOL_DARK, "GLOSS", DECOR)
    curve_tube("茶杯把手", [(loc[0] + 0.10 * scale, loc[1], loc[2] + 0.03 * scale),
                          (loc[0] + 0.18 * scale, loc[1], loc[2] + 0.04 * scale),
                          (loc[0] + 0.11 * scale, loc[1], loc[2] - 0.04 * scale)], 0.018 * scale, cell, "GLOSS", DECOR)
    return cup


def stage_props():
    global DECOR, DYNAMIC, DISPLAY, MATS
    DECOR = bpy.data.collections["02_自由装饰_生活化"]
    DYNAMIC = bpy.data.collections["03_动态元素"]
    DISPLAY = bpy.data.collections["90_展示环境_灯光相机"]
    MATS = {"MATTE": bpy.data.materials["01_细腻哑光_色盘"], "GLOSS": bpy.data.materials["02_清漆反光_色盘"],
            "METAL": bpy.data.materials["03_精工金属_色盘"], "EMISSION": bpy.data.materials["04_柔和自发光_色盘"],
            "GLASS": bpy.data.materials["05_玻璃_色盘"]}
    # Cabinet 1 top plant and woven basket.
    cyl("柜顶_陶盆", (-4.33, 1.55, 3.52), 0.28, 0.32, RICE, "GLOSS", DECOR, vertices=28)
    add_leaf_cluster((-4.33, 1.55, 3.68), 0.85, 8)
    box("柜顶_藤编篮", (-4.33, 2.45, 3.55), (0.72, 0.60, 0.42), WOOD_MID, "MATTE", DECOR, bevel=0.07)
    for i in range(5):
        box("藤编篮_编织", (-4.33, 2.15 + i * 0.15, 3.56), (0.74, 0.025, 0.045), WOOD_DARK, "MATTE", DECOR, bevel=0.005)
    # Cabinet 2 display contents and lamp.
    for i, x in enumerate((-4.73, -4.45, -4.18)):
        add_book_stack((x, -0.82, 1.0 + 0.03 * i), 3, math.pi / 2)
    add_cup((-4.34, -0.76, 1.78), 0.75, SAKURA)
    lamp_base = cyl("柜面小台灯_底座", (-4.50, -1.05, 3.42), 0.20, 0.10, WOOD_DARK, "METAL", DECOR, vertices=24)
    cyl("柜面小台灯_灯杆", (-4.50, -1.05, 3.72), 0.035, 0.56, WOOD_DARK, "METAL", DECOR, vertices=16)
    shade = cyl("柜面小台灯_灯罩_自发光", (-4.50, -1.05, 4.02), 0.25, 0.33, ORANGE, "EMISSION", DECOR, vertices=24)
    shade.scale = (1, 1, 0.7)
    # Desk 1 accessories at (-4,-5), top z=.8.
    box("书桌_摊开笔记本", (-3.78, -5.06, 0.92), (0.58, 0.42, 0.035), RICE, "MATTE", DECOR, rot=(0, 0, -0.12), bevel=0.012)
    box("笔记本_中缝", (-3.78, -5.06, 0.943), (0.018, 0.40, 0.012), COOL_MID, "MATTE", DECOR, rot=(0, 0, -0.12), bevel=0.002)
    add_book_stack((-4.16, -4.47, 0.87), 4, 0.06)
    cyl("书桌_笔筒", (-4.28, -5.52, 1.02), 0.12, 0.30, WOOD_MID, "MATTE", DECOR, vertices=24)
    for i in range(5):
        cyl("书桌_铅笔", (-4.35 + i * 0.035, -5.52, 1.27 + 0.02 * (i % 2)), 0.012, 0.45, [SAKURA, MATCHA, ORANGE][i % 3], "MATTE", DECOR, vertices=10)
    cyl("书桌_多肉盆", (-3.58, -4.47, 0.98), 0.16, 0.23, RICE, "GLOSS", DECOR, vertices=24)
    for i in range(7):
        a = TAU * i / 7
        leaf = sphere("书桌_多肉叶", (-3.58 + math.cos(a) * 0.11, -4.47 + math.sin(a) * 0.11, 1.16), (0.07, 0.14, 0.07), MATCHA_DARK, "MATTE", DECOR)
        leaf.rotation_euler[2] = a
    cyl("绿罩黄铜台灯_底座", (-4.40, -4.48, 0.91), 0.18, 0.09, WOOD_DARK, "METAL", DECOR, vertices=24)
    cyl("绿罩黄铜台灯_灯杆", (-4.40, -4.48, 1.31), 0.028, 0.72, WOOD_DARK, "METAL", DECOR, vertices=16)
    cyl("绿罩黄铜台灯_灯罩", (-4.40, -4.48, 1.65), 0.26, 0.30, MATCHA_DARK, "GLOSS", DECOR, vertices=24)
    # Corkboard with photos, tickets and postcards.
    box("软木留言板", (-4.70, -5.05, 2.65), (0.12, 1.65, 1.20), WOOD_MID, "MATTE", DECOR, bevel=0.045)
    for i, (y, z, cell) in enumerate([(-5.55, 2.85, SAKURA), (-5.08, 2.45, RICE), (-4.67, 2.85, MATCHA), (-5.42, 2.25, ORANGE), (-4.62, 2.25, COOL_LIGHT)]):
        box("留言板_照片票根", (-4.625, y, z), (0.025, 0.32 + 0.08 * (i % 2), 0.24), cell, "MATTE", DECOR, rot=(0, 0.03 * (i - 2), 0), bevel=0.006)
        sphere("留言板_图钉", (-4.605, y, z + 0.11), (0.028, 0.028, 0.028), ORANGE, "GLOSS", DECOR)
    # Tea table 2 accessories.
    cyl("茶具_木托盘", (5.0, 2.5, 0.93), 0.50, 0.055, WOOD_DARK, "MATTE", DECOR, vertices=32)
    cyl("茶具_茶壶", (5.0, 2.5, 1.10), 0.20, 0.30, RICE, "GLOSS", DECOR, vertices=28)
    sphere("茶壶_壶盖", (5.0, 2.5, 1.28), (0.10, 0.10, 0.07), SAKURA, "GLOSS", DECOR)
    add_cup((4.65, 2.48, 1.05), 0.75, MATCHA)
    add_cup((5.34, 2.48, 1.05), 0.75, SAKURA)
    cyl("和果子_小碟", (5.0, 2.06, 0.98), 0.25, 0.045, COOL_LIGHT, "GLOSS", DECOR, vertices=28)
    for i, cell in enumerate((SAKURA, MATCHA, ORANGE)):
        sphere("和果子", (4.84 + i * 0.16, 2.06, 1.07), (0.10, 0.10, 0.07), cell, "MATTE", DECOR)
    # Window vase and dried flowers.
    cyl("窗台_玻璃花瓶", (2.10, 3.43, 1.52), 0.16, 0.55, COOL_LIGHT, "GLASS", DECOR, vertices=28)
    for i in range(7):
        a = -0.55 + i * 0.18
        curve_tube("窗台_干花枝", [(2.10, 3.43, 1.72), (2.10 + math.sin(a) * 0.35, 3.43, 2.28 + 0.06 * (i % 2))], 0.012, WOOD_DARK, "MATTE", DECOR)
        sphere("窗台_干花", (2.10 + math.sin(a) * 0.35, 3.43, 2.31 + 0.06 * (i % 2)), (0.06, 0.06, 0.08), SAKURA, "MATTE", DECOR)
    # Corner palm, woven blanket basket and slippers.
    cyl("角落_散尾葵陶盆", (6.25, -6.68, 0.52), 0.48, 0.82, RICE, "GLOSS", DECOR, vertices=28)
    add_leaf_cluster((6.25, -6.68, 0.88), 2.35, 13)
    box("墙边_藤编收纳筐", (-3.95, -7.10, 0.55), (1.05, 0.80, 0.95), WOOD_MID, "MATTE", DECOR, bevel=0.10)
    for i in range(4):
        cyl("收纳筐_卷毯", (-4.23 + i * 0.19, -7.10, 1.02), 0.13, 0.72, [RICE, MATCHA, SAKURA][i % 3], "MATTE", DECOR, rot=(math.pi / 2, 0, 0), vertices=20)
    for x in (2.95, 3.42):
        box("室内拖鞋_鞋底", (x, -4.18, 0.22), (0.36, 0.72, 0.10), RICE, "MATTE", DECOR, rot=(0, 0, 0.10 if x < 3.2 else -0.08), bevel=0.08)
        box("室内拖鞋_鞋面", (x, -4.05, 0.31), (0.34, 0.32, 0.15), MATCHA, "MATTE", DECOR, bevel=0.07)
    # Wall art and entry coat rack.
    box("浮世绘挂轴_画心", (-0.45, 3.68, 3.45), (1.25, 0.035, 1.85), COOL_LIGHT, "MATTE", DECOR, bevel=0.01)
    box("浮世绘挂轴_夕阳", (-0.45, 3.64, 3.65), (0.55, 0.018, 0.55), ORANGE, "MATTE", DECOR, bevel=0.26)
    for x in (-1.07, 0.17):
        cyl("挂轴_木轴", (x, 3.62, 3.45), 0.045, 1.35, WOOD_DARK, "MATTE", DECOR, rot=(0, math.pi / 2, 0), vertices=16)
    cyl("圆形木质挂牌", (-2.05, 3.63, 3.15), 0.58, 0.05, WOOD_MID, "MATTE", DECOR, rot=(math.pi / 2, 0, 0), vertices=40)
    text_obj("圆牌_静", "静", (-2.05, 3.59, 2.94), 0.42, COOL_DARK, DECOR)
    box("门边_衣架立柱", (-4.45, -7.55, 1.65), (0.10, 0.10, 3.05), WOOD_DARK, "MATTE", DECOR, bevel=0.025)
    box("门边_衣架横杆", (-4.45, -7.55, 3.08), (0.82, 0.10, 0.10), WOOD_DARK, "MATTE", DECOR, bevel=0.025)
    box("米色开衫", (-4.45, -7.46, 2.12), (0.88, 0.07, 1.55), RICE, "MATTE", DECOR, bevel=0.16)
    box("开衫_领口", (-4.45, -7.40, 2.76), (0.28, 0.04, 0.26), SAKURA, "MATTE", DECOR, bevel=0.10)
    # Small magazines and candle near rug.
    box("杂志架", (1.62, -3.42, 0.52), (0.55, 0.72, 0.80), WOOD_DARK, "MATTE", DECOR, rot=(0, 0, -0.10), bevel=0.06)
    for i in range(4):
        box("杂志", (1.62, -3.42 + i * 0.06, 0.66 + i * 0.035), (0.44, 0.04, 0.62), [SAKURA, MATCHA, RICE, COOL_LIGHT][i], "MATTE", DECOR, rot=(0.10, 0, -0.10), bevel=0.012)
    cyl("香薰蜡烛", (2.20, -1.10, 0.35), 0.16, 0.40, RICE, "GLOSS", DECOR, vertices=28)
    sphere("蜡烛_火焰_自发光", (2.20, -1.10, 0.61), (0.055, 0.055, 0.12), ORANGE, "EMISSION", DYNAMIC)


def add_area_light(name, loc, energy, color, size, coll, rotation=(0, 0, 0)):
    data = bpy.data.lights.new(name + "_数据", 'AREA')
    data.energy = energy
    data.color = color
    data.shape = 'DISK'
    data.size = size
    obj = bpy.data.objects.new(name, data)
    coll.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = rotation
    return obj


def track_to(obj, target):
    con = obj.constraints.new(type='TRACK_TO')
    con.target = target
    con.track_axis = 'TRACK_NEGATIVE_Z'
    con.up_axis = 'UP_Y'


def stage_animation():
    global DECOR, DYNAMIC, DISPLAY, MATS
    DECOR = bpy.data.collections["02_自由装饰_生活化"]
    DYNAMIC = bpy.data.collections["03_动态元素"]
    DISPLAY = bpy.data.collections["90_展示环境_灯光相机"]
    MATS = {"MATTE": bpy.data.materials["01_细腻哑光_色盘"], "GLOSS": bpy.data.materials["02_清漆反光_色盘"],
            "METAL": bpy.data.materials["03_精工金属_色盘"], "EMISSION": bpy.data.materials["04_柔和自发光_色盘"],
            "GLASS": bpy.data.materials["05_玻璃_色盘"]}
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 240
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = 960
    scene.render.resolution_y = 960
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.render.use_file_extension = True
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.world.color = (0.055, 0.075, 0.10)
    if scene.world.use_nodes:
        bg = scene.world.node_tree.nodes.get('Background')
        bg.inputs['Color'].default_value = (0.07, 0.09, 0.13, 1)
        bg.inputs['Strength'].default_value = 0.32
    scene.render.use_freestyle = True
    scene.view_layers[0].freestyle_settings.linesets[0].linestyle.color = (0.11, 0.075, 0.055)
    scene.view_layers[0].freestyle_settings.linesets[0].linestyle.thickness = 0.82
    # Camera and third-person miniature composition.
    target = bpy.data.objects.new("镜头_观察中心", None)
    DISPLAY.objects.link(target)
    target.location = (0.6, -1.5, 2.0)
    camera_data = bpy.data.cameras.new("第三视角相机_数据")
    camera = bpy.data.objects.new("第三视角相机", camera_data)
    DISPLAY.objects.link(camera)
    camera.location = (15.8, -18.2, 13.4)
    camera_data.lens = 52
    camera_data.sensor_width = 36
    track_to(camera, target)
    scene.camera = camera
    # Warm/cool light contrast.
    key = add_area_light("窗外黄昏主光", (7.0, 6.5, 8.5), 1500, (1.0, 0.46, 0.22), 8.0, DISPLAY, (0.75, 0, 2.55))
    track_to(key, target)
    key.keyframe_insert(data_path="location", frame=1)
    key.location.x = 4.8
    key.location.z = 6.6
    key.keyframe_insert(data_path="location", frame=240)
    fill = add_area_light("室内柔和补光", (0.5, -3.5, 8.0), 1150, (1.0, 0.78, 0.54), 7.0, DISPLAY)
    track_to(fill, target)
    rim = add_area_light("窗外冷调轮廓光", (7.5, 4.8, 4.0), 900, (0.35, 0.48, 0.78), 5.0, DISPLAY)
    track_to(rim, target)
    # Bamboo pendant with a gently swinging pivot.
    pivot = bpy.data.objects.new("竹编吊灯_摆动轴", None)
    DYNAMIC.objects.link(pivot)
    pivot.location = (1.0, -1.6, 5.75)
    cyl("竹编吊灯_吊线", (0, 0, -0.70), 0.018, 1.4, COOL_DARK, "MATTE", DYNAMIC, parent=pivot)
    shade = cyl("竹编吊灯_灯罩", (0, 0, -1.48), 0.58, 0.62, WOOD_MID, "MATTE", DYNAMIC, vertices=32, parent=pivot)
    shade.scale = (1.0, 1.0, 0.62)
    for i in range(16):
        a = TAU * i / 16
        curve_tube("竹编吊灯_编织条", [(math.cos(a) * 0.18 + 1.0, math.sin(a) * 0.18 - 1.6, 4.48),
                                      (math.cos(a) * 0.52 + 1.0, math.sin(a) * 0.52 - 1.6, 4.10)], 0.018, WOOD_DARK, "MATTE", DYNAMIC)
    bulb = sphere("竹编吊灯_暖灯泡_自发光", (0, 0, -1.52), (0.18, 0.18, 0.22), ORANGE, "EMISSION", DYNAMIC, parent=pivot)
    point_data = bpy.data.lights.new("竹编吊灯_点光数据", 'POINT')
    point_data.energy = 540
    point_data.color = (1.0, 0.53, 0.22)
    point_data.shadow_soft_size = 2.0
    point = bpy.data.objects.new("竹编吊灯_暖光", point_data)
    DYNAMIC.objects.link(point)
    parent_local(point, pivot, (0, 0, -1.58))
    for frame, angle in ((1, -0.025), (60, 0.025), (120, -0.022), (180, 0.022), (240, -0.025)):
        pivot.rotation_euler[1] = angle
        pivot.rotation_euler[0] = angle * 0.42
        pivot.keyframe_insert(data_path="rotation_euler", frame=frame)
    # Desk lamps softly flicker.
    for name, loc, color, energy in [
        ("书桌台灯_暖光", (-4.40, -4.48, 1.55), (1.0, 0.66, 0.30), 180),
        ("柜面台灯_暖光", (-4.50, -1.05, 3.95), (1.0, 0.55, 0.25), 150),
    ]:
        data = bpy.data.lights.new(name + "_数据", 'POINT')
        data.energy = energy
        data.color = color
        data.shadow_soft_size = 1.2
        obj = bpy.data.objects.new(name, data)
        DYNAMIC.objects.link(obj)
        obj.location = loc
        for frame, mul in ((1, 1.0), (48, 0.94), (92, 1.03), (146, 0.97), (201, 1.02), (240, 1.0)):
            data.energy = energy * mul
            data.keyframe_insert(data_path="energy", frame=frame)
    # Curtain strips with phase-offset wind motion.
    for side, x0 in ((-1, 0.86), (1, 6.64)):
        for i in range(5):
            x = x0 + side * i * 0.34
            strip = box("窗边纱帘_飘动", (x, 3.43, 3.20), (0.40, 0.035, 3.75), RICE, "GLASS", DYNAMIC, bevel=0.05)
            strip.rotation_mode = 'XYZ'
            for frame, angle in ((1, 0.015 * i), (60, side * (0.055 + i * 0.006)), (120, -side * 0.025), (180, side * 0.045), (240, 0.015 * i)):
                strip.rotation_euler[1] = angle
                strip.keyframe_insert(data_path="rotation_euler", frame=frame)
    # Tea steam puffs.
    for i in range(5):
        puff = sphere("茶杯热气", (4.65 + 0.035 * (i % 2), 2.48, 1.22 + i * 0.14), (0.035 + i * 0.006, 0.035 + i * 0.006, 0.08), PAPER, "GLASS", DYNAMIC)
        start = 1 + i * 18
        puff.keyframe_insert(data_path="location", frame=start)
        puff.location.x += 0.12 * (-1 if i % 2 else 1)
        puff.location.z += 0.75
        puff.keyframe_insert(data_path="location", frame=start + 100)
        puff.scale = (1.55, 1.55, 1.8)
        puff.keyframe_insert(data_path="scale", frame=start + 100)
        for fc in puff.animation_data.action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'SINE'
    # Tiny birds cross behind the window.
    for i in range(3):
        bird = curve_tube("窗外_飞鸟", [(0, 0, 0), (0.16, 0.06, 0.04), (0.32, 0, 0)], 0.022, COOL_DARK, "MATTE", DYNAMIC)
        bird.location = (0.8 - i * 1.2, 3.93, 3.5 + i * 0.45)
        bird.keyframe_insert(data_path="location", frame=1 + i * 28)
        bird.location.x = 7.2
        bird.location.z += 0.25
        bird.keyframe_insert(data_path="location", frame=155 + i * 28)
    # Moving warm floor patch.
    patch = box("木地板_移动光斑_自发光", (0.2, -3.0, 0.135), (3.5, 2.2, 0.025), ORANGE, "EMISSION", DYNAMIC, rot=(0, 0, -0.30), bevel=0.25)
    patch.scale = (1, 1, 1)
    patch.keyframe_insert(data_path="location", frame=1)
    patch.location.x = 2.4
    patch.location.y = -1.7
    patch.keyframe_insert(data_path="location", frame=240)
    # Configure a clean, overlay-free camera viewport.
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == 'VIEW_3D':
            area.spaces.active.overlay.show_overlays = False
            area.spaces.active.shading.type = 'RENDERED'
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
    scene.frame_set(80)


def world_bbox(root):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    def belongs_to(candidate, ancestor):
        current = candidate.parent
        while current is not None:
            if current == ancestor:
                return True
            current = current.parent
        return False
    descendants = [obj for obj in bpy.data.objects if belongs_to(obj, root)]
    for obj in descendants:
        if obj.type != 'MESH':
            continue
        eval_obj = obj.evaluated_get(depsgraph)
        points.extend(eval_obj.matrix_world @ Vector(corner) for corner in eval_obj.bound_box)
    if not points:
        return None
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi, hi - lo


def expected_dimensions(record):
    kind = record["type"]
    sx, sy, sz = record["scale"]["x"], record["scale"]["y"], record["scale"]["z"]
    if kind == "墙壁":
        local = Vector((record["surfaceSettings"]["width"] * sx, record["surfaceSettings"]["thickness"] * sz,
                        record["surfaceSettings"]["height"] * sy))
    elif kind == "地板":
        local = Vector((record["surfaceSettings"]["length"] * sx, record["surfaceSettings"]["width"] * sz,
                        record["surfaceSettings"]["thickness"] * sy))
    elif kind == "柜子":
        local = Vector((1.4 * sx, 0.55 * sz, 1.65 * sy))
    elif kind == "床":
        local = Vector((2.25 * sx, 1.35 * sz, 1.06 * sy))
    elif kind == "椅子":
        s = record["chairSettings"]
        local = Vector((s["seatWidth"] * sx, s["seatDepth"] * sz, (s["legHeight"] + 0.13 + s["backHeight"]) * sy))
    else:
        s = record["tableSettings"]
        local = Vector((s["width"] * sx, s["depth"] * sz, (s["legHeight"] + s["topThickness"]) * sy))
    angle = abs(math.sin(record["rotation"]["y"]))
    if angle > 0.5:
        local.x, local.y = local.y, local.x
    return local


def stage_validate_save_render():
    with open(LAYOUT_PATH, "r", encoding="utf-8") as handle:
        layout = json.load(handle)
    results = []
    all_ok = True
    for record in layout["components"]:
        root = bpy.data.objects.get(record["name"])
        bbox = world_bbox(root) if root else None
        expected = expected_dimensions(record)
        actual = bbox[2] if bbox else Vector((0, 0, 0))
        delta = actual - expected
        transform_ok = bool(root and root.get("source_position_xyz") == json.dumps(record["position"], ensure_ascii=False)
                            and root.get("source_rotation_xyz") == json.dumps(record["rotation"], ensure_ascii=False)
                            and root.get("source_scale_xyz") == json.dumps(record["scale"], ensure_ascii=False))
        dimensions_ok = max(abs(delta.x), abs(delta.y), abs(delta.z)) <= 0.0025
        ok = transform_ok and dimensions_ok
        all_ok = all_ok and ok
        results.append({
            "name": record["name"], "type": record["type"], "transform_locked": transform_ok,
            "expected_world_dimensions": [round(v, 4) for v in expected],
            "actual_world_dimensions": [round(v, 4) for v in actual],
            "max_dimension_error": round(max(abs(delta.x), abs(delta.y), abs(delta.z)), 6),
            "passed": ok,
        })
    report = {
        "layout": LAYOUT_PATH,
        "fixed_component_count_expected": len(layout["components"]),
        "fixed_component_count_actual": len([o for o in bpy.data.objects if o.get("fixed_component")]),
        "all_passed": all_ok,
        "components": results,
    }
    with open(REPORT_PATH, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    bpy.context.scene["layout_validation_passed"] = all_ok
    bpy.context.scene.render.filepath = PREVIEW_PATH
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print(json.dumps({"blend": BLEND_PATH, "preview": PREVIEW_PATH, "validation": all_ok}, ensure_ascii=False))


STAGE = globals().get("JBR_STAGE", "")
if STAGE == "fixed":
    stage_fixed()
elif STAGE == "environment":
    stage_environment()
elif STAGE == "props":
    stage_props()
elif STAGE == "animation":
    stage_animation()
elif STAGE == "validate_render":
    stage_validate_save_render()
