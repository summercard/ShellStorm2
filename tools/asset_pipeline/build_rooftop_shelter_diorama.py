import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


BASE_SCRIPT = Path(r"I:\工作项目\shellstrom2\ShellStorm2\tools\asset_pipeline\build_rooftop_shelter.py")
ROOFTOP_MODE = "library"
exec(compile(BASE_SCRIPT.read_bytes(), str(BASE_SCRIPT), "exec"), globals())


ASSET_ROOT = PROJECT_ROOT / "assets" / "art" / "environments" / "rooftop_shelter_diorama_3d"
SOURCE_DIR = ASSET_ROOT / "source" / "rooftop_shelter_diorama"
GAME_DIR = ASSET_ROOT / "game_output" / "rooftop_shelter_diorama"
PREVIEW_DIR = ASSET_ROOT / "previews"
SHARED_DIR = ASSET_ROOT / "shared"
DOCS_DIR = ASSET_ROOT / "docs"
PALETTE_FILE = SHARED_DIR / "多巴胺色盘_10x10_512.png"
SOURCE_BLEND = SOURCE_DIR / "env_rooftop_shelter_diorama_source_v003.blend"
GAME_BLEND = GAME_DIR / "env_rooftop_shelter_diorama_game_v003.blend"
FULL_PREVIEW = PREVIEW_DIR / "env_rooftop_shelter_diorama_full_v003.png"
DETAIL_PREVIEW = PREVIEW_DIR / "env_rooftop_shelter_diorama_living_v003.png"
MANIFEST_FILE = DOCS_DIR / "env_rooftop_shelter_diorama_manifest_v003.json"
STATIC_AUDIO = SHARED_DIR / "radio_static_soft_v001.wav"


def torus_object(name, location, major_radius, minor_radius, collection, material_key="metal", cell=None,
                 major_segments=14, minor_segments=4, rotation=(0.0, 0.0, 0.0), category="Props/Survival"):
    vertices = []
    faces = []
    for major in range(major_segments):
        major_angle = math.tau * major / major_segments
        for minor in range(minor_segments):
            minor_angle = math.tau * minor / minor_segments
            ring = major_radius + minor_radius * math.cos(minor_angle)
            vertices.append((
                ring * math.cos(major_angle),
                ring * math.sin(major_angle),
                minor_radius * math.sin(minor_angle),
            ))
    for major in range(major_segments):
        nxt_major = (major + 1) % major_segments
        for minor in range(minor_segments):
            nxt_minor = (minor + 1) % minor_segments
            a = major * minor_segments + minor
            b = nxt_major * minor_segments + minor
            c = nxt_major * minor_segments + nxt_minor
            d = major * minor_segments + nxt_minor
            faces.append((a, b, c, d))
    obj = make_mesh_object(name, vertices, faces, collection, material_key, cell or CELLS["black"], category)
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def add_ac_units():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    energy = COLLECTIONS["输出_Props_Energy"]
    for unit_index, x in enumerate((-7.0, -3.5)):
        body = box(
            f"废弃空调外机_{unit_index}", (x, 18.8, 0.0), (3.0, 1.65, 1.9), energy,
            "metal", CELLS["concrete_light" if unit_index == 0 else "rust"],
            rotation=(0, 0, 0.025 * (-1) ** unit_index), category="Props/Energy", bevel=0.06
        )
        OUTPUT_OBJECTS.append(body)
        fan = cylinder(
            f"空调风扇格栅_{unit_index}", (x, 17.93, 0.95), 0.63, 0.08, energy,
            "metal", CELLS["concrete_dark"], 12, rotation=(math.pi / 2, 0, 0), category="Props/Energy"
        )
        OUTPUT_OBJECTS.append(fan)
        for slat in range(5):
            vent = box(
                f"空调散热片_{unit_index}_{slat}", (x - 1.05 + slat * 0.52, 17.86, 0.28),
                (0.08, 0.035, 1.15), energy, "matte", CELLS["blue_dark"], category="Props/Energy"
            )
            OUTPUT_OBJECTS.append(vent)
        pipe = beam_between(
            f"空调裸露铜管_{unit_index}", (x + 1.1, 18.8, 0.35), (-9.2, 22.6 - unit_index * 0.3, 0.28),
            0.045, energy, "metal", CELLS["rust"], 8, "Props/Energy"
        )
        OUTPUT_OBJECTS.append(pipe)
    cable = box(
        "空调旧电线_风中微颤", (-5.2, 17.75, 2.15), (6.0, 0.035, 0.035), architecture,
        "matte", CELLS["black"], rotation=(0.0, 0.025, 0.0), category="Environment/Architecture"
    )
    OUTPUT_OBJECTS.append(cable)
    animate_rotation(cable, 1, [0.018, 0.035, 0.018], [1, 52, 104], True)


def add_bicycle_wreck():
    props = COLLECTIONS["输出_Props_Survival"]
    wheel_y = -22.35
    rear = (-9.2, wheel_y, 0.92)
    front = (-7.25, wheel_y, 0.92)
    rear_wheel = torus_object(
        "旧自行车后轮残骸", rear, 0.82, 0.07, props, "matte", CELLS["black"],
        rotation=(math.pi / 2, 0.04, 0), category="Props/Survival"
    )
    front_wheel = torus_object(
        "旧自行车前轮残骸", front, 0.82, 0.07, props, "matte", CELLS["black"],
        rotation=(math.pi / 2, -0.12, 0.08), category="Props/Survival"
    )
    OUTPUT_OBJECTS.extend((rear_wheel, front_wheel))
    frame_points = {
        "rear": rear,
        "front": front,
        "crank": (-8.32, wheel_y, 0.72),
        "seat": (-8.65, wheel_y, 1.70),
        "handle": (-7.55, wheel_y, 1.75),
    }
    connections = (
        ("后轮至中轴", "rear", "crank"), ("中轴至座杆", "crank", "seat"),
        ("座杆至后轮", "seat", "rear"), ("座杆至车头", "seat", "handle"),
        ("中轴至车头", "crank", "handle"), ("车头前叉", "handle", "front"),
    )
    for index, (label, start, end) in enumerate(connections):
        tube = beam_between(
            f"自行车车架_{index}_{label}", frame_points[start], frame_points[end], 0.045, props,
            "metal", CELLS["rust" if index % 2 else "blue_dark"], 8, "Props/Survival"
        )
        OUTPUT_OBJECTS.append(tube)
    seat = box("自行车破损车座", (-8.72, wheel_y, 1.68), (0.62, 0.28, 0.14), props, "matte", CELLS["black"], rotation=(0.08, 0, 0), category="Props/Survival", bevel=0.05)
    handlebar = beam_between("自行车歪斜车把", (-7.55, wheel_y - 0.42, 1.76), (-7.55, wheel_y + 0.35, 1.76), 0.035, props, "metal", CELLS["rust_dark"], 8, "Props/Survival")
    OUTPUT_OBJECTS.extend((seat, handlebar))


def add_advertising_frame():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    x, y = -4.0, 22.1
    posts = ((x - 2.9, y, 0.0), (x + 2.9, y, 0.0))
    for index, loc in enumerate(posts):
        post = cylinder(f"旧广告牌支柱_{index}", loc, 0.10, 6.8, architecture, "metal", CELLS["rust_dark"], 8, category="Environment/Architecture")
        OUTPUT_OBJECTS.append(post)
    for index, z in enumerate((2.7, 6.5)):
        beam = box(f"旧广告牌横框_{index}", (x, y, z), (6.0, 0.13, 0.13), architecture, "metal", CELLS["rust_dark"], rotation=(0, 0.02, -0.025), category="Environment/Architecture")
        OUTPUT_OBJECTS.append(beam)
    panel = box(
        "破损旧广告牌残片", (x - 1.0, y - 0.04, 3.0), (3.3, 0.09, 2.6), architecture,
        "matte", CELLS["blue_dark"], rotation=(0, 0.12, -0.08), category="Environment/Architecture"
    )
    OUTPUT_OBJECTS.append(panel)
    for index in range(3):
        brace = beam_between(
            f"广告牌斜撑_{index}", (x - 2.7 + index * 2.7, y, 2.8),
            (x - 1.8 + index * 1.8, y - 1.9, 0.1), 0.055, architecture,
            "metal", CELLS["rust"], 8, "Environment/Architecture"
        )
        OUTPUT_OBJECTS.append(brace)


def add_living_details():
    furniture = COLLECTIONS["输出_Props_Furniture"]
    survival = COLLECTIONS["输出_Props_Survival"]
    farming = COLLECTIONS["输出_Props_Farming"]
    vfx = COLLECTIONS["输出_VFX"]
    lighting = COLLECTIONS["输出_Lighting"]

    patches = (
        (-6.4, 3.29, 0.88, 0.58, 0.42, "rust"),
        (-4.35, 3.29, 0.88, 0.72, 0.36, "canvas"),
        (-5.55, 4.75, 1.35, 0.55, 0.46, "warning"),
    )
    for index, (x, y, z, sx, sz, cell) in enumerate(patches):
        patch = box(
            f"布艺沙发补丁_{index}", (x, y, z), (sx, 0.025, sz), furniture,
            "matte", CELLS[cell], rotation=(0, 0, 0.07 * (-1) ** index), category="Props/Furniture"
        )
        OUTPUT_OBJECTS.append(patch)

    tabletop = box("生锈矮茶几桌面", (-5.3, 1.85, 0.52), (3.0, 1.45, 0.16), furniture, "metal", CELLS["rust"], category="Props/Furniture", bevel=0.05)
    OUTPUT_OBJECTS.append(tabletop)
    for index, loc in enumerate(((-6.45, 1.45, 0.0), (-4.15, 1.45, 0.0), (-6.45, 2.25, 0.0), (-4.15, 2.25, 0.0))):
        leg = box(f"矮茶几锈腿_{index}", loc, (0.12, 0.12, 0.52), furniture, "metal", CELLS["rust_dark"], category="Props/Furniture")
        OUTPUT_OBJECTS.append(leg)

    curtain_specs = (
        ("左侧卷帘", (-7.15, -5.82, 1.15), (2.4, 0.055, 2.9), "green", -0.08),
        ("右侧半开布帘", (4.95, -5.82, 1.55), (2.5, 0.055, 2.2), "canvas", 0.10),
    )
    for index, (label, loc, size, cell, angle) in enumerate(curtain_specs):
        curtain = box(f"棚屋防水布帘_{label}", loc, size, vfx, "matte", CELLS[cell], rotation=(0.03, 0.0, angle), category="VFX")
        curtain["pivot_contract"] = "top_hanging_edge"
        OUTPUT_OBJECTS.append(curtain)
        animate_rotation(curtain, 0, [-0.025, 0.045, -0.025], [1, 58 + index * 8, 116 + index * 12], True)

    # Shelf-scale supplies remain separate assets.
    for index in range(6):
        jar = cylinder(
            f"种子罐_{index}", (4.98 + (index % 3) * 0.33, 1.98, 0.68 + (index // 3) * 0.72),
            0.11, 0.28, farming, "gloss", CELLS["green" if index % 2 else "paper"], 8,
            category="Props/Farming"
        )
        OUTPUT_OBJECTS.append(jar)
    for index in range(5):
        medicine = box(
            f"药品盒_{index}", (3.25 + index * 0.32, 4.15, 1.18 + (index % 2) * 0.18),
            (0.27, 0.20, 0.34), survival, "matte", CELLS["paper" if index != 3 else "red"],
            rotation=(0, 0, 0.05 * index), category="Props/Survival"
        )
        OUTPUT_OBJECTS.append(medicine)
    for index in range(8):
        can = cylinder(
            f"散落空罐头_{index}", (-1.0 + (index % 4) * 0.55, -2.8 - (index // 4) * 0.62, 0.02),
            0.12, 0.28, survival, "metal", CELLS["rust" if index % 3 else "concrete_light"], 8,
            rotation=(0.0, 0.25 * (index % 2), 0.18 * index), category="Props/Survival"
        )
        OUTPUT_OBJECTS.append(can)
    for index in range(7):
        paper = box(
            f"散落旧书报_{index}", (-3.4 + (index % 4) * 0.72, -1.5 - (index // 4) * 0.75, 0.025 + index * 0.004),
            (0.62, 0.46, 0.018), survival, "matte", CELLS["paper" if index % 2 else "concrete_light"],
            rotation=(0, 0, -0.35 + index * 0.13), category="Props/Survival"
        )
        OUTPUT_OBJECTS.append(paper)
        if index == 6:
            animate_rotation(paper, 2, [-0.08, 0.09, -0.08], [1, 65, 130], True)

    for index, loc in enumerate(((5.9, -1.3, 1.9), (5.9, -0.45, 1.8), (5.9, 0.35, 1.7))):
        pack = box(
            f"挂置物资包_{index}", loc, (0.75, 0.32, 0.95), survival, "matte",
            CELLS["green_dark" if index != 1 else "blue_dark"], rotation=(0.06, 0, 0.04 * index),
            category="Props/Survival", bevel=0.08
        )
        OUTPUT_OBJECTS.append(pack)

    lamp = cylinder(
        "棚屋核心复古露营灯_自发光", (-3.3, 1.0, 1.05), 0.24, 0.55, lighting,
        "emissive", CELLS["warning"], 10, category="Lighting"
    )
    OUTPUT_OBJECTS.append(lamp)
    warm = add_light(
        "棚屋核心露营灯光", "POINT", (-3.3, 1.0, 1.4), (1.0, 0.30, 0.08), 185,
        COLLECTIONS["展示_灯光镜头"], 2.0
    )
    warm.data.shadow_soft_size = 2.2
    for frame, energy in ((1, 170), (48, 190), (72, 176), (120, 187)):
        warm.data.energy = energy
        warm.data.keyframe_insert(data_path="energy", frame=frame)


def add_rooftop_story_props():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    survival = COLLECTIONS["输出_Props_Survival"]
    vfx = COLLECTIONS["输出_VFX"]

    # Hanging raincoat on the east railing.
    coat = box(
        "护栏悬挂旧雨衣", (23.55, -5.5, 1.05), (0.055, 1.8, 2.25), vfx,
        "matte", CELLS["warning"], rotation=(0.02, 0.05, 0.08), category="VFX"
    )
    hood = low_sphere(
        "旧雨衣兜帽", (23.48, -5.5, 3.25), (0.34, 0.42, 0.34), vfx,
        "matte", CELLS["warning"], "VFX"
    )
    OUTPUT_OBJECTS.extend((coat, hood))
    animate_rotation(coat, 0, [-0.035, 0.048, -0.035], [1, 70, 140], True)

    # Tool rack and farm tools against the stairwell wall.
    rack = box("靠墙旧工具架", (-13.25, -15.6, 0.0), (0.42, 4.4, 2.65), architecture, "metal", CELLS["rust_dark"], category="Environment/Architecture")
    OUTPUT_OBJECTS.append(rack)
    for index, y in enumerate((-17.1, -16.2, -15.3, -14.4)):
        tool = beam_between(
            f"靠墙旧农具_{index}", (-13.55, y, 0.12), (-13.55, y + 0.25 * (-1) ** index, 2.25),
            0.045, survival, "metal", CELLS["rust"], 8, "Props/Survival"
        )
        OUTPUT_OBJECTS.append(tool)
        head = box(
            f"旧农具头部_{index}", (-13.55, y + 0.25 * (-1) ** index, 2.12),
            (0.55, 0.12, 0.18), survival, "metal", CELLS["rust_dark"],
            rotation=(0, 0, 0.15 * (-1) ** index), category="Props/Survival"
        )
        OUTPUT_OBJECTS.append(head)

    for index, loc in enumerate(((-21.5, -5.5, 0.0), (-20.3, -5.2, 0.0), (-19.2, -5.7, 0.0))):
        weed = low_sphere(
            f"墙角丛生杂草_{index}", (loc[0], loc[1], 0.45), (0.65, 0.42, 0.58),
            COLLECTIONS["输出_Vegetation"], "matte", CELLS["green_dark" if index != 2 else "moss"], "Vegetation"
        )
        weed.rotation_euler.z = 0.55 * index
        OUTPUT_OBJECTS.append(weed)
        animate_rotation(weed, 1, [-0.04, 0.06, -0.04], [1, 44 + index * 7, 88 + index * 13], True)


def add_puddle_ripples():
    ground = COLLECTIONS["输出_Environment_Ground"]
    puddle = cylinder(
        "黄昏积水洼", (-10.4, -7.2, 0.015), 1.55, 0.018, ground,
        "gloss", CELLS["water"], 14, category="Environment/Ground"
    )
    puddle.scale.y = 0.58
    OUTPUT_OBJECTS.append(puddle)
    for index in range(3):
        ripple = torus_object(
            f"积水细碎波纹_{index}", (-10.4, -7.2, 0.045 + index * 0.006),
            0.38 + index * 0.30, 0.018, ground, "gloss", CELLS["concrete_light"],
            major_segments=16, minor_segments=4, category="Environment/Ground"
        )
        ripple.scale.y = 0.58
        ripple.keyframe_insert(data_path="scale", frame=1 + index * 18)
        ripple.scale.x *= 1.28
        ripple.scale.y *= 1.28
        ripple.keyframe_insert(data_path="scale", frame=72 + index * 18)
        if ripple.animation_data and ripple.animation_data.action:
            for fcurve in ripple.animation_data.action.fcurves:
                fcurve.modifiers.new("CYCLES")
        OUTPUT_OBJECTS.append(ripple)


def damage_rooftop_edges():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    ground = COLLECTIONS["输出_Environment_Ground"]
    for name in ("边缘矮墙_北侧", "边缘矮墙_南侧", "边缘矮墙_西侧", "边缘矮墙_东侧"):
        obj = bpy.data.objects.get(name)
        if obj:
            if obj in OUTPUT_OBJECTS:
                OUTPUT_OBJECTS.remove(obj)
            bpy.data.objects.remove(obj, do_unlink=True)

    wall_specs = {
        "北": [((-19.5, 24.65, 0), (11.0, 0.7, 0.88)), ((-5.5, 24.65, 0), (13.0, 0.7, 0.62)), ((10.5, 24.65, 0), (15.0, 0.7, 0.95)), ((22.5, 24.65, 0), (5.0, 0.7, 0.55))],
        "南": [((-20.0, -24.65, 0), (10.0, 0.7, 0.72)), ((-7.0, -24.65, 0), (12.0, 0.7, 1.0)), ((7.5, -24.65, 0), (13.0, 0.7, 0.58)), ((20.5, -24.65, 0), (9.0, 0.7, 0.86))],
        "西": [((-24.65, -19.0, 0), (0.7, 12.0, 0.92)), ((-24.65, -4.5, 0), (0.7, 13.0, 0.60)), ((-24.65, 10.0, 0), (0.7, 12.0, 0.82)), ((-24.65, 21.5, 0), (0.7, 7.0, 0.52))],
        "东": [((24.65, -20.0, 0), (0.7, 10.0, 0.65)), ((24.65, -7.0, 0), (0.7, 12.0, 0.95)), ((24.65, 7.0, 0), (0.7, 12.0, 0.55)), ((24.65, 20.0, 0), (0.7, 10.0, 0.85))],
    }
    for side, segments in wall_specs.items():
        for index, (loc, size) in enumerate(segments):
            wall = box(
                f"破损女儿墙_{side}_{index}", loc, size, architecture, "matte",
                CELLS["concrete" if index % 2 else "concrete_dark"],
                rotation=(0, 0, 0.01 * (-1) ** index), category="Environment/Architecture"
            )
            wall["damage_state"] = "chipped_segment"
            OUTPUT_OBJECTS.append(wall)

    gaps = ((-12.0, 24.4), (14.8, -24.4), (-24.4, 3.0), (24.4, 13.8))
    for gap_index, (x, y) in enumerate(gaps):
        for rod_index in range(3):
            rebar = cylinder(
                f"女儿墙外露钢筋_{gap_index}_{rod_index}",
                (x + (rod_index - 1) * (0.25 if abs(y) > 20 else 0.0), y + (rod_index - 1) * (0.25 if abs(x) > 20 else 0.0), 0.05),
                0.035, 1.15 - rod_index * 0.16, architecture, "metal", CELLS["rust_dark"], 6,
                rotation=(0.12 * (-1) ** rod_index, 0.08 * rod_index, 0), category="Environment/Architecture"
            )
            OUTPUT_OBJECTS.append(rebar)
        for chunk_index in range(7):
            dx = ((chunk_index * 37) % 11 - 5) * 0.12
            dy = ((chunk_index * 19) % 9 - 4) * 0.11
            rubble = box(
                f"女儿墙碎块_{gap_index}_{chunk_index}", (x + dx, y + dy, 0.02),
                (0.20 + 0.07 * (chunk_index % 3), 0.17 + 0.05 * (chunk_index % 2), 0.13 + 0.06 * (chunk_index % 4)),
                ground, "matte", CELLS["concrete_dark"],
                rotation=(0.1 * chunk_index, 0.06 * chunk_index, 0.31 * chunk_index), category="Environment/Ground"
            )
            OUTPUT_OBJECTS.append(rubble)

    crack_origins = ((-18, -9), (-11, 9), (2, -17), (9, 9), (16, -1), (-2, 18))
    for crack_index, (x, y) in enumerate(crack_origins):
        points = [(x, y, 0.025)]
        for step in range(1, 5):
            points.append((x + step * 0.75, y + math.sin(step * 1.7 + crack_index) * 0.65, 0.025))
        for step in range(4):
            crack = beam_between(
                f"扩展地坪裂缝_{crack_index}_{step}", points[step], points[step + 1], 0.028,
                ground, "matte", CELLS["black"], 6, "Environment/Ground"
            )
            OUTPUT_OBJECTS.append(crack)

    for index in range(8):
        fallen = box(
            f"坍塌护栏残段_{index}", (-22.0 + index * 6.0, 23.1 if index % 2 else -23.1, 0.12),
            (3.2, 0.11, 0.11), architecture, "metal", CELLS["rust_dark"],
            rotation=(0.15 + index * 0.04, 0.20 * (-1) ** index, 0.35 * (-1) ** index),
            category="Environment/Architecture"
        )
        OUTPUT_OBJECTS.append(fallen)


def enhance_structure_details():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    energy = COLLECTIONS["输出_Props_Energy"]
    comm = COLLECTIONS["输出_Props_Communication"]
    survival = COLLECTIONS["输出_Props_Survival"]

    roof_panels = (
        (-6.0, 3.25, 5.4, "blue"), (-1.1, 3.25, 4.7, "rust_dark"),
        (2.6, 3.25, 3.1, "glass"), (5.1, 3.25, 2.2, "green_dark"),
    )
    detail_index = 0
    for x, y, width, cell in roof_panels:
        divisions = max(2, int(width / 0.58))
        for line in range(divisions):
            px = x - width * 0.46 + line * width * 0.92 / max(1, divisions - 1)
            rib = box(
                f"棚顶压型板筋_{detail_index}", (px, y, 4.70), (0.045, 9.15, 0.055),
                architecture, "metal", CELLS[cell], category="Environment/Architecture"
            )
            OUTPUT_OBJECTS.append(rib)
            detail_index += 1
    for index, (x, y) in enumerate(((-8.0, -1.4), (-4.0, -1.4), (0.0, -1.4), (3.6, -1.4), (6.0, -1.4))):
        flap = box(
            f"棚顶撕裂翻边_{index}", (x, y, 4.48 - index * 0.03), (1.1, 0.45, 0.07),
            architecture, "metal", CELLS["rust" if index % 2 else "blue_dark"],
            rotation=(0.35 + index * 0.06, 0.06 * (-1) ** index, 0.08 * index), category="Environment/Architecture"
        )
        OUTPUT_OBJECTS.append(flap)
    for index in range(18):
        bolt = cylinder(
            f"棚顶固定螺栓_{index}", (-7.8 + (index % 6) * 2.6, -0.95 + (index // 6) * 4.0, 4.76),
            0.055, 0.035, architecture, "metal", CELLS["concrete_light"], 8, category="Environment/Architecture"
        )
        OUTPUT_OBJECTS.append(bolt)

    tank_specs = ((13.2, 5.0, 1.25), (17.4, 5.0, 1.25), (21.2, 5.3, 1.0))
    for tank_index, (x, y, radius) in enumerate(tank_specs):
        for band_index, z in enumerate((0.65, 1.65, 2.45)):
            band = torus_object(
                f"储水罐加固环_{tank_index}_{band_index}", (x, y, z), radius + 0.035, 0.045,
                energy, "metal", CELLS["rust_dark"], 16, 4, category="Props/Energy"
            )
            OUTPUT_OBJECTS.append(band)
        valve = cylinder(
            f"储水罐检修阀_{tank_index}", (x + radius * 0.72, y - radius * 0.72, 0.38),
            0.13, 0.28, energy, "metal", CELLS["warning"], 8,
            rotation=(math.pi / 2, 0, 0), category="Props/Energy"
        )
        OUTPUT_OBJECTS.append(valve)

    for row in range(2):
        for col in range(3):
            x = 13.0 + col * 4.0
            y = -14.0 + row * 4.8
            for leg_index, dx in enumerate((-1.2, 1.2)):
                leg = beam_between(
                    f"太阳能板折叠支腿_{row}_{col}_{leg_index}", (x + dx, y + 0.55, 0.05),
                    (x + dx, y - 0.15, 0.95), 0.045, energy, "metal", CELLS["rust_dark"], 8, "Props/Energy"
                )
                OUTPUT_OBJECTS.append(leg)
            hinge = cylinder(
                f"太阳能板铰链_{row}_{col}", (x, y + 0.78, 0.42), 0.075, 2.55, energy,
                "metal", CELLS["concrete_light"], 8, rotation=(0, math.pi / 2, 0), category="Props/Energy"
            )
            OUTPUT_OBJECTS.append(hinge)

    for index in range(16):
        knob = cylinder(
            f"广播台旋钮仪表_{index}", (5.0 + (index % 8) * 0.56, 12.88, 2.55 + (index // 8) * 0.36),
            0.07 + 0.015 * (index % 3), 0.055, comm, "gloss",
            CELLS["warning" if index % 5 == 0 else "concrete_light"], 8,
            rotation=(math.pi / 2, 0, 0), category="Props/Communication"
        )
        OUTPUT_OBJECTS.append(knob)

    exhaust = cylinder(
        "柴油发电机锈蚀排气管", (21.5, 1.7, 2.0), 0.13, 2.1, energy,
        "metal", CELLS["rust_dark"], 10, category="Props/Energy"
    )
    cap = cylinder(
        "柴油发电机排气防雨帽", (21.5, 1.7, 4.05), 0.24, 0.12, energy,
        "metal", CELLS["rust"], 10, category="Props/Energy"
    )
    OUTPUT_OBJECTS.extend((exhaust, cap))

    crate_positions = ((-10.5, -16.0, 1.3, 1.0), (-4.8, -15.0, 2.0, 1.4), (-6.5, -10.8, 4.2, 2.5))
    for crate_index, (x, y, sx, sy) in enumerate(crate_positions):
        for slat_index in range(3):
            slat = box(
                f"储物箱加固木条_{crate_index}_{slat_index}",
                (x - sx * 0.35 + slat_index * sx * 0.35, y - sy * 0.51, 0.08),
                (0.12, 0.05, 0.74), survival, "metal", CELLS["rust_dark"], category="Props/Survival"
            )
            OUTPUT_OBJECTS.append(slat)


def add_billboard_letters_and_neon():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    lighting = COLLECTIONS["输出_Lighting"]
    center_y = 21.88
    baseline = 3.20
    letter_x = {"S": -6.40, "A": -4.80, "F": -3.20, "E": -1.60}
    segments = {
        "top": ((0.0, 0.0, 1.95), (1.12, 0.20, 0.16)),
        "mid": ((0.0, 0.0, 1.00), (1.12, 0.20, 0.16)),
        "bottom": ((0.0, 0.0, 0.05), (1.12, 0.20, 0.16)),
        "ul": ((-0.49, 0.0, 1.08), (0.16, 0.20, 0.80)),
        "ur": ((0.49, 0.0, 1.08), (0.16, 0.20, 0.80)),
        "ll": ((-0.49, 0.0, 0.13), (0.16, 0.20, 0.80)),
        "lr": ((0.49, 0.0, 0.13), (0.16, 0.20, 0.80)),
    }
    letter_segments = {
        "S": ("top", "mid", "bottom", "ul", "lr"),
        "A": ("top", "mid", "ul", "ur", "ll", "lr"),
        "F": ("top", "mid", "ul", "ll"),
        "E": ("top", "mid", "bottom", "ul", "ll"),
    }
    broken_neon = {("S", "mid"), ("A", "ur"), ("F", "top"), ("E", "bottom")}
    for letter, names in letter_segments.items():
        for index, segment_name in enumerate(names):
            offset, size = segments[segment_name]
            metal_bar = box(
                f"大型立体广告字_{letter}_{segment_name}",
                (letter_x[letter] + offset[0], center_y, baseline + offset[2]), size,
                architecture, "metal", CELLS["rust" if (ord(letter) + index) % 2 else "concrete_dark"],
                rotation=(0, 0, 0.02 * (-1) ** index), category="Environment/Architecture", bevel=0.025
            )
            metal_bar["billboard_text"] = "SAFE"
            OUTPUT_OBJECTS.append(metal_bar)
            if (letter, segment_name) not in broken_neon and index % 2 == 0:
                neon_size = (size[0] * 0.78, 0.055, max(0.055, size[2] * 0.72))
                neon = box(
                    f"破损霓虹_SAFE_{letter}_{segment_name}_自发光",
                    (letter_x[letter] + offset[0], center_y - 0.14, baseline + offset[2] + size[2] * 0.12),
                    neon_size, lighting, "emissive", CELLS["red" if letter in ("S", "F") else "warning"],
                    rotation=(0, 0, 0.025 * (-1) ** index), category="Lighting"
                )
                neon["neon_state"] = "intermittent_broken"
                OUTPUT_OBJECTS.append(neon)

    for index, loc in enumerate(((-5.6, 21.45, 5.4), (-2.6, 21.45, 4.8))):
        glow = add_light(
            f"广告牌霓虹闪烁灯光_{index}", "POINT", loc,
            (1.0, 0.08 + index * 0.12, 0.015), 0, COLLECTIONS["展示_灯光镜头"], 3.0
        )
        glow.data.shadow_soft_size = 1.7
        for frame, energy in ((1, 0), (18 + index * 12, 180), (32 + index * 12, 25), (70 + index * 18, 210), (94 + index * 20, 0), (132 + index * 17, 165)):
            glow.data.energy = energy
            glow.data.keyframe_insert(data_path="energy", frame=frame)


def add_rooftop_lighting_network():
    lighting = COLLECTIONS["输出_Lighting"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    display = COLLECTIONS["展示_灯光镜头"]

    wire = box(
        "棚屋暖色串灯电线", (-1.0, -5.55, 3.55), (13.0, 0.035, 0.035),
        architecture, "matte", CELLS["black"], rotation=(0, 0.018, 0), category="Environment/Architecture"
    )
    OUTPUT_OBJECTS.append(wire)
    for index in range(9):
        x = -7.0 + index * 1.5
        z = 3.45 - 0.18 * math.sin(index * math.pi / 4)
        bulb = cylinder(
            f"棚屋串灯灯泡_{index}_自发光", (x, -5.62, z), 0.075, 0.16,
            lighting, "emissive", CELLS["warning" if index % 3 else "red"], 8, category="Lighting"
        )
        OUTPUT_OBJECTS.append(bulb)
        if index % 2 == 0:
            light = add_light(
                f"棚屋串灯光源_{index}", "POINT", (x, -5.8, z - 0.05),
                (1.0, 0.30, 0.07), 42, display, 1.0
            )
            light.data.shadow_soft_size = 1.2
            light.data.keyframe_insert(data_path="energy", frame=1)
            light.data.energy = 28 if index == 4 else 38
            light.data.keyframe_insert(data_path="energy", frame=68 + index * 3)
            light.data.energy = 44
            light.data.keyframe_insert(data_path="energy", frame=132)

    path_points = ((-11.5, -8.7), (-6.0, -8.7), (0.0, -8.7), (6.0, -8.0), (9.2, -2.2), (9.2, 4.0), (-10.8, 8.0), (-10.8, 14.0))
    for index, (x, y) in enumerate(path_points):
        post = cylinder(
            f"天台路径灯柱_{index}", (x, y, 0.02), 0.075, 0.72, lighting,
            "metal", CELLS["rust_dark"], 8, category="Lighting"
        )
        cap = cylinder(
            f"天台路径灯_{index}_自发光", (x, y, 0.72), 0.15, 0.16, lighting,
            "emissive", CELLS["warning"], 8, category="Lighting"
        )
        OUTPUT_OBJECTS.extend((post, cap))
        point = add_light(
            f"天台路径灯光源_{index}", "POINT", (x, y, 1.0), (1.0, 0.24, 0.055),
            55 if index < 6 else 38, display, 1.7
        )
        point.data.shadow_soft_size = 1.6

    for index, loc in enumerate(((-14.0, 8.0, 2.5), (11.0, 8.0, 2.7), (8.5, 19.0, 4.0))):
        shade = box(
            f"壁挂检修灯罩_{index}", (loc[0], loc[1], loc[2]), (0.65, 0.35, 0.38),
            lighting, "metal", CELLS["rust_dark"], rotation=(0.08, 0, 0.12 * index), category="Lighting"
        )
        lens = box(
            f"壁挂检修灯_{index}_自发光", (loc[0], loc[1] - 0.19, loc[2] + 0.08), (0.42, 0.05, 0.18),
            lighting, "emissive", CELLS["warning"], category="Lighting"
        )
        OUTPUT_OBJECTS.extend((shade, lens))
        add_light(
            f"壁挂检修灯光源_{index}", "POINT", (loc[0], loc[1] - 0.5, loc[2]),
            (1.0, 0.25, 0.06), 90, display, 2.0
        )


def add_dust_and_smoke_vfx():
    vfx = COLLECTIONS["输出_VFX"]
    city = COLLECTIONS["展示_城市远景"]
    random.seed(6324)

    for index in range(54):
        start = Vector((random.uniform(-27, 18), random.uniform(-24, 22), random.uniform(0.2, 4.5)))
        scale = (random.uniform(0.07, 0.22), random.uniform(0.04, 0.11), random.uniform(0.04, 0.12))
        mote = low_sphere(
            f"动态黄沙尘粒_{index}", start, scale, vfx, "matte",
            CELLS["warning" if index % 7 == 0 else "rust"], "VFX"
        )
        mote["vfx_type"] = "windborne_sand"
        if hasattr(mote, "visible_shadow"):
            mote.visible_shadow = False
        mote.keyframe_insert(data_path="location", frame=1 + index % 23)
        mote.location = start + Vector((14.0 + random.uniform(-2, 4), 2.5 + random.uniform(-1, 2), random.uniform(-0.2, 1.0)))
        mote.keyframe_insert(data_path="location", frame=150 + index % 31)
        if mote.animation_data and mote.animation_data.action:
            for fcurve in mote.animation_data.action.fcurves:
                fcurve.modifiers.new("CYCLES")
        OUTPUT_OBJECTS.append(mote)

    for index in range(14):
        streak = box(
            f"风卷黄沙细线_{index}", (-24 + index * 3.3, -18 + (index % 5) * 8.0, 0.15 + (index % 4) * 0.35),
            (1.2 + 0.25 * (index % 3), 0.035, 0.035), vfx, "matte", CELLS["rust"],
            rotation=(0.0, 0.02 * index, 0.12 + 0.03 * (index % 4)), category="VFX"
        )
        streak.keyframe_insert(data_path="location", frame=1)
        streak.location.x += 18
        streak.location.y += 3.5
        streak.keyframe_insert(data_path="location", frame=180)
        OUTPUT_OBJECTS.append(streak)

    for index in range(11):
        start_x = 21.5 + math.sin(index * 1.73) * 0.48
        start_y = 1.7 + math.cos(index * 1.29) * 0.36
        smoke = low_sphere(
            f"发电机动态烟尘_{index}", (start_x, start_y, 4.2 + index * 0.34),
            (0.18 + index * 0.035, 0.16 + index * 0.03, 0.24 + index * 0.04),
            vfx, "matte", CELLS["concrete_dark"], "VFX"
        )
        smoke.rotation_euler = (0.14 * index, 0.09 * (-1) ** index, 0.31 * index)
        smoke["vfx_type"] = "generator_smoke"
        if hasattr(smoke, "visible_shadow"):
            smoke.visible_shadow = False
        smoke.keyframe_insert(data_path="location", frame=1)
        smoke.location.x -= 2.0 + (index % 4) * 0.75
        smoke.location.y += 1.1 + (index % 3) * 0.65
        smoke.location.z += 4.2 + (index % 5) * 0.38
        smoke.keyframe_insert(data_path="location", frame=190)
        OUTPUT_OBJECTS.append(smoke)

    for index in range(18):
        haze = low_sphere(
            f"城市黄沙烟霾_{index}", (-55 + index * 6.5, 38 + (index % 4) * 7.0, -11 + (index % 4) * 1.2),
            (0.75 + (index % 4) * 0.20, 0.55 + (index % 3) * 0.15, 0.28 + (index % 2) * 0.10),
            city, "matte", CELLS["rust_dark" if index % 4 else "concrete_dark"], "Display/City"
        )
        haze["display_environment"] = True
        haze["vfx_type"] = "distant_dust_haze"
        if hasattr(haze, "visible_shadow"):
            haze.visible_shadow = False
        haze.keyframe_insert(data_path="location", frame=1)
        haze.location.x += 5.5
        haze.location.z += 1.0
        haze.keyframe_insert(data_path="location", frame=260)


def open_shelter_living_view_v003():
    """Turn the full canopy into a rear lean-to and pull the story props into view."""
    for obj in list(bpy.data.objects):
        if obj.name.startswith("棚屋防水布帘_"):
            if obj in OUTPUT_OBJECTS:
                OUTPUT_OBJECTS.remove(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        if obj.name.startswith("棚顶_") or obj.name.startswith("棚顶压型板筋_"):
            obj.scale.y *= 0.36
            obj.location.y = 6.15
        elif obj.name.startswith("棚顶撕裂翻边_"):
            obj.location.y = 4.35
        elif obj.name.startswith("棚顶固定螺栓_"):
            index = int(obj.name.split("_")[-1])
            obj.location.y = 4.75 + (index // 6) * 1.28

    sofa_names = ("沙发", "布艺沙发补丁")
    table_names = ("电缆卷筒", "老式收音机", "收音机调谐盘", "收音机信号表", "桌面杯具工具", "散开地图")
    coffee_names = ("生锈矮茶几", "矮茶几锈腿")
    for obj in bpy.data.objects:
        if any(token in obj.name for token in sofa_names):
            obj.location.y -= 1.55
        elif any(token in obj.name for token in table_names):
            obj.location.y -= 1.95
        elif any(token in obj.name for token in coffee_names):
            obj.location.y -= 1.15

    architecture = COLLECTIONS["输出_Environment_Architecture"]
    vfx = COLLECTIONS["输出_VFX"]
    for index, x in enumerate((-7.8, 5.8)):
        roll = cylinder(
            f"棚屋卷起防水布_{index}", (x, 4.45, 3.82), 0.16, 2.1, vfx,
            "matte", (9, 3), 10, rotation=(0, math.pi / 2, 0), category="VFX"
        )
        strap = torus_object(
            f"卷起防水布绑带_{index}", (x, 4.45, 3.82), 0.18, 0.025,
            architecture, "metal", (9, 2), 10, 4, rotation=(0, math.pi / 2, 0),
            category="Environment/Architecture"
        )
        OUTPUT_OBJECTS.extend((roll, strap))


def add_fine_prop_structure_v003():
    furniture = COLLECTIONS["输出_Props_Furniture"]
    survival = COLLECTIONS["输出_Props_Survival"]
    lighting = COLLECTIONS["输出_Lighting"]
    energy = COLLECTIONS["输出_Props_Energy"]

    # Sofa seams, feet and tuft buttons make the focal furniture read as upholstered rather than stacked boxes.
    for index, (start, end) in enumerate((
        ((-7.15, 2.02, 0.87), (-3.65, 2.02, 0.87)),
        ((-7.15, 3.26, 0.87), (-3.65, 3.26, 0.87)),
        ((-5.40, 2.02, 0.87), (-5.40, 3.26, 0.87)),
        ((-7.25, 3.24, 1.12), (-3.55, 3.24, 1.12)),
    )):
        seam = beam_between(
            f"沙发包边压线_{index}", start, end, 0.028, furniture,
            "matte", CELLS["blue_dark"], 8, "Props/Furniture"
        )
        OUTPUT_OBJECTS.append(seam)
    for index, x in enumerate((-6.55, -5.40, -4.25)):
        button = cylinder(
            f"沙发靠背纽扣_{index}", (x, 3.24, 1.48), 0.075, 0.035, furniture,
            "gloss", CELLS["teal"], 8, rotation=(math.pi / 2, 0, 0), category="Props/Furniture"
        )
        OUTPUT_OBJECTS.append(button)
    for index, loc in enumerate(((-7.15, 2.20, 0.0), (-3.65, 2.20, 0.0), (-7.15, 3.15, 0.0), (-3.65, 3.15, 0.0))):
        foot = box(f"沙发金属短脚_{index}", loc, (0.16, 0.16, 0.24), furniture, "metal", (9, 2), category="Props/Furniture")
        OUTPUT_OBJECTS.append(foot)

    # Radio grille, twin knobs and a telescopic aerial.
    for index in range(7):
        grille = box(
            f"收音机扬声器格栅_{index}", (-2.10 + index * 0.10, 1.17, 1.12),
            (0.035, 0.025, 0.30), survival, "metal", (9, 4), category="Props/Survival"
        )
        OUTPUT_OBJECTS.append(grille)
    for index, x in enumerate((-1.56, -1.38)):
        knob = cylinder(
            f"收音机控制旋钮_{index}", (x, 1.16, 1.15), 0.075, 0.045, survival,
            "gloss", CELLS["warning"], 10, rotation=(math.pi / 2, 0, 0), category="Props/Survival"
        )
        OUTPUT_OBJECTS.append(knob)
    aerial = beam_between(
        "收音机伸缩天线", (-2.12, 1.42, 1.48), (-2.72, 1.42, 2.52),
        0.022, survival, "metal", (9, 5), 8, "Props/Survival"
    )
    OUTPUT_OBJECTS.append(aerial)

    # The lantern gains a protective cage, top cap and carry handle.
    for index, angle in enumerate((0.0, math.pi / 2, math.pi, math.pi * 1.5)):
        x = -3.3 + math.cos(angle) * 0.31
        y = 1.0 + math.sin(angle) * 0.31
        cage = cylinder(
            f"复古露营灯防护笼_{index}", (x, y, 0.96), 0.018, 0.78, lighting,
            "metal", (9, 3), 6, category="Lighting"
        )
        OUTPUT_OBJECTS.append(cage)
    cap = cylinder("复古露营灯顶盖", (-3.3, 1.0, 1.68), 0.34, 0.10, lighting, "metal", (9, 2), 10, category="Lighting")
    handle = torus_object("复古露营灯提手", (-3.3, 1.0, 1.88), 0.39, 0.025, lighting, "metal", (9, 4), 12, 4, rotation=(math.pi / 2, 0, 0), category="Lighting")
    OUTPUT_OBJECTS.extend((cap, handle))
    living_glow = add_light(
        "开放起居区暖色柔光", "POINT", (-5.0, 2.4, 2.65), (1.0, 0.38, 0.12),
        260, COLLECTIONS["展示_灯光镜头"], 3.2
    )
    living_glow.data.shadow_soft_size = 2.8

    # AC fans receive recessed hubs, blades and pipe clamps.
    for unit_index, x in enumerate((-7.0, -3.5)):
        hub = cylinder(
            f"空调风扇轴心_{unit_index}", (x, 17.86, 0.95), 0.14, 0.10, energy,
            "metal", (9, 2), 10, rotation=(math.pi / 2, 0, 0), category="Props/Energy"
        )
        OUTPUT_OBJECTS.append(hub)
        for blade_index in range(5):
            blade = box(
                f"空调风扇叶片_{unit_index}_{blade_index}", (x, 17.84, 0.95),
                (0.48, 0.035, 0.13), energy, "metal", (9, 3),
                rotation=(0, 0, blade_index * math.tau / 5), category="Props/Energy", bevel=0.025
            )
            OUTPUT_OBJECTS.append(blade)


def add_ground_decay_v003():
    ground = COLLECTIONS["输出_Environment_Ground"]
    survival = COLLECTIONS["输出_Props_Survival"]
    random.seed(9031)

    # Broad stains and cross-tile cracks soften the regular 10x10 module read without changing module interfaces.
    stain_specs = ((-17.2, -16.8, 2.7, 0.55), (-9.8, 11.8, 3.3, 0.38), (8.5, -5.8, 2.4, 0.62),
                   (17.5, 14.0, 3.0, 0.42), (1.0, 18.2, 2.2, 0.52), (12.2, 1.0, 2.8, 0.36))
    for index, (x, y, radius, squash) in enumerate(stain_specs):
        stain = cylinder(
            f"跨地砖深色污渍_{index}", (x, y, 0.012), radius, 0.012, ground,
            "matte", (9, 1 if index % 2 else 2), 13, category="Environment/Ground"
        )
        stain.scale.y = squash
        stain.rotation_euler.z = 0.27 * index
        OUTPUT_OBJECTS.append(stain)

    for crack_index, (x, y, angle) in enumerate(((-15, -1, 0.12), (-5, -12, -0.34), (5, 14, 0.25), (15, 7, -0.18))):
        points = [(x, y, 0.035)]
        for step in range(1, 8):
            points.append((x + math.cos(angle) * step * 1.25, y + math.sin(angle) * step * 1.25 + math.sin(step * 1.9) * 0.65, 0.035))
        for step in range(len(points) - 1):
            crack = beam_between(
                f"跨模块断裂缝_{crack_index}_{step}", points[step], points[step + 1], 0.035,
                ground, "matte", (9, 0), 6, "Environment/Ground"
            )
            OUTPUT_OBJECTS.append(crack)

    debris_positions = ((-20, -12), (-16, -3), (-12, 18), (-7, -19), (1, -14), (6, 17), (11, 8), (17, -2), (20, 18))
    for cluster, (x, y) in enumerate(debris_positions):
        panel = box(
            f"地面弯折废铁皮_{cluster}", (x, y, 0.035), (1.5 + 0.2 * (cluster % 3), 0.72, 0.055),
            survival, "metal", (9, 2 + cluster % 2), rotation=(0.04, 0.08 * (-1) ** cluster, 0.31 * cluster),
            category="Props/Survival"
        )
        OUTPUT_OBJECTS.append(panel)
        for piece in range(3):
            rubble = box(
                f"地面混凝土碎块_{cluster}_{piece}",
                (x - 0.6 + piece * 0.55, y + 0.55 + math.sin(piece + cluster) * 0.35, 0.02),
                (0.22 + 0.10 * (piece % 2), 0.18 + 0.08 * ((piece + 1) % 2), 0.16 + 0.05 * piece),
                ground, "matte", (9, 2 + (cluster + piece) % 2),
                rotation=(0.18 * piece, 0.12 * cluster, 0.45 * (cluster + piece)), category="Environment/Ground"
            )
            OUTPUT_OBJECTS.append(rubble)


def rebuild_city_architecture_v003():
    city = COLLECTIONS["展示_城市远景"]
    removable = ("远景废弃楼_", "远景楼顶水箱_", "远景通信杆_")
    for obj in list(city.objects):
        if obj.name.startswith(removable):
            bpy.data.objects.remove(obj, do_unlink=True)

    tower_specs = (
        (-55, -36, 12, 11, 40), (-38, -51, 10, 14, 34), (-15, -58, 13, 10, 43),
        (12, -60, 11, 13, 38), (38, -52, 14, 10, 46), (57, -34, 12, 12, 35),
        (62, -5, 13, 10, 42), (59, 23, 10, 14, 33), (48, 46, 15, 12, 40),
        (22, 58, 12, 15, 36), (-6, 63, 15, 11, 44), (-34, 56, 12, 13, 37),
        (-55, 39, 13, 11, 42), (-64, 13, 11, 15, 34), (-63, -13, 14, 10, 39),
        (-82, -43, 15, 14, 34), (-47, -78, 13, 16, 31), (0, -84, 16, 13, 37),
        (48, -75, 14, 15, 33), (82, -32, 15, 12, 38), (78, 35, 14, 16, 32),
        (35, 80, 16, 13, 35), (-24, 83, 15, 15, 31), (-76, 51, 14, 13, 36),
    )
    for index, (x, y, sx, sy, height) in enumerate(tower_specs):
        base_z = -22.0
        lower_h = height * (0.52 + 0.04 * (index % 3))
        middle_h = height * 0.27
        upper_h = height - lower_h - middle_h
        rotation = 0.025 * ((index % 5) - 2)
        segments = (
            (f"远景结构楼_{index}_裙楼", (x, y, base_z), (sx, sy, lower_h)),
            (f"远景结构楼_{index}_退台", (x + 0.45 * (-1) ** index, y - 0.30, base_z + lower_h), (sx * 0.84, sy * 0.82, middle_h)),
            (f"远景结构楼_{index}_破损塔冠", (x - 0.30, y + 0.35 * (-1) ** index, base_z + lower_h + middle_h), (sx * (0.62 + 0.05 * (index % 2)), sy * 0.66, upper_h)),
        )
        for segment_name, loc, size in segments:
            building = box(segment_name, loc, size, city, "matte", (9, 1 + index % 3), rotation=(0, 0, rotation), category="Display/City")
            building["display_environment"] = True

        top_z = base_z + height
        for floor in range(max(4, int(height // 4.2))):
            z = base_z + 2.2 + floor * 3.7
            if z > top_z - 2.0:
                break
            window_cell = CELLS["warning"] if index % 7 == 0 and floor in (2, 5) else (9, 0)
            role = "emissive" if window_cell == CELLS["warning"] else "gloss"
            south_name = f"远景楼窗带_南_{index}_{floor}" + ("_自发光" if role == "emissive" else "")
            south = box(
                south_name, (x, y - sy * 0.505, z),
                (sx * 0.68, 0.055, 0.42), city, role, window_cell, rotation=(0, 0, rotation), category="Display/City"
            )
            east = box(
                f"远景楼窗带_东_{index}_{floor}", (x + sx * 0.505, y, z + 0.72),
                (0.055, sy * 0.62, 0.36), city, "gloss", (9, 0), rotation=(0, 0, rotation), category="Display/City"
            )
            south["display_environment"] = True
            east["display_environment"] = True

        for rib_index, offset in enumerate((-0.38, 0.38)):
            rib = box(
                f"远景楼立面竖肋_{index}_{rib_index}", (x + sx * offset, y - sy * 0.51, base_z),
                (0.22, 0.10, lower_h * 0.92), city, "metal", (9, 2), category="Display/City"
            )
            rib["display_environment"] = True

        if index % 3 == 0:
            tank = cylinder(
                f"远景精细楼顶水箱_{index}", (x - sx * 0.18, y, top_z), min(sx, sy) * 0.14,
                1.8, city, "metal", (9, 2), 10, category="Display/City"
            )
            tank["display_environment"] = True
            for band_index in range(2):
                band = torus_object(
                    f"远景水箱箍带_{index}_{band_index}",
                    (x - sx * 0.18, y, top_z + 0.45 + band_index * 0.75), min(sx, sy) * 0.145,
                    0.035, city, "metal", (9, 3), 12, 4, category="Display/City"
                )
                band["display_environment"] = True
        if index % 4 == 0:
            mast = cylinder(
                f"远景楼顶折损天线_{index}", (x + sx * 0.22, y, top_z), 0.07, 4.5,
                city, "metal", (9, 1), 8, rotation=(0.06 * (-1) ** index, 0.08, 0), category="Display/City"
            )
            mast["display_environment"] = True

        # Missing corner caps and fallen facade plates establish damage without boolean-heavy geometry.
        for damage_index in range(2):
            damage = box(
                f"远景楼破损立面残片_{index}_{damage_index}",
                (x + sx * (0.38 - damage_index * 0.15), y - sy * 0.53, top_z - 1.2 - damage_index * 1.1),
                (sx * (0.18 + 0.05 * damage_index), 0.12, 0.65 + 0.35 * damage_index),
                city, "metal", (9, 0), rotation=(0.12 * damage_index, 0.08, rotation + 0.12 * (-1) ** damage_index),
                category="Display/City"
            )
            damage["display_environment"] = True

    # Dense, low-contrast dust banks collect below roof level between the towers.
    random.seed(9044)
    for index in range(34):
        angle = math.tau * index / 34.0
        radius = 48 + (index % 5) * 7.0
        haze = low_sphere(
            f"楼群底部弥漫烟尘_{index}",
            (math.cos(angle) * radius, math.sin(angle) * radius, -20.0 + (index % 4) * 0.65),
            (1.1 + (index % 3) * 0.35, 0.65 + (index % 4) * 0.18, 0.38 + (index % 2) * 0.14),
            city, "matte", (9, 2 + index % 2), "Display/City"
        )
        haze["display_environment"] = True
        haze["vfx_type"] = "city_base_dust_bank"
        if hasattr(haze, "visible_shadow"):
            haze.visible_shadow = False
        haze.keyframe_insert(data_path="location", frame=1)
        haze.location.x += 3.5
        haze.location.z += 0.5
        haze.keyframe_insert(data_path="location", frame=300)


def apply_unified_palette_v003():
    """Use close cool-gray values for most area; reserve chroma for deliberate focal points."""
    accent_tokens = (
        "霓虹", "自发光", "沙发", "收音机", "地图", "便签", "露营灯", "灯泡",
        "灯_", "雨衣", "警示布条", "番茄果实",
    )
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        name = obj.name
        category = obj.get("asset_category", "")
        if any(token in name for token in accent_tokens):
            continue
        if category == "Vegetation":
            palette_uv(obj.data, CELLS["green_dark"] if "枯" not in name else (9, 3))
            continue
        if name.startswith("地砖_G"):
            gx = int(name.split("_")[1][1:])
            gy = int(name.split("_")[2][1:])
            palette_uv(obj.data, (9, 3 + ((gx + gy) % 2)))
            continue
        gray_seed = sum(ord(char) for char in name)
        if category.startswith("Display/"):
            palette_uv(obj.data, (9, 2 + gray_seed % 3))
        elif category.startswith(("Environment/", "Props/Energy", "Props/Communication", "Collision/", "VFX")):
            palette_uv(obj.data, (9, 3 + gray_seed % 3))
        elif category.startswith(("Props/Farming", "Props/Survival", "Props/Furniture")):
            palette_uv(obj.data, (9, 3 + gray_seed % 3))


def setup_gradient_sunset_world():
    scene = bpy.context.scene
    world = scene.world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    links = world.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputWorld")
    output.location = (520, 0)
    background = nodes.new("ShaderNodeBackground")
    background.name = "黄昏渐变背景"
    background.location = (260, 0)
    background.inputs["Strength"].default_value = 0.36
    texcoord = nodes.new("ShaderNodeTexCoord")
    texcoord.location = (-620, 0)
    separate = nodes.new("ShaderNodeSeparateXYZ")
    separate.location = (-420, 0)
    mapping = nodes.new("ShaderNodeMapRange")
    mapping.location = (-220, 0)
    mapping.inputs["From Min"].default_value = -0.18
    mapping.inputs["From Max"].default_value = 0.82
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.location = (20, 0)
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    low = ramp.color_ramp.elements[0]
    low.position = 0.0
    low.color = (0.085, 0.050, 0.046, 1.0)
    middle = ramp.color_ramp.elements.new(0.32)
    middle.color = (0.105, 0.060, 0.060, 1.0)
    high = ramp.color_ramp.elements.new(0.72)
    high.color = (0.030, 0.052, 0.080, 1.0)
    top = ramp.color_ramp.elements.new(1.0)
    top.color = (0.014, 0.026, 0.048, 1.0)
    links.new(texcoord.outputs["Normal"], separate.inputs["Vector"])
    links.new(separate.outputs["Z"], mapping.inputs["Value"])
    links.new(mapping.outputs["Result"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], background.inputs["Color"])
    links.new(background.outputs["Background"], output.inputs["Surface"])

    background.inputs["Strength"].keyframe_insert(data_path="default_value", frame=1)
    background.inputs["Strength"].default_value = 0.30
    background.inputs["Strength"].keyframe_insert(data_path="default_value", frame=360)
    middle.color = (0.115, 0.065, 0.058, 1.0)
    middle.keyframe_insert(data_path="color", frame=1)
    middle.color = (0.065, 0.042, 0.058, 1.0)
    middle.keyframe_insert(data_path="color", frame=360)

    sunset = add_light(
        "黄昏低角度太阳", "SUN", (-35, -42, 24), (0.82, 0.34, 0.16), 0.90,
        COLLECTIONS["展示_灯光镜头"]
    )
    sunset.rotation_euler = (math.radians(72), math.radians(-18), math.radians(128))
    sunset.data.angle = math.radians(9)
    cool_fill = add_light(
        "黄昏冷色环境补光", "AREA", (8, -18, 42), (0.24, 0.34, 0.50), 1380,
        COLLECTIONS["展示_灯光镜头"], 46
    )
    cool_fill.rotation_euler = (0.12, 0.0, 0.35)


def setup_atmospheric_perspective_v003():
    scene = bpy.context.scene
    scene.world.mist_settings.use_mist = True
    scene.world.mist_settings.start = 82.0
    scene.world.mist_settings.depth = 112.0
    scene.world.mist_settings.falloff = "QUADRATIC"
    scene.view_layers[0].use_pass_mist = True
    scene.use_nodes = True
    nodes = scene.node_tree.nodes
    links = scene.node_tree.links
    nodes.clear()

    render_layers = nodes.new("CompositorNodeRLayers")
    render_layers.location = (-420, 40)
    mist_range = nodes.new("CompositorNodeMapRange")
    mist_range.location = (-180, -120)
    mist_range.inputs["From Min"].default_value = 0.02
    mist_range.inputs["From Max"].default_value = 0.62
    mist_range.inputs["To Min"].default_value = 0.0
    mist_range.inputs["To Max"].default_value = 0.28
    mist_range.use_clamp = True
    mix = nodes.new("CompositorNodeMixRGB")
    mix.name = "黄昏冷灰空气透视"
    mix.location = (80, 40)
    mix.blend_type = "MIX"
    mix.inputs[2].default_value = (0.070, 0.100, 0.135, 1.0)
    composite = nodes.new("CompositorNodeComposite")
    composite.location = (330, 40)
    links.new(render_layers.outputs["Image"], mix.inputs[1])
    links.new(render_layers.outputs["Mist"], mist_range.inputs["Value"])
    links.new(mist_range.outputs["Value"], mix.inputs[0])
    links.new(mix.outputs["Image"], composite.inputs["Image"])


def apply_toon_dusk_style():
    scene = bpy.context.scene
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 1400
    scene.render.resolution_percentage = 100
    scene.view_settings.look = "AgX - Medium Low Contrast"
    scene.view_settings.exposure = 0.95
    scene.render.film_transparent = False
    if hasattr(scene.render, "use_freestyle"):
        scene.render.use_freestyle = True
        scene.render.line_thickness = 1.05
        freestyle = scene.view_layers[0].freestyle_settings
        line_set = freestyle.linesets[0]
        line_set.select_silhouette = True
        line_set.select_border = True
        line_set.select_crease = True
        line_set.select_material_boundary = False
        line_set.linestyle.color = (0.010, 0.014, 0.020)
        line_set.linestyle.thickness = 1.05

    light_adjustments = {
        "阴天傍晚主光": ((0.38, 0.46, 0.58), 1.70),
        "冷色天空补光": ((0.28, 0.36, 0.50), 1450),
        "庇护所整体暖光": ((1.0, 0.34, 0.10), 430),
        "城市轮廓光": ((0.25, 0.31, 0.40), 760),
    }
    for name, (color, energy) in light_adjustments.items():
        obj = bpy.data.objects.get(name)
        if obj and obj.type == "LIGHT":
            obj.data.color = color
            obj.data.energy = energy

    camera = bpy.data.objects.get("第三视角_微缩模型主镜头")
    camera.location = (61, -61, 57)
    camera.data.ortho_scale = 70
    camera.rotation_euler = (Vector((0, 0, 2.4)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera


def write_diorama_manifest(tile_counts):
    category_counts = {}
    for obj in bpy.context.scene.objects:
        category = obj.get("asset_category")
        if category:
            category_counts[category] = category_counts.get(category, 0) + 1
    manifest = {
        "asset": "三渲二末世天台庇护所微缩景观",
        "asset_id": "ENV_ROOFTOP_SHELTER_DIORAMA_003",
        "version": "v003",
        "dimensions_m": [50.0, 50.0],
        "grid_module_m": [5.0, 5.0],
        "ground_module_count": 100,
        "tile_type_counts": tile_counts,
        "style": ["toon-rendered", "low-poly", "hard-outline", "restrained-gray-dusk", "atmospheric-dust"],
        "palette": str(PALETTE_FILE),
        "materials": [material.name for material in MATERIALS.values()],
        "category_object_counts": category_counts,
        "source_prototype_count": len(SOURCE_PROTOTYPES),
        "game_output_object_count": len(OUTPUT_OBJECTS),
        "collision_object_count": len(COLLISION_OBJECTS),
        "animation_frame_range": [1, 360],
        "ui_visible_in_showcase": False,
        "deliverables": {
            "source_blend": str(SOURCE_BLEND),
            "game_blend": str(GAME_BLEND),
            "full_preview": str(FULL_PREVIEW),
            "living_preview": str(DETAIL_PREVIEW),
        },
    }
    MANIFEST_FILE.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def build_diorama():
    ensure_dirs()
    clear_scene()
    setup_collections()
    setup_palette_materials()
    tile_counts = build_ground()
    build_rooftop_shell()
    build_shelter()
    build_farming()
    build_energy_water()
    build_communication()
    build_entry_defense_and_clutter()
    build_city_background()
    create_source_prototypes()
    setup_audio()
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes.clear()
    base_background = world.node_tree.nodes.new("ShaderNodeBackground")
    base_background.name = "Background"
    base_output = world.node_tree.nodes.new("ShaderNodeOutputWorld")
    world.node_tree.links.new(base_background.outputs["Background"], base_output.inputs["Surface"])
    setup_render()
    add_ac_units()
    add_bicycle_wreck()
    add_advertising_frame()
    add_living_details()
    add_rooftop_story_props()
    add_puddle_ripples()
    damage_rooftop_edges()
    enhance_structure_details()
    open_shelter_living_view_v003()
    add_fine_prop_structure_v003()
    add_ground_decay_v003()
    rebuild_city_architecture_v003()
    add_billboard_letters_and_neon()
    add_rooftop_lighting_network()
    add_dust_and_smoke_vfx()
    apply_unified_palette_v003()
    apply_toon_dusk_style()
    setup_gradient_sunset_world()
    setup_atmospheric_perspective_v003()
    write_diorama_manifest(tile_counts)
    save_deliverables()
    print(json.dumps({
        "status": "built",
        "objects": len(bpy.context.scene.objects),
        "meshes": sum(1 for obj in bpy.context.scene.objects if obj.type == "MESH"),
        "materials": len(bpy.data.materials),
        "output_objects": len(OUTPUT_OBJECTS),
        "collisions": len(COLLISION_OBJECTS),
        "source_blend": str(SOURCE_BLEND),
        "game_blend": str(GAME_BLEND),
    }, ensure_ascii=False))


def render_diorama_previews():
    scene = bpy.context.scene
    camera = bpy.data.objects.get("第三视角_微缩模型主镜头")
    if camera is None:
        raise RuntimeError("Main camera is missing")
    scene.camera = camera
    scene.frame_set(84)
    camera.location = (42, -42, 34)
    camera.data.ortho_scale = 44
    camera.rotation_euler = (Vector((-2.0, 0.5, 2.7)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 1400
    scene.render.filepath = str(DETAIL_PREVIEW)
    bpy.ops.render.render(write_still=True)

    scene.frame_set(126)
    camera.location = (61, -61, 57)
    camera.data.ortho_scale = 70
    camera.rotation_euler = (Vector((0, 0, 2.4)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(FULL_PREVIEW)
    bpy.ops.render.render(write_still=True)
    save_deliverables()
    print(json.dumps({"status": "rendered", "full": str(FULL_PREVIEW), "detail": str(DETAIL_PREVIEW)}, ensure_ascii=False))


DIORAMA_MODE = globals().get("DIORAMA_MODE", "build")
if DIORAMA_MODE == "build":
    build_diorama()
elif DIORAMA_MODE == "render":
    render_diorama_previews()
else:
    raise ValueError(f"Unknown DIORAMA_MODE: {DIORAMA_MODE}")
