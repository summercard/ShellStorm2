import bpy
import json
import math
import os
import runpy
import sys
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_SCRIPT = os.path.join(os.path.dirname(SCRIPT_DIR), "卧室", "build_japanese_bedroom.py")

OFFICE_STAGE = ""
_office_file = __file__
__file__ = BASE_SCRIPT
JBR_STAGE = ""
exec(compile(open(BASE_SCRIPT, "r", encoding="utf-8").read(), BASE_SCRIPT, "exec"), globals())
__file__ = _office_file

LAYOUT_PATH = os.path.join(SCRIPT_DIR, "scene.json")
BLEND_PATH = os.path.join(SCRIPT_DIR, "办公室03_日式微缩场景.blend")
PREVIEW_PATH = os.path.join(SCRIPT_DIR, "办公室03_日式微缩场景_预览.png")
PALETTE_PATH = os.path.join(SCRIPT_DIR, "办公室03_色盘_10x10_512.png")
REPORT_PATH = os.path.join(SCRIPT_DIR, "办公室03_布局校验.json")
UV_REPORT_PATH = os.path.join(SCRIPT_DIR, "办公室03_色盘UV验收.json")

TYPE_BOUNDS = {
    "办公桌": Vector((1.6, 0.75, 0.795)),
    "办公椅": Vector((1.10, 1.10, 1.25)),
    "显示器": Vector((0.90, 0.25, 1.05)),
    "文件柜": Vector((0.85, 0.5725, 1.25)),
    "书架": Vector((1.10, 0.38, 1.80)),
    "打印机": Vector((0.68, 0.70, 0.56)),
    "饮水机": Vector((0.42, 0.52, 1.43)),
    "会议桌": Vector((1.90, 1.178, 0.835)),
    "白板": Vector((1.60, 0.1975, 1.875)),
    "门": Vector((1.25, 0.225, 2.35)),
    "窗": Vector((2.15, 0.17, 1.70)),
    "柜子": Vector((1.40, 0.61, 1.65)),
}


def number(value):
    return float(value)


def load_layout():
    with open(LAYOUT_PATH, "r", encoding="utf-8") as handle:
        return json.load(handle)


def make_root(record, coll):
    root = bpy.data.objects.new(record["name"], None)
    coll.objects.link(root)
    p, r, s = record["position"], record["rotation"], record["scale"]
    root.location = tuple(number(p[axis]) for axis in ("x", "y", "z"))
    root.rotation_euler = tuple(math.radians(number(r[axis])) for axis in ("x", "y", "z"))
    root.scale = tuple(number(s[axis]) for axis in ("x", "y", "z"))
    root.empty_display_type = 'CUBE'
    root.empty_display_size = 0.20
    root.lock_location = (True, True, True)
    root.lock_rotation = (True, True, True)
    root.lock_scale = (True, True, True)
    root["fixed_component"] = True
    root["layout_type"] = record["type"]
    root["layout_group"] = record.get("group") or ""
    root["coordinate_system"] = "blender-z-up"
    root["source_position_xyz"] = json.dumps(p, ensure_ascii=False)
    root["source_rotation_xyz"] = json.dumps(r, ensure_ascii=False)
    root["source_scale_xyz"] = json.dumps(s, ensure_ascii=False)
    return root


def build_surface_fixed(root, record, coll):
    settings = record["surfaceSettings"]
    if settings["kind"] == "floor":
        dims = (number(settings["length"]), number(settings["width"]), number(settings["thickness"]))
        box(root.name + "_暖灰地砖", (0, 0, dims[2] / 2), dims, COOL_LIGHT, "MATTE", coll,
            bevel=0.018, parent=root)
        for x in (-2.35, 2.35):
            box(root.name + "_砖缝", (x, 0, dims[2] - 0.004), (0.015, dims[1] - 0.08, 0.008), COOL_MID,
                "MATTE", coll, bevel=0.002, parent=root)
    else:
        width, depth, height = number(settings["width"]), number(settings["thickness"]), number(settings["height"])
        box(root.name + "_米白墙体", (0, 0, height / 2), (width, depth, height), PAPER, "MATTE", coll,
            bevel=0.018, parent=root)
        box(root.name + "_浅木护墙条", (0, -depth * 0.46, 0.48), (width - 0.04, depth * 0.06, 0.08),
            WOOD_LIGHT, "MATTE", coll, bevel=0.01, parent=root)
        box(root.name + "_踢脚线", (0, -depth * 0.49, 0.10), (width - 0.02, depth * 0.02, 0.18),
            WOOD_MID, "MATTE", coll, bevel=0.006, parent=root)


def build_office_desk(root, coll):
    box(root.name + "_浅木桌面", (0, 0, 0.75), (1.6, 0.75, 0.09), WOOD_LIGHT, "MATTE", coll,
        bevel=0.045, parent=root)
    for x in (-0.68, 0.68):
        for y in (-0.27, 0.27):
            box(root.name + "_金属桌腿", (x, y, 0.36), (0.07, 0.07, 0.72), COOL_DARK, "METAL", coll,
                bevel=0.014, parent=root)
    box(root.name + "_抽屉柜", (-0.53, 0, 0.28), (0.38, 0.60, 0.56), COOL_LIGHT, "MATTE", coll,
        bevel=0.035, parent=root)
    for z in (0.19, 0.39):
        box(root.name + "_抽屉线", (-0.53, -0.305, z), (0.30, 0.012, 0.018), COOL_DARK, "METAL", coll,
            bevel=0.003, parent=root)
    box(root.name + "_理线槽", (0.25, 0.24, 0.63), (0.65, 0.10, 0.08), COOL_DARK, "METAL", coll,
        bevel=0.018, parent=root)


def build_office_chair(root, coll):
    cyl(root.name + "_五星脚包络", (0, 0, 0.03), 0.55, 0.06, COOL_DARK, "METAL", coll, vertices=40,
        parent=root)
    for i in range(5):
        angle = math.tau * i / 5
        box(root.name + "_五星脚", (math.cos(angle) * 0.27, math.sin(angle) * 0.27, 0.08),
            (0.52, 0.055, 0.045), COOL_DARK, "METAL", coll, rot=(0, 0, angle), bevel=0.012, parent=root)
        sphere(root.name + "_脚轮", (math.cos(angle) * 0.49, math.sin(angle) * 0.49, 0.09),
               (0.055, 0.055, 0.055), COOL_DARK, "GLOSS", coll, parent=root)
    cyl(root.name + "_升降杆", (0, 0, 0.29), 0.055, 0.46, COOL_DARK, "METAL", coll, vertices=16,
        parent=root)
    box(root.name + "_坐垫", (0, 0, 0.50), (0.62, 0.62, 0.12), BLUE_DUSK, "MATTE", coll,
        bevel=0.07, parent=root)
    box(root.name + "_网布靠背", (0, 0.25, 0.90), (0.58, 0.12, 0.70), MATCHA_DARK, "MATTE", coll,
        bevel=0.07, parent=root)
    for x in (-0.25, 0.25):
        box(root.name + "_扶手", (x, 0.02, 0.72), (0.06, 0.42, 0.07), COOL_DARK, "MATTE", coll,
            bevel=0.025, parent=root)


def build_monitor(root, coll):
    box(root.name + "_屏幕框", (0, 0, 1.22), (0.90, 0.06, 0.56), COOL_DARK, "MATTE", coll,
        bevel=0.035, parent=root)
    box(root.name + "_屏幕_自发光", (0, -0.035, 1.22), (0.79, 0.018, 0.45), BLUE_DUSK, "EMISSION", coll,
        bevel=0.018, parent=root)
    box(root.name + "_屏幕柔光条_自发光", (0.08, -0.046, 1.27), (0.42, 0.006, 0.035), MATCHA, "EMISSION", coll,
        bevel=0.008, parent=root)
    cyl(root.name + "_支架", (0, 0, 0.72), 0.035, 0.44, COOL_DARK, "METAL", coll, vertices=16,
        parent=root)
    box(root.name + "_底座", (0, 0, 0.475), (0.42, 0.25, 0.05), COOL_DARK, "METAL", coll,
        bevel=0.025, parent=root)


def build_file_cabinet(root, coll):
    box(root.name + "_柜体", (0, -0.025, 0.625), (0.85, 0.57, 1.25), COOL_LIGHT, "MATTE", coll,
        bevel=0.035, parent=root)
    for z, cell in ((0.33, MATCHA), (0.63, SAKURA), (0.93, BLUE_DUSK)):
        box(root.name + "_抽屉缝", (0, -0.303, z), (0.72, 0.018, 0.025), COOL_DARK, "MATTE", coll,
            bevel=0.004, parent=root)
        box(root.name + "_标签夹", (0, -0.3075, z + 0.08), (0.19, 0.010, 0.08), cell, "GLOSS", coll,
            bevel=0.012, parent=root)
    for x in (-0.32, 0.32):
        cyl(root.name + "_柜脚", (x, 0, 0.035), 0.035, 0.07, COOL_DARK, "METAL", coll, vertices=12,
            parent=root)


def build_shelf(root, coll):
    box(root.name + "_背框", (0, 0.03, 0.90), (1.10, 0.32, 1.80), WOOD_MID, "MATTE", coll,
        bevel=0.028, parent=root)
    for z in (0.30, 0.74, 1.18, 1.62):
        box(root.name + "_层板", (0, 0, z), (1.00, 0.38, 0.055), WOOD_LIGHT, "MATTE", coll,
            bevel=0.012, parent=root)
    colors = [MATCHA, SAKURA, ORANGE, BLUE_DUSK, RICE]
    for row, z in enumerate((0.43, 0.87, 1.31)):
        for i in range(5):
            box(root.name + "_资料册", (-0.38 + i * 0.19, -0.10, z), (0.13, 0.16, 0.25 + 0.025 * (i % 2)),
                colors[(row + i) % len(colors)], "MATTE", coll, bevel=0.012, parent=root)


def build_printer(root, coll):
    box(root.name + "_底部纸盒", (0, 0, 0.04), (0.68, 0.70, 0.08), COOL_DARK, "MATTE", coll,
        bevel=0.035, parent=root)
    box(root.name + "_机身", (0, -0.05, 0.26), (0.68, 0.52, 0.36), COOL_LIGHT, "MATTE", coll,
        bevel=0.055, parent=root)
    box(root.name + "_扫描盖", (0, -0.05, 0.53), (0.62, 0.48, 0.06), COOL_DARK, "GLOSS", coll,
        bevel=0.035, parent=root)
    box(root.name + "_出纸槽", (0, -0.315, 0.22), (0.46, 0.05, 0.13), COOL_DARK, "MATTE", coll,
        bevel=0.018, parent=root)
    box(root.name + "_待机灯_自发光", (0.22, -0.337, 0.35), (0.08, 0.008, 0.035), MATCHA, "EMISSION", coll,
        bevel=0.009, parent=root)


def build_water_dispenser(root, coll):
    box(root.name + "_底座", (0, 0, 0.04), (0.42, 0.52, 0.08), COOL_DARK, "MATTE", coll,
        bevel=0.035, parent=root)
    box(root.name + "_机身", (0, 0, 0.55), (0.38, 0.42, 0.94), RICE, "MATTE", coll,
        bevel=0.055, parent=root)
    cyl(root.name + "_水桶", (0, 0, 1.22), 0.18, 0.42, BLUE_DUSK, "GLASS", coll, vertices=28,
        parent=root)
    box(root.name + "_接水区", (0, -0.225, 0.55), (0.28, 0.07, 0.24), COOL_DARK, "MATTE", coll,
        bevel=0.025, parent=root)
    for x, cell in ((-0.08, BLUE_DUSK), (0.08, SAKURA)):
        cyl(root.name + "_水龙头", (x, -0.200, 0.72), 0.022, 0.11, cell, "GLOSS", coll,
            rot=(math.pi / 2, 0, 0), vertices=12, parent=root)
    box(root.name + "_状态灯_自发光", (0, -0.255, 0.88), (0.12, 0.006, 0.035), MATCHA, "EMISSION", coll,
        bevel=0.008, parent=root)


def build_meeting_table(root, coll):
    top = cyl(root.name + "_原木桌面", (0, 0, 0.78), 0.95, 0.11, WOOD_LIGHT, "MATTE", coll, vertices=40,
              parent=root)
    top.scale.y = 0.62
    base = cyl(root.name + "_中央桌腿", (0, 0, 0.35), 0.32, 0.70, COOL_DARK, "METAL", coll, vertices=24,
               parent=root)
    foot = cyl(root.name + "_椭圆底座", (0, 0, 0.035), 0.62, 0.07, COOL_DARK, "METAL", coll, vertices=32,
               parent=root)
    foot.scale.y = 0.62


def build_whiteboard(root, coll):
    box(root.name + "_铝框", (0, 0, 1.35), (1.60, 0.065, 1.05), COOL_LIGHT, "METAL", coll,
        bevel=0.025, parent=root)
    box(root.name + "_板面", (0, -0.020, 1.35), (1.46, 0.018, 0.90), PAPER, "GLOSS", coll,
        bevel=0.012, parent=root)
    box(root.name + "_笔槽", (0, 0.10, 0.805), (1.10, 0.13, 0.05), COOL_MID, "MATTE", coll,
        bevel=0.014, parent=root)
    for x in (-0.65, 0.65):
        box(root.name + "_支腿", (x, 0, 0.39), (0.055, 0.055, 0.78), COOL_DARK, "METAL", coll,
            bevel=0.012, parent=root)
    for x, z, cell in ((-0.45, 1.55, SAKURA), (-0.05, 1.30, MATCHA), (0.42, 1.48, ORANGE)):
        box(root.name + "_磁吸便签", (x, -0.025, z), (0.22, 0.008, 0.16), cell, "MATTE", coll,
            bevel=0.006, parent=root)


def build_door(root, coll):
    box(root.name + "_浅木门扇", (0, 0, 1.175), (1.25, 0.13, 2.35), WOOD_LIGHT, "MATTE", coll,
        bevel=0.035, parent=root)
    box(root.name + "_窄玻璃窗", (0, -0.055, 1.52), (0.34, 0.018, 0.92), BLUE_DUSK, "GLASS", coll,
        bevel=0.025, parent=root)
    sphere(root.name + "_门把", (0.42, 0.10, 1.15), (0.06, 0.06, 0.06), ORANGE, "METAL", coll,
           parent=root)


def build_window(root, coll):
    box(root.name + "_玻璃", (0, 0, 1.45), (2.00, 0.12, 1.55), BLUE_DUSK, "GLASS", coll,
        bevel=0.012, parent=root)
    for x in (-0.65, 0, 0.65):
        box(root.name + "_竖框", (x, 0, 1.45), (0.07, 0.17, 1.70), WOOD_MID, "MATTE", coll,
            bevel=0.012, parent=root)
    box(root.name + "_横框", (0, 0, 1.45), (2.15, 0.17, 0.07), WOOD_MID, "MATTE", coll,
        bevel=0.012, parent=root)


def build_rest_table(root, record, coll):
    settings = record["tableSettings"]
    build_table(root, settings, coll, low=False)


def build_rest_chair(root, record, coll):
    build_chair(root, record["chairSettings"], coll)


def build_rest_cabinet(root, coll):
    box(root.name + "_矮柜主体", (0, 0, 0.825), (1.40, 0.55, 1.65), WOOD_LIGHT, "MATTE", coll,
        bevel=0.055, parent=root)
    for x in (-0.34, 0.34):
        box(root.name + "_柜门", (x, -0.28, 0.82), (0.62, 0.04, 1.45), RICE, "MATTE", coll,
            bevel=0.018, parent=root)
        sphere(root.name + "_圆拉手", (x + (-0.16 if x > 0 else 0.16), -0.30, 0.85),
               (0.035, 0.035, 0.035), ORANGE, "METAL", coll, parent=root)


def stage_fixed():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    global MASTER, FIXED, FLOORS, WALLS, EQUIPMENT, DECOR, DYNAMIC, DISPLAY, MATS
    MASTER = get_or_create_collection("办公室03_中文资产管理")
    FIXED = get_or_create_collection("01_固定元素_布局锁定", MASTER)
    FLOORS = get_or_create_collection("01_地板_36块", FIXED)
    WALLS = get_or_create_collection("02_外墙与隔断_11面", FIXED)
    EQUIPMENT = get_or_create_collection("03_办公设施_51件", FIXED)
    DECOR = get_or_create_collection("02_自由装饰_办公生活", MASTER)
    DYNAMIC = get_or_create_collection("03_动态元素", MASTER)
    DISPLAY = get_or_create_collection("90_展示环境_灯光相机", MASTER)
    MATS = setup_materials()
    layout = load_layout()
    scene = bpy.context.scene
    scene["layout_source"] = LAYOUT_PATH
    scene["layout_saved_at"] = layout.get("savedAt", "")
    scene["layout_version"] = layout.get("version", 0)
    scene["coordinate_system"] = layout.get("coordinateSystem", "")
    scene["fixed_component_count"] = len(layout["components"])
    builders = {
        "办公桌": build_office_desk, "办公椅": build_office_chair, "显示器": build_monitor,
        "文件柜": build_file_cabinet, "书架": build_shelf, "打印机": build_printer,
        "饮水机": build_water_dispenser, "会议桌": build_meeting_table, "白板": build_whiteboard,
        "门": build_door, "窗": build_window, "柜子": build_rest_cabinet,
    }
    for record in layout["components"]:
        kind = record["type"]
        coll = FLOORS if kind == "地板" else WALLS if kind == "墙壁" else EQUIPMENT
        root = make_root(record, coll)
        if kind in ("地板", "墙壁"):
            build_surface_fixed(root, record, coll)
        elif kind == "桌子":
            build_rest_table(root, record, coll)
        elif kind == "椅子":
            build_rest_chair(root, record, coll)
        else:
            builders[kind](root, coll)


def world_from(root, local):
    return root.matrix_world @ Vector(local)


def add_desk_props(root, index):
    positions = {
        "键盘": ((0.10, -0.12, 0.825), (0.55, 0.20, 0.035), COOL_DARK),
        "鼠标": ((0.48, -0.13, 0.84), (0.11, 0.16, 0.055), COOL_MID),
        "便签": ((-0.25, -0.18, 0.83), (0.18, 0.16, 0.018), [SAKURA, MATCHA, ORANGE][index % 3]),
    }
    angle = root.rotation_euler.z
    for label, (local, dims, cell) in positions.items():
        box(root.name + "_" + label, world_from(root, local), dims, cell, "MATTE", DECOR,
            rot=(0, 0, angle), bevel=0.015)
    mug_pos = world_from(root, (-0.48, -0.15, 0.93))
    cyl(root.name + "_保温杯", mug_pos, 0.08, 0.20, [MATCHA, SAKURA, RICE][index % 3], "GLOSS", DECOR,
        vertices=24)
    if index % 2 == 0:
        pot_pos = world_from(root, (0.58, 0.16, 0.93))
        cyl(root.name + "_桌面绿植盆", pot_pos, 0.09, 0.17, RICE, "GLOSS", DECOR, vertices=20)
        for j in range(5):
            a = math.tau * j / 5
            leaf = sphere(root.name + "_桌面绿植叶", (pot_pos.x + math.cos(a) * 0.07, pot_pos.y + math.sin(a) * 0.07, pot_pos.z + 0.15),
                          (0.05, 0.11, 0.045), MATCHA_DARK, "MATTE", DECOR)
            leaf.rotation_euler.z = a


def stage_decor():
    global DECOR, DYNAMIC, DISPLAY, MATS
    DECOR = bpy.data.collections["02_自由装饰_办公生活"]
    DYNAMIC = bpy.data.collections["03_动态元素"]
    DISPLAY = bpy.data.collections["90_展示环境_灯光相机"]
    MATS = {"MATTE": bpy.data.materials["01_细腻哑光_色盘"], "GLOSS": bpy.data.materials["02_清漆反光_色盘"],
            "METAL": bpy.data.materials["03_精工金属_色盘"], "EMISSION": bpy.data.materials["04_柔和自发光_色盘"],
            "GLASS": bpy.data.materials["05_玻璃_色盘"]}
    # Floor grid and circulation bands.
    for x in range(-15, 16, 5):
        box("地砖_纵向接缝", (x, 0, 0.108), (0.025, 30, 0.016), COOL_MID, "MATTE", DECOR, bevel=0.004)
    for y in range(-15, 16, 5):
        box("地砖_横向接缝", (0, y, 0.109), (30, 0.025, 0.016), COOL_MID, "MATTE", DECOR, bevel=0.004)
    box("中央原木导向带", (0, 0.2, 0.125), (2.1, 27.5, 0.045), WOOD_LIGHT, "MATTE", DECOR, bevel=0.05)
    box("会议室雾蓝地毯", (1.0, -11.0, 0.135), (8.3, 6.5, 0.055), BLUE_DUSK, "MATTE", DECOR, bevel=0.10)
    box("休息区樱粉地毯", (-10.6, -10.6, 0.135), (5.2, 5.0, 0.055), SAKURA, "MATTE", DECOR, bevel=0.12)
    # Desk props anchored to every fixed desk.
    desks = sorted([o for o in bpy.data.objects if o.get("layout_type") == "办公桌"], key=lambda o: o.name)
    for index, root in enumerate(desks):
        add_desk_props(root, index)
    # Meeting table props.
    meeting = bpy.data.objects.get("会议桌")
    if meeting:
        for x, y, cell in ((-0.42, 0.18, SAKURA), (0.18, -0.20, MATCHA), (0.48, 0.14, ORANGE)):
            pos = world_from(meeting, (x, y, 0.86))
            box("会议桌_会议本", pos, (0.38, 0.27, 0.025), cell, "MATTE", DECOR,
                rot=(0, 0, meeting.rotation_euler.z + 0.08 * x), bevel=0.015)
        speaker = world_from(meeting, (0, 0, 0.91))
        cyl("会议桌_无线扬声器", speaker, 0.17, 0.14, COOL_DARK, "GLOSS", DECOR, vertices=28)
        cup = world_from(meeting, (-0.62, -0.18, 0.93))
        cyl("会议桌_咖啡杯", cup, 0.10, 0.18, RICE, "GLOSS", DECOR, vertices=28)
        torus("会议桌_杯口", (cup.x, cup.y, cup.z + 0.09), 0.085, 0.012, COOL_DARK, "GLOSS", DECOR)
    # Rest area tea details.
    rest = bpy.data.objects.get("左下休息桌")
    if rest:
        tray = world_from(rest, (0, 0, 1.36))
        box("休息桌_木托盘", tray, (0.70, 0.45, 0.04), WOOD_DARK, "MATTE", DECOR,
            rot=(0, 0, rest.rotation_euler.z), bevel=0.025)
        for dx, cell in ((-0.18, MATCHA), (0.18, SAKURA)):
            pos = world_from(rest, (dx, 0, 1.49))
            cyl("休息桌_陶瓷杯", pos, 0.10, 0.20, cell, "GLOSS", DECOR, vertices=24)
    # Entry identity, umbrella stand and visitor plant.
    box("主入口_公司木质铭牌", (3.0, -14.65, 1.25), (3.2, 0.08, 0.72), WOOD_MID, "MATTE", DECOR, bevel=0.06)
    text_obj("公司铭牌_文字", "STUDIO 03", (3.0, -14.70, 1.06), 0.28, RICE, DECOR)
    cyl("主入口_伞架", (-2.1, -13.9, 0.52), 0.34, 0.90, COOL_DARK, "MATTE", DECOR, vertices=28)
    for i in range(5):
        curve_tube("主入口_雨伞", [(-2.28 + i * 0.09, -13.9, 0.35), (-2.28 + i * 0.09, -13.9, 1.25)],
                   0.018, [MATCHA, SAKURA, BLUE_DUSK][i % 3], "MATTE", DECOR)
    # Large office plants positioned away from main paths.
    for base in ((-13.2, 12.5, 0.46), (12.8, -12.2, 0.46), (-12.8, -5.8, 0.46), (6.2, 12.7, 0.46)):
        cyl("办公室_大型绿植盆", base, 0.42, 0.75, COOL_DARK, "GLOSS", DECOR, vertices=28)
        for i in range(10):
            a = math.tau * i / 10
            end = (base[0] + math.cos(a) * 0.65, base[1] + math.sin(a) * 0.65, base[2] + 1.8 + 0.12 * (i % 3))
            curve_tube("办公室_绿植叶柄", [(base[0], base[1], base[2] + 0.35), end], 0.025, MATCHA_DARK, "MATTE", DECOR)
            leaf = sphere("办公室_大型绿植叶", end, (0.13, 0.34, 0.065), MATCHA_DARK, "MATTE", DECOR)
            leaf.rotation_euler.z = a
    # Print supplies and recycling boxes.
    for root in [o for o in bpy.data.objects if o.get("layout_type") == "打印机"]:
        pos = world_from(root, (0.55, 0, 0.17))
        box(root.name + "_备用纸箱", pos, (0.42, 0.45, 0.30), RICE, "MATTE", DECOR,
            rot=(0, 0, root.rotation_euler.z), bevel=0.035)
    # Segmented luminaires keep the miniature readable from above.
    for x in (-8, 0, 8):
        for y in (-10, -4, 2, 8):
            box("顶部_分段灯槽", (x, y, 3.55), (3.8, 0.55, 0.10), COOL_LIGHT, "MATTE", DECOR, bevel=0.025)
            box("顶部_分段灯_自发光", (x, y, 3.49), (3.45, 0.38, 0.035), RICE, "EMISSION", DECOR, bevel=0.018)
    # East window blinds.
    for y0 in (10, 5, 0, -5):
        for i in range(8):
            box("东窗_百叶片", (14.56, y0 - 0.82 + i * 0.23, 1.48), (0.045, 0.18, 1.55), RICE, "GLASS", DYNAMIC,
                rot=(0, 0.10, 0), bevel=0.012)
    # Wall clock and seconds hand.
    cyl("行政区_挂钟", (0.0, 14.68, 1.25), 0.42, 0.055, WOOD_MID, "MATTE", DECOR,
        rot=(math.pi / 2, 0, 0), vertices=40)
    box("行政区_挂钟秒针", (0.0, 14.62, 1.42), (0.025, 0.025, 0.34), SAKURA, "MATTE", DYNAMIC, bevel=0.005)


def add_area_light(name, loc, energy, color, size, coll):
    data = bpy.data.lights.new(name + "_数据", 'AREA')
    data.energy = energy
    data.color = color
    data.shape = 'DISK'
    data.size = size
    obj = bpy.data.objects.new(name, data)
    coll.objects.link(obj)
    obj.location = loc
    return obj


def track(obj, target):
    con = obj.constraints.new(type='TRACK_TO')
    con.target = target
    con.track_axis = 'TRACK_NEGATIVE_Z'
    con.up_axis = 'UP_Y'


def stage_animation():
    global DECOR, DYNAMIC, DISPLAY, MATS
    DECOR = bpy.data.collections["02_自由装饰_办公生活"]
    DYNAMIC = bpy.data.collections["03_动态元素"]
    DISPLAY = bpy.data.collections["90_展示环境_灯光相机"]
    MATS = {"MATTE": bpy.data.materials["01_细腻哑光_色盘"], "GLOSS": bpy.data.materials["02_清漆反光_色盘"],
            "METAL": bpy.data.materials["03_精工金属_色盘"], "EMISSION": bpy.data.materials["04_柔和自发光_色盘"],
            "GLASS": bpy.data.materials["05_玻璃_色盘"]}
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 240
    scene.frame_set(72)
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = 1120
    scene.render.resolution_y = 920
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.world.color = (0.04, 0.055, 0.075)
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.045, 0.065, 0.09, 1)
    bg.inputs['Strength'].default_value = 0.30
    scene.render.use_freestyle = True
    scene.view_layers[0].freestyle_settings.linesets[0].linestyle.color = (0.08, 0.075, 0.07)
    scene.view_layers[0].freestyle_settings.linesets[0].linestyle.thickness = 0.72
    target = bpy.data.objects.new("镜头_办公室中心", None)
    DISPLAY.objects.link(target)
    target.location = (0, 0, 0.8)
    camera_data = bpy.data.cameras.new("第三视角相机_数据")
    camera = bpy.data.objects.new("第三视角相机", camera_data)
    DISPLAY.objects.link(camera)
    camera.location = (35.5, -39.5, 36.0)
    camera_data.lens = 52
    track(camera, target)
    scene.camera = camera
    sun = add_area_light("东窗午后主光", (26, -6, 20), 2200, (1.0, 0.55, 0.28), 13.0, DISPLAY)
    track(sun, target)
    sun.keyframe_insert(data_path="location", frame=1)
    sun.location.y = 8
    sun.location.z = 16
    sun.keyframe_insert(data_path="location", frame=240)
    fill = add_area_light("室内米白补光", (-4, -2, 20), 2300, (1.0, 0.82, 0.64), 18.0, DISPLAY)
    track(fill, target)
    rim = add_area_light("东窗冷调轮廓光", (20, 15, 10), 1450, (0.38, 0.55, 0.85), 10.0, DISPLAY)
    track(rim, target)
    # Gentle luminaire breathing.
    for y in (-11, -5.5, 0, 5.5, 11):
        data = bpy.data.lights.new(f"顶部线灯_{y}_数据", 'AREA')
        data.energy = 420
        data.color = (1.0, 0.78, 0.52)
        data.shape = 'RECTANGLE'
        data.size = 10
        data.size_y = 0.6
        obj = bpy.data.objects.new(f"顶部线灯_{y}", data)
        DYNAMIC.objects.link(obj)
        obj.location = (0, y, 3.15)
        obj.rotation_euler = (0, 0, 0)
        for frame, factor in ((1, 1.0), (60, 0.97), (120, 1.02), (180, 0.98), (240, 1.0)):
            data.energy = 420 * factor
            data.keyframe_insert(data_path="energy", frame=frame)
    # Printer sheet movement, independent of fixed printer bounds.
    printer = bpy.data.objects.get("右下打印机")
    if printer:
        start = world_from(printer, (0, -0.36, 0.33))
        sheet = box("打印机_动态出纸", start, (0.44, 0.30, 0.018), PAPER, "MATTE", DYNAMIC,
                    rot=(0, 0, printer.rotation_euler.z), bevel=0.006)
        sheet.keyframe_insert(data_path="location", frame=1)
        direction = Vector((0, -0.28, 0))
        direction.rotate(printer.rotation_euler)
        sheet.location += direction
        sheet.keyframe_insert(data_path="location", frame=160)
    # Steam above the meeting coffee.
    meeting = bpy.data.objects.get("会议桌")
    if meeting:
        base = world_from(meeting, (-0.62, -0.18, 1.06))
        for i in range(5):
            puff = sphere("会议咖啡_热气", (base.x, base.y, base.z + i * 0.14),
                          (0.035 + i * 0.008, 0.035 + i * 0.008, 0.08), PAPER, "GLASS", DYNAMIC)
            start = 1 + i * 22
            puff.keyframe_insert(data_path="location", frame=start)
            puff.location.x += 0.18 * (-1 if i % 2 else 1)
            puff.location.z += 0.85
            puff.keyframe_insert(data_path="location", frame=start + 110)
    # Blind sway.
    for i, obj in enumerate([o for o in DYNAMIC.objects if o.name.startswith("东窗_百叶片")]):
        for frame, angle in ((1, 0.08), (80, 0.12 + 0.01 * (i % 3)), (160, 0.06), (240, 0.08)):
            obj.rotation_euler.y = angle
            obj.keyframe_insert(data_path="rotation_euler", frame=frame)
    # Bird silhouettes beyond east windows.
    for i in range(3):
        bird = curve_tube("东窗外_飞鸟", [(0, 0, 0), (0.18, 0.05, 0.06), (0.36, 0, 0)], 0.025,
                          COOL_DARK, "MATTE", DYNAMIC)
        bird.location = (15.2, -12 + i * 3, 2.4 + i * 0.25)
        bird.keyframe_insert(data_path="location", frame=1 + i * 30)
        bird.location.y = 12
        bird.location.z += 0.35
        bird.keyframe_insert(data_path="location", frame=170 + i * 20)
    # Clock second hand.
    hand = bpy.data.objects.get("行政区_挂钟秒针")
    if hand:
        hand.rotation_euler.y = 0
        hand.keyframe_insert(data_path="rotation_euler", frame=1)
        hand.rotation_euler.y = math.tau
        hand.keyframe_insert(data_path="rotation_euler", frame=240)
        for fc in hand.animation_data.action.fcurves:
            for point in fc.keyframe_points:
                point.interpolation = 'LINEAR'
    # Moving sun patch on the main circulation route.
    patch = box("地面午后光带_自发光", (5.8, -3.0, 0.17), (7.5, 2.1, 0.022), ORANGE, "EMISSION", DYNAMIC,
                rot=(0, 0, 0.18), bevel=0.20)
    patch.keyframe_insert(data_path="location", frame=1)
    patch.location.y = 4.5
    patch.location.x = 3.0
    patch.keyframe_insert(data_path="location", frame=240)
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == 'VIEW_3D':
            area.spaces.active.overlay.show_overlays = False
            area.spaces.active.shading.type = 'RENDERED'
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
    scene.frame_set(72)


def belongs_to(candidate, ancestor):
    current = candidate.parent
    while current is not None:
        if current == ancestor:
            return True
        current = current.parent
    return False


def fixed_bbox(root):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or not belongs_to(obj, root):
            continue
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    if not points:
        return None
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high, high - low


def local_contract(record):
    kind = record["type"]
    if kind == "地板":
        s = record["surfaceSettings"]
        return Vector((number(s["length"]), number(s["width"]), number(s["thickness"])))
    if kind == "墙壁":
        s = record["surfaceSettings"]
        return Vector((number(s["width"]), number(s["thickness"]), number(s["height"])))
    if kind == "桌子":
        s = record["tableSettings"]
        return Vector((number(s["width"]), number(s["depth"]), number(s["legHeight"]) + number(s["topThickness"])))
    if kind == "椅子":
        s = record["chairSettings"]
        return Vector((number(s["seatWidth"]), number(s["seatDepth"]),
                       number(s["legHeight"]) + 0.13 + number(s["backHeight"])))
    return TYPE_BOUNDS[kind].copy()


def expected_world_dimensions(record):
    dims = local_contract(record)
    scale = record["scale"]
    dims = Vector((dims.x * number(scale["x"]), dims.y * number(scale["y"]), dims.z * number(scale["z"])))
    angle = math.radians(number(record["rotation"]["z"]))
    c, s = abs(math.cos(angle)), abs(math.sin(angle))
    return Vector((c * dims.x + s * dims.y, s * dims.x + c * dims.y, dims.z))


def stage_validate_render():
    layout = load_layout()
    results = []
    passed = True
    for record in layout["components"]:
        root = bpy.data.objects.get(record["name"])
        bbox = fixed_bbox(root) if root else None
        actual = bbox[2] if bbox else Vector((0, 0, 0))
        expected = expected_world_dimensions(record)
        error = max(abs(actual.x - expected.x), abs(actual.y - expected.y), abs(actual.z - expected.z))
        transform_ok = bool(root and root.get("source_position_xyz") == json.dumps(record["position"], ensure_ascii=False)
                            and root.get("source_rotation_xyz") == json.dumps(record["rotation"], ensure_ascii=False)
                            and root.get("source_scale_xyz") == json.dumps(record["scale"], ensure_ascii=False))
        ok = transform_ok and error <= 0.003
        passed = passed and ok
        results.append({"name": record["name"], "type": record["type"], "transform_locked": transform_ok,
                        "expected_world_dimensions": [round(v, 4) for v in expected],
                        "actual_world_dimensions": [round(v, 4) for v in actual],
                        "max_dimension_error": round(error, 6), "passed": ok})
    report = {"layout": LAYOUT_PATH, "fixed_component_count_expected": len(layout["components"]),
              "fixed_component_count_actual": len([o for o in bpy.data.objects if o.get("fixed_component")]),
              "all_passed": passed, "components": results}
    with open(REPORT_PATH, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    scene = bpy.context.scene
    scene["layout_validation_passed"] = passed
    scene.render.filepath = PREVIEW_PATH
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print(json.dumps({"blend": BLEND_PATH, "preview": PREVIEW_PATH, "validation": passed}, ensure_ascii=False))


def run_uv_validation():
    validator = os.path.join(os.path.expanduser("~"), ".codex", "skills", "blender-game-prop-standard",
                             "scripts", "validate_game_prop.py")
    old_argv = list(sys.argv)
    sys.argv = ["blender", "--", "--max-materials", "12", "--all-meshes", "--json", UV_REPORT_PATH]
    code = 1
    try:
        runpy.run_path(validator, run_name="__main__")
    except SystemExit as exc:
        code = int(exc.code or 0)
    finally:
        sys.argv = old_argv
    print("OFFICE_UV_VALIDATOR_EXIT", code)


STAGE = globals().get("OFFICE03_STAGE", "")
if STAGE == "fixed":
    stage_fixed()
elif STAGE == "decor":
    stage_decor()
elif STAGE == "animation":
    stage_animation()
elif STAGE == "validate_render":
    stage_validate_render()
elif STAGE == "uv_validate":
    run_uv_validation()
