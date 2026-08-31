import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


BASE_SCRIPT = Path(r"I:\工作项目\shellstrom2\ShellStorm2\tools\asset_pipeline\build_rooftop_shelter.py")
ROOFTOP_MODE = "library"
exec(compile(BASE_SCRIPT.read_bytes(), str(BASE_SCRIPT), "exec"), globals())


ASSET_ROOT = PROJECT_ROOT / "assets" / "art" / "environments" / "soviet_snow_street_corner_3d"
SOURCE_DIR = ASSET_ROOT / "source" / "soviet_snow_street_corner"
GAME_DIR = ASSET_ROOT / "game_output" / "soviet_snow_street_corner"
PREVIEW_DIR = ASSET_ROOT / "previews"
SHARED_DIR = ASSET_ROOT / "shared"
DOCS_DIR = ASSET_ROOT / "docs"
PALETTE_FILE = SHARED_DIR / "苏联雪夜色盘_10x10_512.png"
SOURCE_BLEND = SOURCE_DIR / "env_soviet_snow_street_corner_source_v001.blend"
GAME_BLEND = GAME_DIR / "env_soviet_snow_street_corner_game_v001.blend"
FULL_PREVIEW = PREVIEW_DIR / "env_soviet_snow_street_corner_full_v001.png"
DETAIL_PREVIEW = PREVIEW_DIR / "env_soviet_snow_street_corner_entry_v001.png"
MANIFEST_FILE = DOCS_DIR / "env_soviet_snow_street_corner_manifest_v001.json"


def ensure_soviet_dirs():
    for directory in (SOURCE_DIR, GAME_DIR, PREVIEW_DIR, SHARED_DIR, DOCS_DIR):
        directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PALETTE_SOURCE, PALETTE_FILE)


def setup_soviet_collections():
    root = make_collection("前苏联雪地街角_中文资产管理")
    source = make_collection("01_制作组件_已统一材质", root)
    output = make_collection("02_游戏输出_整合模型", root)
    collision = make_collection("03_游戏碰撞_独立阻挡", root)
    display = make_collection("90_展示环境_灯光相机", root)
    categories = (
        "Environment_Architecture", "Environment_Ground", "Props_Interior", "Props_Street",
        "Props_Transit", "Props_Signage", "Props_Vehicle", "Vegetation", "Lighting", "VFX", "Shared",
    )
    for category in categories:
        make_collection(f"源_{category}", source)
        make_collection(f"输出_{category}", output)
    make_collection("碰撞_Architecture", collision)
    make_collection("碰撞_Ground", collision)
    make_collection("展示_灯光镜头", display)
    source.hide_viewport = True
    source.hide_render = True
    collision.hide_viewport = True
    collision.hide_render = True


def add_output(obj):
    OUTPUT_OBJECTS.append(obj)
    return obj


def torus_object(name, location, major_radius, minor_radius, collection, material_key="metal", cell=(9, 2),
                 major_segments=16, minor_segments=4, rotation=(0.0, 0.0, 0.0), category="Props/Street"):
    vertices = []
    faces = []
    for major in range(major_segments):
        a = math.tau * major / major_segments
        for minor in range(minor_segments):
            b = math.tau * minor / minor_segments
            ring = major_radius + minor_radius * math.cos(b)
            vertices.append((ring * math.cos(a), ring * math.sin(a), minor_radius * math.sin(b)))
    for major in range(major_segments):
        nxt_major = (major + 1) % major_segments
        for minor in range(minor_segments):
            nxt_minor = (minor + 1) % minor_segments
            faces.append((
                major * minor_segments + minor,
                nxt_major * minor_segments + minor,
                nxt_major * minor_segments + nxt_minor,
                major * minor_segments + nxt_minor,
            ))
    obj = make_mesh_object(name, vertices, faces, collection, material_key, cell, category)
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def text_mesh(name, body, location, size, collection, material_key, cell,
              rotation=(math.pi / 2, 0, 0), category="Props/Signage", extrude=0.025, align="CENTER"):
    curve = bpy.data.curves.new(name + "_Curve", "FONT")
    curve.body = body
    curve.align_x = align
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = 0.006
    curve.bevel_resolution = 0
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    obj.data.materials.append(MATERIALS[material_key])
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    converted = bpy.context.object
    converted.name = name
    palette_uv(converted.data, cell)
    tag_object(converted, category, version="v001")
    return converted


def star_mesh(name, location, outer_radius, inner_radius, depth, collection, material_key, cell,
              rotation=(math.pi / 2, 0, 0), category="Props/Signage"):
    vertices = []
    for z in (0.0, depth):
        for i in range(10):
            radius = outer_radius if i % 2 == 0 else inner_radius
            angle = math.pi / 2 + i * math.pi / 5
            vertices.append((math.cos(angle) * radius, math.sin(angle) * radius, z))
    faces = [tuple(reversed(range(10))), tuple(range(10, 20))]
    for i in range(10):
        nxt = (i + 1) % 10
        faces.append((i, nxt, 10 + nxt, 10 + i))
    obj = make_mesh_object(name, vertices, faces, collection, material_key, cell, category)
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def soft_puff(name, location, scale, collection, material_key="gloss", cell=(9, 7), category="VFX"):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    obj.scale = scale
    obj.data.materials.clear()
    obj.data.materials.append(MATERIALS[material_key])
    palette_uv(obj.data, cell)
    tag_object(obj, category, version="v001")
    return obj


def loop_location(obj, frames, locations, interpolation="SINE"):
    for frame, location in zip(frames, locations):
        obj.location = location
        obj.keyframe_insert(data_path="location", frame=frame)
    if obj.animation_data and obj.animation_data.action:
        for fcurve in obj.animation_data.action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = interpolation
            fcurve.modifiers.new("CYCLES")


def build_base_and_streets():
    ground = COLLECTIONS["输出_Environment_Ground"]
    street = COLLECTIONS["输出_Props_Street"]
    collision = COLLECTIONS["碰撞_Ground"]
    add_output(box("雪地微缩景观方形底座", (0, 0, -1.10), (36, 36, 1.10), ground, "matte", (9, 1), category="Environment/Ground", bevel=0.38))
    add_output(box("深灰主街冻结路面", (0, -13.0, 0.0), (36, 8.5, 0.16), ground, "gloss", (9, 2), category="Environment/Ground"))
    add_output(box("深灰侧街冻结路面", (13.2, 1.0, 0.0), (8.2, 20.0, 0.16), ground, "gloss", (9, 2), category="Environment/Ground"))
    add_output(box("公寓前宽阔人行道", (-3.0, -6.2, 0.16), (27.5, 5.2, 0.25), ground, "matte", (9, 4), category="Environment/Ground"))
    add_output(box("公寓侧街人行道", (8.3, 3.3, 0.16), (4.0, 13.7, 0.25), ground, "matte", (9, 4), category="Environment/Ground"))

    for row in range(3):
        for col in range(12):
            slab = box(
                f"积雪混凝土人行道板_{row}_{col}", (-14.3 + col * 2.05, -8.0 + row * 1.58, 0.42),
                (1.88, 1.42, 0.06), ground, "matte", (9, 5 + (row + col) % 2),
                rotation=(0, 0, 0.008 * ((col % 3) - 1)), category="Environment/Ground"
            )
            slab["module_size_m"] = [2.05, 1.58, 0.06]
            add_output(slab)
    for row in range(7):
        for col in range(2):
            add_output(box(
                f"侧街积雪路板_{row}_{col}", (10.0 + col * 1.72, -2.2 + row * 1.75, 0.42),
                (1.55, 1.58, 0.06), ground, "matte", (9, 5 + (row + col) % 2), category="Environment/Ground"
            ))

    # Snow cover is layered and irregular, not a single flat white plane.
    for index, (loc, size) in enumerate((
        ((-10.5, 6.5, 0.42), (10.0, 14.5, 0.22)), ((2.4, 9.8, 0.42), (12.2, 8.0, 0.28)),
        ((-11.5, -10.3, 0.23), (8.5, 2.0, 0.32)), ((5.0, -9.8, 0.23), (9.8, 1.2, 0.25)),
        ((14.8, 10.0, 0.24), (2.4, 10.0, 0.30)),
    )):
        add_output(box(f"厚积雪覆盖区_{index}", loc, size, ground, "matte", (9, 9), category="Environment/Ground", bevel=0.22))
    for index in range(22):
        x = -16.0 + (index * 3.17) % 31.0
        y = -10.3 + 0.45 * math.sin(index * 1.9)
        add_output(low_sphere(f"路缘不规则雪堆_{index}", (x, y, 0.42), (0.85, 0.35, 0.25), ground, "matte", (9, 9), "Environment/Ground"))

    # Tram rails cut through the slushy road.
    for rail_y in (-14.05, -12.15):
        add_output(box(f"积雪街角电车钢轨_{rail_y}", (0, rail_y, 0.20), (35.0, 0.13, 0.11), street, "metal", (9, 3), category="Props/Transit"))
    for index, x in enumerate(range(-16, 17, 2)):
        add_output(box(f"电车轨枕_{index}", (x, -13.10, 0.13), (0.20, 2.60, 0.08), street, "matte", (9, 1), category="Props/Transit"))
        if index % 2 == 0:
            add_output(low_sphere(f"轨道缝深色雪泥_{index}", (x + 0.5, -13.1, 0.24), (0.7, 0.28, 0.08), ground, "gloss", (9, 2), "Environment/Ground"))
    for pole_index, x in enumerate((-15, -6, 3, 12)):
        add_output(cylinder(f"电车接触网深灰杆_{pole_index}", (x, -16.1, 0.2), 0.10, 7.2, street, "metal", (9, 1), 8, category="Props/Transit"))
        add_output(beam_between(f"接触网横臂_{pole_index}", (x, -16.1, 6.9), (x, -13.1, 7.1), 0.045, street, "metal", (9, 2), 8, "Props/Transit"))
    add_output(box("电车顶部接触电线", (0, -13.1, 7.0), (35.0, 0.025, 0.025), street, "metal", (9, 0), category="Props/Transit"))

    col = box("COL_雪地方形底座", (0, 0, -1.15), (36, 36, 1.15), collision, "matte", (9, 1), category="Collision/Ground")
    col.display_type = "WIRE"
    COLLISION_OBJECTS.append(col)


def build_stalinist_apartment():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    interior = COLLECTIONS["输出_Props_Interior"]
    lighting = COLLECTIONS["输出_Lighting"]
    collision = COLLECTIONS["碰撞_Architecture"]

    # Open-front structural shell keeps the interior readable from the showcase camera.
    add_output(box("斯大林式公寓楼首层地板", (-2.5, 3.3, 0.45), (20.5, 11.8, 0.28), architecture, "matte", (9, 3), category="Environment/Architecture"))
    add_output(box("公寓楼深灰后墙", (-2.5, 8.9, 0.45), (20.5, 0.55, 16.0), architecture, "matte", (9, 3), category="Environment/Architecture"))
    add_output(box("公寓楼左侧厚重山墙", (-12.45, 3.3, 0.45), (0.60, 11.8, 16.0), architecture, "matte", (9, 2), category="Environment/Architecture"))
    add_output(box("公寓楼右侧厚重山墙", (7.45, 4.6, 0.45), (0.60, 9.2, 16.0), architecture, "matte", (9, 2), category="Environment/Architecture"))
    for floor, z in enumerate((5.55, 10.65, 15.75)):
        add_output(box(f"楼层灰白石膏檐线_{floor}", (-2.5, 3.3, z), (21.2, 12.3, 0.38), architecture, "matte", (9, 7), category="Environment/Architecture", bevel=0.08))
    for pier_index, x in enumerate((-11.9, -8.6, -5.2, -1.3, 2.8, 6.9)):
        add_output(box(f"正立面深灰承重壁柱_{pier_index}", (x, -2.47, 0.55), (0.62, 0.55, 15.2), architecture, "matte", (9, 3), category="Environment/Architecture", bevel=0.05))
        for floor, z in enumerate((5.18, 10.28, 15.38)):
            add_output(box(f"壁柱灰白柱头_{pier_index}_{floor}", (x, -2.62, z), (1.0, 0.72, 0.38), architecture, "matte", (9, 7), category="Environment/Architecture"))

    # Ground-floor facade and central arched portal.
    for segment, (x, width) in enumerate(((-10.3, 2.4), (-6.9, 2.6), (1.0, 3.1), (5.1, 3.0))):
        add_output(box(f"首层深灰窗间墙_{segment}", (x, -2.42, 0.55), (width, 0.55, 5.0), architecture, "matte", (9, 3), category="Environment/Architecture"))
    add_output(box("拱形门廊左厚墙", (-3.55, -2.72, 0.55), (1.15, 1.20, 4.95), architecture, "matte", (9, 2), category="Environment/Architecture", bevel=0.08))
    add_output(box("拱形门廊右厚墙", (-0.05, -2.72, 0.55), (1.15, 1.20, 4.95), architecture, "matte", (9, 2), category="Environment/Architecture", bevel=0.08))
    add_output(box("拱形门廊厚重顶梁", (-1.8, -2.72, 4.30), (4.65, 1.20, 1.20), architecture, "matte", (9, 2), category="Environment/Architecture", bevel=0.16))
    add_output(torus_object("门廊灰白拱券浮雕", (-1.8, -3.35, 4.05), 1.72, 0.18, architecture, "matte", (9, 8), 20, 5, (math.pi / 2, 0, 0), "Environment/Architecture"))
    for stone_index in range(9):
        angle = math.pi * stone_index / 8
        x = -1.8 + math.cos(angle) * 1.73
        z = 3.95 + math.sin(angle) * 1.73
        add_output(box(f"门廊拱券楔石_{stone_index}", (x, -3.46, z), (0.38, 0.24, 0.52), architecture, "matte", (9, 7), rotation=(0, angle, 0), category="Environment/Architecture"))

    # Heavy double door, glazing and curtain.
    for side, x in enumerate((-2.45, -1.15)):
        add_output(box(f"门廊深灰双扇玻璃门框_{side}", (x, -3.38, 0.60), (1.20, 0.15, 3.45), architecture, "metal", (9, 1), category="Environment/Architecture", bevel=0.04))
        add_output(box(f"门廊暖光玻璃门芯_{side}_自发光", (x, -3.47, 1.05), (0.88, 0.04, 2.62), lighting, "emissive", CELLS["rust"], category="Lighting"))
    for curtain_index, x in enumerate((-2.52, -1.08)):
        curtain = box(f"门廊厚重灰呢门帘_{curtain_index}", (x, -3.56, 0.72), (1.26, 0.08, 3.10), interior, "matte", (9, 3), category="Props/Interior")
        curtain.rotation_euler.z = -0.04 if curtain_index == 0 else 0.04
        curtain.keyframe_insert(data_path="rotation_euler", frame=1)
        curtain.rotation_euler.z += 0.10 if curtain_index == 0 else -0.10
        curtain.keyframe_insert(data_path="rotation_euler", frame=75)
        curtain.rotation_euler.z += -0.06 if curtain_index == 0 else 0.06
        curtain.keyframe_insert(data_path="rotation_euler", frame=150)
        if curtain.animation_data and curtain.animation_data.action:
            for fcurve in curtain.animation_data.action.fcurves:
                fcurve.modifiers.new("CYCLES")
        add_output(curtain)

    # Upper facade bays, tall windows and plaster reliefs.
    window_centers = (-10.15, -6.9, -3.6, 0.2, 3.45, 6.4)
    for floor, base_z in enumerate((5.85, 10.95)):
        for window_index, x in enumerate(window_centers):
            add_output(box(f"高窗深灰凹槽_{floor}_{window_index}", (x, -2.50, base_z), (2.05, 0.42, 3.75), architecture, "matte", (9, 1), category="Environment/Architecture"))
            add_output(box(f"高窗暖橙室内光_{floor}_{window_index}_自发光", (x, -2.74, base_z + 0.30), (1.60, 0.04, 2.75), lighting, "emissive", CELLS["rust"], category="Lighting"))
            for mullion, dx in enumerate((-0.78, 0, 0.78)):
                add_output(box(f"高窗煤黑竖框_{floor}_{window_index}_{mullion}", (x + dx, -2.84, base_z), (0.10, 0.12, 3.25), architecture, "metal", (9, 0), category="Environment/Architecture"))
            for bar, dz in enumerate((0.65, 2.25)):
                add_output(box(f"高窗煤黑横框_{floor}_{window_index}_{bar}", (x, -2.84, base_z + dz), (1.62, 0.12, 0.10), architecture, "metal", (9, 0), category="Environment/Architecture"))
            add_output(box(f"高窗灰白石窗台_{floor}_{window_index}", (x, -2.88, base_z - 0.18), (2.35, 0.58, 0.24), architecture, "matte", (9, 8), category="Environment/Architecture", bevel=0.04))
            add_output(box(f"高窗积雪窗台_{floor}_{window_index}", (x, -2.96, base_z + 0.06), (2.15, 0.48, 0.16), architecture, "matte", (9, 9), category="Environment/Architecture", bevel=0.09))
            add_output(box(f"高窗灰泥三角窗楣_{floor}_{window_index}", (x, -2.86, base_z + 3.55), (2.45, 0.42, 0.28), architecture, "matte", (9, 7), rotation=(0, 0, 0.04 * ((window_index % 2) - 0.5)), category="Environment/Architecture"))

    # Cast-iron balconies on two levels.
    for balcony_index, (x, z) in enumerate(((-7.0, 9.50), (3.5, 9.50), (-7.0, 14.55), (3.5, 14.55))):
        add_output(box(f"深灰铸铁阳台底板_{balcony_index}", (x, -3.12, z), (4.5, 1.45, 0.22), architecture, "metal", (9, 2), category="Environment/Architecture"))
        add_output(box(f"阳台厚积雪_{balcony_index}", (x, -3.24, z + 0.22), (4.25, 1.25, 0.20), architecture, "matte", (9, 9), category="Environment/Architecture", bevel=0.10))
        for post_index in range(7):
            px = x - 2.0 + post_index * 0.67
            add_output(cylinder(f"阳台深灰栏杆柱_{balcony_index}_{post_index}", (px, -3.72, z + 0.25), 0.035, 1.22, architecture, "metal", (9, 1), 6, category="Environment/Architecture"))
            if post_index < 6:
                add_output(beam_between(f"阳台铸铁交叉花饰_{balcony_index}_{post_index}", (px, -3.72, z + 0.35), (px + 0.67, -3.72, z + 1.32), 0.025, architecture, "metal", (9, 2), 6, "Environment/Architecture"))
        add_output(box(f"阳台深灰顶扶手_{balcony_index}", (x, -3.72, z + 1.47), (4.45, 0.10, 0.10), architecture, "metal", (9, 1), category="Environment/Architecture"))
        if balcony_index < 2:
            add_output(box(f"阳台结冰晾衣绳_{balcony_index}", (x, -3.85, z + 2.05), (3.85, 0.025, 0.025), architecture, "metal", (9, 2), category="Environment/Architecture"))
            for cloth_index in range(4):
                cloth = box(f"结冰灰衣物_{balcony_index}_{cloth_index}", (x - 1.45 + cloth_index * 0.95, -3.88, z + 1.35), (0.62, 0.05, 0.82), interior, "matte", (9, 4 + cloth_index % 2), rotation=(0, 0, 0.03 * (cloth_index - 1.5)), category="Props/Interior")
                add_output(cloth)

    # Roof and deep snow cap.
    add_output(box("公寓楼平屋顶结构", (-2.5, 3.3, 16.05), (21.3, 12.3, 0.55), architecture, "matte", (9, 2), category="Environment/Architecture", bevel=0.08))
    add_output(box("公寓楼屋顶厚雪毯", (-2.5, 3.1, 16.62), (21.0, 12.0, 0.48), architecture, "matte", (9, 9), category="Environment/Architecture", bevel=0.24))
    for edge_index, x in enumerate((-11.5, -8.0, -4.0, 0.0, 4.0, 6.6)):
        add_output(low_sphere(f"屋檐松软雪垂_{edge_index}", (x, -2.83, 16.95), (1.6, 0.42, 0.24), architecture, "matte", (9, 9), "Environment/Architecture"))
        for icicle_index in range(3):
            length = 0.35 + 0.18 * ((edge_index + icicle_index) % 3)
            add_output(cylinder(f"屋檐冰柱_{edge_index}_{icicle_index}", (x - 0.55 + icicle_index * 0.55, -3.04, 16.20 - length), 0.035, length, architecture, "gloss", (9, 9), 6, category="Environment/Architecture"))
    for chimney_index, x in enumerate((-8.5, 3.8)):
        add_output(box(f"深灰砖烟囱_{chimney_index}", (x, 5.5, 16.85), (1.2, 1.2, 2.5), architecture, "matte", (9, 2), category="Environment/Architecture", bevel=0.05))
        add_output(box(f"烟囱积雪帽_{chimney_index}", (x, 5.5, 19.30), (1.5, 1.5, 0.22), architecture, "matte", (9, 9), category="Environment/Architecture", bevel=0.10))

    col = box("COL_斯大林式公寓主体", (-2.5, 3.3, 0.4), (20.5, 11.8, 16.2), collision, "matte", (9, 1), category="Collision/Architecture")
    col.display_type = "WIRE"
    COLLISION_OBJECTS.append(col)


def build_entry_and_window_interiors():
    interior = COLLECTIONS["输出_Props_Interior"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    lighting = COLLECTIONS["输出_Lighting"]

    add_output(box("门廊暗红楼梯间地毯", (-1.8, 0.9, 0.66), (3.1, 7.0, 0.06), interior, "matte", CELLS["red"], category="Props/Interior"))
    for step_index in range(8):
        add_output(box(f"门廊楼梯踏步_{step_index}", (-0.4, 3.8 + step_index * 0.42, 0.66 + step_index * 0.28), (3.2, 0.55, 0.28), architecture, "matte", (9, 5), category="Environment/Architecture"))
        if step_index % 2 == 0:
            add_output(box(f"楼梯暗红毯条_{step_index}", (-0.4, 3.50 + step_index * 0.42, 0.95 + step_index * 0.28), (1.25, 0.50, 0.035), interior, "matte", CELLS["red"], category="Props/Interior"))
    for post_index in range(7):
        x = 1.2
        y = 3.8 + post_index * 0.48
        z = 1.1 + post_index * 0.28
        add_output(cylinder(f"楼梯深灰铸铁扶手柱_{post_index}", (x, y, z), 0.035, 0.95, interior, "metal", (9, 1), 6, category="Props/Interior"))
    add_output(beam_between("楼梯深灰连续扶手", (1.2, 3.7, 2.0), (1.2, 7.0, 4.0), 0.06, interior, "metal", (9, 1), 8, "Props/Interior"))

    # Mailboxes, floor plates, wall phone and newspapers.
    for row in range(4):
        for col in range(5):
            add_output(box(f"门廊深灰信箱格_{row}_{col}", (-10.4 + col * 0.62, 8.45, 1.0 + row * 0.52), (0.55, 0.25, 0.44), interior, "metal", (9, 2 + (row + col) % 2), category="Props/Interior"))
            add_output(cylinder(f"信箱圆锁_{row}_{col}", (-10.4 + col * 0.62, 8.28, 1.18 + row * 0.52), 0.035, 0.04, interior, "metal", (9, 7), 6, rotation=(math.pi / 2, 0, 0), category="Props/Interior"))
    add_output(text_mesh("搪瓷楼层号牌_一层", "1", (-3.9, -3.10, 3.25), 0.55, interior, "matte", (9, 9), category="Props/Interior"))
    add_output(box("门廊公用电话机", (-8.8, 8.25, 1.25), (0.65, 0.35, 0.90), interior, "matte", (9, 2), category="Props/Interior", bevel=0.08))
    add_output(cylinder("公用电话旋转拨盘", (-8.8, 8.02, 1.58), 0.20, 0.05, interior, "gloss", (9, 6), 12, rotation=(math.pi / 2, 0, 0), category="Props/Interior"))
    for paper_index in range(10):
        add_output(box(f"角落旧报纸_{paper_index}", (-9.6 + 0.12 * paper_index, 7.4 + 0.08 * (paper_index % 3), 0.72 + 0.025 * paper_index), (0.85, 0.60, 0.025), interior, "matte", (9, 7 + paper_index % 2), rotation=(0, 0, -0.2 + paper_index * 0.035), category="Props/Interior"))
    for crate_index in range(3):
        add_output(box(f"牛奶瓶金属箱_{crate_index}", (-7.5 + crate_index * 0.85, 7.75, 0.70), (0.75, 0.65, 0.55), interior, "metal", (9, 3), category="Props/Interior"))
        for bottle_index in range(4):
            add_output(cylinder(f"旧牛奶瓶_{crate_index}_{bottle_index}", (-7.75 + crate_index * 0.85 + (bottle_index % 2) * 0.32, 7.55 + (bottle_index // 2) * 0.30, 1.22), 0.07, 0.42, interior, "gloss", (9, 8), 8, category="Props/Interior"))

    # Street-facing warm room vignettes.
    room_centers = (-9.7, 3.8)
    for room_index, x in enumerate(room_centers):
        add_output(box(f"临街窗口室内木桌_{room_index}", (x, -0.8, 1.0), (2.2, 1.1, 0.16), interior, "matte", (9, 3), category="Props/Interior"))
        for leg_index, (dx, dy) in enumerate(((-0.8, -0.35), (0.8, -0.35), (-0.8, 0.35), (0.8, 0.35))):
            add_output(box(f"室内桌腿_{room_index}_{leg_index}", (x + dx, -0.8 + dy, 0.55), (0.10, 0.10, 0.48), interior, "matte", (9, 2), category="Props/Interior"))
        add_output(box(f"老式收音机机身_{room_index}", (x - 0.55, -0.9, 1.18), (0.82, 0.32, 0.55), interior, "matte", (9, 2), category="Props/Interior", bevel=0.06))
        add_output(cylinder(f"收音机调谐盘_{room_index}", (x - 0.55, -1.08, 1.40), 0.14, 0.04, interior, "gloss", (9, 7), 12, rotation=(math.pi / 2, 0, 0), category="Props/Interior"))
        add_output(cylinder(f"搪瓷茶壶壶身_{room_index}", (x + 0.40, -0.8, 1.20), 0.24, 0.42, interior, "metal", (9, 7), 10, category="Props/Interior"))
        add_output(torus_object(f"茶壶提手_{room_index}", (x + 0.40, -0.8, 1.73), 0.28, 0.035, interior, "metal", (9, 2), 12, 4, category="Props/Interior"))
        add_output(cylinder(f"绿植花盆_{room_index}", (x + 0.95, -1.0, 1.18), 0.22, 0.30, interior, "matte", (9, 4), 10, category="Props/Interior"))
        for leaf_index in range(7):
            add_output(low_sphere(f"窗台低饱和绿植叶_{room_index}_{leaf_index}", (x + 0.95 + 0.22 * math.cos(leaf_index), -1.0, 1.58 + 0.12 * (leaf_index % 3)), (0.22, 0.08, 0.10), interior, "matte", (8, 5), "Props/Interior"))
        add_output(box(f"老式台灯灯座_{room_index}", (x + 0.05, -0.75, 1.18), (0.22, 0.22, 0.18), interior, "metal", CELLS["warning"], category="Props/Interior"))
        add_output(cylinder(f"老式台灯暖光灯罩_{room_index}_自发光", (x + 0.05, -0.75, 1.38), 0.28, 0.36, lighting, "emissive", CELLS["warning"], 10, category="Lighting"))
        for doll_index in range(3):
            add_output(low_sphere(f"窗边套娃_{room_index}_{doll_index}", (x + 0.65 + doll_index * 0.22, -1.18, 1.37), (0.11, 0.08, 0.18 - doll_index * 0.03), interior, "matte", CELLS["red" if doll_index == 0 else "warning"], "Props/Interior"))
        for curtain_side in (-1, 1):
            add_output(box(f"灰白蕾丝窗帘_{room_index}_{curtain_side}", (x + curtain_side * 1.05, -2.72, 1.0), (0.30, 0.04, 3.40), interior, "matte", (9, 9), rotation=(0, 0, curtain_side * 0.06), category="Props/Interior"))

    # Two readable street windows layer silhouettes in front of a recessed warm panel.
    for showcase_index, x in enumerate((-8.6, 4.3)):
        add_output(box(f"临街暖光生活窗口_{showcase_index}_自发光", (x, -2.82, 1.02), (2.55, 0.04, 3.35), lighting, "emissive", CELLS["rust"], category="Lighting"))
        for frame_index, (dx, dz, sx, sz) in enumerate((
            (-1.28, 0.0, 0.12, 3.55), (1.28, 0.0, 0.12, 3.55), (0.0, 0.0, 2.65, 0.12),
            (0.0, 3.43, 2.65, 0.12), (0.0, 1.72, 2.55, 0.10),
        )):
            add_output(box(f"临街煤黑高窗框_{showcase_index}_{frame_index}", (x + dx, -2.96, 1.02 + dz), (sx, 0.10, sz), architecture, "metal", (9, 0), category="Environment/Architecture"))
        add_output(box(f"窗口内收音机剪影_{showcase_index}", (x - 0.45, -3.02, 1.35), (0.72, 0.18, 0.48), interior, "matte", (9, 1), category="Props/Interior", bevel=0.04))
        add_output(cylinder(f"窗口内搪瓷茶壶剪影_{showcase_index}", (x + 0.38, -3.03, 1.34), 0.19, 0.40, interior, "metal", (9, 8), 10, category="Props/Interior"))
        add_output(torus_object(f"窗口内茶壶提手剪影_{showcase_index}", (x + 0.38, -3.03, 1.86), 0.24, 0.03, interior, "metal", (9, 1), 12, 4, category="Props/Interior"))
        add_output(cylinder(f"窗口内盆栽花盆_{showcase_index}", (x + 0.88, -3.04, 1.34), 0.17, 0.25, interior, "matte", (9, 5), 8, category="Props/Interior"))
        for leaf_index in range(5):
            add_output(low_sphere(f"窗口内盆栽叶剪影_{showcase_index}_{leaf_index}", (x + 0.88 + 0.18 * math.cos(leaf_index), -3.06, 1.72 + 0.12 * (leaf_index % 2)), (0.18, 0.04, 0.10), interior, "matte", (9, 3), "Props/Interior"))
        for curtain_side in (-1, 1):
            add_output(box(f"临街灰白蕾丝帘前层_{showcase_index}_{curtain_side}", (x + curtain_side * 1.02, -3.06, 1.10), (0.30, 0.035, 3.10), interior, "matte", (9, 9), rotation=(0, 0, curtain_side * 0.06), category="Props/Interior"))


def build_rooftop_propaganda_sign():
    signage = COLLECTIONS["输出_Props_Signage"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    lighting = COLLECTIONS["输出_Lighting"]
    vfx = COLLECTIONS["输出_VFX"]
    panel_y = -0.2
    panel_z = 20.6

    for post_index, x in enumerate((-10.0, -5.0, 0.0, 5.0)):
        add_output(box(f"宣传牌深灰支撑立柱_{post_index}", (x, 2.0, 16.65), (0.28, 0.28, 4.10), architecture, "metal", (9, 1), category="Environment/Architecture"))
        add_output(beam_between(f"宣传牌背部斜撑_{post_index}", (x, 2.0, 17.2), (x, panel_y, 20.0), 0.09, architecture, "metal", (9, 2), 8, "Environment/Architecture"))
    add_output(box("宣传标语牌红色主背板", (-2.5, panel_y, panel_z), (18.2, 0.30, 3.5), signage, "gloss", CELLS["red"], category="Props/Signage", bevel=0.14))
    for edge_index, (loc, size) in enumerate((
        ((-2.5, -0.38, panel_z), (18.8, 0.18, 0.18)), ((-2.5, -0.38, panel_z + 3.32), (18.8, 0.18, 0.18)),
        ((-11.75, -0.38, panel_z), (0.18, 0.18, 3.5)), ((6.75, -0.38, panel_z), (0.18, 0.18, 3.5)),
    )):
        add_output(box(f"宣传牌深灰铆接边框_{edge_index}", loc, size, signage, "metal", (9, 1), category="Props/Signage"))
    for rivet_index in range(16):
        x = -11.2 + rivet_index * 1.16
        add_output(cylinder(f"宣传牌边框铆钉_{rivet_index}", (x, -0.55, panel_z + 0.32), 0.055, 0.04, signage, "metal", (9, 7), 8, rotation=(math.pi / 2, 0, 0), category="Props/Signage"))
        add_output(cylinder(f"宣传牌上缘积雪点_{rivet_index}", (x, -0.40, panel_z + 3.45), 0.16, 0.12, signage, "matte", (9, 9), 8, category="Props/Signage"))
    add_output(text_mesh("革命口号白字_自发光", "СЛАВА ТРУДУ", (-2.5, -0.58, panel_z + 1.65), 1.25, lighting, "emissive", (9, 9), category="Lighting", extrude=0.045))
    add_output(star_mesh("宣传牌苏维埃五角星", (-10.4, -0.63, panel_z + 1.65), 1.1, 0.48, 0.12, signage, "gloss", CELLS["warning"], category="Props/Signage"))
    gear = torus_object("宣传牌工业齿轮徽章", (5.25, -0.62, panel_z + 1.65), 1.05, 0.20, signage, "metal", (9, 8), 16, 5, (math.pi / 2, 0, 0), "Props/Signage")
    add_output(gear)
    for tooth_index in range(12):
        angle = math.tau * tooth_index / 12
        add_output(box(f"宣传牌齿轮齿_{tooth_index}", (5.25 + math.cos(angle) * 1.28, -0.66, panel_z + 1.65 + math.sin(angle) * 1.28), (0.36, 0.18, 0.18), signage, "metal", (9, 7), rotation=(0, angle, 0), category="Props/Signage"))

    # Slow rotating factory signal light.
    signal_root = bpy.data.objects.new("工厂红色信号灯_旋转根", None)
    vfx.objects.link(signal_root)
    add_output(cylinder("工厂信号灯深灰底座", (7.4, 0.5, 18.0), 0.45, 0.55, signage, "metal", (9, 1), 12, category="Props/Signage"))
    beacon = cylinder("工厂红色旋转信号灯_自发光", (7.4, 0.5, 18.55), 0.28, 0.65, lighting, "emissive", CELLS["red"], 12, category="Lighting")
    beacon.parent = signal_root
    add_output(beacon)
    arm = box("工厂信号灯旋转遮光片", (7.72, 0.5, 18.65), (0.75, 0.08, 0.40), signage, "metal", (9, 1), category="Props/Signage")
    arm.parent = signal_root
    add_output(arm)
    signal_root.location = (7.4, 0.5, 18.6)
    animate_rotation(signal_root, 2, [0, math.tau], [1, 240], True)

    # Subtle sign flicker using scale avoids unsupported material animation contracts.
    title = bpy.data.objects.get("革命口号白字_自发光")
    if title:
        title.scale = (1, 1, 1)
        title.keyframe_insert(data_path="scale", frame=1)
        title.scale = (0.985, 0.985, 0.985)
        title.keyframe_insert(data_path="scale", frame=8)
        title.scale = (1, 1, 1)
        title.keyframe_insert(data_path="scale", frame=18)
        if title.animation_data and title.animation_data.action:
            for fcurve in title.animation_data.action.fcurves:
                fcurve.modifiers.new("CYCLES")


def build_street_props_and_vehicle():
    street = COLLECTIONS["输出_Props_Street"]
    vehicle = COLLECTIONS["输出_Props_Vehicle"]
    signage = COLLECTIONS["输出_Props_Signage"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    interior = COLLECTIONS["输出_Props_Interior"]
    lighting = COLLECTIONS["输出_Lighting"]

    # Old cast-iron street lamp and snow cap.
    lamp_x, lamp_y = (7.8, -8.0)
    add_output(cylinder("老式铸铁路灯立柱", (lamp_x, lamp_y, 0.45), 0.18, 7.5, street, "metal", (9, 1), 10, category="Props/Street"))
    for collar_index, z in enumerate((0.55, 2.2, 6.9)):
        add_output(torus_object(f"路灯铸铁装饰环_{collar_index}", (lamp_x, lamp_y, z), 0.25, 0.065, street, "metal", (9, 2), 12, 4, category="Props/Street"))
    add_output(beam_between("路灯弯曲挑臂", (lamp_x, lamp_y, 7.2), (lamp_x - 0.8, lamp_y, 8.0), 0.10, street, "metal", (9, 1), 10, "Props/Street"))
    add_output(low_sphere("路灯球形暖光灯罩_自发光", (lamp_x - 0.95, lamp_y, 7.9), (0.55, 0.55, 0.62), lighting, "emissive", CELLS["warning"], "Lighting"))
    add_output(low_sphere("路灯灯罩积雪帽", (lamp_x - 0.95, lamp_y, 8.48), (0.62, 0.62, 0.20), street, "matte", (9, 9), "Props/Street"))

    # Yellow-red Soviet post box.
    add_output(cylinder("苏联邮政黄色圆柱邮筒", (9.8, -7.7, 0.48), 0.55, 1.85, street, "gloss", CELLS["warning"], 14, category="Props/Street"))
    add_output(low_sphere("邮筒红色穹顶", (9.8, -7.7, 2.34), (0.58, 0.58, 0.34), street, "gloss", CELLS["red"], "Props/Street"))
    add_output(box("邮筒煤黑投信口", (9.8, -8.24, 1.62), (0.70, 0.08, 0.24), street, "metal", (9, 0), category="Props/Street"))
    add_output(star_mesh("邮筒苏维埃小星徽", (9.8, -8.31, 1.05), 0.25, 0.11, 0.04, street, "metal", CELLS["red"], category="Props/Street"))
    add_output(low_sphere("邮筒顶部积雪", (9.8, -7.7, 2.66), (0.64, 0.64, 0.18), street, "matte", (9, 9), "Props/Street"))

    # Detailed black Volga sedan.
    car_root = bpy.data.objects.new("伏尔加黑色轿车_组件根", None)
    vehicle.objects.link(car_root)
    car_x, car_y = (-5.0, -13.2)
    for name, loc, size, cell in (
        ("伏尔加轿车深灰底盘", (car_x, car_y, 0.48), (6.2, 2.25, 0.45), (9, 0)),
        ("伏尔加轿车煤黑车身", (car_x, car_y, 0.82), (5.8, 2.15, 1.18), (9, 1)),
        ("伏尔加轿车车顶舱", (car_x - 0.25, car_y, 1.95), (3.45, 1.90, 1.15), (9, 2)),
        ("伏尔加轿车前引擎盖", (car_x + 2.15, car_y, 1.36), (1.65, 2.05, 0.28), (9, 1)),
        ("伏尔加轿车后备箱", (car_x - 2.25, car_y, 1.28), (1.35, 2.05, 0.36), (9, 1)),
    ):
        part = box(name, loc, size, vehicle, "gloss", cell, category="Props/Vehicle", bevel=0.15)
        part.parent = car_root
        add_output(part)
    for side in (-1, 1):
        side_y = car_y + side * 1.08
        for window_index, wx in enumerate((car_x - 1.15, car_x + 0.25, car_x + 1.05)):
            window = box(f"伏尔加侧窗_{side}_{window_index}", (wx, side_y, 2.15), (0.95, 0.06, 0.72), vehicle, "gloss", (9, 0), category="Props/Vehicle", bevel=0.04)
            window.parent = car_root
            add_output(window)
        mirror = box(f"伏尔加后视镜_{side}", (car_x + 1.45, car_y + side * 1.36, 1.75), (0.35, 0.25, 0.25), vehicle, "gloss", (9, 5), category="Props/Vehicle", bevel=0.08)
        mirror.parent = car_root
        add_output(mirror)
    for axle_x in (-2.0, 2.0):
        for side in (-1, 1):
            wheel = cylinder(f"伏尔加车轮_{axle_x}_{side}", (car_x + axle_x, car_y + side * 1.04, 0.47), 0.52, 0.26, vehicle, "metal", (9, 0), 14, rotation=(math.pi / 2, 0, 0), category="Props/Vehicle")
            wheel.parent = car_root
            add_output(wheel)
            hub = cylinder(f"伏尔加银灰轮毂_{axle_x}_{side}", (car_x + axle_x, car_y + side * 1.20, 0.47), 0.24, 0.06, vehicle, "metal", (9, 7), 12, rotation=(math.pi / 2, 0, 0), category="Props/Vehicle")
            hub.parent = car_root
            add_output(hub)
    add_output(box("伏尔加挡风玻璃扫雪区", (car_x + 0.55, car_y - 0.98, 2.18), (1.65, 0.05, 0.62), vehicle, "gloss", (9, 5), rotation=(0.18, 0, 0), category="Props/Vehicle"))
    add_output(low_sphere("伏尔加车顶厚雪", (car_x - 0.25, car_y, 3.05), (1.95, 1.05, 0.22), vehicle, "matte", (9, 9), "Props/Vehicle"))
    add_output(low_sphere("伏尔加引擎盖厚雪", (car_x + 2.10, car_y, 1.70), (1.25, 1.00, 0.18), vehicle, "matte", (9, 9), "Props/Vehicle"))
    for light_side in (-1, 1):
        add_output(cylinder(f"伏尔加前灯_{light_side}_自发光", (car_x + 3.02, car_y + light_side * 0.68, 1.12), 0.22, 0.08, lighting, "emissive", CELLS["warning"], 12, rotation=(0, math.pi / 2, 0), category="Lighting"))

    # Worker statue with geometric coat silhouette, no living figure.
    sx, sy = (8.7, -4.7)
    add_output(box("工人雕像深灰石基座", (sx, sy, 0.48), (2.6, 2.6, 1.25), architecture, "matte", (9, 3), category="Environment/Architecture", bevel=0.12))
    add_output(box("工人雕像基座积雪", (sx, sy, 1.73), (2.75, 2.75, 0.22), architecture, "matte", (9, 9), category="Environment/Architecture", bevel=0.14))
    add_output(box("工人雕像厚重躯干", (sx, sy, 1.82), (1.25, 0.85, 2.45), street, "matte", (9, 2), rotation=(0, 0, -0.08), category="Props/Street", bevel=0.10))
    add_output(low_sphere("工人雕像头部", (sx, sy, 4.55), (0.42, 0.40, 0.50), street, "matte", (9, 2), "Props/Street"))
    add_output(beam_between("工人雕像抬起手臂", (sx + 0.45, sy, 3.55), (sx + 1.55, sy, 5.0), 0.18, street, "matte", (9, 2), 8, "Props/Street"))
    add_output(box("工人雕像手持齿轮", (sx + 1.70, sy, 4.85), (0.55, 0.18, 0.55), street, "metal", (9, 3), rotation=(0, 0.4, 0), category="Props/Street"))
    add_output(low_sphere("工人雕像肩头积雪", (sx, sy, 4.12), (0.78, 0.52, 0.14), street, "matte", (9, 9), "Props/Street"))

    build_tea_kiosk(street, interior, signage, lighting)


def build_tea_kiosk(street, interior, signage, lighting):
    x, y = (-12.3, -5.2)
    add_output(box("热茶亭深灰木质底座", (x, y, 0.48), (5.1, 3.5, 0.35), street, "matte", (9, 2), category="Props/Street", bevel=0.08))
    for post_index, (dx, dy) in enumerate(((-2.2, -1.4), (2.2, -1.4), (-2.2, 1.4), (2.2, 1.4))):
        add_output(box(f"热茶亭深灰立柱_{post_index}", (x + dx, y + dy, 0.75), (0.22, 0.22, 3.9), street, "matte", (9, 2), category="Props/Street"))
    add_output(box("热茶亭深灰后墙", (x, y + 1.45, 0.75), (4.8, 0.18, 3.7), street, "matte", (9, 3), category="Props/Street"))
    add_output(box("热茶亭暖橙内墙_自发光", (x, y + 1.30, 1.0), (4.3, 0.05, 2.6), lighting, "emissive", CELLS["rust"], category="Lighting"))
    add_output(box("热茶亭服务柜台", (x, y - 1.52, 1.30), (4.3, 0.60, 0.24), interior, "matte", (9, 3), category="Props/Interior"))
    roof = box("热茶亭深灰波形铁皮顶", (x, y, 4.55), (5.6, 4.0, 0.28), street, "metal", (9, 2), rotation=(0.08, 0, 0), category="Props/Street", bevel=0.05)
    add_output(roof)
    for rib_index in range(8):
        add_output(box(f"茶亭铁皮顶波纹_{rib_index}", (x - 2.45 + rib_index * 0.70, y, 4.84), (0.08, 3.8, 0.12), street, "metal", (9, 4), rotation=(0.08, 0, 0), category="Props/Street"))
    add_output(low_sphere("热茶亭屋顶厚积雪", (x, y, 5.0), (2.85, 2.05, 0.30), street, "matte", (9, 9), "Props/Street"))
    for icicle_index in range(11):
        length = 0.30 + 0.10 * (icicle_index % 4)
        add_output(cylinder(f"热茶亭檐口冰凌_{icicle_index}", (x - 2.4 + icicle_index * 0.48, y - 1.98, 4.42 - length), 0.025, length, street, "gloss", (9, 9), 6, category="Props/Street"))
    add_output(box("热茶亭红旗布", (x + 2.4, y - 0.1, 3.25), (1.55, 0.05, 0.90), signage, "matte", CELLS["red"], rotation=(0, 0, -0.12), category="Props/Signage"))
    add_output(star_mesh("热茶亭红旗白星", (x + 2.42, y - 0.16, 3.68), 0.28, 0.12, 0.04, signage, "matte", (9, 9), category="Props/Signage"))
    add_output(cylinder("茶亭搪瓷茶壶", (x - 0.7, y - 1.65, 1.55), 0.34, 0.55, interior, "metal", (9, 8), 12, category="Props/Interior"))
    add_output(torus_object("茶亭茶壶提手", (x - 0.7, y - 1.65, 2.18), 0.40, 0.045, interior, "metal", (9, 2), 14, 4, category="Props/Interior"))
    for cup_index in range(4):
        add_output(cylinder(f"茶亭搪瓷杯_{cup_index}", (x + 0.1 + cup_index * 0.42, y - 1.65, 1.55), 0.12, 0.25, interior, "metal", (9, 8), 10, category="Props/Interior"))
    for seed_bag in range(3):
        add_output(box(f"葵花籽纸袋_{seed_bag}", (x + 1.05 + seed_bag * 0.32, y - 1.65, 1.55), (0.26, 0.18, 0.42), interior, "matte", CELLS["warning"], rotation=(0, 0, -0.08 + seed_bag * 0.08), category="Props/Interior"))


def build_supporting_street_details():
    street = COLLECTIONS["输出_Props_Street"]
    signage = COLLECTIONS["输出_Props_Signage"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    vegetation = COLLECTIONS["输出_Vegetation"]
    lighting = COLLECTIONS["输出_Lighting"]

    # Poster board with curled posters.
    add_output(box("苏联海报栏深灰水泥背板", (13.8, 1.2, 0.55), (0.40, 5.4, 3.4), signage, "matte", (9, 3), category="Props/Signage", bevel=0.06))
    for poster_index, (z, cell, text) in enumerate(((1.1, CELLS["red"], "ТЕАТР"), (2.2, CELLS["warning"], "МОЛОКО"), (3.25, CELLS["red"], "КИНО"))):
        add_output(box(f"风雪卷边海报_{poster_index}", (13.55, -0.2 + poster_index * 1.35, z), (0.05, 1.08, 0.90), signage, "matte", cell, rotation=(0, 0.04 * (poster_index - 1), 0), category="Props/Signage"))
        add_output(text_mesh(f"海报白字_{poster_index}", text, (13.47, -0.2 + poster_index * 1.35, z + 0.45), 0.22, signage, "matte", (9, 9), rotation=(math.pi / 2, 0, math.pi / 2), category="Props/Signage", extrude=0.012))

    # Air-raid vent and bus shelter.
    add_output(box("防空洞深灰水泥通风墩", (12.0, 12.0, 0.48), (2.5, 2.3, 2.0), architecture, "matte", (9, 3), category="Environment/Architecture", bevel=0.14))
    for louver_index in range(5):
        add_output(box(f"防空洞黑色百叶_{louver_index}", (10.72, 11.35 + louver_index * 0.32, 1.22), (0.10, 0.22, 0.08), architecture, "metal", (9, 0), category="Environment/Architecture"))
    add_output(low_sphere("防空洞通风墩积雪", (12.0, 12.0, 2.55), (1.35, 1.25, 0.22), architecture, "matte", (9, 9), "Environment/Architecture"))

    bx, by = (13.1, -3.5)
    add_output(box("水泥候车亭后墙", (bx, by, 0.5), (0.40, 5.0, 3.8), architecture, "matte", (9, 3), category="Environment/Architecture"))
    add_output(box("候车亭厚重顶板", (bx - 1.25, by, 4.15), (2.8, 5.2, 0.30), architecture, "matte", (9, 4), category="Environment/Architecture"))
    add_output(low_sphere("候车亭顶积雪", (bx - 1.25, by, 4.48), (1.50, 2.72, 0.20), architecture, "matte", (9, 9), "Environment/Architecture"))
    add_output(box("候车亭深灰长凳", (bx - 1.15, by, 0.78), (2.2, 3.4, 0.28), street, "matte", (9, 2), category="Props/Street"))

    # Frozen drain and climbing vines.
    for grate_index in range(8):
        add_output(box(f"结冰排水沟格栅_{grate_index}", (8.8 + grate_index * 0.55, -9.2, 0.42), (0.42, 0.55, 0.08), street, "metal", (9, 2), category="Props/Street"))
        if grate_index % 2:
            add_output(low_sphere(f"格栅透明薄冰_{grate_index}", (8.8 + grate_index * 0.55, -9.2, 0.51), (0.28, 0.34, 0.05), street, "gloss", (9, 8), "Props/Street"))
    for vine_index in range(9):
        x = -11.5 + vine_index * 1.0
        add_output(beam_between(f"被雪覆盖的爬墙藤蔓_{vine_index}", (x, 8.6, 0.8), (x + 0.6 * math.sin(vine_index), 8.55, 5.0 + (vine_index % 3)), 0.025, vegetation, "matte", (9, 3), 6, "Vegetation"))
        for leaf_index in range(3):
            add_output(low_sphere(f"结霜藤蔓叶_{vine_index}_{leaf_index}", (x + 0.18 * leaf_index, 8.45, 1.6 + leaf_index * 1.1), (0.18, 0.06, 0.10), vegetation, "matte", (9, 9), "Vegetation"))

    # Small traffic signal at the corner.
    add_output(cylinder("远处交通信号灯杆", (15.8, -10.2, 0.35), 0.08, 4.2, street, "metal", (9, 1), 8, category="Props/Street"))
    add_output(box("远处交通信号灯箱", (15.8, -10.2, 4.25), (0.55, 0.38, 1.35), street, "metal", (9, 1), category="Props/Street"))
    for signal_index, (z, cell) in enumerate(((5.25, CELLS["red"]), (4.85, CELLS["warning"]), (4.45, (8, 5)))):
        lamp = cylinder(f"交通信号灯_{signal_index}_自发光", (15.58, -10.2, z), 0.12, 0.04, lighting, "emissive", cell, 10, rotation=(0, math.pi / 2, 0), category="Lighting")
        add_output(lamp)


def add_snow_weather_and_vfx():
    vfx = COLLECTIONS["输出_VFX"]
    ground = COLLECTIONS["输出_Environment_Ground"]
    random.seed(1961)

    # Large, soft flakes distributed through the viewing volume.
    for flake_index in range(190):
        start_frame = 1 + (flake_index * 17) % 180
        x = random.uniform(-17.0, 17.0)
        y = random.uniform(-16.0, 15.0)
        z = random.uniform(4.0, 25.0)
        scale = random.uniform(0.035, 0.11)
        flake = low_sphere(f"持续飘雪雪花_{flake_index}", (x, y, z), (scale, scale, scale * 0.5), vfx, "matte", (9, 9), "VFX")
        flake["vfx_type"] = "looping_soft_snow"
        loop_location(flake, (start_frame, start_frame + 180), ((x, y, z), (x + random.uniform(-2.0, 2.0), y + random.uniform(-0.8, 0.8), z - 13.0)), "LINEAR")
        add_output(flake)

    # Windblown particles near ground.
    for gust_index in range(28):
        x = -16.0 + gust_index * 1.15
        y = -9.5 + 0.55 * math.sin(gust_index * 1.8)
        particle = low_sphere(f"地面积雪风吹雪粒_{gust_index}", (x, y, 0.60), (0.10, 0.045, 0.035), vfx, "matte", (9, 9), "VFX")
        loop_location(particle, (1 + gust_index * 4, 110 + gust_index * 4), ((x, y, 0.60), (x + 7.0, y + 0.8, 1.15)), "LINEAR")
        add_output(particle)

    # Chimney smoke and tea steam use separate soft low-poly puffs.
    for chimney_index, cx in enumerate((-8.5, 3.8)):
        for puff_index in range(14):
            z = 19.5 + puff_index * 0.24
            puff = soft_puff(f"烟囱炊烟_{chimney_index}_{puff_index}", (cx, 5.5, z), (0.22 + puff_index * 0.025, 0.18 + puff_index * 0.02, 0.24 + puff_index * 0.035), vfx, "gloss", (9, 7), "VFX")
            loop_location(puff, (1 + puff_index * 11, 145 + puff_index * 11), ((cx, 5.5, z), (cx + 2.4, 5.8, z + 5.0)), "SINE")
            add_output(puff)
    for puff_index in range(16):
        x = -13.0 + 0.08 * math.sin(puff_index)
        y = -6.8
        z = 2.1 + puff_index * 0.10
        puff = soft_puff(f"热茶亭袅袅蒸汽_{puff_index}", (x, y, z), (0.16 + puff_index * 0.016, 0.12, 0.20 + puff_index * 0.025), vfx, "gloss", (9, 8), "VFX")
        loop_location(puff, (1 + puff_index * 9, 125 + puff_index * 9), ((x, y, z), (x + 1.0, y, z + 3.2)), "SINE")
        add_output(puff)

    # Icicle drops and occasional roof snow chunks.
    for drop_index in range(8):
        x = -10.0 + drop_index * 2.1
        drop = low_sphere(f"屋檐冰柱滴水_{drop_index}", (x, -3.08, 16.1), (0.035, 0.035, 0.08), vfx, "gloss", (9, 9), "VFX")
        loop_location(drop, (40 + drop_index * 23, 105 + drop_index * 23), ((x, -3.08, 16.1), (x, -3.08, 10.5)), "LINEAR")
        add_output(drop)
    for chunk_index in range(5):
        x = -9.0 + chunk_index * 4.0
        chunk = low_sphere(f"屋顶偶尔滑落小雪块_{chunk_index}", (x, -2.9, 16.85), (0.28, 0.18, 0.16), vfx, "matte", (9, 9), "VFX")
        loop_location(chunk, (90 + chunk_index * 45, 145 + chunk_index * 45), ((x, -2.9, 16.85), (x + 0.5, -4.5, 12.0)), "SINE")
        add_output(chunk)

    # Irregular compressed snow marks break the clean paving rhythm.
    for mark_index in range(26):
        x = -15.0 + (mark_index * 2.45) % 26.0
        y = -8.0 + (mark_index % 3) * 1.35
        add_output(low_sphere(f"压实冰面与雪泥斑_{mark_index}", (x, y, 0.50), (0.42, 0.20, 0.035), ground, "gloss", (9, 4 + mark_index % 2), "Environment/Ground"))


def create_source_prototypes():
    prototypes = (
        ("深灰水泥墙模块", (4.0, 0.5, 5.0), "源_Environment_Architecture", "matte", (9, 3), "Environment/Architecture"),
        ("灰白石膏檐线模块", (4.0, 0.45, 0.45), "源_Environment_Architecture", "matte", (9, 7), "Environment/Architecture"),
        ("积雪路板模块", (2.05, 1.58, 0.10), "源_Environment_Ground", "matte", (9, 9), "Environment/Ground"),
        ("深灰铸铁栏杆模块", (3.0, 0.12, 1.2), "源_Props_Street", "metal", (9, 1), "Props/Street"),
        ("宣传牌红色面板模块", (4.0, 0.20, 1.0), "源_Props_Signage", "gloss", CELLS["red"], "Props/Signage"),
    )
    for index, (name, size, collection_name, role, cell, category) in enumerate(prototypes):
        obj = box(f"源组件_{name}", (-70 + index * 6.0, 0, 0), size, COLLECTIONS[collection_name], role, cell, category=category)
        obj["asset_id"] = f"ENV_SOVIET_SNOW_MODULE_{index:02d}"
        obj["snap_grid_m"] = 0.25
        SOURCE_PROTOTYPES.append(obj)


def correct_cool_gray_palette_orientation():
    """The palette image is top-origin while Blender UV rows are bottom-origin."""
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or not obj.data.uv_layers:
            continue
        layer = obj.data.uv_layers.get("PaletteUV")
        if layer is None or not layer.data:
            continue
        uv = layer.data[0].uv
        col = max(0, min(9, int(uv.x * 10.0)))
        row = max(0, min(9, int(uv.y * 10.0)))
        if col == 9:
            palette_uv(obj.data, (9, 9 - row))


def setup_render_and_lighting():
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 360
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 1500
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.75
    if hasattr(scene.render, "use_freestyle"):
        scene.render.use_freestyle = True
        scene.render.line_thickness = 1.0
        line_set = scene.view_layers[0].freestyle_settings.linesets[0]
        line_set.select_silhouette = True
        line_set.select_border = True
        line_set.select_crease = True
        line_set.select_material_boundary = False
        line_set.linestyle.color = (0.012, 0.016, 0.022)
        line_set.linestyle.thickness = 1.0

    world = scene.world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    links = world.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputWorld")
    background = nodes.new("ShaderNodeBackground")
    background.inputs["Color"].default_value = (0.055, 0.075, 0.105, 1.0)
    background.inputs["Strength"].default_value = 0.46
    links.new(background.outputs["Background"], output.inputs["Surface"])

    display = COLLECTIONS["展示_灯光镜头"]
    moon = add_light("雪夜冷灰蓝主光", "SUN", (-28, -35, 42), (0.36, 0.48, 0.68), 2.4, display)
    moon.rotation_euler = (math.radians(48), math.radians(-20), math.radians(-32))
    moon.data.angle = math.radians(14)
    fill = add_light("厚雪环境柔和补光", "AREA", (14, -20, 28), (0.42, 0.56, 0.76), 2100, display, 36)
    fill.rotation_euler = (0.35, 0, 0.3)
    facade = add_light("深灰建筑轮廓补光", "AREA", (-12, -9, 20), (0.25, 0.34, 0.48), 1150, display, 24)
    facade.rotation_euler = (math.radians(75), 0, -0.15)
    warm_entry = add_light("门廊温暖橙光", "AREA", (-1.8, -3.8, 3.2), (1.0, 0.29, 0.06), 920, display, 8)
    warm_entry.rotation_euler = (math.radians(82), 0, 0)
    warm_kiosk = add_light("热茶亭暖黄灯光", "POINT", (-12.3, -5.4, 3.2), (1.0, 0.38, 0.08), 500, display, 4)
    lamp_glow = add_light("路灯雪中暖黄光晕", "POINT", (6.85, -8.0, 7.8), (1.0, 0.48, 0.10), 700, display, 4)
    lamp_glow.data.shadow_soft_size = 2.2
    sign_rim = add_light("红色宣传牌微弱反光", "AREA", (-2.5, -2.0, 21.5), (0.8, 0.04, 0.03), 520, display, 15)
    sign_rim.rotation_euler = (math.radians(78), 0, 0)

    camera = add_camera("第三视角_苏联雪夜微缩模型主镜头", (43, -47, 35), (-1.0, 0.2, 7.2), 55, display)
    scene.camera = camera
    focus = bpy.data.objects.new("自由观察旋转中心", None)
    display.objects.link(focus)
    focus.location = (-1.0, 0.2, 6.5)
    focus["interaction_hint"] = "Orbit, pan and zoom in Blender viewport; no in-scene UI"


def write_manifest():
    counts = {}
    for obj in bpy.context.scene.objects:
        category = obj.get("asset_category")
        if category:
            counts[category] = counts.get(category, 0) + 1
    manifest = {
        "asset": "前苏联风格雪地街角微缩景观",
        "asset_id": "ENV_SOVIET_SNOW_STREET_CORNER_001",
        "version": "v001",
        "base_dimensions_m": [36.0, 36.0],
        "style": ["toon-rendered", "Soviet-realist", "snow-night", "85-percent-gray-white", "15-percent-accents"],
        "palette": str(PALETTE_FILE),
        "materials": [material.name for material in MATERIALS.values()],
        "category_object_counts": counts,
        "source_prototype_count": len(SOURCE_PROTOTYPES),
        "game_output_object_count": len(OUTPUT_OBJECTS),
        "collision_object_count": len(COLLISION_OBJECTS),
        "animation_frame_range": [1, 360],
        "contains_people_or_animals": False,
        "ui_visible_in_showcase": False,
        "deliverables": {
            "source_blend": str(SOURCE_BLEND), "game_blend": str(GAME_BLEND),
            "full_preview": str(FULL_PREVIEW), "entry_preview": str(DETAIL_PREVIEW),
        },
    }
    MANIFEST_FILE.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def save_deliverables():
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND))
    bpy.ops.wm.save_as_mainfile(filepath=str(GAME_BLEND), copy=True)


def build_scene():
    ensure_soviet_dirs()
    clear_scene()
    setup_soviet_collections()
    setup_palette_materials()
    build_base_and_streets()
    build_stalinist_apartment()
    build_entry_and_window_interiors()
    build_rooftop_propaganda_sign()
    build_street_props_and_vehicle()
    build_supporting_street_details()
    add_snow_weather_and_vfx()
    create_source_prototypes()
    correct_cool_gray_palette_orientation()
    setup_render_and_lighting()
    write_manifest()
    save_deliverables()
    print(json.dumps({
        "status": "built", "objects": len(bpy.context.scene.objects),
        "meshes": sum(1 for obj in bpy.context.scene.objects if obj.type == "MESH"),
        "materials": len(bpy.data.materials), "output_objects": len(OUTPUT_OBJECTS),
        "source_blend": str(SOURCE_BLEND), "game_blend": str(GAME_BLEND),
    }, ensure_ascii=False))


def render_previews():
    scene = bpy.context.scene
    camera = bpy.data.objects.get("第三视角_苏联雪夜微缩模型主镜头")
    if camera is None:
        raise RuntimeError("Main camera is missing")
    scene.camera = camera
    scene.frame_set(118)
    camera.location = (43, -47, 35)
    camera.data.ortho_scale = 55
    camera.rotation_euler = (Vector((-1.0, 0.2, 7.2)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(FULL_PREVIEW)
    bpy.ops.render.render(write_still=True)

    scene.frame_set(78)
    camera.location = (28, -35, 22)
    camera.data.ortho_scale = 36
    camera.rotation_euler = (Vector((-2.0, -0.8, 5.8)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(DETAIL_PREVIEW)
    bpy.ops.render.render(write_still=True)
    save_deliverables()
    print(json.dumps({"status": "rendered", "full": str(FULL_PREVIEW), "detail": str(DETAIL_PREVIEW)}, ensure_ascii=False))


SOVIET_MODE = globals().get("SOVIET_MODE", "build")
if SOVIET_MODE == "build":
    build_scene()
elif SOVIET_MODE == "render":
    render_previews()
elif SOVIET_MODE == "library":
    pass
else:
    raise ValueError(f"Unknown SOVIET_MODE: {SOVIET_MODE}")
