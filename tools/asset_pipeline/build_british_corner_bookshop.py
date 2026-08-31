import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


BASE_SCRIPT = Path(r"I:\工作项目\shellstrom2\ShellStorm2\tools\asset_pipeline\build_rooftop_shelter.py")
ROOFTOP_MODE = "library"
exec(compile(BASE_SCRIPT.read_bytes(), str(BASE_SCRIPT), "exec"), globals())


ASSET_ROOT = PROJECT_ROOT / "assets" / "art" / "environments" / "british_corner_bookshop_3d"
SOURCE_DIR = ASSET_ROOT / "source" / "british_corner_bookshop"
GAME_DIR = ASSET_ROOT / "game_output" / "british_corner_bookshop"
PREVIEW_DIR = ASSET_ROOT / "previews"
SHARED_DIR = ASSET_ROOT / "shared"
DOCS_DIR = ASSET_ROOT / "docs"
PALETTE_FILE = SHARED_DIR / "多巴胺色盘_10x10_512.png"
SOURCE_BLEND = SOURCE_DIR / "env_british_corner_bookshop_source_v002.blend"
GAME_BLEND = GAME_DIR / "env_british_corner_bookshop_game_v002.blend"
FULL_PREVIEW = PREVIEW_DIR / "env_british_corner_bookshop_full_v002.png"
DETAIL_PREVIEW = PREVIEW_DIR / "env_british_corner_bookshop_interior_v002.png"
MANIFEST_FILE = DOCS_DIR / "env_british_corner_bookshop_manifest_v002.json"


def ensure_bookshop_dirs():
    for directory in (SOURCE_DIR, GAME_DIR, PREVIEW_DIR, SHARED_DIR, DOCS_DIR):
        directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PALETTE_SOURCE, PALETTE_FILE)


def setup_bookshop_collections():
    root = make_collection("英伦街角书店_中文资产管理")
    source = make_collection("01_制作组件_已统一材质", root)
    output = make_collection("02_游戏输出_整合模型", root)
    collision = make_collection("03_游戏碰撞_独立阻挡", root)
    display = make_collection("90_展示环境_灯光相机", root)
    categories = (
        "Environment_Architecture", "Environment_Ground", "Props_Furniture", "Props_Books",
        "Props_Street", "Props_Transit", "Props_Advertisement", "Vegetation", "Lighting", "VFX", "Shared",
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


def torus_object(name, location, major_radius, minor_radius, collection, material_key="metal", cell=None,
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
        next_major = (major + 1) % major_segments
        for minor in range(minor_segments):
            next_minor = (minor + 1) % minor_segments
            faces.append((
                major * minor_segments + minor,
                next_major * minor_segments + minor,
                next_major * minor_segments + next_minor,
                major * minor_segments + next_minor,
            ))
    obj = make_mesh_object(name, vertices, faces, collection, material_key, cell or CELLS["black"], category)
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def text_mesh(name, body, location, size, collection, material_key, cell, rotation=(math.pi / 2, 0, 0),
              category="Props/Advertisement", extrude=0.035, align="CENTER"):
    curve = bpy.data.curves.new(name + "_Curve", "FONT")
    curve.body = body
    curve.align_x = align
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = 0.008
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
    tag_object(converted, category, version="v002")
    return converted


def add_output(obj):
    OUTPUT_OBJECTS.append(obj)
    return obj


def build_base_and_street():
    ground = COLLECTIONS["输出_Environment_Ground"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    collision = COLLECTIONS["碰撞_Ground"]
    street = COLLECTIONS["输出_Props_Street"]

    add_output(box("微缩景观方形底座", (0, 0, -1.0), (34, 34, 1.0), ground, "matte", CELLS["concrete_dark"], category="Environment/Ground", bevel=0.35))
    add_output(box("潮湿主街路面", (0, -12.8, 0.0), (34, 8.0, 0.12), ground, "gloss", (9, 2), category="Environment/Ground"))
    add_output(box("潮湿侧街路面", (12.8, 1.2, 0.0), (8.0, 20.0, 0.12), ground, "gloss", (9, 2), category="Environment/Ground"))
    add_output(box("街角人行道主体", (-3.0, -5.8, 0.12), (26.0, 6.0, 0.20), ground, "matte", (9, 5), category="Environment/Ground"))
    add_output(box("书店侧面人行道", (7.0, 3.0, 0.12), (4.0, 12.0, 0.20), ground, "matte", (9, 5), category="Environment/Ground"))
    add_output(box("转角斜切路缘", (8.4, -6.6, 0.12), (5.0, 1.0, 0.28), ground, "matte", CELLS["concrete_light"], rotation=(0, 0, -0.55), category="Environment/Ground"))

    # Stone flags stay modular and slightly varied through neighboring cool-gray palette cells.
    for row in range(3):
        for col in range(12):
            x = -14.8 + col * 2.05
            y = -7.7 + row * 1.75
            slab = box(
                f"人行道石板_{row}_{col}", (x, y, 0.33), (1.90, 1.58, 0.045), ground,
                "matte", (9, 5 + (row + col) % 2), rotation=(0, 0, 0.012 * ((col % 3) - 1)),
                category="Environment/Ground"
            )
            slab["module_size_m"] = [2.05, 1.75, 0.045]
            add_output(slab)
    for row in range(6):
        for col in range(2):
            slab = box(
                f"侧街石板_{row}_{col}", (9.7 + col * 1.75, -1.8 + row * 1.85, 0.33),
                (1.58, 1.70, 0.045), ground, "matte", (9, 5 + (row + col) % 2),
                category="Environment/Ground"
            )
            add_output(slab)

    for index, x in enumerate(range(-15, 11, 2)):
        drain = box(f"主街排水沟格栅_{index}", (x, -9.25, 0.18), (1.45, 0.48, 0.07), ground, "metal", (9, 1), category="Environment/Ground")
        add_output(drain)
        for bar in range(5):
            add_output(box(f"排水格栅槽_{index}_{bar}", (x - 0.5 + bar * 0.25, -9.27, 0.26), (0.06, 0.38, 0.025), ground, "matte", CELLS["black"], category="Environment/Ground"))

    # Tram rails and overhead contact line.
    for rail_y in (-13.55, -11.95):
        add_output(box(f"电车钢轨_{rail_y}", (0, rail_y, 0.17), (33.0, 0.10, 0.10), street, "metal", (9, 4), category="Props/Street"))
    for index, x in enumerate(range(-15, 16, 3)):
        add_output(box(f"电车轨枕_{index}", (x, -12.75, 0.12), (0.18, 2.25, 0.08), street, "matte", CELLS["wood_dark"], category="Props/Street"))
    for x in (-15, -6, 3, 12):
        add_output(cylinder(f"电车接触网杆_{x}", (x, -15.8, 0.1), 0.09, 7.2, street, "metal", CELLS["black"], 8, category="Props/Street"))
        add_output(beam_between(f"接触网横臂_{x}", (x, -15.8, 6.9), (x, -12.7, 7.1), 0.045, street, "metal", (9, 2), 8, "Props/Street"))
    add_output(box("电车顶部接触电线", (0, -12.7, 7.05), (33.0, 0.025, 0.025), street, "metal", CELLS["black"], category="Props/Street"))

    col = box("COL_方形底座", (0, 0, -1.05), (34, 34, 1.05), collision, "matte", (9, 1), category="Collision/Ground")
    col.display_type = "WIRE"
    COLLISION_OBJECTS.append(col)


def build_bookshop_architecture():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    books = COLLECTIONS["输出_Props_Books"]
    ad = COLLECTIONS["输出_Props_Advertisement"]

    # Open-front construction: structural side/back walls frame large glass panes and reveal the interior.
    add_output(box("书店首层地板", (-2.0, 3.0, 0.34), (18.0, 11.0, 0.26), architecture, "matte", CELLS["wood_dark"], category="Environment/Architecture"))
    add_output(box("书店左侧承重墙", (-10.8, 3.0, 0.4), (0.45, 11.0, 12.4), architecture, "matte", CELLS["green_dark"], category="Environment/Architecture"))
    add_output(box("书店右侧转角墙", (6.8, 4.7, 0.4), (0.45, 7.6, 12.4), architecture, "matte", CELLS["green_dark"], category="Environment/Architecture"))
    add_output(box("书店后墙", (-2.0, 8.3, 0.4), (18.0, 0.45, 12.4), architecture, "matte", CELLS["green_dark"], category="Environment/Architecture"))
    add_output(box("二层楼板檐线", (-2.0, 3.0, 6.25), (18.6, 11.4, 0.34), architecture, "matte", CELLS["canvas"], category="Environment/Architecture", bevel=0.08))
    front_roof = box("英伦坡屋顶_前坡", (-2.0, 0.25, 13.10), (19.2, 6.2, 0.30), architecture, "matte", CELLS["blue_dark"], rotation=(0.26, 0, 0), category="Environment/Architecture", bevel=0.08)
    rear_roof = box("英伦坡屋顶_后坡", (-2.0, 5.75, 13.10), (19.2, 6.2, 0.30), architecture, "matte", CELLS["blue_dark"], rotation=(-0.26, 0, 0), category="Environment/Architecture", bevel=0.08)
    add_output(front_roof)
    add_output(rear_roof)
    add_output(box("英伦屋脊盖瓦", (-2.0, 3.02, 13.88), (19.4, 0.34, 0.34), architecture, "matte", CELLS["black"], category="Environment/Architecture", bevel=0.10))
    for chimney_index, x in enumerate((-7.4, 3.4)):
        add_output(box(f"砖红烟囱_{chimney_index}", (x, 5.2, 12.85), (1.25, 1.15, 2.65), architecture, "matte", CELLS["rust"], category="Environment/Architecture"))
        add_output(box(f"烟囱奶油石压顶_{chimney_index}", (x, 5.2, 15.45), (1.50, 1.40, 0.28), architecture, "matte", CELLS["canvas"], category="Environment/Architecture", bevel=0.05))
        for pot_index in (-0.28, 0.28):
            add_output(cylinder(f"烟囱陶土风帽_{chimney_index}_{pot_index}", (x + pot_index, 5.2, 15.72), 0.18, 0.55, architecture, "matte", CELLS["rust_dark"], 10, category="Environment/Architecture"))
    add_output(box("书店前檐黑色天沟", (-2.0, -2.70, 12.28), (19.5, 0.24, 0.26), architecture, "metal", CELLS["black"], category="Environment/Architecture", bevel=0.07))
    add_output(box("奶油石材屋檐", (-2.0, -2.52, 11.95), (18.8, 0.55, 0.48), architecture, "matte", CELLS["canvas"], category="Environment/Architecture"))

    # First-floor frontage columns and shop cornice.
    for index, x in enumerate((-10.2, -3.1, 2.0, 6.2)):
        add_output(box(f"首层墨绿立柱_{index}", (x, -2.28, 0.42), (0.52, 0.55, 5.75), architecture, "matte", CELLS["green_dark"], category="Environment/Architecture", bevel=0.04))
        add_output(box(f"立柱奶油石脚_{index}", (x, -2.32, 0.42), (0.72, 0.66, 0.48), architecture, "matte", CELLS["canvas"], category="Environment/Architecture"))
    add_output(box("首层横向木质檐口", (-2.0, -2.3, 5.65), (18.0, 0.58, 0.55), architecture, "matte", CELLS["wood_dark"], category="Environment/Architecture", bevel=0.06))

    # Arched door made from a rectangular leaf, fanlight and radial trim.
    add_output(box("英伦拱形木门门扇", (-0.55, -2.42, 0.48), (2.5, 0.30, 4.45), architecture, "matte", CELLS["wood_dark"], category="Environment/Architecture", bevel=0.07))
    arch_cap = cylinder("木门圆拱上冠", (-0.55, -2.44, 4.70), 1.18, 0.22, architecture, "matte", CELLS["wood_dark"], 16, rotation=(math.pi / 2, 0, 0), category="Environment/Architecture")
    arch_glass = cylinder("木门拱形玻璃窗", (-0.55, -2.60, 4.74), 0.68, 0.06, architecture, "gloss", CELLS["glass"], 16, rotation=(math.pi / 2, 0, 0), category="Environment/Architecture")
    add_output(arch_cap)
    add_output(arch_glass)
    for index, angle in enumerate((0.0, math.pi / 4, math.pi / 2, math.pi * 3 / 4, math.pi)):
        x = -0.55 + math.cos(angle) * 1.35
        z = 4.62 + math.sin(angle) * 1.35
        add_output(cylinder(f"拱门奶油石饰条_{index}", (x, -2.63, z), 0.10, 0.42, architecture, "matte", CELLS["canvas"], 8, rotation=(math.pi / 2, 0, angle), category="Environment/Architecture"))
    add_output(cylinder("黄铜门把手", (0.28, -2.68, 2.45), 0.10, 0.24, architecture, "metal", CELLS["warning"], 10, rotation=(math.pi / 2, 0, 0), category="Environment/Architecture"))
    add_output(box("黄铜门锁面板", (0.28, -2.60, 2.12), (0.22, 0.05, 0.42), architecture, "metal", CELLS["warning"], category="Environment/Architecture"))

    # Large shop windows, frames and lower wood panels.
    window_specs = ((-6.65, 5.8), (4.15, 3.6))
    for index, (x, width) in enumerate(window_specs):
        glass = box(f"落地橱窗玻璃_{index}", (x, -2.46, 0.72), (width, 0.08, 4.55), architecture, "gloss", CELLS["glass"], category="Environment/Architecture")
        glass.hide_render = True
        glass["showcase_visibility"] = "hidden_for_clear_interior_view; editable_source_component"
        add_output(glass)
        add_output(box(f"橱窗下部木板_{index}", (x, -2.53, 0.43), (width + 0.18, 0.28, 0.72), architecture, "matte", CELLS["wood_dark"], category="Environment/Architecture"))
        for divider in (-0.33, 0.33):
            add_output(box(f"橱窗竖框_{index}_{divider}", (x + width * divider, -2.58, 0.78), (0.10, 0.20, 4.42), architecture, "matte", CELLS["wood_dark"], category="Environment/Architecture"))
        add_output(box(f"橱窗横框_{index}", (x, -2.59, 3.45), (width, 0.20, 0.11), architecture, "matte", CELLS["wood_dark"], category="Environment/Architecture"))
        for highlight in range(3):
            add_output(box(f"橱窗玻璃高光条_{index}_{highlight}", (x - width * 0.32 + highlight * width * 0.32, -2.68, 1.15 + highlight * 0.86), (0.035, 0.018, 1.05), architecture, "gloss", CELLS["glass"], rotation=(0, 0.08, 0.10), category="Environment/Architecture"))

    # Second-floor facade: green wall bands, windows, cream quoins and drain pipes.
    add_output(box("二层正立面", (-2.0, -2.17, 6.30), (18.0, 0.38, 5.60), architecture, "matte", CELLS["green_dark"], category="Environment/Architecture"))
    for index, x in enumerate((-8.0, -4.0, 0.0, 4.0)):
        add_output(box(f"二层深棕窗框_{index}", (x, -2.42, 7.0), (2.65, 0.20, 3.65), architecture, "matte", CELLS["wood_dark"], category="Environment/Architecture"))
        add_output(box(f"二层夜色玻璃_{index}", (x, -2.54, 7.28), (2.25, 0.06, 2.92), architecture, "gloss", CELLS["blue_dark"], category="Environment/Architecture"))
        add_output(box(f"二层窗中梃_{index}", (x, -2.60, 7.30), (0.10, 0.08, 2.95), architecture, "matte", CELLS["canvas"], category="Environment/Architecture"))
        add_output(box(f"二层窗横梃_{index}", (x, -2.60, 8.65), (2.24, 0.08, 0.10), architecture, "matte", CELLS["canvas"], category="Environment/Architecture"))
    for index, x in enumerate((-10.45, 6.45)):
        for z in (6.5, 7.55, 8.60, 9.65, 10.70):
            add_output(box(f"奶油石转角块_{index}_{z}", (x, -2.42, z), (0.72, 0.34, 0.72), architecture, "matte", CELLS["canvas"], category="Environment/Architecture"))
    add_output(cylinder("书店雨水立管", (6.45, -2.65, 0.4), 0.09, 11.4, architecture, "metal", (9, 2), 8, category="Environment/Architecture"))
    for z in (1.2, 4.0, 7.0, 10.0):
        add_output(torus_object(f"雨水管固定箍_{z}", (6.45, -2.65, z), 0.11, 0.025, architecture, "metal", CELLS["warning"], 10, 4, category="Environment/Architecture"))

    # Wooden hanging sign and bracket.
    add_output(beam_between("书店招牌铁艺支架", (-3.0, -2.8, 5.95), (-3.0, -4.15, 6.55), 0.055, ad, "metal", CELLS["black"], 8, "Props/Advertisement"))
    sign = box("手写体木质招牌", (-3.0, -4.25, 5.85), (4.2, 0.18, 1.05), ad, "matte", CELLS["wood"], rotation=(0.03, 0, 0.02), category="Props/Advertisement", bevel=0.08)
    add_output(sign)
    add_output(text_mesh("木牌文字_Bookshop", "Bookshop", (-3.0, -4.36, 6.35), 0.58, ad, "matte", CELLS["canvas"], category="Props/Advertisement", extrude=0.018))

    # Bell assembly with a real rotation pivot.
    bell_parent = bpy.data.objects.new("黄铜门铃旋转轴", None)
    ad.objects.link(bell_parent)
    bell_parent.location = (1.25, -2.9, 5.55)
    bell_parent["pivot_contract"] = "real_hinge_axis"
    bell = cylinder("复古黄铜门铃", (1.25, -2.9, 5.08), 0.22, 0.52, ad, "metal", CELLS["warning"], 12, category="Props/Advertisement")
    bell_world = bell.matrix_world.copy()
    bell.parent = bell_parent
    bell.matrix_world = bell_world
    add_output(bell)
    add_output(torus_object("门铃下沿", (1.25, -2.9, 5.12), 0.25, 0.035, ad, "metal", CELLS["warning"], 12, 4, category="Props/Advertisement"))
    animate_rotation(bell_parent, 1, [-0.08, 0.10, -0.08], [1, 48, 96], True)


def build_interior():
    furniture = COLLECTIONS["输出_Props_Furniture"]
    books = COLLECTIONS["输出_Props_Books"]
    lighting = COLLECTIONS["输出_Lighting"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    vegetation = COLLECTIONS["输出_Vegetation"]
    random.seed(1847)

    # Floor-to-ceiling oak shelves on back wall and side walls.
    shelf_specs = ((-7.6, 7.75, 5.2), (-2.0, 7.75, 5.2), (3.6, 7.75, 5.2))
    for shelf_index, (x, y, width) in enumerate(shelf_specs):
        add_output(box(f"深色橡木书架背板_{shelf_index}", (x, y, 0.58), (width, 0.32, 5.0), furniture, "matte", CELLS["wood_dark"], category="Props/Furniture"))
        for side in (-1, 1):
            add_output(box(f"书架侧柱_{shelf_index}_{side}", (x + side * width * 0.48, y - 0.10, 0.58), (0.16, 0.48, 5.05), furniture, "matte", CELLS["wood"], category="Props/Furniture"))
        for level in range(6):
            z = 0.72 + level * 0.80
            add_output(box(f"书架层板_{shelf_index}_{level}", (x, y - 0.22, z), (width, 0.62, 0.10), furniture, "matte", CELLS["wood"], category="Props/Furniture"))
            for book_index in range(13):
                bx = x - width * 0.43 + book_index * (width * 0.86 / 12)
                height = 0.46 + 0.17 * ((book_index + level + shelf_index) % 3)
                cells = ("red", "blue", "green", "purple", "warning", "canvas")
                book = box(
                    f"书架精装书_{shelf_index}_{level}_{book_index}", (bx, y - 0.59, z + 0.10),
                    (0.22, 0.28, height), books, "matte", CELLS[cells[(book_index + level * 2) % len(cells)]],
                    rotation=(0, 0, 0.025 * ((book_index % 3) - 1)), category="Props/Books", bevel=0.018
                )
                add_output(book)

    # Sliding brass ladder and rail.
    add_output(box("滑动书梯黄铜轨道", (-2.0, 7.1, 4.92), (15.8, 0.10, 0.10), furniture, "metal", CELLS["warning"], category="Props/Furniture"))
    for side in (-1, 1):
        add_output(beam_between(f"滑动书梯侧梁_{side}", (-5.2 + side * 0.58, 6.8, 0.6), (-4.7 + side * 0.58, 6.8, 4.9), 0.065, furniture, "matte", CELLS["wood"], 8, "Props/Furniture"))
    for rung in range(7):
        add_output(box(f"书梯踏棍_{rung}", (-4.7 + rung * 0.07, 6.8, 0.82 + rung * 0.55), (1.2, 0.14, 0.10), furniture, "matte", CELLS["wood"], rotation=(0, 0.10, 0), category="Props/Furniture"))

    # Window display tables and piles visible through the glazing.
    for display_index, x in enumerate((-7.2, 3.9)):
        add_output(box(f"橱窗陈列台_{display_index}", (x, -1.15, 0.52), (4.1 if display_index == 0 else 2.8, 1.45, 0.78), furniture, "matte", CELLS["wood_dark"], category="Props/Furniture", bevel=0.05))
        for stack in range(5):
            for level in range(2 + stack % 3):
                book = box(
                    f"橱窗堆叠旧书_{display_index}_{stack}_{level}",
                    (x - 1.45 + stack * 0.72, -1.36 + 0.06 * level, 1.31 + level * 0.13),
                    (0.62, 0.42, 0.10), books, "matte", CELLS[("red", "green", "purple", "warning")[stack % 4]],
                    rotation=(0, 0, -0.12 + stack * 0.05), category="Props/Books", bevel=0.018
                )
                add_output(book)
        fern_pot = cylinder(f"橱窗蕨类花盆_{display_index}", (x + 1.45, -1.35, 1.30), 0.25, 0.42, vegetation, "matte", CELLS["rust"], 10, category="Vegetation")
        add_output(fern_pot)
        for leaf_index in range(7):
            leaf = low_sphere(
                f"橱窗蕨类叶片_{display_index}_{leaf_index}",
                (x + 1.45 + math.cos(leaf_index * 0.9) * 0.35, -1.35 + math.sin(leaf_index * 0.9) * 0.20, 1.75 + (leaf_index % 2) * 0.22),
                (0.32, 0.10, 0.09), vegetation, "matte", CELLS["green"], "Vegetation"
            )
            leaf.rotation_euler.z = leaf_index * 0.9
            add_output(leaf)

    # Reading corner: leather sofa, Persian rug, table and green-shade lamps.
    add_output(box("波斯地毯", (-6.4, 3.4, 0.62), (5.2, 3.6, 0.045), furniture, "matte", CELLS["purple"], category="Props/Furniture", bevel=0.05))
    for stripe in range(7):
        add_output(box(f"波斯地毯花纹_{stripe}", (-8.3 + stripe * 0.62, 3.4, 0.67), (0.20, 3.0, 0.018), furniture, "matte", CELLS["warning" if stripe % 2 else "red"], category="Props/Furniture"))
    sofa_parts = (
        ("皮沙发底座", (-7.1, 4.6, 0.65), (3.9, 1.55, 0.58)),
        ("皮沙发坐垫", (-7.1, 4.25, 1.18), (3.45, 1.05, 0.34)),
        ("皮沙发靠背", (-7.1, 5.15, 0.95), (3.9, 0.32, 1.55)),
        ("皮沙发左扶手", (-9.0, 4.5, 0.78), (0.42, 1.45, 0.88)),
        ("皮沙发右扶手", (-5.2, 4.5, 0.78), (0.42, 1.45, 0.88)),
    )
    for name, loc, size in sofa_parts:
        add_output(box(name, loc, size, furniture, "gloss", CELLS["rust_dark"], category="Props/Furniture", bevel=0.12))
    for index, x in enumerate((-8.0, -7.1, -6.2)):
        add_output(cylinder(f"皮沙发扣钉_{index}", (x, 4.98, 1.95), 0.065, 0.035, furniture, "metal", CELLS["warning"], 8, rotation=(math.pi / 2, 0, 0), category="Props/Furniture"))
    add_output(cylinder("阅读角圆桌", (-3.9, 3.4, 0.68), 0.72, 0.68, furniture, "matte", CELLS["wood"], 12, category="Props/Furniture"))

    # Cash desk and coffee corner.
    add_output(box("老式木质收银台", (3.6, 4.6, 0.62), (4.6, 1.6, 1.35), furniture, "matte", CELLS["wood_dark"], category="Props/Furniture", bevel=0.06))
    for panel in (-1.35, 0, 1.35):
        add_output(box(f"收银台黄铜嵌条_{panel}", (3.6 + panel, 3.78, 0.85), (0.08, 0.05, 0.92), furniture, "metal", CELLS["warning"], category="Props/Furniture"))
    add_output(box("意式咖啡机主体", (4.2, 5.7, 2.0), (1.45, 0.75, 0.92), furniture, "metal", (9, 7), category="Props/Furniture", bevel=0.08))
    for head in (-0.38, 0.38):
        add_output(cylinder(f"咖啡机冲煮头_{head}", (4.2 + head, 5.27, 2.34), 0.13, 0.16, furniture, "metal", CELLS["black"], 10, rotation=(math.pi / 2, 0, 0), category="Props/Furniture"))
    for cup_index in range(5):
        add_output(cylinder(f"陶瓷咖啡杯_{cup_index}", (2.5 + cup_index * 0.42, 5.15, 2.0), 0.12, 0.22, furniture, "gloss", CELLS["canvas" if cup_index % 2 else "purple"], 10, category="Props/Furniture"))

    # Gramophone, fireplace, book crates and cat bed hint.
    add_output(box("留声机木质机箱", (-2.2, 6.0, 0.62), (1.5, 1.1, 0.80), furniture, "matte", CELLS["wood_dark"], category="Props/Furniture", bevel=0.05))
    horn = cylinder("留声机紫铜喇叭", (-2.2, 5.72, 1.42), 0.55, 0.75, furniture, "metal", CELLS["rust"], 12, rotation=(math.pi / 2, 0, 0), category="Props/Furniture")
    horn.scale.x = 1.35
    add_output(horn)
    add_output(box("壁炉造型壁龛", (5.75, 7.82, 0.62), (1.85, 0.45, 2.75), architecture, "matte", CELLS["canvas"], category="Environment/Architecture"))
    add_output(box("壁炉黑色炉膛", (5.75, 7.50, 0.68), (1.15, 0.08, 1.40), architecture, "matte", CELLS["black"], category="Environment/Architecture"))
    add_output(box("猫窝软垫_无动物", (0.2, 6.5, 0.62), (1.35, 1.0, 0.28), furniture, "matte", CELLS["purple"], category="Props/Furniture", bevel=0.18))
    for crate_index, loc in enumerate(((-9.2, 1.2, 0.62), (-8.1, 1.1, 0.62), (5.6, 1.0, 0.62))):
        add_output(box(f"地面书箱_{crate_index}", loc, (1.15, 0.85, 0.70), books, "matte", CELLS["wood"], rotation=(0, 0, 0.08 * crate_index), category="Props/Books", bevel=0.04))
        for book_index in range(4):
            add_output(box(f"书箱内图书_{crate_index}_{book_index}", (loc[0] - 0.35 + book_index * 0.23, loc[1], 1.31), (0.18, 0.55, 0.62), books, "matte", CELLS[("red", "blue", "green", "warning")[book_index]], category="Props/Books"))

    # Category labels and poster wall are real text geometry with palette UVs.
    for index, (body, x) in enumerate((("FICTION", -7.6), ("POETRY", -2.0), ("HISTORY", 3.6))):
        add_output(text_mesh(f"书架分类牌_{body}", body, (x, 7.48, 5.35), 0.28, books, "matte", CELLS["canvas"], category="Props/Books", extrude=0.012))
    for index, (body, x, cell) in enumerate((("READ", -8.0, "red"), ("DREAM", -5.7, "purple"), ("RETURN", -3.1, "warning"))):
        add_output(box(f"复古书封海报底板_{index}", (x, 7.40, 3.05), (1.55, 0.05, 1.70), books, "matte", CELLS[cell], category="Props/Books"))
        add_output(text_mesh(f"复古海报文字_{index}", body, (x, 7.32, 3.92), 0.22, books, "matte", CELLS["canvas"], category="Props/Books", extrude=0.008))

    # Lamps and chandelier.
    lamp_specs = ((-7.0, -1.2, 2.25), (3.9, -1.2, 2.25), (-3.9, 3.4, 2.15))
    for index, loc in enumerate(lamp_specs):
        add_output(cylinder(f"绿罩台灯灯杆_{index}", (loc[0], loc[1], loc[2] - 0.75), 0.045, 0.75, lighting, "metal", CELLS["warning"], 8, category="Lighting"))
        shade = cylinder(f"绿罩台灯灯罩_{index}", loc, 0.36, 0.30, lighting, "gloss", CELLS["green"], 12, category="Lighting")
        shade.scale.z = 0.55
        add_output(shade)
        add_output(cylinder(f"绿罩台灯灯泡_{index}_自发光", (loc[0], loc[1], loc[2] - 0.12), 0.11, 0.18, lighting, "emissive", CELLS["warning"], 10, category="Lighting"))
        light = add_light(f"橱窗台灯暖光_{index}", "POINT", (loc[0], loc[1] - 0.2, loc[2]), (1.0, 0.42, 0.12), 120, COLLECTIONS["展示_灯光镜头"], 2.3)
        light.data.shadow_soft_size = 1.3
        for frame, energy in ((1, 112), (56 + index * 11, 126), (112 + index * 17, 116)):
            light.data.energy = energy
            light.data.keyframe_insert(data_path="energy", frame=frame)
    for arm in range(6):
        angle = math.tau * arm / 6
        add_output(beam_between(f"水晶吊灯黄铜臂_{arm}", (-2.0, 2.5, 5.25), (-2.0 + math.cos(angle) * 1.0, 2.5 + math.sin(angle) * 1.0, 4.55), 0.035, lighting, "metal", CELLS["warning"], 8, "Lighting"))
        add_output(low_sphere(f"水晶吊灯坠饰_{arm}", (-2.0 + math.cos(angle) * 1.0, 2.5 + math.sin(angle) * 1.0, 4.42), (0.15, 0.15, 0.22), lighting, "gloss", CELLS["glass"], "Lighting"))
    chandelier = add_light("书店内部水晶吊灯暖光", "POINT", (-2.0, 2.5, 4.65), (1.0, 0.34, 0.10), 620, COLLECTIONS["展示_灯光镜头"], 6.0)
    chandelier.data.shadow_soft_size = 2.8


def build_steampunk_billboard():
    ad = COLLECTIONS["输出_Props_Advertisement"]
    lighting = COLLECTIONS["输出_Lighting"]
    vfx = COLLECTIONS["输出_VFX"]
    display = COLLECTIONS["展示_灯光镜头"]

    # Layered brass frame mounted above the second-storey windows.
    add_output(box("蒸汽朋克广告牌背板", (-2.0, -2.78, 8.55), (12.8, 0.30, 3.55), ad, "matte", CELLS["purple"], category="Props/Advertisement", bevel=0.16))
    for index, (loc, size) in enumerate((((-2.0, -2.98, 11.92), (13.2, 0.20, 0.22)), ((-2.0, -2.98, 8.50), (13.2, 0.20, 0.22)), ((-8.5, -2.98, 8.55), (0.22, 0.20, 3.55)), ((4.5, -2.98, 8.55), (0.22, 0.20, 3.55)))):
        add_output(box(f"广告牌黄铜框_{index}", loc, size, ad, "metal", CELLS["warning"], category="Props/Advertisement", bevel=0.035))
    for index in range(18):
        x = -8.25 + (index % 9) * 1.56
        z = 8.72 if index < 9 else 11.72
        add_output(cylinder(f"广告牌边缘铆钉_{index}", (x, -3.14, z), 0.07, 0.05, ad, "metal", CELLS["warning"], 8, rotation=(math.pi / 2, 0, 0), category="Props/Advertisement"))

    # Central open-book icon: two covers, pages and glowing spine.
    add_output(box("发光复古书籍左页_自发光", (-3.25, -3.12, 9.20), (2.25, 0.08, 1.65), ad, "emissive", CELLS["warning"], rotation=(0, -0.12, -0.10), category="Props/Advertisement"))
    add_output(box("发光复古书籍右页_自发光", (-0.75, -3.12, 9.20), (2.25, 0.08, 1.65), ad, "emissive", CELLS["canvas"], rotation=(0, 0.12, 0.10), category="Props/Advertisement"))
    add_output(box("发光书籍中央书脊_自发光", (-2.0, -3.24, 9.18), (0.16, 0.06, 1.82), lighting, "emissive", CELLS["red"], category="Lighting"))
    for page in range(4):
        add_output(box(f"发光书籍页线_{page}_自发光", (-3.25 if page < 2 else -0.75, -3.23, 8.88 + (page % 2) * 0.62), (1.45, 0.04, 0.055), lighting, "emissive", CELLS["purple"], rotation=(0, 0, -0.08 if page < 2 else 0.08), category="Lighting"))
    add_output(text_mesh("广告牌主标题_BOOKSHOP_自发光", "BOOKSHOP", (-2.0, -3.32, 11.25), 0.62, ad, "emissive", CELLS["warning"], category="Props/Advertisement", extrude=0.025))

    # Animated gears with separate pivots and teeth.
    gear_specs = ((-6.3, 9.55, 1.05, "rust"), (2.55, 9.58, 1.20, "warning"), (0.65, 10.65, 0.64, "green"))
    for gear_index, (x, z, radius, cell) in enumerate(gear_specs):
        pivot = bpy.data.objects.new(f"广告牌齿轮旋转轴_{gear_index}", None)
        ad.objects.link(pivot)
        pivot.location = (x, -3.15, z)
        pivot["pivot_contract"] = "gear_center"
        ring = torus_object(f"蒸汽朋克齿轮环_{gear_index}", (x, -3.15, z), radius, 0.13, ad, "metal", CELLS[cell], 16, 4, rotation=(math.pi / 2, 0, 0), category="Props/Advertisement")
        ring_world = ring.matrix_world.copy()
        ring.parent = pivot
        ring.matrix_world = ring_world
        add_output(ring)
        add_output(cylinder(f"齿轮轮毂_{gear_index}", (x, -3.20, z), 0.20, 0.10, ad, "metal", CELLS[cell], 10, rotation=(math.pi / 2, 0, 0), category="Props/Advertisement"))
        for tooth in range(12):
            angle = math.tau * tooth / 12
            tooth_obj = box(
                f"齿轮齿_{gear_index}_{tooth}",
                (x + math.cos(angle) * (radius + 0.16), -3.15, z + math.sin(angle) * (radius + 0.16)),
                (0.28, 0.18, 0.16), ad, "metal", CELLS[cell], rotation=(0, angle, 0), category="Props/Advertisement"
            )
            tooth_world = tooth_obj.matrix_world.copy()
            tooth_obj.parent = pivot
            tooth_obj.matrix_world = tooth_world
            add_output(tooth_obj)
        animate_rotation(pivot, 1, [0, math.tau * (-1 if gear_index % 2 else 1)], [1, 240 + gear_index * 40], True)

    # Pipes, pressure gauges and steam outlets.
    for pipe_index, x in enumerate((-7.6, 3.75)):
        add_output(cylinder(f"广告牌蒸汽立管_{pipe_index}", (x, -3.10, 8.72), 0.10, 2.50, ad, "metal", CELLS["rust"], 10, category="Props/Advertisement"))
        add_output(torus_object(f"广告牌管道阀轮_{pipe_index}", (x, -3.25, 9.35), 0.30, 0.045, ad, "metal", CELLS["red"], 12, 4, rotation=(math.pi / 2, 0, 0), category="Props/Advertisement"))
        add_output(cylinder(f"广告牌蒸汽喷口_{pipe_index}", (x, -3.15, 10.65), 0.18, 0.42, ad, "metal", CELLS["rust_dark"], 10, category="Props/Advertisement"))
        for puff in range(6):
            steam = low_sphere(
                f"广告牌周期蒸汽_{pipe_index}_{puff}", (x, -3.2, 11.1 + puff * 0.38),
                (0.20 + puff * 0.06, 0.12 + puff * 0.04, 0.18 + puff * 0.05), vfx,
                "gloss", CELLS["paper"], "VFX"
            )
            steam["vfx_type"] = "periodic_white_steam"
            steam.keyframe_insert(data_path="location", frame=1 + pipe_index * 45)
            steam.scale = Vector((0.08, 0.08, 0.08))
            steam.keyframe_insert(data_path="scale", frame=1 + pipe_index * 45)
            steam.location.z += 2.0
            steam.location.x += 0.5 * (-1) ** pipe_index
            steam.scale = Vector((0.65, 0.45, 0.65))
            steam.keyframe_insert(data_path="location", frame=80 + puff * 8 + pipe_index * 45)
            steam.keyframe_insert(data_path="scale", frame=80 + puff * 8 + pipe_index * 45)
            add_output(steam)

    # Color-block neon perimeter and animated glow lights.
    neon_specs = (
        ("上沿", (-2.0, -3.25, 11.55), (10.5, 0.06, 0.08), "green"),
        ("下沿", (-2.0, -3.25, 8.82), (10.5, 0.06, 0.08), "warning"),
        ("左沿", (-7.25, -3.25, 8.85), (0.08, 0.06, 2.72), "purple"),
        ("右沿", (3.25, -3.25, 8.85), (0.08, 0.06, 2.72), "red"),
    )
    for index, (label, loc, size, cell) in enumerate(neon_specs):
        neon = box(f"广告牌霓虹灯管_{label}_自发光", loc, size, lighting, "emissive", CELLS[cell], category="Lighting", bevel=0.03)
        add_output(neon)
    for index, loc in enumerate(((-5.3, -4.0, 10.0), (1.5, -4.0, 10.0))):
        glow = add_light(f"广告牌霓虹闪烁光_{index}", "POINT", loc, (0.72, 0.10 + index * 0.22, 1.0 if index == 0 else 0.18), 150, display, 3.8)
        glow.data.shadow_soft_size = 2.1
        for frame, energy in ((1, 125), (28 + index * 9, 172), (42 + index * 13, 112), (96 + index * 17, 160)):
            glow.data.energy = energy
            glow.data.keyframe_insert(data_path="energy", frame=frame)


def build_street_props():
    street = COLLECTIONS["输出_Props_Street"]
    transit = COLLECTIONS["输出_Props_Transit"]
    lighting = COLLECTIONS["输出_Lighting"]
    vfx = COLLECTIONS["输出_VFX"]
    vegetation = COLLECTIONS["输出_Vegetation"]
    display = COLLECTIONS["展示_灯光镜头"]

    # Classic red pillar box with crown-like emblem geometry.
    add_output(cylinder("英伦红色邮筒主体", (-12.8, -6.8, 0.34), 0.62, 2.45, street, "gloss", CELLS["red"], 14, category="Props/Street"))
    add_output(cylinder("邮筒穹顶", (-12.8, -6.8, 2.72), 0.72, 0.36, street, "gloss", CELLS["red"], 14, category="Props/Street"))
    add_output(box("邮筒投信口", (-12.8, -7.38, 2.15), (0.72, 0.06, 0.24), street, "metal", CELLS["black"], category="Props/Street"))
    add_output(box("邮筒铭牌", (-12.8, -7.43, 1.35), (0.62, 0.04, 0.72), street, "matte", CELLS["canvas"], category="Props/Street"))
    for ray in range(5):
        angle = math.tau * ray / 5
        add_output(beam_between(f"邮筒王室徽章_{ray}", (-12.8, -7.45, 2.55), (-12.8 + math.cos(angle) * 0.28, -7.45, 2.55 + math.sin(angle) * 0.28), 0.035, street, "metal", CELLS["warning"], 6, "Props/Street"))

    # Gas lamps and iron fence.
    lamp_positions = ((-9.8, -7.6), (7.8, -7.8), (9.4, 5.5))
    for index, (x, y) in enumerate(lamp_positions):
        add_output(cylinder(f"黑色铸铁路灯柱_{index}", (x, y, 0.34), 0.11, 4.5, lighting, "metal", CELLS["black"], 10, category="Lighting"))
        add_output(box(f"煤气灯玻璃灯罩_{index}", (x, y, 4.65), (0.62, 0.62, 0.90), lighting, "gloss", CELLS["glass"], category="Lighting", bevel=0.06))
        add_output(cylinder(f"煤气路灯灯泡_{index}_自发光", (x, y, 4.82), 0.15, 0.30, lighting, "emissive", CELLS["warning"], 10, category="Lighting"))
        light = add_light(f"煤气路灯暖光_{index}", "POINT", (x, y, 4.8), (1.0, 0.33, 0.08), 210, display, 4.0)
        light.data.shadow_soft_size = 2.0
        for frame, energy in ((1, 195), (72 + index * 13, 218), (144 + index * 17, 200)):
            light.data.energy = energy
            light.data.keyframe_insert(data_path="energy", frame=frame)
    for index, x in enumerate((-14.2, -12.2, -10.2, 3.5, 5.5, 7.5)):
        add_output(cylinder(f"黑色铁艺围栏柱_{index}", (x, -8.7, 0.34), 0.06, 1.10, street, "metal", CELLS["black"], 8, category="Props/Street"))
    for z in (0.85, 1.35):
        add_output(box(f"铁艺围栏横杆_{z}", (-3.2, -8.7, z), (22.5, 0.07, 0.07), street, "metal", CELLS["black"], category="Props/Street"))

    # Bench and plaid scarf.
    for slat in range(5):
        add_output(box(f"铸铁长椅木条_{slat}", (-8.7, -5.9 + slat * 0.22, 0.78 + (slat > 2) * (slat - 2) * 0.30), (3.2, 0.16, 0.16), street, "matte", CELLS["wood"], rotation=(0.05 * max(0, slat - 2), 0, 0), category="Props/Street", bevel=0.035))
    for side in (-1, 1):
        add_output(box(f"长椅铸铁腿_{side}", (-8.7 + side * 1.25, -5.75, 0.34), (0.15, 0.78, 0.65), street, "metal", CELLS["black"], category="Props/Street"))
    scarf = box("长椅格纹围巾", (-8.3, -5.62, 1.34), (0.72, 0.08, 1.35), vfx, "matte", CELLS["purple"], rotation=(0.05, 0.05, -0.18), category="VFX")
    add_output(scarf)
    for stripe in range(3):
        add_output(box(f"格纹围巾明黄条_{stripe}", (-8.55 + stripe * 0.25, -5.68, 1.36), (0.06, 0.04, 1.20), vfx, "matte", CELLS["warning"], rotation=(0.05, 0.05, -0.18), category="VFX"))
    animate_rotation(scarf, 1, [-0.04, 0.05, -0.04], [1, 70, 140], True)

    # Road sign and convex corner mirror.
    add_output(cylinder("查令十字路牌立柱", (8.7, -5.1, 0.34), 0.07, 3.6, street, "metal", CELLS["black"], 8, category="Props/Street"))
    add_output(box("查令十字路牌底板", (8.7, -5.25, 3.25), (4.4, 0.14, 0.68), street, "matte", CELLS["green_dark"], category="Props/Street", bevel=0.05))
    add_output(text_mesh("路牌文字_Charing_Cross_Rd", "Charing Cross Rd", (8.7, -5.34, 3.58), 0.36, street, "matte", CELLS["canvas"], category="Props/Street", extrude=0.012))
    add_output(cylinder("街角转弯圆镜", (8.7, -4.95, 5.0), 0.62, 0.10, street, "gloss", CELLS["glass"], 16, rotation=(math.pi / 2, 0, 0), category="Props/Street"))
    add_output(torus_object("街角圆镜橙色边框", (8.7, -5.02, 5.0), 0.65, 0.06, street, "metal", CELLS["warning"], 16, 4, rotation=(math.pi / 2, 0, 0), category="Props/Street"))

    # Bicycle with book parcel and dried flowers.
    wheel_centers = ((2.2, -6.8, 1.15), (4.35, -6.8, 1.15))
    wheel_objects = []
    for index, center in enumerate(wheel_centers):
        wheel = torus_object(f"复古黑色自行车车轮_{index}", center, 0.82, 0.055, street, "metal", CELLS["black"], 18, 4, rotation=(math.pi / 2, 0, 0), category="Props/Street")
        add_output(wheel)
        wheel_objects.append(wheel)
        for spoke in range(8):
            angle = math.tau * spoke / 8
            add_output(beam_between(f"自行车辐条_{index}_{spoke}", center, (center[0] + math.cos(angle) * 0.74, center[1], center[2] + math.sin(angle) * 0.74), 0.012, street, "metal", (9, 3), 6, "Props/Street"))
    bike_points = {"rear": wheel_centers[0], "front": wheel_centers[1], "crank": (3.1, -6.8, 1.0), "seat": (2.75, -6.8, 2.05), "handle": (3.9, -6.8, 2.15)}
    for index, (a, b) in enumerate((("rear", "crank"), ("crank", "seat"), ("seat", "rear"), ("seat", "handle"), ("crank", "handle"), ("handle", "front"))):
        add_output(beam_between(f"自行车车架_{index}", bike_points[a], bike_points[b], 0.045, street, "metal", CELLS["black"], 8, "Props/Street"))
    add_output(box("自行车牛皮纸书包", (4.05, -6.82, 2.15), (1.15, 0.52, 0.62), street, "matte", CELLS["canvas"], category="Props/Street", bevel=0.06))
    for flower in range(5):
        add_output(beam_between(f"自行车干花茎_{flower}", (4.2, -6.8, 2.45), (4.5 + flower * 0.10, -6.8, 3.15 + 0.10 * (flower % 2)), 0.015, vegetation, "matte", CELLS["green_dark"], 6, "Vegetation"))
        add_output(low_sphere(f"自行车干花_{flower}", (4.5 + flower * 0.10, -6.8, 3.18 + 0.10 * (flower % 2)), (0.10, 0.06, 0.10), vegetation, "matte", CELLS["rust"], "Vegetation"))
    for wheel in wheel_objects:
        animate_rotation(wheel, 1, [0, 0.12, 0], [1, 80, 160], True)

    # Notice board, disguised AC crate and climbing ivy.
    add_output(box("社区公告栏木框", (6.25, 6.5, 1.1), (0.28, 3.8, 2.8), street, "matte", CELLS["wood_dark"], category="Props/Street"))
    for index, (y, z, cell) in enumerate(((5.2, 1.6, "purple"), (6.1, 2.5, "warning"), (7.1, 1.4, "red"), (7.7, 2.5, "green"))):
        add_output(box(f"公告栏戏剧海报_{index}", (6.05, y, z), (0.05, 0.75, 0.92), street, "matte", CELLS[cell], rotation=(0, 0.03 * index, 0), category="Props/Street"))
    add_output(box("木箱伪装空调外机", (6.2, 1.9, 0.34), (1.25, 2.1, 1.55), street, "matte", CELLS["wood"], category="Props/Street"))
    for slat in range(5):
        add_output(box(f"空调木箱通风百叶_{slat}", (5.55, 1.25 + slat * 0.32, 0.75), (0.06, 0.20, 0.68), street, "metal", (9, 2), category="Props/Street"))
    for vine in range(10):
        y = 0.0 + vine * 0.72
        add_output(beam_between(f"书店侧墙藤蔓茎_{vine}", (6.95, y, 1.0), (7.0, y + 0.4, 2.4 + vine * 0.55), 0.025, vegetation, "matte", CELLS["green_dark"], 6, "Vegetation"))
        leaf = low_sphere(f"书店侧墙藤蔓叶_{vine}", (7.05, y + 0.2, 2.1 + vine * 0.55), (0.24, 0.10, 0.16), vegetation, "matte", CELLS["green"], "Vegetation")
        add_output(leaf)
        animate_rotation(leaf, 0, [-0.035, 0.04, -0.035], [1, 60 + vine * 3, 120 + vine * 4], True)

    # Green double-decker tram with warm windows and contact pole.
    tram_root = bpy.data.objects.new("复古双层电车_动画根", None)
    transit.objects.link(tram_root)
    tram_root.location = (-5.0, -12.75, 0.30)
    tram_root["pivot_contract"] = "vehicle_ground_center"
    body_parts = (
        ("电车下层车身", (0, 0, 0.45), (8.5, 2.45, 2.25), "green_dark"),
        ("电车上层车身", (0, 0, 2.70), (7.8, 2.30, 2.05), "green"),
        ("电车奶油色腰线", (0, -1.26, 2.25), (8.2, 0.08, 0.18), "canvas"),
        ("电车屋顶", (0, 0, 4.76), (8.2, 2.55, 0.22), "black"),
    )
    for name, loc, size, cell in body_parts:
        obj = box(name, loc, size, transit, "matte", CELLS[cell], category="Props/Transit", bevel=0.10)
        obj.parent = tram_root
        add_output(obj)
    for level, z in enumerate((1.45, 3.55)):
        for side in (-1, 1):
            for window in range(5):
                x = -2.8 + window * 1.4
                pane = box(f"电车暖光车窗_{level}_{side}_{window}_自发光", (x, side * 1.24, z), (0.92, 0.05, 0.72), lighting, "emissive", CELLS["warning"], category="Lighting", bevel=0.035)
                pane.parent = tram_root
                add_output(pane)
    for axle in (-2.7, 2.7):
        for side in (-1, 1):
            wheel = cylinder(f"电车车轮_{axle}_{side}", (axle, side * 1.20, 0.42), 0.48, 0.20, transit, "metal", CELLS["black"], 12, rotation=(math.pi / 2, 0, 0), category="Props/Transit")
            wheel.parent = tram_root
            add_output(wheel)
    pole = beam_between("电车受电弓", (0, 0, 4.95), (1.6, 0, 6.75), 0.055, transit, "metal", CELLS["warning"], 8, "Props/Transit")
    pole.parent = tram_root
    add_output(pole)
    tram_root.keyframe_insert(data_path="location", frame=1)
    tram_root.location.x = 10.0
    tram_root.keyframe_insert(data_path="location", frame=320)
    if tram_root.animation_data and tram_root.animation_data.action:
        for fcurve in tram_root.animation_data.action.fcurves:
            fcurve.modifiers.new("CYCLES")


def add_weather_and_wet_details():
    ground = COLLECTIONS["输出_Environment_Ground"]
    vfx = COLLECTIONS["输出_VFX"]
    lighting = COLLECTIONS["输出_Lighting"]
    random.seed(2251)

    # Puddles and animated ripples.
    for puddle_index, (x, y, radius, squash) in enumerate(((-13.5, -11.0, 1.5, 0.45), (-4.0, -10.3, 1.9, 0.38), (6.3, -14.8, 1.3, 0.55), (10.8, 1.0, 1.1, 0.42))):
        puddle = cylinder(f"潮湿街面积水_{puddle_index}", (x, y, 0.24), radius, 0.018, ground, "gloss", CELLS["water"], 16, category="Environment/Ground")
        puddle.scale.y = squash
        add_output(puddle)
        for ripple_index in range(2):
            ripple = torus_object(f"雨滴积水波纹_{puddle_index}_{ripple_index}", (x, y, 0.27 + ripple_index * 0.008), 0.28 + ripple_index * 0.30, 0.012, vfx, "gloss", CELLS["concrete_light"], 16, 4, category="VFX")
            ripple.scale.y = squash
            ripple.keyframe_insert(data_path="scale", frame=1 + ripple_index * 24)
            ripple.scale.x *= 1.45
            ripple.scale.y *= 1.45
            ripple.keyframe_insert(data_path="scale", frame=72 + ripple_index * 24)
            if ripple.animation_data and ripple.animation_data.action:
                for fcurve in ripple.animation_data.action.fcurves:
                    fcurve.modifiers.new("CYCLES")
            add_output(ripple)

    # Restrained rain streaks and droplets on shop glass.
    for index in range(42):
        streak = box(
            f"英伦夜雨细线_{index}",
            (random.uniform(-16, 16), random.uniform(-16, 10), random.uniform(2.0, 13.0)),
            (0.018, 0.018, random.uniform(0.35, 0.75)), vfx, "gloss", CELLS["glass"],
            rotation=(0.05, -0.06, 0), category="VFX"
        )
        streak["vfx_type"] = "light_rain"
        streak.keyframe_insert(data_path="location", frame=1 + index % 17)
        streak.location.z -= 7.0
        streak.location.x += 0.8
        streak.keyframe_insert(data_path="location", frame=75 + index % 23)
        if streak.animation_data and streak.animation_data.action:
            for fcurve in streak.animation_data.action.fcurves:
                fcurve.modifiers.new("CYCLES")
        add_output(streak)
    for pane_index, x in enumerate((-8.1, -6.6, -5.1, 3.3, 4.6)):
        for drop in range(3):
            droplet = box(
                f"橱窗玻璃雨痕_{pane_index}_{drop}", (x + drop * 0.18, -2.68, 1.4 + drop * 0.85),
                (0.025, 0.018, 0.55 + 0.22 * drop), vfx, "gloss", CELLS["glass"],
                rotation=(0.05, 0, 0.03 * drop), category="VFX"
            )
            droplet.keyframe_insert(data_path="location", frame=1 + drop * 20)
            droplet.location.z -= 1.5
            droplet.keyframe_insert(data_path="location", frame=100 + drop * 20)
            add_output(droplet)

    # Open display book with subtly animated pages.
    for page_index, angle in enumerate((-0.18, -0.07, 0.08, 0.20)):
        page = box(
            f"橱窗开放书页_{page_index}", (-5.8 + (page_index > 1) * 0.45, -1.65, 1.72 + page_index * 0.012),
            (0.62, 0.44, 0.018), vfx, "matte", CELLS["paper"], rotation=(0, angle, -0.18 if page_index < 2 else 0.18), category="VFX"
        )
        add_output(page)
        if page_index == 3:
            animate_rotation(page, 1, [0.12, 0.32, 0.12], [1, 75, 150], True)

    # Distant traffic signal, kept as a secondary accent.
    add_output(cylinder("远处交通灯立柱", (14.2, 10.0, 0.34), 0.08, 4.4, lighting, "metal", CELLS["black"], 8, category="Lighting"))
    add_output(box("远处交通灯箱", (14.2, 10.0, 4.45), (0.62, 0.48, 1.55), lighting, "metal", CELLS["black"], category="Lighting", bevel=0.08))
    for index, (z, cell) in enumerate(((5.55, "red"), (5.02, "warning"), (4.50, "green"))):
        signal = cylinder(f"远处交通信号_{index}_自发光", (14.2, 9.73, z), 0.15, 0.05, lighting, "emissive", CELLS[cell], 10, rotation=(math.pi / 2, 0, 0), category="Lighting")
        add_output(signal)


def add_entrance_garden_and_falling_leaves_v002():
    vegetation = COLLECTIONS["输出_Vegetation"]
    street = COLLECTIONS["输出_Props_Street"]
    vfx = COLLECTIONS["输出_VFX"]
    random.seed(8207)

    planter_specs = (
        (-2.55, -3.05, 0.52, 0.62), (1.55, -3.10, 0.48, 0.58),
        (-9.40, -3.05, 0.58, 0.70), (5.75, -3.02, 0.52, 0.62),
    )
    for planter_index, (x, y, radius, height) in enumerate(planter_specs):
        planter = cylinder(
            f"书店入口复古花盆_{planter_index}", (x, y, 0.36), radius, height,
            street, "matte", (8, 3 + planter_index % 2), 12, category="Props/Street"
        )
        add_output(planter)
        add_output(torus_object(
            f"入口花盆黄铜箍_{planter_index}", (x, y, 0.78), radius + 0.035, 0.035,
            street, "metal", CELLS["warning"], 12, 4, category="Props/Street"
        ))
        for branch in range(7):
            angle = math.tau * branch / 7 + planter_index * 0.37
            height_step = 0.85 + 0.16 * (branch % 3)
            end = (x + math.cos(angle) * 0.38, y + math.sin(angle) * 0.30, 0.78 + height_step)
            add_output(beam_between(
                f"入口植物枝条_{planter_index}_{branch}", (x, y, 0.75), end, 0.022,
                vegetation, "matte", (8, 5), 6, "Vegetation"
            ))
            for leaf_index in range(2):
                leaf = low_sphere(
                    f"入口植物叶片_{planter_index}_{branch}_{leaf_index}",
                    (end[0] + math.cos(angle + leaf_index * 1.7) * 0.20,
                     end[1] + math.sin(angle + leaf_index * 1.7) * 0.12,
                     end[2] - 0.08 + leaf_index * 0.20),
                    (0.27, 0.11, 0.09), vegetation, "matte", (8, 5), "Vegetation"
                )
                leaf.rotation_euler.z = angle + leaf_index * 0.7
                add_output(leaf)
                animate_rotation(leaf, 0, [-0.025, 0.035, -0.025], [1, 58 + branch * 3, 116 + branch * 4], True)

    # Ground moss and low planting break the hard storefront edge.
    for patch_index, (x, y) in enumerate(((-10.2, -4.15), (-7.8, -4.0), (2.3, -4.1), (4.8, -4.0), (7.0, -2.0))):
        patch = cylinder(
            f"入口石缝青苔_{patch_index}", (x, y, 0.39), 0.46 + 0.08 * (patch_index % 2),
            0.025, vegetation, "matte", (8, 5), 10, category="Vegetation"
        )
        patch.scale.y = 0.34
        add_output(patch)

    # Leaves use individually animated pivots so their paths and rotations can be edited independently.
    for leaf_index in range(28):
        start = Vector((random.uniform(-14.0, 10.0), random.uniform(-8.0, 5.0), random.uniform(2.0, 10.5)))
        leaf = low_sphere(
            f"动态飘落树叶_{leaf_index}", start,
            (0.16 + 0.04 * (leaf_index % 3), 0.055, 0.11 + 0.025 * (leaf_index % 2)),
            vfx, "matte", (8, 5 if leaf_index % 5 else 4), "VFX"
        )
        leaf["vfx_type"] = "wind_driven_falling_leaf"
        leaf.rotation_euler = (0.30 * leaf_index, 0.17 * leaf_index, 0.55 * leaf_index)
        first_frame = 1 + leaf_index % 37
        leaf.keyframe_insert(data_path="location", frame=first_frame)
        leaf.keyframe_insert(data_path="rotation_euler", frame=first_frame)
        leaf.location = start + Vector((3.5 + random.uniform(-1.0, 1.0), -1.4 + random.uniform(-0.6, 0.6), -8.5))
        leaf.rotation_euler = (leaf.rotation_euler.x + math.tau * 1.5, leaf.rotation_euler.y + math.tau, leaf.rotation_euler.z + math.tau * 2.0)
        leaf.keyframe_insert(data_path="location", frame=150 + leaf_index % 43)
        leaf.keyframe_insert(data_path="rotation_euler", frame=150 + leaf_index % 43)
        if leaf.animation_data and leaf.animation_data.action:
            for fcurve in leaf.animation_data.action.fcurves:
                for point in fcurve.keyframe_points:
                    point.interpolation = "LINEAR"
                fcurve.modifiers.new("CYCLES")
        add_output(leaf)

    # A few settled leaves keep the animation visually connected to the ground.
    for leaf_index, (x, y, angle) in enumerate(((-11.5, -6.0, 0.4), (-6.2, -7.1, -0.7), (-1.2, -5.7, 0.9), (3.0, -4.6, -0.2), (6.2, -7.0, 0.6), (10.0, -2.0, -0.9))):
        leaf = low_sphere(
            f"地面潮湿落叶_{leaf_index}", (x, y, 0.42), (0.25, 0.07, 0.035),
            vegetation, "matte", (8, 4 if leaf_index % 2 else 5), "Vegetation"
        )
        leaf.rotation_euler.z = angle
        add_output(leaf)


def add_drain_steam_v002():
    ground = COLLECTIONS["输出_Environment_Ground"]
    vfx = COLLECTIONS["输出_VFX"]
    street = COLLECTIONS["输出_Props_Street"]
    drain_x, drain_y = (-1.5, -8.15)

    add_output(cylinder(
        "街角圆形下水道井盖", (drain_x, drain_y, 0.30), 0.78, 0.08,
        ground, "metal", (9, 2), 18, category="Environment/Ground"
    ))
    add_output(torus_object(
        "下水道井盖外圈", (drain_x, drain_y, 0.39), 0.68, 0.055,
        ground, "metal", (9, 3), 18, 4, category="Environment/Ground"
    ))
    for slot in range(7):
        add_output(box(
            f"下水道井盖热气槽_{slot}", (drain_x - 0.48 + slot * 0.16, drain_y, 0.40),
            (0.055, 0.82, 0.025), ground, "matte", (9, 1), category="Environment/Ground"
        ))
    for valve_index, x in enumerate((drain_x - 0.32, drain_x + 0.32)):
        add_output(cylinder(
            f"下水道检修螺栓_{valve_index}", (x, drain_y, 0.41), 0.07, 0.04,
            street, "metal", (9, 4), 8, category="Props/Street"
        ))

    for puff_index in range(15):
        base_angle = puff_index * 1.37
        start = Vector((
            drain_x + math.cos(base_angle) * (0.10 + 0.03 * (puff_index % 3)),
            drain_y + math.sin(base_angle) * 0.12,
            0.48 + puff_index * 0.12,
        ))
        steam = low_sphere(
            f"下水道周期热蒸汽_{puff_index}", start,
            (0.16 + puff_index * 0.018, 0.12 + puff_index * 0.014, 0.20 + puff_index * 0.025),
            vfx, "gloss", (9, 8), "VFX"
        )
        steam["vfx_type"] = "warm_drain_steam"
        if hasattr(steam, "visible_shadow"):
            steam.visible_shadow = False
        start_frame = 1 + (puff_index * 13) % 90
        steam.scale = Vector((0.08, 0.08, 0.08))
        steam.keyframe_insert(data_path="location", frame=start_frame)
        steam.keyframe_insert(data_path="scale", frame=start_frame)
        steam.location = start + Vector((0.65 + 0.08 * puff_index, 0.20 * math.sin(base_angle), 3.2 + 0.10 * puff_index))
        steam.scale = Vector((0.72, 0.48, 0.72))
        steam.keyframe_insert(data_path="location", frame=start_frame + 105)
        steam.keyframe_insert(data_path="scale", frame=start_frame + 105)
        if steam.animation_data and steam.animation_data.action:
            for fcurve in steam.animation_data.action.fcurves:
                fcurve.modifiers.new("CYCLES")
        add_output(steam)


def build_elevated_metro_v002():
    transit = COLLECTIONS["输出_Props_Transit"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    lighting = COLLECTIONS["输出_Lighting"]

    track_y = 12.4
    deck_z = 17.2
    # Elevated steelwork is kept behind the shop and above the roof silhouette.
    for column_index, x in enumerate((-15.0, -8.0, -1.0, 6.0, 13.0)):
        for side in (-1, 1):
            column_y = track_y + side * 1.65
            add_output(box(
                f"空中地铁高架立柱_{column_index}_{side}", (x, column_y, 0.35),
                (0.42, 0.42, deck_z - 0.2), architecture, "metal", (9, 1),
                category="Environment/Architecture", bevel=0.04
            ))
            add_output(box(
                f"高架立柱奶油石基座_{column_index}_{side}", (x, column_y, 0.35),
                (0.85, 0.85, 0.55), architecture, "matte", (9, 5), category="Environment/Architecture"
            ))
        add_output(box(
            f"空中地铁横向承重梁_{column_index}", (x, track_y, deck_z - 0.55),
            (0.58, 4.2, 0.55), architecture, "metal", (9, 2), category="Environment/Architecture"
        ))
        for brace_side in (-1, 1):
            add_output(beam_between(
                f"空中地铁斜撑_{column_index}_{brace_side}",
                (x, track_y + brace_side * 1.55, deck_z - 3.6),
                (x, track_y, deck_z - 0.65), 0.11, architecture, "metal", (9, 2), 8,
                "Environment/Architecture"
            ))

    for rail_index, y in enumerate((track_y - 0.72, track_y + 0.72)):
        add_output(box(
            f"空中地铁纵向箱梁_{rail_index}", (0, y, deck_z), (33.0, 0.48, 0.42),
            architecture, "metal", (9, 2), category="Environment/Architecture", bevel=0.05
        ))
        add_output(box(
            f"空中地铁钢轨_{rail_index}", (0, y, deck_z + 0.44), (33.0, 0.12, 0.12),
            transit, "metal", (9, 4), category="Props/Transit"
        ))
    for sleeper_index, x in enumerate(range(-16, 17, 2)):
        add_output(box(
            f"空中地铁轨枕_{sleeper_index}", (x, track_y, deck_z + 0.30),
            (0.18, 2.35, 0.10), transit, "matte", (9, 1), category="Props/Transit"
        ))
    for guard_side in (-1, 1):
        guard_y = track_y + guard_side * 1.35
        add_output(box(
            f"空中地铁检修护栏_{guard_side}", (0, guard_y, deck_z + 1.15),
            (33.0, 0.08, 0.08), architecture, "metal", (9, 2), category="Environment/Architecture"
        ))
        for post_index, x in enumerate(range(-16, 17, 2)):
            add_output(cylinder(
                f"空中地铁护栏柱_{guard_side}_{post_index}", (x, guard_y, deck_z + 0.45),
                0.035, 0.78, architecture, "metal", (9, 2), 6, category="Environment/Architecture"
            ))

    metro_root = bpy.data.objects.new("空中地铁_往返动画根", None)
    transit.objects.link(metro_root)
    metro_root.location = (0, 0, 0)
    metro_root["pivot_contract"] = "train_ground_center"
    metro_root["animation_contract"] = "bidirectional_loop_frames_1_360"

    for car_index, center_x in enumerate((-3.45, 3.45)):
        car_parts = (
            (f"空中地铁车厢下体_{car_index}", (center_x, track_y, deck_z + 0.55), (6.55, 2.35, 1.55), (8, 3)),
            (f"空中地铁车厢上体_{car_index}", (center_x, track_y, deck_z + 2.10), (6.20, 2.18, 1.60), (8, 4)),
            (f"空中地铁流线屋顶_{car_index}", (center_x, track_y, deck_z + 3.68), (6.30, 2.28, 0.22), (9, 2)),
            (f"空中地铁低饱和腰线_{car_index}", (center_x, track_y - 1.20, deck_z + 1.70), (6.15, 0.06, 0.18), (9, 6)),
        )
        for name, loc, size, cell in car_parts:
            part = box(name, loc, size, transit, "matte", cell, category="Props/Transit", bevel=0.12)
            part.parent = metro_root
            add_output(part)
        for side in (-1, 1):
            for window_index in range(5):
                window_x = center_x - 2.35 + window_index * 1.18
                window = box(
                    f"空中地铁暖光车窗_{car_index}_{side}_{window_index}_自发光",
                    (window_x, track_y + side * 1.12, deck_z + 2.42),
                    (0.82, 0.05, 0.72), lighting, "emissive", CELLS["warning"],
                    category="Lighting", bevel=0.035
                )
                window.parent = metro_root
                add_output(window)
            door = box(
                f"空中地铁滑门_{car_index}_{side}", (center_x, track_y + side * 1.14, deck_z + 1.25),
                (1.05, 0.06, 2.10), transit, "metal", (8, 5), category="Props/Transit", bevel=0.04
            )
            door.parent = metro_root
            add_output(door)
        for bogie_x in (-2.0, 2.0):
            bogie = box(
                f"空中地铁转向架_{car_index}_{bogie_x}", (center_x + bogie_x, track_y, deck_z + 0.12),
                (1.15, 1.75, 0.34), transit, "metal", (9, 1), category="Props/Transit"
            )
            bogie.parent = metro_root
            add_output(bogie)
            for wheel_side in (-1, 1):
                wheel = cylinder(
                    f"空中地铁钢轮_{car_index}_{bogie_x}_{wheel_side}",
                    (center_x + bogie_x, track_y + wheel_side * 0.74, deck_z + 0.26),
                    0.28, 0.16, transit, "metal", (9, 0), 12,
                    rotation=(math.pi / 2, 0, 0), category="Props/Transit"
                )
                wheel.parent = metro_root
                add_output(wheel)
        for roof_unit in (-1.4, 1.4):
            unit = box(
                f"空中地铁车顶设备_{car_index}_{roof_unit}",
                (center_x + roof_unit, track_y, deck_z + 3.90), (1.2, 0.85, 0.30),
                transit, "metal", (9, 2), category="Props/Transit", bevel=0.06
            )
            unit.parent = metro_root
            add_output(unit)

    connector = box(
        "空中地铁车厢风琴连接", (0, track_y, deck_z + 1.55), (0.46, 2.0, 2.40),
        transit, "matte", (9, 1), category="Props/Transit", bevel=0.05
    )
    connector.parent = metro_root
    add_output(connector)
    metro_root.location.x = -9.5
    metro_root.keyframe_insert(data_path="location", frame=1)
    metro_root.location.x = 9.5
    metro_root.keyframe_insert(data_path="location", frame=180)
    metro_root.location.x = -9.5
    metro_root.keyframe_insert(data_path="location", frame=360)
    if metro_root.animation_data and metro_root.animation_data.action:
        for fcurve in metro_root.animation_data.action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = "SINE"
            fcurve.modifiers.new("CYCLES")


def enhance_billboard_structure_v002():
    ad = COLLECTIONS["输出_Props_Advertisement"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    lighting = COLLECTIONS["输出_Lighting"]

    # Deep cantilever frame makes the billboard read as a mounted mechanical installation.
    for mount_index, x in enumerate((-7.7, -4.0, -0.2, 3.6)):
        add_output(box(
            f"广告牌外伸粗体悬臂_{mount_index}", (x, -3.95, 8.45),
            (0.28, 2.35, 0.32), architecture, "metal", (9, 1), category="Environment/Architecture", bevel=0.04
        ))
        add_output(beam_between(
            f"广告牌悬臂下斜撑_{mount_index}", (x, -2.55, 7.35), (x, -5.05, 8.48),
            0.11, architecture, "metal", (9, 2), 8, "Environment/Architecture"
        ))
        add_output(beam_between(
            f"广告牌悬臂上拉杆_{mount_index}", (x, -2.55, 11.85), (x, -5.05, 10.70),
            0.085, architecture, "metal", (9, 3), 8, "Environment/Architecture"
        ))
    for level, z in enumerate((8.45, 10.15, 11.85)):
        add_output(box(
            f"广告牌外伸纵向桁架_{level}", (-2.0, -5.02, z),
            (13.7, 0.24, 0.24), architecture, "metal", (9, 2), category="Environment/Architecture", bevel=0.035
        ))
    for bay_index in range(7):
        x0 = -8.0 + bay_index * 1.95
        x1 = x0 + 1.95
        add_output(beam_between(
            f"广告牌背部交叉撑_A_{bay_index}", (x0, -5.02, 8.55), (x1, -5.02, 11.75),
            0.055, architecture, "metal", (9, 3), 8, "Environment/Architecture"
        ))
        add_output(beam_between(
            f"广告牌背部交叉撑_B_{bay_index}", (x0, -5.02, 11.75), (x1, -5.02, 8.55),
            0.055, architecture, "metal", (9, 3), 8, "Environment/Architecture"
        ))

    # Large pipes run around and beyond the sign, with elbows represented as valve rings.
    for pipe_index, (x, cell) in enumerate(((-8.85, (9, 2)), (4.85, (9, 3)))):
        add_output(cylinder(
            f"广告牌延展粗蒸汽管_{pipe_index}", (x, -4.65, 7.55), 0.18, 4.60,
            ad, "metal", cell, 12, category="Props/Advertisement"
        ))
        add_output(box(
            f"广告牌顶部延展管_{pipe_index}",
            ((x - 6.0) / 2 if pipe_index == 0 else (x + 6.0) / 2, -4.65, 12.10),
            (abs(x + 6.0) if pipe_index == 0 else abs(6.0 - x), 0.34, 0.34),
            ad, "metal", cell, category="Props/Advertisement", bevel=0.06
        ))
        add_output(torus_object(
            f"广告牌粗管检修阀_{pipe_index}", (x, -4.82, 9.85), 0.46, 0.07,
            ad, "metal", CELLS["red"], 14, 4, rotation=(math.pi / 2, 0, 0), category="Props/Advertisement"
        ))

    # Two secondary gear layers add depth outside the original sign silhouette.
    for gear_index, (x, z, radius) in enumerate(((-9.1, 10.75, 0.72), (5.1, 9.35, 0.86))):
        pivot = bpy.data.objects.new(f"广告牌外置齿轮旋转轴_{gear_index}", None)
        ad.objects.link(pivot)
        pivot.location = (x, -4.98, z)
        pivot["pivot_contract"] = "gear_center"
        ring = torus_object(
            f"广告牌外置齿轮环_{gear_index}", (x, -4.98, z), radius, 0.11,
            ad, "metal", CELLS["warning" if gear_index else "purple"], 14, 4,
            rotation=(math.pi / 2, 0, 0), category="Props/Advertisement"
        )
        ring_world = ring.matrix_world.copy()
        ring.parent = pivot
        ring.matrix_world = ring_world
        add_output(ring)
        for tooth_index in range(10):
            angle = math.tau * tooth_index / 10
            tooth = box(
                f"广告牌外置齿轮齿_{gear_index}_{tooth_index}",
                (x + math.cos(angle) * (radius + 0.13), -4.98, z + math.sin(angle) * (radius + 0.13)),
                (0.24, 0.18, 0.14), ad, "metal", CELLS["warning" if gear_index else "purple"],
                rotation=(0, angle, 0), category="Props/Advertisement"
            )
            tooth_world = tooth.matrix_world.copy()
            tooth.parent = pivot
            tooth.matrix_world = tooth_world
            add_output(tooth)
        animate_rotation(pivot, 1, [0, math.tau * (-1 if gear_index else 1)], [1, 300], True)

    for light_index, loc in enumerate(((-8.8, -5.2, 11.9), (4.8, -5.2, 11.9))):
        lamp = cylinder(
            f"广告牌外伸检修灯_{light_index}_自发光", loc, 0.13, 0.22,
            lighting, "emissive", CELLS["warning"], 10, category="Lighting"
        )
        add_output(lamp)


def apply_unified_palette_v002():
    """Keep most surfaces in a low-saturation teal/blue-gray family and reserve three accents."""
    primary_cells = ((8, 3), (8, 4), (8, 5), (9, 3), (9, 4))
    accent_tokens = (
        "自发光", "霓虹", "广告牌背板", "广告牌主标题", "发光复古书籍",
        "邮筒主体", "邮筒穹顶", "王室徽章", "黄铜门把手", "黄铜门锁",
        "黄铜门铃", "花盆黄铜箍", "海报", "地毯花纹", "沙发扣钉",
        "粗管检修阀", "外置齿轮", "齿轮齿", "齿轮环",
        "下水道周期热蒸汽",
    )
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if any(token in obj.name for token in accent_tokens):
            continue
        category = obj.get("asset_category", "")
        seed = sum(ord(char) for char in obj.name)
        if category in ("Lighting",):
            continue
        if category == "Vegetation":
            palette_uv(obj.data, (8, 5 if seed % 4 else 4))
            continue
        if category.startswith(("Environment/", "Props/", "VFX", "Collision/")):
            palette_uv(obj.data, primary_cells[seed % len(primary_cells)])

    # Explicit focal surfaces keep the requested ink-green identity while remaining below 40% saturation.
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if any(token in obj.name for token in ("书店左侧承重墙", "书店右侧转角墙", "书店后墙", "二层正立面", "首层墨绿立柱")):
            palette_uv(obj.data, (8, 5))


def create_source_prototypes():
    source_ground = COLLECTIONS["源_Environment_Ground"]
    source_arch = COLLECTIONS["源_Environment_Architecture"]
    source_furniture = COLLECTIONS["源_Props_Furniture"]
    source_ad = COLLECTIONS["源_Props_Advertisement"]
    prototypes = (
        ("石板路模块", (2.05, 1.75, 0.08), source_ground, "matte", "concrete_light", "Environment/Ground"),
        ("墨绿外墙模块", (4.0, 0.45, 5.8), source_arch, "matte", "green_dark", "Environment/Architecture"),
        ("奶油石材线脚", (4.0, 0.35, 0.45), source_arch, "matte", "canvas", "Environment/Architecture"),
        ("深橡木书架模块", (3.8, 0.6, 5.0), source_furniture, "matte", "wood_dark", "Props/Furniture"),
        ("广告牌黄铜框模块", (4.0, 0.20, 0.22), source_ad, "metal", "warning", "Props/Advertisement"),
    )
    for index, (name, size, collection, role, cell, category) in enumerate(prototypes):
        proto = box(f"源组件_{name}", (-70 + index * 6.0, 0, 0), size, collection, role, CELLS[cell], category=category)
        proto["asset_id"] = f"ENV_BOOKSHOP_MODULE_{index:02d}"
        proto["snap_grid_m"] = 0.25
        SOURCE_PROTOTYPES.append(proto)


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
    scene.view_settings.exposure = 0.58
    if hasattr(scene.render, "use_freestyle"):
        scene.render.use_freestyle = True
        scene.render.line_thickness = 1.0
        line_set = scene.view_layers[0].freestyle_settings.linesets[0]
        line_set.select_silhouette = True
        line_set.select_border = True
        line_set.select_crease = True
        line_set.select_material_boundary = False
        line_set.linestyle.color = (0.008, 0.012, 0.014)
        line_set.linestyle.thickness = 1.0

    world = scene.world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    links = world.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputWorld")
    background = nodes.new("ShaderNodeBackground")
    background.inputs["Color"].default_value = (0.018, 0.033, 0.052, 1.0)
    background.inputs["Strength"].default_value = 0.30
    links.new(background.outputs["Background"], output.inputs["Surface"])

    display = COLLECTIONS["展示_灯光镜头"]
    moon = add_light("英伦夜色冷月主光", "SUN", (-25, -35, 45), (0.22, 0.34, 0.55), 2.05, display)
    moon.rotation_euler = (math.radians(48), math.radians(-18), math.radians(-35))
    moon.data.angle = math.radians(18)
    fill = add_light("潮湿街景冷色补光", "AREA", (10, -18, 28), (0.18, 0.34, 0.48), 1750, display, 34)
    fill.rotation_euler = (0.25, 0, 0.3)
    interior = add_light("书店内部整体暖光", "AREA", (-2, 2.2, 5.3), (1.0, 0.34, 0.09), 680, display, 11)
    interior.rotation_euler = (0.15, 0, 0)
    shopfront = add_light("橱窗外溢暖光", "AREA", (-2, -3.8, 3.1), (1.0, 0.28, 0.07), 390, display, 12)
    shopfront.rotation_euler = (math.radians(82), 0, 0)
    rim = add_light("蒸汽朋克广告牌轮廓光", "AREA", (-2, -6.0, 10.0), (0.55, 0.14, 0.75), 680, display, 10)
    rim.rotation_euler = (math.radians(78), 0, 0)

    camera = add_camera("第三视角_英伦街角微缩模型主镜头", (40, -45, 34), (-1.5, 0.4, 5.8), 53, display)
    camera.data.dof.use_dof = False
    scene.camera = camera
    focus = bpy.data.objects.new("自由观察旋转中心", None)
    display.objects.link(focus)
    focus.location = (-1.5, -0.8, 3.8)
    focus["interaction_hint"] = "Orbit, pan and zoom in Blender viewport; no in-scene UI"


def write_manifest():
    categories = {}
    for obj in bpy.context.scene.objects:
        category = obj.get("asset_category")
        if category:
            categories[category] = categories.get(category, 0) + 1
    manifest = {
        "asset": "英伦风街角书店微缩景观",
        "asset_id": "ENV_BRITISH_CORNER_BOOKSHOP_002",
        "version": "v002",
        "base_dimensions_m": [34.0, 34.0],
        "style": [
            "toon-rendered", "restrained-dopamine-color", "British-vintage", "steampunk",
            "wet-night", "elevated-metro", "falling-leaves", "drain-steam",
        ],
        "palette": str(PALETTE_FILE),
        "materials": [material.name for material in MATERIALS.values()],
        "category_object_counts": categories,
        "source_prototype_count": len(SOURCE_PROTOTYPES),
        "game_output_object_count": len(OUTPUT_OBJECTS),
        "collision_object_count": len(COLLISION_OBJECTS),
        "animation_frame_range": [1, 360],
        "contains_people_or_animals": False,
        "ui_visible_in_showcase": False,
        "deliverables": {
            "source_blend": str(SOURCE_BLEND),
            "game_blend": str(GAME_BLEND),
            "full_preview": str(FULL_PREVIEW),
            "interior_preview": str(DETAIL_PREVIEW),
        },
    }
    MANIFEST_FILE.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def save_deliverables():
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND))
    bpy.ops.wm.save_as_mainfile(filepath=str(GAME_BLEND), copy=True)


def build_scene():
    ensure_bookshop_dirs()
    clear_scene()
    setup_bookshop_collections()
    setup_palette_materials()
    build_base_and_street()
    build_bookshop_architecture()
    build_interior()
    build_steampunk_billboard()
    build_street_props()
    add_weather_and_wet_details()
    add_entrance_garden_and_falling_leaves_v002()
    add_drain_steam_v002()
    build_elevated_metro_v002()
    enhance_billboard_structure_v002()
    create_source_prototypes()
    apply_unified_palette_v002()
    setup_render_and_lighting()
    write_manifest()
    save_deliverables()
    print(json.dumps({
        "status": "built",
        "objects": len(bpy.context.scene.objects),
        "meshes": sum(1 for obj in bpy.context.scene.objects if obj.type == "MESH"),
        "materials": len(bpy.data.materials),
        "output_objects": len(OUTPUT_OBJECTS),
        "source_blend": str(SOURCE_BLEND),
        "game_blend": str(GAME_BLEND),
    }, ensure_ascii=False))


def render_previews():
    scene = bpy.context.scene
    camera = bpy.data.objects.get("第三视角_英伦街角微缩模型主镜头")
    if camera is None:
        raise RuntimeError("Main camera is missing")
    scene.camera = camera
    scene.frame_set(112)
    camera.location = (40, -45, 34)
    camera.data.ortho_scale = 53
    camera.rotation_euler = (Vector((-1.5, 0.4, 5.8)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(FULL_PREVIEW)
    bpy.ops.render.render(write_still=True)

    scene.frame_set(72)
    camera.location = (25, -31, 19)
    camera.data.ortho_scale = 31
    camera.rotation_euler = (Vector((-1.8, 0.4, 3.8)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(DETAIL_PREVIEW)
    bpy.ops.render.render(write_still=True)
    save_deliverables()
    print(json.dumps({"status": "rendered", "full": str(FULL_PREVIEW), "detail": str(DETAIL_PREVIEW)}, ensure_ascii=False))


BOOKSHOP_MODE = globals().get("BOOKSHOP_MODE", "build")
if BOOKSHOP_MODE == "build":
    build_scene()
elif BOOKSHOP_MODE == "render":
    render_previews()
else:
    raise ValueError(f"Unknown BOOKSHOP_MODE: {BOOKSHOP_MODE}")
