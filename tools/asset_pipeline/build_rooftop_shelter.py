import json
import math
import random
import shutil
import wave
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
ASSET_ROOT = PROJECT_ROOT / "assets" / "art" / "environments" / "rooftop_shelter_3d"
SOURCE_DIR = ASSET_ROOT / "source" / "rooftop_shelter"
GAME_DIR = ASSET_ROOT / "game_output" / "rooftop_shelter"
PREVIEW_DIR = ASSET_ROOT / "previews"
SHARED_DIR = ASSET_ROOT / "shared"
DOCS_DIR = ASSET_ROOT / "docs"
PALETTE_SOURCE = PROJECT_ROOT / "assets" / "art" / "shared" / "palette" / "设施低亮多巴胺色盘_10x10_512.png"
PALETTE_FILE = SHARED_DIR / "多巴胺色盘_10x10_512.png"
SOURCE_BLEND = SOURCE_DIR / "env_rooftop_shelter_source_v001.blend"
GAME_BLEND = GAME_DIR / "env_rooftop_shelter_game_v001.blend"
FULL_PREVIEW = PREVIEW_DIR / "env_rooftop_shelter_full_v001.png"
DETAIL_PREVIEW = PREVIEW_DIR / "env_rooftop_shelter_detail_v001.png"
MANIFEST_FILE = DOCS_DIR / "env_rooftop_shelter_manifest_v001.json"
STATIC_AUDIO = SHARED_DIR / "radio_static_soft_v001.wav"


CELLS = {
    "concrete_dark": (9, 2),
    "concrete": (9, 4),
    "concrete_light": (9, 6),
    "blue": (8, 5),
    "blue_dark": (8, 3),
    "teal": (7, 4),
    "green": (6, 4),
    "green_dark": (5, 4),
    "moss": (6, 5),
    "rust": (4, 7),
    "rust_dark": (3, 7),
    "wood": (5, 7),
    "wood_dark": (2, 7),
    "canvas": (7, 6),
    "warning": (6, 6),
    "red": (2, 8),
    "paper": (9, 8),
    "water": (7, 5),
    "glass": (8, 6),
    "black": (0, 0),
    "purple": (4, 2),
}


MATERIALS = {}
COLLECTIONS = {}
OUTPUT_OBJECTS = []
SOURCE_PROTOTYPES = []
COLLISION_OBJECTS = []
LIGHT_OBJECTS = []


def ensure_dirs():
    for directory in (SOURCE_DIR, GAME_DIR, PREVIEW_DIR, SHARED_DIR, DOCS_DIR):
        directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PALETTE_SOURCE, PALETTE_FILE)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.speakers,
        bpy.data.collections,
    ):
        for datablock in list(datablocks):
            datablocks.remove(datablock)
    for image in list(bpy.data.images):
        if image.name != "Render Result":
            bpy.data.images.remove(image)
    OUTPUT_OBJECTS.clear()
    SOURCE_PROTOTYPES.clear()
    COLLISION_OBJECTS.clear()
    LIGHT_OBJECTS.clear()
    MATERIALS.clear()
    COLLECTIONS.clear()


def make_collection(name, parent=None):
    collection = bpy.data.collections.new(name)
    if parent is None:
        bpy.context.scene.collection.children.link(collection)
    else:
        parent.children.link(collection)
    COLLECTIONS[name] = collection
    return collection


def setup_collections():
    root = make_collection("末世天台庇护所_中文资产管理")
    source = make_collection("01_制作组件_已统一材质", root)
    output = make_collection("02_游戏输出_整合模型", root)
    collision = make_collection("03_游戏碰撞_独立阻挡", root)
    display = make_collection("90_展示环境_灯光相机", root)

    categories = (
        "Environment_Architecture",
        "Environment_Ground",
        "Props_Furniture",
        "Props_Survival",
        "Props_Communication",
        "Props_Energy",
        "Props_Farming",
        "Vegetation",
        "Lighting",
        "VFX",
        "UI",
        "Shared",
    )
    for category in categories:
        make_collection(f"源_{category}", source)
        make_collection(f"输出_{category}", output)
    make_collection("碰撞_Ground", collision)
    make_collection("碰撞_Architecture", collision)
    make_collection("展示_城市远景", display)
    make_collection("展示_灯光镜头", display)
    source.hide_viewport = True
    source.hide_render = True
    collision.hide_viewport = True
    collision.hide_render = True
    COLLECTIONS["输出_UI"].hide_render = True
    COLLECTIONS["源_UI"].hide_render = True


def setup_palette_materials():
    image = bpy.data.images.load(str(PALETTE_FILE), check_existing=False)
    image.name = "多巴胺色盘_10x10_512"
    image.colorspace_settings.name = "sRGB"
    image.pack()

    definitions = (
        ("metal", "01_精工金属_紫色骨架", 0.86, 0.28, 0.18, 0.0),
        ("matte", "02_细腻哑光_青绿大面", 0.02, 0.70, 0.0, 0.0),
        ("gloss", "03_清漆反光_紫粉点缀", 0.16, 0.15, 0.68, 0.0),
        ("emissive", "04_柔和自发光_UI灯光", 0.0, 0.36, 0.0, 1.35),
    )
    for key, name, metallic, roughness, coat, emission_strength in definitions:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        output.location = (440, 0)
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.location = (140, 0)
        uv = nodes.new("ShaderNodeUVMap")
        uv.uv_map = "PaletteUV"
        uv.location = (-520, 0)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        tex.extension = "EXTEND"
        tex.location = (-260, 0)
        links.new(uv.outputs["UV"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if bsdf.inputs.get("Coat Weight"):
            bsdf.inputs["Coat Weight"].default_value = coat
        if emission_strength > 0.0:
            links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
        MATERIALS[key] = material


def palette_uv(mesh, cell):
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    layer = mesh.uv_layers.new(name="PaletteUV")
    layer.active_render = True
    mesh.uv_layers.active = layer
    col, row = cell
    center_x = (col + 0.5) / 10.0
    center_y = (row + 0.5) / 10.0
    radius = 0.023
    for polygon in mesh.polygons:
        count = len(polygon.loop_indices)
        for index, loop_index in enumerate(polygon.loop_indices):
            angle = math.tau * index / max(3, count) + 0.25
            layer.data[loop_index].uv = (
                center_x + math.cos(angle) * radius,
                center_y + math.sin(angle) * radius,
            )


def tag_object(obj, category, asset_id=None, version="v001"):
    obj["asset_id"] = asset_id or obj.name
    obj["asset_category"] = category
    obj["asset_version"] = version
    obj["forward_axis"] = "-Y"
    obj["up_axis"] = "+Z"


def make_mesh_object(name, vertices, faces, collection, material_key="matte", cell=None, category="Shared"):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    material = MATERIALS[material_key]
    mesh.materials.append(material)
    palette_uv(mesh, cell or CELLS["concrete"])
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    tag_object(obj, category)
    return obj


def box(name, location, size, collection, material_key="matte", cell=None, rotation=(0.0, 0.0, 0.0), category="Shared", bevel=0.0):
    sx, sy, sz = size
    vertices = [
        (-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0), (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0),
        (-sx / 2, -sy / 2, sz), (sx / 2, -sy / 2, sz), (sx / 2, sy / 2, sz), (-sx / 2, sy / 2, sz),
    ]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    obj = make_mesh_object(name, vertices, faces, collection, material_key, cell, category)
    obj.location = location
    obj.rotation_euler = rotation
    if bevel > 0.0:
        modifier = obj.modifiers.new("低模倒角", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        modifier.limit_method = "ANGLE"
    return obj


def cylinder(name, location, radius, height, collection, material_key="matte", cell=None, vertices_count=10, rotation=(0.0, 0.0, 0.0), category="Shared"):
    vertices = []
    for z in (0.0, height):
        for index in range(vertices_count):
            angle = math.tau * index / vertices_count
            vertices.append((math.cos(angle) * radius, math.sin(angle) * radius, z))
    faces = []
    faces.append(tuple(reversed(range(vertices_count))))
    faces.append(tuple(range(vertices_count, vertices_count * 2)))
    for index in range(vertices_count):
        nxt = (index + 1) % vertices_count
        faces.append((index, nxt, vertices_count + nxt, vertices_count + index))
    obj = make_mesh_object(name, vertices, faces, collection, material_key, cell, category)
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def low_sphere(name, location, scale, collection, material_key="matte", cell=None, category="Vegetation"):
    sx, sy, sz = scale
    vertices = [
        (0, 0, sz), (sx, 0, 0), (0, sy, 0), (-sx, 0, 0), (0, -sy, 0), (0, 0, -sz)
    ]
    faces = [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 1), (5, 2, 1), (5, 3, 2), (5, 4, 3), (5, 1, 4)]
    obj = make_mesh_object(name, vertices, faces, collection, material_key, cell, category)
    obj.location = location
    return obj


def beam_between(name, start, end, radius, collection, material_key="metal", cell=None, vertices_count=8, category="Shared"):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    obj = cylinder(name, start, radius, direction.length, collection, material_key, cell, vertices_count, category=category)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def dish(name, location, radius, depth, collection, rotation=(0.0, 0.0, 0.0)):
    segments = 12
    rings = 3
    vertices = [(0.0, 0.0, 0.0)]
    for ring in range(1, rings + 1):
        r = radius * ring / rings
        z = depth * (r / radius) ** 2
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((math.cos(angle) * r, math.sin(angle) * r, z))
    faces = []
    for index in range(segments):
        faces.append((0, 1 + index, 1 + (index + 1) % segments))
    for ring in range(1, rings):
        lower = 1 + (ring - 1) * segments
        upper = 1 + ring * segments
        for index in range(segments):
            nxt = (index + 1) % segments
            faces.append((lower + index, upper + index, upper + nxt, lower + nxt))
    obj = make_mesh_object(name, vertices, faces, collection, "metal", CELLS["concrete_light"], "Props/Communication")
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def add_light(name, light_type, location, color, energy, collection, size=5.0):
    data = bpy.data.lights.new(name + "_Data", light_type)
    data.color = color
    data.energy = energy
    if hasattr(data, "shape"):
        data.shape = "DISK"
    if hasattr(data, "size"):
        data.size = size
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    LIGHT_OBJECTS.append(obj)
    return obj


def add_camera(name, location, target, ortho_scale, collection):
    data = bpy.data.cameras.new(name + "_Data")
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    data.lens = 52
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    return obj


def animate_rotation(obj, axis, values, frames, cycles=False):
    obj.rotation_mode = "XYZ"
    for value, frame in zip(values, frames):
        obj.rotation_euler[axis] = value
        obj.keyframe_insert(data_path="rotation_euler", index=axis, frame=frame)
    if obj.animation_data and obj.animation_data.action:
        for fcurve in obj.animation_data.action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = "LINEAR"
            if cycles:
                fcurve.modifiers.new("CYCLES")


def build_ground():
    ground = COLLECTIONS["输出_Environment_Ground"]
    collision = COLLECTIONS["碰撞_Ground"]
    random.seed(7103)
    tile_counts = {}
    for gx in range(10):
        for gy in range(10):
            x = -22.5 + gx * 5.0
            y = -22.5 + gy * 5.0
            if gx in (0, 9) or gy in (0, 9):
                tile_type = "边缘护栏地砖"
            elif 3 <= gx <= 6 and 3 <= gy <= 6:
                tile_type = "棚屋基础地砖"
            elif gx <= 2 and gy >= 4:
                tile_type = "种植区地砖"
            elif gx >= 7 and gy <= 5:
                tile_type = "设备安装地砖"
            elif gx <= 2 and gy <= 2:
                tile_type = "屋顶入口地砖"
            elif (gx + gy) % 13 == 0:
                tile_type = "排水口地砖"
            elif (gx * 3 + gy) % 11 == 0:
                tile_type = "管线接口地砖"
            elif (gx + gy * 2) % 9 == 0:
                tile_type = "积水地砖"
            elif (gx * 5 + gy) % 8 == 0:
                tile_type = "青苔地砖"
            elif (gx + gy) % 7 == 0:
                tile_type = "严重破损地砖"
            elif (gx * 2 + gy) % 5 == 0:
                tile_type = "裂缝地砖"
            else:
                tile_type = "完整水泥地砖"
            tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1
            shade = "concrete" if (gx + gy) % 3 else "concrete_dark"
            tile = box(
                f"地砖_G{gx:02d}_{gy:02d}_{tile_type}", (x, y, -0.25), (5.0, 5.0, 0.25), ground,
                "matte", CELLS[shade], category="Environment/Ground"
            )
            tile["module_size_m"] = [5.0, 5.0, 0.25]
            tile["grid_coordinate"] = [gx, gy]
            tile["module_type"] = tile_type
            OUTPUT_OBJECTS.append(tile)
            col = box(
                f"COL_地砖_G{gx:02d}_{gy:02d}", (x, y, -0.30), (5.0, 5.0, 0.30), collision,
                "matte", CELLS["concrete_dark"], category="Collision/Ground"
            )
            col.display_type = "WIRE"
            col["collision_shape"] = "box"
            COLLISION_OBJECTS.append(col)

            detail_z = 0.01
            if tile_type in ("裂缝地砖", "严重破损地砖"):
                for part in range(2 if tile_type == "裂缝地砖" else 4):
                    crack = box(
                        f"裂缝_{gx}_{gy}_{part}",
                        (x + random.uniform(-1.5, 1.5), y + random.uniform(-1.4, 1.4), detail_z),
                        (random.uniform(0.5, 1.5), 0.06, 0.025), ground, "matte", CELLS["concrete_dark"],
                        rotation=(0, 0, random.uniform(-1.2, 1.2)), category="Environment/Ground"
                    )
                    OUTPUT_OBJECTS.append(crack)
            elif tile_type == "积水地砖":
                puddle = cylinder(f"浅积水_{gx}_{gy}", (x + 0.4, y - 0.3, detail_z), 1.15, 0.018, ground, "gloss", CELLS["water"], 10, category="Environment/Ground")
                puddle.scale.y = 0.55
                OUTPUT_OBJECTS.append(puddle)
            elif tile_type == "青苔地砖":
                moss = cylinder(f"青苔斑_{gx}_{gy}", (x - 0.5, y + 0.5, detail_z), 1.0, 0.025, ground, "matte", CELLS["moss"], 9, category="Vegetation")
                moss.scale.y = 0.45
                OUTPUT_OBJECTS.append(moss)
            elif tile_type == "排水口地砖":
                drain = box(f"排水篦子_{gx}_{gy}", (x, y, detail_z), (1.3, 1.3, 0.08), ground, "metal", CELLS["concrete_dark"], category="Environment/Ground")
                OUTPUT_OBJECTS.append(drain)
                for slot in range(-2, 3):
                    bar = box(f"排水槽条_{gx}_{gy}_{slot}", (x + slot * 0.22, y, 0.095), (0.07, 1.0, 0.03), ground, "metal", CELLS["black"], category="Environment/Ground")
                    OUTPUT_OBJECTS.append(bar)
            elif tile_type == "管线接口地砖":
                port = cylinder(f"管线接口_{gx}_{gy}", (x, y, detail_z), 0.42, 0.18, ground, "metal", CELLS["rust"], 10, category="Environment/Ground")
                OUTPUT_OBJECTS.append(port)
    return tile_counts


def build_rooftop_shell():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    collision = COLLECTIONS["碰撞_Architecture"]
    building = box("屋顶建筑主体", (0, 0, -8.25), (50, 50, 8.0), architecture, "matte", CELLS["concrete_dark"], category="Environment/Architecture")
    building["actual_building_volume"] = True
    OUTPUT_OBJECTS.append(building)

    parapets = [
        ("北侧", (0, 24.65, 0), (50, 0.7, 1.0)),
        ("南侧", (0, -24.65, 0), (50, 0.7, 1.0)),
        ("西侧", (-24.65, 0, 0), (0.7, 50, 1.0)),
        ("东侧", (24.65, 0, 0), (0.7, 50, 1.0)),
    ]
    for side, loc, size in parapets:
        wall = box(f"边缘矮墙_{side}", loc, size, architecture, "matte", CELLS["concrete"], category="Environment/Architecture")
        OUTPUT_OBJECTS.append(wall)
        col = box(f"COL_边缘矮墙_{side}", loc, size, collision, "matte", CELLS["concrete_dark"], category="Collision/Architecture")
        col.display_type = "WIRE"
        COLLISION_OBJECTS.append(col)

    for side in (-1, 1):
        y = side * 23.9
        for x in range(-22, 23, 4):
            post = cylinder(f"护栏柱_NS_{side}_{x}", (x, y, 1.0), 0.07, 1.15, architecture, "metal", CELLS["rust_dark"], 8, category="Environment/Architecture")
            OUTPUT_OBJECTS.append(post)
        for z in (1.45, 2.05):
            rail = box(f"护栏横杆_NS_{side}_{z}", (0, y, z), (45, 0.10, 0.10), architecture, "metal", CELLS["rust_dark"], category="Environment/Architecture")
            OUTPUT_OBJECTS.append(rail)
    for side in (-1, 1):
        x = side * 23.9
        for y in range(-22, 23, 4):
            post = cylinder(f"护栏柱_EW_{side}_{y}", (x, y, 1.0), 0.07, 1.15, architecture, "metal", CELLS["rust_dark"], 8, category="Environment/Architecture")
            OUTPUT_OBJECTS.append(post)
        for z in (1.45, 2.05):
            rail = box(f"护栏横杆_EW_{side}_{z}", (x, 0, z), (0.10, 45, 0.10), architecture, "metal", CELLS["rust_dark"], category="Environment/Architecture")
            OUTPUT_OBJECTS.append(rail)

    for index, x in enumerate(range(-20, 21, 5)):
        bag = box(f"北侧沙袋_{index}", (x, 23.0, 0.05), (2.1, 0.75, 0.45), architecture, "matte", CELLS["canvas"], rotation=(0, 0, 0.12 * (index % 2)), category="Environment/Architecture", bevel=0.12)
        OUTPUT_OBJECTS.append(bag)


def build_shelter():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    furniture = COLLECTIONS["输出_Props_Furniture"]
    survival = COLLECTIONS["输出_Props_Survival"]
    lighting = COLLECTIONS["输出_Lighting"]
    vfx = COLLECTIONS["输出_VFX"]

    x0, x1, y0, y1 = -8.5, 6.5, -6.0, 8.0
    for index, (x, y) in enumerate(((x0, y0), (x1, y0), (x0, y1), (x1, y1), (-1, y0), (-1, y1))):
        post = cylinder(f"生活棚立柱_{index}", (x, y, 0.0), 0.11, 4.5 + (0.15 if y == y1 else 0), architecture, "metal", CELLS["purple"], 8, category="Environment/Architecture")
        OUTPUT_OBJECTS.append(post)
    for index, (a, b) in enumerate((((x0, y0, 4.5), (x1, y0, 4.5)), ((x0, y1, 4.65), (x1, y1, 4.65)), ((x0, y0, 4.5), (x0, y1, 4.65)), ((x1, y0, 4.5), (x1, y1, 4.65)), ((-1, y0, 4.5), (-1, y1, 4.65)))):
        beam = beam_between(f"生活棚横梁_{index}", a, b, 0.09, architecture, "metal", CELLS["purple"], 8, "Environment/Architecture")
        OUTPUT_OBJECTS.append(beam)

    roof_specs = [
        ("铁皮蓝", (-6.0, 3.25, 4.56), (5.4, 9.9, 0.12), "matte", "blue", -0.012),
        ("铁皮锈", (-1.1, 3.25, 4.61), (4.7, 9.7, 0.12), "metal", "rust", -0.010),
        ("透明板", (2.6, 3.25, 4.66), (3.1, 9.5, 0.10), "gloss", "glass", -0.010),
        ("防水帆布", (5.1, 3.25, 4.70), (2.2, 10.0, 0.08), "matte", "green", -0.012),
    ]
    for name, loc, size, role, cell, tilt in roof_specs:
        panel = box(f"棚顶_{name}", loc, size, architecture, role, CELLS[cell], rotation=(tilt, 0, 0), category="Environment/Architecture")
        OUTPUT_OBJECTS.append(panel)
        if "帆布" in name:
            animate_rotation(panel, 0, [tilt - 0.008, tilt + 0.010, tilt - 0.008], [1, 60, 120], True)
            panel["vfx"] = "subtle_wind"

    for index, loc in enumerate(((-8.35, 2.5, 0.0), (-8.35, 6.1, 0.0), (6.35, 5.9, 0.0))):
        panel = box(f"拼装墙板_{index}", loc, (0.16, 3.0, 3.2), architecture, "matte", CELLS["blue" if index == 0 else "rust"], rotation=(0, 0, 0.03 * index), category="Environment/Architecture")
        OUTPUT_OBJECTS.append(panel)
    back_panel = box("旧广告牌背墙", (-1.0, 7.85, 0.0), (12.0, 0.18, 3.4), architecture, "matte", CELLS["blue_dark"], category="Environment/Architecture")
    OUTPUT_OBJECTS.append(back_panel)

    for index, x in enumerate((-6.2, -2.0, 2.3, 5.3)):
        weight = box(f"棚顶压砖_{index}", (x, 6.8, 4.69), (0.8, 0.45, 0.28), architecture, "matte", CELLS["rust_dark"], rotation=(0, 0, 0.12 * (-1) ** index), category="Environment/Architecture")
        OUTPUT_OBJECTS.append(weight)
    for index, x in enumerate((-7.5, 5.5)):
        rope = beam_between(f"棚顶加固绳_{index}", (x, -5.4, 0.2), (x + 0.4 * (-1) ** index, 7.4, 4.7), 0.025, architecture, "matte", CELLS["canvas"], 6, "Environment/Architecture")
        OUTPUT_OBJECTS.append(rope)

    # Sofa and rest corner.
    sofa_parts = [
        ("沙发底座", (-5.4, 4.3, 0.0), (4.0, 1.55, 0.55), "blue"),
        ("沙发坐垫左", (-6.35, 3.95, 0.55), (1.75, 1.25, 0.32), "blue"),
        ("沙发坐垫右", (-4.45, 3.95, 0.55), (1.75, 1.25, 0.32), "blue_dark"),
        ("沙发靠背", (-5.4, 4.95, 0.45), (4.0, 0.35, 1.55), "blue_dark"),
        ("沙发扶手左", (-7.55, 4.25, 0.25), (0.38, 1.65, 0.9), "blue"),
        ("沙发扶手右", (-3.25, 4.25, 0.25), (0.38, 1.65, 0.9), "blue"),
    ]
    for name, loc, size, cell in sofa_parts:
        obj = box(name, loc, size, furniture, "matte", CELLS[cell], category="Props/Furniture", bevel=0.10)
        OUTPUT_OBJECTS.append(obj)

    spool = cylinder("电缆卷筒圆桌", (-1.6, 3.4, 0.0), 1.05, 0.78, furniture, "matte", CELLS["wood"], 12, category="Props/Furniture")
    OUTPUT_OBJECTS.append(spool)
    spool_top = cylinder("电缆卷筒桌面", (-1.6, 3.4, 0.78), 1.35, 0.16, furniture, "matte", CELLS["wood_dark"], 12, category="Props/Furniture")
    OUTPUT_OBJECTS.append(spool_top)
    radio = box("老式收音机", (-1.8, 3.35, 0.96), (1.0, 0.45, 0.58), survival, "matte", CELLS["green_dark"], category="Props/Survival", bevel=0.05)
    OUTPUT_OBJECTS.append(radio)
    dial = cylinder("收音机调谐盘", (-1.52, 3.10, 1.15), 0.12, 0.04, survival, "gloss", CELLS["paper"], 10, rotation=(math.pi / 2, 0, 0), category="Props/Survival")
    OUTPUT_OBJECTS.append(dial)
    needle = box("收音机信号表指针", (-1.78, 3.07, 1.25), (0.035, 0.04, 0.24), survival, "emissive", CELLS["warning"], rotation=(0, 0, -0.25), category="Props/Survival")
    needle.name += "_自发光"
    OUTPUT_OBJECTS.append(needle)
    animate_rotation(needle, 1, [-0.15, 0.18, -0.08, 0.12], [1, 28, 55, 90], True)

    for index, (loc, cell) in enumerate((((-0.9, 3.45, 0.96), "paper"), ((-1.2, 3.65, 0.97), "warning"), ((-2.4, 3.55, 0.96), "red"))):
        item = cylinder(f"桌面杯具工具_{index}", loc, 0.10 if index == 0 else 0.06, 0.24 if index == 0 else 0.35, survival, "metal", CELLS[cell], 8, category="Props/Survival")
        OUTPUT_OBJECTS.append(item)
    for index in range(3):
        paper = box(f"散开地图_{index}", (-1.4 + index * 0.35, 4.0 - index * 0.12, 0.955 + index * 0.003), (0.62, 0.45, 0.012), survival, "matte", CELLS["paper"], rotation=(0, 0, -0.18 + index * 0.16), category="Props/Survival")
        OUTPUT_OBJECTS.append(paper)

    # Workbench, bed, storage and wall story panels.
    worktop = box("木箱金属工作桌_桌面", (2.7, 4.8, 0.9), (4.6, 1.4, 0.22), furniture, "matte", CELLS["wood"], category="Props/Furniture", bevel=0.04)
    OUTPUT_OBJECTS.append(worktop)
    for index, x in enumerate((0.9, 4.5)):
        leg = box(f"工作桌支架_{index}", (x, 4.8, 0.0), (0.22, 1.2, 0.9), furniture, "metal", CELLS["purple"], category="Props/Furniture")
        OUTPUT_OBJECTS.append(leg)
    for index in range(4):
        crate = box(f"工作桌旧木箱_{index}", (1.2 + index * 0.85, 5.0, 0.0), (0.75, 1.0, 0.72), survival, "matte", CELLS["wood_dark" if index % 2 else "wood"], category="Props/Survival", bevel=0.04)
        OUTPUT_OBJECTS.append(crate)
    cot = box("简易床铺", (2.6, 0.4, 0.35), (5.2, 2.0, 0.28), furniture, "matte", CELLS["green_dark"], category="Props/Furniture", bevel=0.08)
    OUTPUT_OBJECTS.append(cot)
    sleeping = box("卷起睡袋", (3.8, 0.4, 0.70), (1.8, 0.72, 0.45), survival, "matte", CELLS["green"], rotation=(0, 0, 0.18), category="Props/Survival", bevel=0.16)
    OUTPUT_OBJECTS.append(sleeping)
    cabinet = box("收纳柜", (5.4, 6.2, 0.0), (1.5, 1.1, 2.7), furniture, "metal", CELLS["blue_dark"], category="Props/Furniture", bevel=0.04)
    OUTPUT_OBJECTS.append(cabinet)
    for index in range(3):
        shelf = box(f"工具架层板_{index}", (5.55, 2.2, 0.5 + index * 0.72), (1.4, 0.55, 0.10), furniture, "metal", CELLS["rust_dark"], category="Props/Furniture")
        OUTPUT_OBJECTS.append(shelf)
    for index in range(8):
        note = box(f"背墙故事便签_{index}", (-6.2 + (index % 4) * 1.2, 7.72, 1.2 + (index // 4) * 1.0), (0.75 + 0.18 * (index % 2), 0.025, 0.55), survival, "matte", CELLS["paper" if index % 3 else "warning"], rotation=(0, 0, 0.03 * (-1) ** index), category="Props/Survival")
        OUTPUT_OBJECTS.append(note)
        if index < 5:
            route = box(f"地图路线色条_{index}", (-6.35 + index * 0.9, 7.685, 1.55 + 0.1 * (index % 2)), (0.50, 0.018, 0.05), survival, "matte", CELLS["red" if index % 2 else "blue"], rotation=(0, 0, 0.4 - index * 0.12), category="Props/Survival")
            OUTPUT_OBJECTS.append(route)

    stove = cylinder("小型火炉", (-6.5, -1.9, 0.0), 0.68, 1.1, survival, "metal", CELLS["rust_dark"], 12, category="Props/Survival")
    OUTPUT_OBJECTS.append(stove)
    kettle = cylinder("烧水壶", (-6.5, -1.9, 1.12), 0.38, 0.45, survival, "metal", CELLS["concrete_light"], 10, category="Props/Survival")
    OUTPUT_OBJECTS.append(kettle)
    for index, loc in enumerate(((-4.6, -2.2, 0.0), (-3.7, -2.0, 0.0), (-5.2, -3.2, 0.0))):
        crate = box(f"休息角物资_{index}", loc, (0.8, 0.7, 0.65), survival, "matte", CELLS["wood" if index < 2 else "green"], rotation=(0, 0, 0.12 * index), category="Props/Survival", bevel=0.04)
        OUTPUT_OBJECTS.append(crate)

    for index, loc in enumerate(((-4.0, 1.2, 3.4), (2.0, 3.0, 3.6), (-5.8, -1.8, 2.8))):
        bulb = cylinder(f"暖色露营灯_{index}_自发光", loc, 0.16, 0.28, lighting, "emissive", CELLS["warning"], 10, category="Lighting")
        OUTPUT_OBJECTS.append(bulb)
        lamp = add_light(f"暖色灯光_{index}", "POINT", (loc[0], loc[1], loc[2] - 0.1), (1.0, 0.48, 0.18), 95, COLLECTIONS["展示_灯光镜头"], 2.0)
        lamp.data.shadow_soft_size = 2.4
        lamp.data.keyframe_insert(data_path="energy", frame=1)
        lamp.data.energy = 78 if index == 1 else 88
        lamp.data.keyframe_insert(data_path="energy", frame=54 + index * 17)
        lamp.data.energy = 95
        lamp.data.keyframe_insert(data_path="energy", frame=120)

    cloth = box("晾晒衣物_布片", (6.8, -2.5, 2.2), (0.05, 2.8, 1.4), vfx, "matte", CELLS["blue"], rotation=(0.04, 0, -0.08), category="VFX")
    OUTPUT_OBJECTS.append(cloth)
    animate_rotation(cloth, 0, [-0.04, 0.05, -0.04], [1, 55, 110], True)
    for index in range(4):
        line = beam_between(f"晾衣绳_{index}", (6.7, -4.2 + index * 0.04, 3.8), (6.7, 0.0 + index * 0.04, 3.8), 0.018, architecture, "matte", CELLS["canvas"], 6, "Environment/Architecture")
        OUTPUT_OBJECTS.append(line)


def build_farming():
    props = COLLECTIONS["输出_Props_Farming"]
    vegetation = COLLECTIONS["输出_Vegetation"]
    vfx = COLLECTIONS["输出_VFX"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    random.seed(2046)

    beds = [
        (-19.5, 2.0, 3.5, 2.2, "土豆"), (-14.8, 2.0, 3.5, 2.2, "卷心菜"),
        (-19.5, 6.2, 3.5, 2.2, "番茄"), (-14.8, 6.2, 3.5, 2.2, "香草"),
        (-19.5, 10.3, 3.5, 2.2, "玉米"), (-14.8, 10.3, 3.5, 2.2, "攀爬植物"),
    ]
    for bed_index, (x, y, sx, sy, crop) in enumerate(beds):
        container = box(f"种植箱_{bed_index}_{crop}", (x, y, 0.0), (sx, sy, 0.65), props, "matte", CELLS["wood" if bed_index % 2 else "rust"], category="Props/Farming", bevel=0.05)
        soil = box(f"种植土_{bed_index}", (x, y, 0.62), (sx - 0.25, sy - 0.25, 0.12), props, "matte", CELLS["wood_dark"], category="Props/Farming")
        OUTPUT_OBJECTS.extend((container, soil))
        rows = 3 if crop in ("香草", "卷心菜") else 2
        for ix in range(rows):
            for iy in range(3):
                px = x + (ix - (rows - 1) / 2) * (sx - 0.8) / max(1, rows - 1)
                py = y + (iy - 1) * 0.52
                height = 0.45
                if crop == "玉米":
                    height = 1.9 + 0.25 * ((ix + iy) % 2)
                stem = cylinder(f"{crop}_茎_{bed_index}_{ix}_{iy}", (px, py, 0.74), 0.035 if crop != "玉米" else 0.06, height, vegetation, "matte", CELLS["green_dark"], 6, category="Vegetation")
                OUTPUT_OBJECTS.append(stem)
                leaf_count = 3 if crop != "香草" else 2
                for leaf_index in range(leaf_count):
                    leaf = low_sphere(
                        f"{crop}_叶_{bed_index}_{ix}_{iy}_{leaf_index}",
                        (px + 0.12 * math.cos(leaf_index * 2.1), py + 0.12 * math.sin(leaf_index * 2.1), 0.95 + min(height - 0.2, leaf_index * height / leaf_count)),
                        (0.28 if crop != "玉米" else 0.38, 0.14, 0.08), vegetation, "matte",
                        CELLS["moss" if (bed_index + leaf_index) % 5 else "warning"], "Vegetation"
                    )
                    leaf.rotation_euler.z = leaf_index * 1.4
                    OUTPUT_OBJECTS.append(leaf)
                    if bed_index in (2, 4) and ix == 0 and iy == 1 and leaf_index == 0:
                        animate_rotation(leaf, 1, [-0.06, 0.08, -0.06], [1, 45, 90], True)
                if crop == "番茄" and iy != 0:
                    fruit = low_sphere(f"番茄果实_{bed_index}_{ix}_{iy}", (px + 0.15, py, 1.22), (0.14, 0.14, 0.14), vegetation, "gloss", CELLS["red"], "Vegetation")
                    OUTPUT_OBJECTS.append(fruit)

    tub = box("废弃浴缸种植池", (-18.0, 15.0, 0.0), (5.0, 2.2, 0.85), props, "gloss", CELLS["concrete_light"], category="Props/Farming", bevel=0.12)
    tub_soil = box("浴缸种植土", (-18.0, 15.0, 0.78), (4.5, 1.7, 0.16), props, "matte", CELLS["wood_dark"], category="Props/Farming")
    OUTPUT_OBJECTS.extend((tub, tub_soil))
    for index in range(8):
        cabbage = low_sphere(f"浴缸卷心菜_{index}", (-19.7 + (index % 4) * 1.12, 14.55 + (index // 4) * 0.9, 1.12), (0.44, 0.44, 0.34), vegetation, "matte", CELLS["green" if index != 6 else "warning"], "Vegetation")
        OUTPUT_OBJECTS.append(cabbage)

    # Greenhouse frame and film.
    for index, x in enumerate((-20.8, -16.8, -12.8)):
        for y in (18.5, 22.0):
            post = cylinder(f"温室立柱_{index}_{y}", (x, y, 0.0), 0.06, 3.0, architecture, "metal", CELLS["concrete_light"], 8, category="Environment/Architecture")
            OUTPUT_OBJECTS.append(post)
    for index, y in enumerate((18.5, 22.0)):
        ridge = beam_between(f"温室拱架_{index}", (-20.8, y, 3.0), (-12.8, y, 3.0), 0.05, architecture, "metal", CELLS["concrete_light"], 8, "Environment/Architecture")
        OUTPUT_OBJECTS.append(ridge)
    greenhouse_roof = box("温室塑料薄膜_顶部", (-16.8, 20.25, 3.0), (8.2, 3.7, 0.045), vfx, "gloss", CELLS["glass"], rotation=(0.025, 0, 0), category="VFX")
    OUTPUT_OBJECTS.append(greenhouse_roof)
    animate_rotation(greenhouse_roof, 0, [0.018, 0.034, 0.018], [1, 65, 130], True)

    barrel = cylinder("种植区储水桶", (-11.3, 15.0, 0.0), 1.05, 2.4, props, "matte", CELLS["blue"], 12, category="Props/Farming")
    OUTPUT_OBJECTS.append(barrel)
    compost = box("小型堆肥箱", (-11.5, 11.2, 0.0), (2.2, 1.8, 1.4), props, "matte", CELLS["wood_dark"], category="Props/Farming", bevel=0.04)
    OUTPUT_OBJECTS.append(compost)
    for index in range(5):
        bottle = cylinder(f"滴灌塑料瓶_{index}", (-21.0 + index * 2.05, 8.6, 0.35), 0.16, 0.55, props, "gloss", CELLS["glass"], 8, category="Props/Farming")
        OUTPUT_OBJECTS.append(bottle)
        hose = beam_between(f"滴灌软管_{index}", (-21.0 + index * 2.05, 8.6, 0.45), (-21.0 + index * 2.05, 6.9, 0.75), 0.025, props, "matte", CELLS["black"], 6, "Props/Farming")
        OUTPUT_OBJECTS.append(hose)
    for index, loc in enumerate(((-12.1, 14.2, 0.0), (-11.2, 13.4, 0.0), (-12.0, 12.6, 0.0))):
        tool = beam_between(f"园艺工具_{index}", loc, (loc[0] + 0.3, loc[1], 1.35), 0.045, props, "metal", CELLS["rust"], 8, "Props/Farming")
        OUTPUT_OBJECTS.append(tool)


def build_energy_water():
    energy = COLLECTIONS["输出_Props_Energy"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    vfx = COLLECTIONS["输出_VFX"]

    for row in range(2):
        for col in range(3):
            x = 13.0 + col * 4.0
            y = -14.0 + row * 4.8
            frame = box(f"太阳能板框_{row}_{col}", (x, y, 0.8), (3.3, 2.2, 0.12), energy, "metal", CELLS["purple"], rotation=(0.32 + col * 0.025, 0, 0.05 * (col - 1)), category="Props/Energy")
            surface = box(f"太阳能板面_{row}_{col}", (x, y - 0.03, 0.93), (3.05, 2.0, 0.055), energy, "gloss", CELLS["blue_dark" if (row + col) % 4 else "concrete_dark"], rotation=(0.32 + col * 0.025, 0, 0.05 * (col - 1)), category="Props/Energy")
            OUTPUT_OBJECTS.extend((frame, surface))
            for line in (-0.75, 0, 0.75):
                strip = box(f"太阳能板分隔线_{row}_{col}_{line}", (x + line, y - 0.05, 0.995), (0.035, 1.85, 0.025), energy, "metal", CELLS["concrete_light"], rotation=(0.32 + col * 0.025, 0, 0.05 * (col - 1)), category="Props/Energy")
                OUTPUT_OBJECTS.append(strip)

    for index, loc in enumerate(((13.0, -3.5, 0.0), (16.2, -3.5, 0.0), (19.4, -3.5, 0.0))):
        battery = box(f"蓄电池柜_{index}", loc, (2.3, 1.6, 2.1), energy, "metal", CELLS["green_dark"], category="Props/Energy", bevel=0.05)
        OUTPUT_OBJECTS.append(battery)
        led = box(f"蓄电池状态灯_{index}_自发光", (loc[0] + 0.65, loc[1] - 0.82, 1.55), (0.18, 0.04, 0.12), energy, "emissive", CELLS["green" if index != 1 else "warning"], category="Props/Energy")
        OUTPUT_OBJECTS.append(led)
    generator = box("柴油发电机主体", (20.0, 1.4, 0.0), (5.0, 2.5, 2.2), energy, "metal", CELLS["rust"], category="Props/Energy", bevel=0.10)
    OUTPUT_OBJECTS.append(generator)
    for index in range(3):
        vent = box(f"发电机散热槽_{index}", (18.7 + index * 1.1, 0.12, 0.72), (0.65, 0.05, 0.5), energy, "matte", CELLS["black"], category="Props/Energy")
        OUTPUT_OBJECTS.append(vent)

    # Water collection and repair logic.
    tanks = ((13.2, 5.0, 1.25), (17.4, 5.0, 1.25), (21.2, 5.3, 1.0))
    for index, (x, y, radius) in enumerate(tanks):
        tank = cylinder(f"雨水储水罐_{index}", (x, y, 0.0), radius, 3.1 if index < 2 else 2.6, energy, "metal" if index == 2 else "matte", CELLS["blue" if index < 2 else "concrete_light"], 12, category="Props/Energy")
        OUTPUT_OBJECTS.append(tank)
    pipe_pairs = ((tanks[0], tanks[1]), (tanks[1], tanks[2]))
    for index, (a, b) in enumerate(pipe_pairs):
        pipe = beam_between(f"水箱连接软管_{index}", (a[0] + 0.4, a[1], 0.8), (b[0] - 0.4, b[1], 0.8), 0.075, energy, "matte", CELLS["black"], 8, "Props/Energy")
        OUTPUT_OBJECTS.append(pipe)
        tape = cylinder(f"水管修补胶带_{index}", ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.72), 0.12, 0.28, energy, "matte", CELLS["canvas"], 8, rotation=(0, math.pi / 2, 0), category="Props/Energy")
        OUTPUT_OBJECTS.append(tape)
    drain_pipe = beam_between("屋顶排水主管", (24.0, 16.5, 2.0), (21.2, 5.3, 2.2), 0.14, energy, "metal", CELLS["rust_dark"], 10, "Props/Energy")
    OUTPUT_OBJECTS.append(drain_pipe)

    # Wind turbine, pivot at the real rotor center.
    mast = cylinder("小型风机塔杆", (20.0, 12.0, 0.0), 0.16, 8.0, energy, "metal", CELLS["concrete_light"], 10, category="Props/Energy")
    OUTPUT_OBJECTS.append(mast)
    nacelle = box("小型风机机舱", (20.0, 12.0, 7.75), (1.5, 0.75, 0.65), energy, "metal", CELLS["concrete_light"], category="Props/Energy", bevel=0.08)
    OUTPUT_OBJECTS.append(nacelle)
    rotor = bpy.data.objects.new("小型风机旋转中心", None)
    energy.objects.link(rotor)
    rotor.location = (20.0, 11.58, 8.05)
    for index in range(3):
        blade = box(f"风机叶片_{index}", (0, 0, 0), (0.26, 0.12, 2.6), energy, "matte", CELLS["paper"], rotation=(0, index * math.tau / 3, 0), category="Props/Energy")
        blade.location = (0, 0, 0)
        blade.parent = rotor
        blade.location = (0, 0, 0)
        OUTPUT_OBJECTS.append(blade)
    hub = cylinder("风机轮毂", (0, 0, -0.15), 0.32, 0.45, energy, "metal", CELLS["rust"], 10, rotation=(math.pi / 2, 0, 0), category="Props/Energy")
    hub.parent = rotor
    hub.location = (0, 0, 0)
    OUTPUT_OBJECTS.append(hub)
    animate_rotation(rotor, 1, [0.0, math.tau], [1, 180], True)

    for index, (start, end) in enumerate((((10.5, -2.0, 0.08), (18.0, -3.5, 0.08)), ((9.0, 1.0, 0.10), (13.0, 5.0, 0.10)), ((7.0, -7.0, 0.12), (13.0, -8.5, 0.12)))):
        cable = beam_between(f"地面电缆水管_{index}", start, end, 0.045 + index * 0.012, energy, "matte", CELLS["black" if index != 1 else "blue_dark"], 8, "Props/Energy")
        OUTPUT_OBJECTS.append(cable)
    power_box = box("临时配电箱", (10.0, 1.8, 0.0), (2.0, 0.8, 2.3), energy, "metal", CELLS["green_dark"], category="Props/Energy", bevel=0.04)
    OUTPUT_OBJECTS.append(power_box)


def build_communication():
    comm = COLLECTIONS["输出_Props_Communication"]
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    lighting = COLLECTIONS["输出_Lighting"]

    platform = box("广播通讯加高平台", (7.5, 15.5, 0.0), (8.5, 7.5, 1.2), architecture, "metal", CELLS["purple"], category="Environment/Architecture")
    OUTPUT_OBJECTS.append(platform)
    for ix in (-3.5, 3.5):
        for iy in (-3.0, 3.0):
            leg = box(f"广播平台支腿_{ix}_{iy}", (7.5 + ix, 15.5 + iy, 0.0), (0.25, 0.25, 1.2), architecture, "metal", CELLS["purple"], category="Environment/Architecture")
            OUTPUT_OBJECTS.append(leg)
    booth = box("广播台半开放机柜", (7.0, 16.0, 1.2), (5.4, 3.2, 2.8), comm, "matte", CELLS["blue_dark"], category="Props/Communication", bevel=0.06)
    OUTPUT_OBJECTS.append(booth)
    desk = box("广播控制桌", (7.1, 13.7, 1.2), (5.2, 1.4, 1.15), comm, "matte", CELLS["wood"], category="Props/Communication", bevel=0.04)
    OUTPUT_OBJECTS.append(desk)
    for index in range(4):
        radio = box(f"无线电收发机_{index}", (5.25 + index * 1.25, 13.2, 2.4 + (index % 2) * 0.15), (1.05, 0.55, 0.65), comm, "metal", CELLS["green_dark" if index % 2 else "rust_dark"], category="Props/Communication", bevel=0.035)
        OUTPUT_OBJECTS.append(radio)
        for led_index in range(2):
            led = box(f"无线电指示灯_{index}_{led_index}_自发光", (4.95 + index * 1.25 + led_index * 0.24, 12.91, 2.74 + (index % 2) * 0.15), (0.10, 0.04, 0.09), comm, "emissive", CELLS["warning" if led_index else "green"], category="Props/Communication")
            OUTPUT_OBJECTS.append(led)
    mic = cylinder("广播麦克风", (9.4, 13.4, 2.45), 0.10, 0.65, comm, "metal", CELLS["concrete_light"], 10, rotation=(0.15, 0, 0), category="Props/Communication")
    OUTPUT_OBJECTS.append(mic)
    headphone = cylinder("监听耳机", (4.7, 13.2, 2.42), 0.35, 0.10, comm, "matte", CELLS["black"], 12, category="Props/Communication")
    OUTPUT_OBJECTS.append(headphone)
    for index in range(5):
        chart = box(f"频率联络记录板_{index}", (5.0 + index * 0.85, 14.35, 3.25), (0.62, 0.04, 0.82), comm, "matte", CELLS["paper" if index % 2 else "warning"], rotation=(0, 0, 0.035 * (-1) ** index), category="Props/Communication")
        OUTPUT_OBJECTS.append(chart)

    tower_origin = (10.2, 18.0, 1.2)
    mast = cylinder("通信主桅杆", tower_origin, 0.16, 13.2, comm, "metal", CELLS["concrete_light"], 10, category="Props/Communication")
    OUTPUT_OBJECTS.append(mast)
    for z in (4.0, 7.2, 10.3):
        for angle in (0.0, math.tau / 3, math.tau * 2 / 3):
            anchor = (tower_origin[0] + math.cos(angle) * 5.2, tower_origin[1] + math.sin(angle) * 5.2, 0.25)
            cable = beam_between(f"通信塔拉线_{z}_{angle:.2f}", (tower_origin[0], tower_origin[1], z + 1.2), anchor, 0.018, comm, "metal", CELLS["concrete_dark"], 6, "Props/Communication")
            OUTPUT_OBJECTS.append(cable)

    antenna_pivot = bpy.data.objects.new("大型定向天线旋转中心", None)
    comm.objects.link(antenna_pivot)
    antenna_pivot.location = (10.2, 18.0, 10.2)
    yagi_beam = box("八木天线主梁", (0, 0, 0), (6.0, 0.10, 0.10), comm, "metal", CELLS["concrete_light"], category="Props/Communication")
    yagi_beam.parent = antenna_pivot
    yagi_beam.location = (0, 0, 0)
    OUTPUT_OBJECTS.append(yagi_beam)
    for index in range(9):
        cross = box(f"八木天线振子_{index}", (-2.6 + index * 0.65, 0, 0), (0.07, 1.9 - abs(4 - index) * 0.08, 0.07), comm, "metal", CELLS["concrete_light"], category="Props/Communication")
        cross.parent = antenna_pivot
        OUTPUT_OBJECTS.append(cross)
    animate_rotation(antenna_pivot, 2, [-0.28, 0.30, -0.28], [1, 180, 360], True)

    sat = dish("卫星接收锅", (5.0, 19.4, 5.6), 1.75, 0.55, comm, rotation=(0.95, 0.18, -0.65))
    OUTPUT_OBJECTS.append(sat)
    sat_pole = cylinder("卫星锅支撑杆", (5.0, 19.4, 1.2), 0.12, 4.7, comm, "metal", CELLS["rust_dark"], 10, category="Props/Communication")
    OUTPUT_OBJECTS.append(sat_pole)
    for index, x in enumerate((3.8, 6.2, 8.0)):
        whip = cylinder(f"无线电鞭状天线_{index}", (x, 18.8 + index * 0.4, 4.0), 0.035, 4.0 + index * 0.7, comm, "metal", CELLS["concrete_light"], 8, category="Props/Communication")
        OUTPUT_OBJECTS.append(whip)

    beacon = cylinder("天线红色信号灯_自发光", (10.2, 18.0, 14.45), 0.18, 0.32, lighting, "emissive", CELLS["red"], 10, category="Lighting")
    OUTPUT_OBJECTS.append(beacon)
    beacon_light = add_light("天线红色闪烁灯光", "POINT", (10.2, 18.0, 14.7), (1.0, 0.03, 0.02), 0, COLLECTIONS["展示_灯光镜头"], 1.0)
    for frame, energy in ((1, 0), (25, 120), (42, 0), (95, 0), (120, 120), (138, 0)):
        beacon_light.data.energy = energy
        beacon_light.data.keyframe_insert(data_path="energy", frame=frame)

    for index, end in enumerate(((13.0, 5.0, 1.0), (16.2, -3.5, 0.8), (20.0, 1.4, 0.8))):
        cable = beam_between(f"广播设备供电电缆_{index}", (7.5, 15.5, 1.1), end, 0.045, comm, "matte", CELLS["black"], 8, "Props/Communication")
        OUTPUT_OBJECTS.append(cable)


def build_entry_defense_and_clutter():
    architecture = COLLECTIONS["输出_Environment_Architecture"]
    survival = COLLECTIONS["输出_Props_Survival"]
    furniture = COLLECTIONS["输出_Props_Furniture"]
    lighting = COLLECTIONS["输出_Lighting"]
    vfx = COLLECTIONS["输出_VFX"]
    collision = COLLECTIONS["碰撞_Architecture"]
    random.seed(981)

    stairwell = box("楼梯间出口主体", (-17.5, -16.5, 0.0), (8.0, 7.0, 5.2), architecture, "matte", CELLS["concrete"], category="Environment/Architecture", bevel=0.06)
    stairwell["logical_wall_height_m"] = 9.0
    stairwell["visual_height_m"] = 5.2
    OUTPUT_OBJECTS.append(stairwell)
    roof = box("楼梯间铁皮顶", (-17.5, -16.5, 5.2), (8.4, 7.4, 0.22), architecture, "metal", CELLS["rust"], rotation=(0.03, 0, 0), category="Environment/Architecture")
    OUTPUT_OBJECTS.append(roof)
    for index, x in enumerate((-18.7, -16.3)):
        door = box(f"楼梯间双层防护门_{index}", (x, -20.03, 0.1), (2.15, 0.18, 3.35), architecture, "metal", CELLS["blue_dark" if index == 0 else "rust_dark"], category="Environment/Architecture", bevel=0.035)
        door["pivot_contract"] = "hinge_outer_edge"
        OUTPUT_OBJECTS.append(door)
    bar = box("防护门横向门闩", (-17.5, -20.18, 1.75), (4.8, 0.16, 0.18), architecture, "metal", CELLS["concrete_light"], category="Environment/Architecture")
    OUTPUT_OBJECTS.append(bar)
    bell = cylinder("入口警报铃", (-14.3, -20.15, 3.5), 0.28, 0.35, survival, "metal", CELLS["warning"], 10, rotation=(math.pi / 2, 0, 0), category="Props/Survival")
    OUTPUT_OBJECTS.append(bell)
    entrance_light = cylinder("入口简易照明_自发光", (-17.5, -20.2, 4.1), 0.18, 0.30, lighting, "emissive", CELLS["warning"], 10, rotation=(math.pi / 2, 0, 0), category="Lighting")
    OUTPUT_OBJECTS.append(entrance_light)
    add_light("入口暖色灯光", "POINT", (-17.5, -20.6, 3.8), (1.0, 0.42, 0.14), 110, COLLECTIONS["展示_灯光镜头"], 2.5)

    lookout = box("低矮瞭望台", (16.5, -20.0, 0.0), (6.0, 5.0, 1.0), architecture, "metal", CELLS["wood_dark"], category="Environment/Architecture")
    OUTPUT_OBJECTS.append(lookout)
    telescope = cylinder("瞭望望远镜", (16.5, -20.0, 2.1), 0.26, 1.8, survival, "metal", CELLS["concrete_light"], 10, rotation=(0.2, 1.15, 0.1), category="Props/Survival")
    OUTPUT_OBJECTS.append(telescope)
    tripod_points = ((15.8, -20.5, 1.0), (17.2, -20.5, 1.0), (16.5, -19.2, 1.0))
    for index, point in enumerate(tripod_points):
        leg = beam_between(f"望远镜三脚架_{index}", (16.5, -20.0, 2.25), point, 0.045, survival, "metal", CELLS["purple"], 8, "Props/Survival")
        OUTPUT_OBJECTS.append(leg)
    searchlight = cylinder("瞭望探照灯_外壳", (19.0, -19.5, 1.5), 0.45, 0.8, lighting, "metal", CELLS["concrete_light"], 10, rotation=(0.3, 1.1, 0), category="Lighting")
    OUTPUT_OBJECTS.append(searchlight)

    # Clear, intentional clutter lanes.
    clutter = [
        ("分类木箱", (-10.5, -16.0), (1.3, 1.0, 0.9), "wood"),
        ("塑料筐", (-8.8, -16.1), (1.1, 0.8, 0.65), "blue"),
        ("油桶", (-6.9, -16.0), (1.2, 1.2, 1.6), "rust"),
        ("工具箱", (-10.2, -13.8), (1.5, 0.65, 0.55), "green_dark"),
        ("备用铁皮", (-7.8, -13.8), (2.8, 0.25, 1.2), "blue_dark"),
        ("回收材料箱", (-4.8, -15.0), (2.0, 1.4, 1.0), "wood_dark"),
        ("折叠推车", (-3.0, -13.5), (1.2, 0.7, 1.4), "rust_dark"),
    ]
    for index, (label, (x, y), size, cell) in enumerate(clutter):
        if label == "油桶":
            obj = cylinder(f"{label}_{index}", (x, y, 0.0), 0.6, 1.6, survival, "metal", CELLS[cell], 12, category="Props/Survival")
        else:
            obj = box(f"{label}_{index}", (x, y, 0.0), size, survival, "matte" if cell != "rust_dark" else "metal", CELLS[cell], rotation=(0, 0, 0.04 * (-1) ** index), category="Props/Survival", bevel=0.04)
        OUTPUT_OBJECTS.append(obj)
    for index in range(4):
        tire = cylinder(f"备用轮胎_{index}", (-2.4 + index * 0.75, -17.5, 0.0), 0.55, 0.34, survival, "matte", CELLS["black"], 12, rotation=(math.pi / 2, 0, 0), category="Props/Survival")
        OUTPUT_OBJECTS.append(tire)
    tarp = box("防水布覆盖物资", (-6.5, -10.8, 0.9), (4.8, 3.1, 0.10), vfx, "matte", CELLS["green"], rotation=(0.04, -0.03, 0.08), category="VFX")
    OUTPUT_OBJECTS.append(tarp)
    for index, loc in enumerate(((-8.5, -12.0, 0.95), (-4.6, -9.8, 0.95), (-8.4, -9.7, 0.95), (-4.7, -12.0, 0.95))):
        brick = box(f"防水布压砖_{index}", loc, (0.55, 0.34, 0.22), survival, "matte", CELLS["rust_dark"], category="Props/Survival")
        OUTPUT_OBJECTS.append(brick)

    # Wooden walkways and warning strips keep the visual reading ordered.
    for index, (loc, size, rot) in enumerate((((0, -9.0, 0.02), (22, 1.2, 0.10), 0.0), ((-12.0, -1.0, 0.02), (1.2, 18, 0.10), 0.0), ((8.0, 9.5, 0.02), (1.2, 11, 0.10), -0.1))):
        walkway = box(f"木板便道_{index}", loc, size, architecture, "matte", CELLS["wood_dark"], rotation=(0, 0, rot), category="Environment/Architecture")
        OUTPUT_OBJECTS.append(walkway)
        for stripe in range(3):
            strip = box(f"便道黄色警戒线_{index}_{stripe}", (loc[0] + (stripe - 1) * 0.28, loc[1], loc[2] + 0.11), (0.06, size[1] * 0.86, 0.015) if size[1] > size[0] else (size[0] * 0.86, 0.06, 0.015), architecture, "matte", CELLS["warning"], rotation=(0, 0, rot), category="Environment/Architecture")
            OUTPUT_OBJECTS.append(strip)

    for index, loc in enumerate(((-23.6, -10, 2.4), (-23.6, 8, 2.8), (23.6, -4, 2.6), (0, 23.6, 2.5))):
        if abs(loc[0]) > 20:
            size = (0.04, 1.2, 0.55)
        else:
            size = (1.2, 0.04, 0.55)
        flag = box(f"边缘警示布条_{index}", loc, size, vfx, "matte", CELLS["red" if index % 2 else "warning"], rotation=(0.04, 0.0, 0.05 * (-1) ** index), category="VFX")
        OUTPUT_OBJECTS.append(flag)
        animate_rotation(flag, 0, [-0.05, 0.06, -0.05], [1, 48 + index * 6, 100 + index * 5], True)


def build_city_background():
    city = COLLECTIONS["展示_城市远景"]
    random.seed(777)
    positions = []
    for ring in (38, 52, 68, 84):
        count = 10 if ring < 60 else 14
        for index in range(count):
            angle = math.tau * index / count + 0.17 * (ring / 38)
            x = math.cos(angle) * ring + random.uniform(-5, 5)
            y = math.sin(angle) * ring + random.uniform(-5, 5)
            if abs(x) < 31 and abs(y) < 31:
                continue
            positions.append((x, y, ring))
    for index, (x, y, ring) in enumerate(positions):
        sx = random.uniform(7, 15)
        sy = random.uniform(7, 15)
        height = random.uniform(14, 38) * (1.0 if ring < 60 else 0.75)
        base_z = -22.0
        cell = CELLS["concrete_dark" if ring < 60 else "blue_dark"]
        building = box(f"远景废弃楼_{index}", (x, y, base_z), (sx, sy, height), city, "matte", cell, rotation=(0, 0, random.uniform(-0.12, 0.12)), category="Display/City")
        building["display_environment"] = True
        if index % 4 == 0:
            tank = cylinder(f"远景楼顶水箱_{index}", (x, y, base_z + height), min(sx, sy) * 0.18, 2.0, city, "metal", CELLS["concrete_dark"], 10, category="Display/City")
            tank["display_environment"] = True
        if index % 5 == 0:
            mast = cylinder(f"远景通信杆_{index}", (x + sx * 0.2, y, base_z + height), 0.08, 5.0, city, "metal", CELLS["concrete_dark"], 8, category="Display/City")
            mast["display_environment"] = True
    crane_x, crane_y = -52.0, 35.0
    crane = cylinder("远景停止起重机塔身", (crane_x, crane_y, -15.0), 0.5, 28.0, city, "metal", CELLS["rust_dark"], 8, category="Display/City")
    boom = box("远景停止起重机吊臂", (crane_x + 8, crane_y, 12.0), (18.0, 0.45, 0.45), city, "metal", CELLS["rust_dark"], rotation=(0, 0.06, 0.12), category="Display/City")
    crane["display_environment"] = True
    boom["display_environment"] = True

    for index, loc in enumerate(((46, -38, 8), (-48, -45, 12), (58, 30, 6))):
        signal = cylinder(f"远景不稳定电力信号_{index}_自发光", loc, 0.12, 0.25, city, "emissive", CELLS["warning"], 8, category="Display/City")
        signal["display_environment"] = True
        animate_rotation(signal, 2, [0, 0.2, 0], [1, 80 + index * 13, 160 + index * 21], True)
    for index, loc in enumerate(((-35, 30, -2), (40, 42, -4))):
        for puff in range(4):
            smoke = low_sphere(
                f"远景微弱烟雾_{index}_{puff}",
                (loc[0] + puff * 0.25, loc[1], loc[2] + puff * 1.1),
                (0.38 + puff * 0.05, 0.30 + puff * 0.04, 0.48),
                city, "matte", CELLS["black"], "Display/City"
            )
            smoke["display_environment"] = True
            smoke.keyframe_insert(data_path="location", frame=1)
            smoke.location.z += 1.0
            smoke.location.x += 0.35
            smoke.keyframe_insert(data_path="location", frame=180)


def create_source_prototypes():
    source_ground = COLLECTIONS["源_Environment_Ground"]
    source_arch = COLLECTIONS["源_Environment_Architecture"]
    source_facility = COLLECTIONS["源_Props_Communication"]
    prototypes = []
    tile_types = (
        "完整水泥地砖", "裂缝地砖", "积水地砖", "青苔地砖", "排水口地砖", "管线接口地砖",
        "种植区地砖", "棚屋基础地砖", "设备安装地砖", "边缘护栏地砖", "屋顶入口地砖", "严重破损地砖",
    )
    for index, tile_type in enumerate(tile_types):
        proto = box(f"源组件_5x5地砖_{tile_type}", (-220 + index * 6, 0, 0), (5, 5, 0.25), source_ground, "matte", CELLS["concrete" if index % 2 else "concrete_dark"], category="Environment/Ground")
        proto["asset_id"] = f"ENV_ROOF_TILE_{index:02d}"
        proto["module_size_m"] = [5.0, 5.0, 0.25]
        proto["snap_grid_m"] = 5.0
        proto["module_type"] = tile_type
        prototypes.append(proto)
    for index, (name, size, role, cell) in enumerate((
        ("棚屋立柱", (0.22, 0.22, 4.5), "metal", "purple"),
        ("棚屋横梁", (5.0, 0.18, 0.18), "metal", "purple"),
        ("拼装墙板", (5.0, 0.15, 3.2), "matte", "blue"),
        ("铁皮屋顶", (5.0, 5.0, 0.12), "metal", "rust"),
        ("防水帆布", (5.0, 5.0, 0.08), "matte", "green"),
        ("护栏模块", (5.0, 0.12, 1.1), "metal", "rust_dark"),
        ("广播平台", (5.0, 5.0, 1.2), "metal", "purple"),
    )):
        proto = box(f"源组件_{name}", (-220 + index * 7, 10, 0), size, source_arch if index < 6 else source_facility, role, CELLS[cell], category="Environment/Architecture")
        proto["asset_id"] = f"ENV_ROOF_ARCH_{index:02d}"
        prototypes.append(proto)
    SOURCE_PROTOTYPES.extend(prototypes)


def setup_audio():
    sample_rate = 22050
    duration = 2.4
    random.seed(31415)
    frames = bytearray()
    for index in range(int(sample_rate * duration)):
        envelope = 0.22 if (index // 3200) % 4 == 1 else 0.06
        value = int(max(-1.0, min(1.0, random.uniform(-1, 1) * envelope)) * 32767)
        frames.extend(int(value).to_bytes(2, "little", signed=True))
    with wave.open(str(STATIC_AUDIO), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(frames)
    sound = bpy.data.sounds.load(str(STATIC_AUDIO), check_existing=False)
    speaker_data = bpy.data.speakers.new("收音机微弱杂音_Data")
    speaker_data.sound = sound
    speaker_data.volume = 0.12
    speaker_data.attenuation = 1.0
    speaker = bpy.data.objects.new("收音机微弱杂音_Speaker", speaker_data)
    COLLECTIONS["输出_VFX"].objects.link(speaker)
    speaker.location = (-1.8, 3.35, 1.2)
    speaker["audio_behavior"] = "occasional_low_static"


def setup_render():
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 360
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1200
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.use_file_extension = True
    scene.world.color = (0.018, 0.025, 0.035)
    scene.view_settings.look = "AgX - Medium Low Contrast"
    scene.view_settings.exposure = 0.7

    world = scene.world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.025, 0.040, 0.055, 1.0)
    bg.inputs["Strength"].default_value = 0.42

    display = COLLECTIONS["展示_灯光镜头"]
    sun = add_light("阴天傍晚主光", "SUN", (20, -30, 55), (0.46, 0.58, 0.72), 2.8, display)
    sun.rotation_euler = (math.radians(38), math.radians(-20), math.radians(-28))
    sun.data.angle = math.radians(14)
    area = add_light("冷色天空补光", "AREA", (-18, -10, 38), (0.35, 0.48, 0.64), 2200, display, 38)
    area.rotation_euler = (0.25, 0.0, 0.55)
    warm = add_light("庇护所整体暖光", "AREA", (-2, 1, 10), (1.0, 0.42, 0.16), 780, display, 12)
    warm.rotation_euler = (0.0, 0.0, 0.0)
    rim = add_light("城市轮廓光", "AREA", (24, 30, 25), (0.28, 0.42, 0.60), 900, display, 24)
    rim.rotation_euler = (0.6, 0.0, 3.6)

    camera = add_camera("第三视角_微缩模型主镜头", (66, -66, 57), (0, 0, 2.7), 74, display)
    camera.data.dof.use_dof = False
    scene.camera = camera
    focus = bpy.data.objects.new("自由观察旋转中心", None)
    display.objects.link(focus)
    focus.location = (0, 0, 2.5)
    focus["interaction_hint"] = "Use Blender viewport orbit, pan and zoom; no in-scene UI"


def write_manifest(tile_counts):
    category_counts = {}
    for obj in bpy.context.scene.objects:
        category = obj.get("asset_category")
        if category:
            category_counts[category] = category_counts.get(category, 0) + 1
    manifest = {
        "asset": "末世天台庇护所",
        "asset_id": "ENV_ROOFTOP_SHELTER_001",
        "version": "v001",
        "dimensions_m": [50.0, 50.0],
        "grid_module_m": [5.0, 5.0],
        "ground_module_count": 100,
        "tile_type_counts": tile_counts,
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
            "detail_preview": str(DETAIL_PREVIEW),
        },
    }
    MANIFEST_FILE.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def save_deliverables():
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND))
    bpy.ops.wm.save_as_mainfile(filepath=str(GAME_BLEND), copy=True)


def build_scene():
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
    setup_render()
    write_manifest(tile_counts)
    save_deliverables()
    print(json.dumps({
        "status": "built",
        "objects": len(bpy.context.scene.objects),
        "meshes": sum(1 for obj in bpy.context.scene.objects if obj.type == "MESH"),
        "materials": len(bpy.data.materials),
        "output_objects": len(OUTPUT_OBJECTS),
        "source_prototypes": len(SOURCE_PROTOTYPES),
        "collisions": len(COLLISION_OBJECTS),
        "source_blend": str(SOURCE_BLEND),
        "game_blend": str(GAME_BLEND),
    }, ensure_ascii=False))


def render_previews():
    ensure_dirs()
    scene = bpy.context.scene
    camera = bpy.data.objects.get("第三视角_微缩模型主镜头")
    if camera is None:
        raise RuntimeError("Main camera is missing")
    scene.camera = camera
    scene.frame_set(48)
    camera.location = (42, -42, 34)
    camera.data.ortho_scale = 49
    camera.rotation_euler = (Vector((-2, 1, 2.8)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1200
    scene.render.filepath = str(DETAIL_PREVIEW)
    bpy.ops.render.render(write_still=True)

    scene.frame_set(72)
    camera.location = (66, -66, 57)
    camera.data.ortho_scale = 74
    camera.rotation_euler = (Vector((0, 0, 2.7)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(FULL_PREVIEW)
    bpy.ops.render.render(write_still=True)
    save_deliverables()
    print(json.dumps({"status": "rendered", "full": str(FULL_PREVIEW), "detail": str(DETAIL_PREVIEW)}, ensure_ascii=False))


MODE = globals().get("ROOFTOP_MODE", "build")
if MODE == "build":
    build_scene()
elif MODE == "render":
    render_previews()
elif MODE == "library":
    pass
else:
    raise ValueError(f"Unknown ROOFTOP_MODE: {MODE}")
