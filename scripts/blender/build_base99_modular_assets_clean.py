import bpy
import json
import math
from pathlib import Path
from mathutils import Matrix, Vector


OUTPUT_DIR = Path(
    "/Users/summercards/ShellStorm2/assets/art/environments/base_facility_3d/"
    "source/env_base99_modular_room"
)
OUTPUT_BLEND = OUTPUT_DIR / "env_base99_modular_room_assets_clean_v001.blend"
OUTPUT_MANIFEST = OUTPUT_DIR / "env_base99_modular_room_assets_clean_v001_manifest.json"
PALETTE_PATH = Path(
    "/Users/summercards/ShellStorm2/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
)

MATERIAL_NAMES = (
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
    "04_柔和自发光_UI灯光",
)
EMISSIVE_MATERIAL = MATERIAL_NAMES[3]


def in_collection(obj, name):
    return any(collection.name == name for collection in obj.users_collection)


def is_mesh(obj):
    return obj.type == "MESH"


MODULES = [
    {
        "index": 1,
        "asset_id": "ENV-BASE99-FLOOR-RIVET-5M",
        "logic_id": "base99_floor_rivet_5m",
        "name": "地板模块_5x5米_带铆钉铁皮带",
        "short": "带铆钉地板",
        "arrangement": (-28.0, 28.0, 0.0),
        "rotation_z": 0.0,
        "select": lambda obj: is_mesh(obj) and obj.name.startswith("楼板组件_X00_Y00_5x5米_"),
    },
    {
        "index": 2,
        "asset_id": "ENV-BASE99-FLOOR-PLAIN-5M",
        "logic_id": "base99_floor_plain_5m",
        "name": "地板模块_5x5米_无铆钉铁皮带",
        "short": "普通地板",
        "arrangement": (0.0, 28.0, 0.0),
        "rotation_z": 0.0,
        "select": lambda obj: is_mesh(obj) and obj.name.startswith("楼板组件_X00_Y01_5x5米_"),
    },
    {
        "index": 3,
        "asset_id": "ENV-BASE99-DOOR-LIFT-22X25",
        "logic_id": "base99_door_lift_2p2x2p5",
        "name": "滑升门模块_2.2x2.5米",
        "short": "滑升门",
        "arrangement": (28.0, 28.0, 0.0),
        "rotation_z": math.radians(90.0),
        "select": lambda obj: is_mesh(obj) and obj.parent is not None and obj.parent.name == "门扇滑升节点",
    },
    {
        "index": 4,
        "asset_id": "ENV-BASE99-WALL-PLAIN-5X9",
        "logic_id": "base99_wall_plain_5x9",
        "name": "普通墙体模块_5x9米",
        "short": "普通墙体",
        "arrangement": (-28.0, 0.0, 0.0),
        "rotation_z": 0.0,
        "select": lambda obj: is_mesh(obj) and obj.name.startswith("墙体组件_北_00_5x9米_"),
    },
    {
        "index": 5,
        "asset_id": "ENV-BASE99-WALL-DOOR-5X9",
        "logic_id": "base99_wall_door_5x9",
        "name": "带门墙体模块_5x9米",
        "short": "带门墙体",
        "arrangement": (0.0, 0.0, 0.0),
        "rotation_z": math.radians(90.0),
        "select": lambda obj: (
            is_mesh(obj)
            and obj.parent is not None
            and obj.parent.name in {"门墙结构_门柱与门楣", "门框结构_紫色金属"}
        ),
    },
    {
        "index": 6,
        "asset_id": "ENV-BASE99-WALL-WINDOW-5X9",
        "logic_id": "base99_wall_window_5x9",
        "name": "带窗墙体模块_5x9米",
        "short": "带窗墙体",
        "arrangement": (28.0, 0.0, 0.0),
        "rotation_z": 0.0,
        "select": lambda obj: is_mesh(obj) and obj.name.startswith("工业竖窗墙_01_"),
    },
    {
        "index": 7,
        "asset_id": "ENV-BASE99-MEZZANINE-20X10-Z7",
        "logic_id": "base99_mezzanine_20x10_z7",
        "name": "二层楼中楼楼板_20x10米_Z7米",
        "short": "二层楼板",
        "arrangement": (-28.0, -32.0, 0.0),
        "rotation_z": 0.0,
        "select": lambda obj: (
            is_mesh(obj)
            and (
                (obj.parent is not None and obj.parent.name in {"01_阁楼平台_4x2地砖_根节点", "04_结构支撑_根节点"})
                or (in_collection(obj, "03_护栏与扶手") and obj.name.startswith("平台"))
                or (in_collection(obj, "05_未来风格灯带") and obj.name.startswith("阁楼"))
            )
        ),
    },
    {
        "index": 8,
        "asset_id": "ENV-BASE99-STAIR-L-Z7",
        "logic_id": "base99_stair_l_z7",
        "name": "L型楼梯_地面至二层_Z7米",
        "short": "L型楼梯",
        "arrangement": (0.0, -32.0, 0.0),
        "rotation_z": 0.0,
        "select": lambda obj: (
            is_mesh(obj)
            and (
                (obj.parent is not None and obj.parent.name == "02_L字楼梯_双跑_根节点")
                or (in_collection(obj, "03_护栏与扶手") and (obj.name.startswith("L梯") or obj.name.startswith("转角平台")))
                or (in_collection(obj, "05_未来风格灯带") and (obj.name.startswith("L梯") or obj.name.startswith("转角平台")))
            )
        ),
    },
    {
        "index": 9,
        "asset_id": "ENV-BASE99-STAIR-EXTERIOR-H2",
        "logic_id": "base99_stair_exterior_h2",
        "name": "二楼外门小楼梯_高差2米",
        "short": "外门小楼梯",
        "arrangement": (28.0, -32.0, 0.0),
        "rotation_z": 0.0,
        "select": lambda obj: (
            is_mesh(obj)
            and obj.parent is not None
            and obj.parent.name == "阁楼至天台门_8级台阶_宽2.8米"
        ),
    },
]


def intended_world_matrix(obj, cache):
    if obj.name in cache:
        return cache[obj.name]
    local = obj.matrix_basis.copy()
    result = intended_world_matrix(obj.parent, cache) @ local if obj.parent is not None else local
    cache[obj.name] = result
    return result


def mesh_bounds(source_objects, rotation_matrix, matrix_cache):
    points = []
    for source in source_objects:
        world = rotation_matrix @ intended_world_matrix(source, matrix_cache)
        points.extend(world @ vertex.co for vertex in source.data.vertices)
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    rebase = Vector(((minimum.x + maximum.x) * 0.5, (minimum.y + maximum.y) * 0.5, minimum.z))
    return minimum, maximum, rebase


def ensure_palette_uv(mesh):
    palette = mesh.uv_layers.get("PaletteUV")
    if palette is None:
        raise RuntimeError(f"Mesh {mesh.name} is missing PaletteUV")
    for layer in list(mesh.uv_layers):
        if layer.name != "PaletteUV":
            mesh.uv_layers.remove(layer)
    mesh.uv_layers.active = palette
    palette.active_render = True


def make_collection(name, parent):
    collection = bpy.data.collections.new(name)
    parent.children.link(collection)
    return collection


def make_empty(name, collection, location, module):
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 1.0
    root.location = location
    root["asset_id"] = module["asset_id"]
    root["logic_id"] = module["logic_id"]
    root["unit"] = "meter"
    root["blender_forward"] = "-Y"
    root["godot_forward"] = "-Z"
    root["module_local_origin"] = "xy_center_bottom_z0"
    root["arrangement_offset"] = list(location)
    root["export_note"] = "导出该模块前将根节点位置归零"
    collection.objects.link(root)
    return root


def clone_source_object(source, local_transform, collection, root, name):
    mesh = source.data.copy()
    mesh.name = f"{name}_网格"
    mesh.transform(local_transform)
    ensure_palette_uv(mesh)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = root
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = Matrix.Identity(4)
    return obj


def object_is_emissive(obj):
    materials = [material for material in obj.data.materials if material]
    return bool(materials) and all(material.name == EMISSIVE_MATERIAL for material in materials)


def join_objects(objects, name, collection, root):
    if not objects:
        return None
    duplicates = []
    for source in objects:
        mesh = source.data.copy()
        duplicate = bpy.data.objects.new(f"{source.name}_整合副本", mesh)
        collection.objects.link(duplicate)
        duplicates.append(duplicate)
    bpy.ops.object.select_all(action="DESELECT")
    for duplicate in duplicates:
        duplicate.select_set(True)
    bpy.context.view_layer.objects.active = duplicates[0]
    if len(duplicates) > 1:
        bpy.ops.object.join()
    output = duplicates[0]
    output.name = name
    output.data.name = f"{name}_网格"
    ensure_palette_uv(output.data)
    output.parent = root
    output.matrix_parent_inverse = Matrix.Identity(4)
    output.matrix_basis = Matrix.Identity(4)
    return output


def normalize_material_nodes(materials):
    if not PALETTE_PATH.exists():
        raise RuntimeError(f"Palette is missing: {PALETTE_PATH}")
    image = bpy.data.images.get("设施低亮多巴胺色盘_10x10_512")
    if image is None:
        image = bpy.data.images.load(str(PALETTE_PATH), check_existing=True)
        image.name = "设施低亮多巴胺色盘_10x10_512"
    image.colorspace_settings.name = "sRGB"
    image.pack()
    for material in materials:
        if not material.use_nodes or not material.node_tree:
            continue
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
        if principled is None:
            continue
        uv_node = next((node for node in nodes if node.type == "UVMAP"), None)
        if uv_node is None:
            uv_node = nodes.new("ShaderNodeUVMap")
        uv_node.name = "PaletteUV_显式通道"
        uv_node.uv_map = "PaletteUV"
        image_node = next((node for node in nodes if node.type == "TEX_IMAGE"), None)
        if image_node is None:
            image_node = nodes.new("ShaderNodeTexImage")
        image_node.name = "设施低亮多巴胺色盘_Closest"
        image_node.image = image
        image_node.interpolation = "Closest"
        for link in list(image_node.inputs["Vector"].links):
            links.remove(link)
        links.new(uv_node.outputs["UV"], image_node.inputs["Vector"])
        for link in list(principled.inputs["Base Color"].links):
            links.remove(link)
        links.new(image_node.outputs["Color"], principled.inputs["Base Color"])
        if material.name == EMISSIVE_MATERIAL:
            for link in list(principled.inputs["Emission Color"].links):
                links.remove(link)
            links.new(image_node.outputs["Color"], principled.inputs["Emission Color"])
            principled.inputs["Emission Strength"].default_value = 1.35


def add_display_environment(parent):
    display = make_collection("90_展示环境_灯光相机", parent)
    camera_data = bpy.data.cameras.new("基地99层模块总览_相机")
    camera = bpy.data.objects.new("基地99层模块总览_相机", camera_data)
    display.objects.link(camera)
    camera.location = (82.0, -112.0, 78.0)
    target = Vector((0.0, -3.0, 5.0))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = 52.0
    bpy.context.scene.camera = camera
    for index, (location, energy, size) in enumerate(
        [((-52.0, -42.0, 72.0), 3600.0, 18.0), ((62.0, 38.0, 58.0), 2800.0, 16.0), ((0.0, -62.0, 34.0), 1900.0, 12.0)],
        start=1,
    ):
        light_data = bpy.data.lights.new(f"验收面光_{index:02d}", "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(f"验收面光_{index:02d}", light_data)
        display.objects.link(light)
        light.location = location
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
    return display


def local_bounds(objects):
    points = [vertex.co for obj in objects for vertex in obj.data.vertices]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


original_objects = list(bpy.data.objects)
original_collections = list(bpy.data.collections)
matrix_cache = {}
material_lookup = {name: bpy.data.materials.get(name) for name in MATERIAL_NAMES}
missing_materials = [name for name, material in material_lookup.items() if material is None]
if missing_materials:
    raise RuntimeError(f"Missing shared materials: {missing_materials}")
normalize_material_nodes(material_lookup.values())

scene_root = bpy.context.scene.collection
master = make_collection("基地99层模块资产总览_中文资产管理", scene_root)
source_master = make_collection("01_制作组件_已统一材质", master)
source_master.hide_viewport = True
source_master.hide_render = True
output_master = make_collection("02_游戏输出_整合模型", master)
output_master.hide_viewport = False
output_master.hide_render = False

manifest_modules = []
for module in MODULES:
    selected = sorted((obj for obj in original_objects if module["select"](obj)), key=lambda obj: obj.name)
    if not selected:
        raise RuntimeError(f"No source objects found for {module['name']}")
    rotation = Matrix.Rotation(module["rotation_z"], 4, "Z")
    source_minimum, source_maximum, rebase = mesh_bounds(selected, rotation, matrix_cache)
    local_from_world = Matrix.Translation(-rebase) @ rotation

    numbered_name = f"{module['index']:02d}_{module['name']}"
    source_collection = make_collection(f"{numbered_name}_制作组件", source_master)
    output_collection = make_collection(f"{numbered_name}_游戏输出", output_master)
    source_root = make_empty(
        f"{module['asset_id']}_制作根节点",
        source_collection,
        module["arrangement"],
        module,
    )
    output_root = make_empty(
        f"{module['asset_id']}_输出根节点",
        output_collection,
        module["arrangement"],
        module,
    )

    source_copies = []
    for source_index, source in enumerate(selected, start=1):
        transform = local_from_world @ intended_world_matrix(source, matrix_cache)
        source_name = f"{module['short']}_制作_{source_index:03d}_{source.name}"
        source_copies.append(
            clone_source_object(source, transform, source_collection, source_root, source_name)
        )

    emissive_sources = [obj for obj in source_copies if object_is_emissive(obj)]
    body_sources = [obj for obj in source_copies if not object_is_emissive(obj)]
    body_name = f"{module['short']}_主体_金属哑光反光"
    emissive_name = f"{module['short']}_UI灯光_柔和自发光"
    body_output = join_objects(body_sources, body_name, output_collection, output_root)
    emissive_output = join_objects(emissive_sources, emissive_name, output_collection, output_root)
    outputs = [obj for obj in (body_output, emissive_output) if obj is not None]
    minimum, maximum = local_bounds(outputs)
    output_root["local_bounds_min"] = list(minimum)
    output_root["local_bounds_max"] = list(maximum)
    output_root["local_dimensions"] = list(maximum - minimum)
    output_root["source_object_count"] = len(selected)
    output_root["output_mesh_count"] = len(outputs)
    if module["asset_id"] == "ENV-BASE99-DOOR-LIFT-22X25":
        output_root["door_clear_width_m"] = 2.2
        output_root["door_clear_height_m"] = 2.5
        output_root["runtime_motion"] = "vertical_lift"
        output_root["runtime_owner"] = "RoomDoor3D"
        output_root["collision_in_glb"] = False
        output_root["prompt_in_glb"] = False
    manifest_modules.append(
        {
            "index": module["index"],
            "asset_id": module["asset_id"],
            "logic_id": module["logic_id"],
            "display_name": module["name"],
            "source_object_count": len(selected),
            "output_meshes": [obj.name for obj in outputs],
            "materials": sorted(
                {material.name for obj in outputs for material in obj.data.materials if material}
            ),
            "local_bounds_min": [round(value, 5) for value in minimum],
            "local_bounds_max": [round(value, 5) for value in maximum],
            "local_dimensions": [round(value, 5) for value in maximum - minimum],
            "arrangement_offset": list(module["arrangement"]),
            "forward": "Blender -Y / Godot -Z",
        }
    )

display_collection = add_display_environment(master)
keep_objects = {
    obj
    for collection in (source_master, output_master, display_collection)
    for obj in collection.all_objects
}
for obj in original_objects:
    if obj not in keep_objects:
        bpy.data.objects.remove(obj, do_unlink=True)

keep_collections = {master, source_master, output_master, display_collection}
keep_collections.update(source_master.children)
keep_collections.update(output_master.children)
for collection in reversed(original_collections):
    if collection not in keep_collections:
        bpy.data.collections.remove(collection)

# Blender may add numeric suffixes while legacy collections with the same names
# still exist. Restore the exact production names after legacy data is removed.
master.name = "基地99层模块资产总览_中文资产管理"
source_master.name = "01_制作组件_已统一材质"
output_master.name = "02_游戏输出_整合模型"
display_collection.name = "90_展示环境_灯光相机"

for material in list(bpy.data.materials):
    if material.name not in MATERIAL_NAMES:
        bpy.data.materials.remove(material)
for mesh in bpy.data.meshes:
    if mesh.users:
        ensure_palette_uv(mesh)

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1400
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = (0.012, 0.018, 0.032)
scene["asset_pack"] = "ENV-BASE99-MODULAR-ROOM"
scene["asset_pack_version"] = "v001"
scene["module_count"] = len(MODULES)
scene["source_autosave"] = bpy.data.filepath
scene["door_runtime_contract"] = "RoomDoor3D: DoorPanel + front/back LockStripe + external collision/prompt"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
manifest = {
    "asset_pack": "ENV-BASE99-MODULAR-ROOM",
    "version": "v001",
    "source": bpy.data.filepath,
    "output_blend": str(OUTPUT_BLEND),
    "module_count": len(MODULES),
    "shared_materials": list(MATERIAL_NAMES),
    "palette": str(PALETTE_PATH),
    "palette_packed": False,
    "palette_policy": "single external scene/facility palette; GLB exports omit images",
    "door_runtime_contract": {
        "clear_width_m": 2.2,
        "clear_height_m": 2.5,
        "visual": "moving door leaf plus front/back emissive status strips",
        "wall_owns_frame": True,
        "godot_wrapper_owns_collision_prompt_and_motion": True,
    },
    "modules": manifest_modules,
}
OUTPUT_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
print(f"BASE99_CLEAN_BLEND_WRITTEN:{OUTPUT_BLEND}")
print(f"BASE99_MANIFEST_WRITTEN:{OUTPUT_MANIFEST}")
