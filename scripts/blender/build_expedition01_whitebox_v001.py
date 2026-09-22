"""Build Expedition level 01 v001 whitebox.

Run with:
    blender --background --python scripts/blender/build_expedition01_whitebox_v001.py

Scope of this version: the expedition Boss arena only. Expedition 01 has no
other whitebox asset yet, so ASSETS holds exactly one entry; the list is kept
so later expedition rooms can be appended without touching the framework.

The arena is a size derivative of the battle arena
(source/art/whitebox/tower_zones/battle_level01/v003, 190x90m). It is NOT
produced by scaling that .blend: v003 forbids scaling and joining, so every
wall must stay a fixed 5m slot and every door wall must keep independent left
and right piers plus a lintel. The arena is therefore rebuilt procedurally on
the 5m module grid at the owner-specified 50x40m.

50 x 40 m = 10 x 8 grid slots. Both axes are whole multiples of GRID_UNIT, so
no FIXED_TRIM edge piece is produced anywhere in this asset, and the door
offsets are picked from the grid-clean set (odd multiples of 2.5m) so that the
slots before and after each door also close on whole 5m modules.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = ROOT / "source/art/whitebox/tower_zones/expedition_01/v001"
BLEND_DIR = OUTPUT_ROOT / "blender"
PACKAGE_DIR = OUTPUT_ROOT / "data/component_packages"
VALIDATION_DIR = OUTPUT_ROOT / "data/validation"
RENDER_DIR = OUTPUT_ROOT / "renders"
PALETTE_PATH = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

VERSION = "v001"
FLOOR_THICKNESS = 0.30
LOGICAL_WALL_HEIGHT = 12.0
VISUAL_WALL_HEIGHT = 11.9
WALL_THICKNESS = 0.30
DOOR_WIDTH = 2.2
DOOR_HEIGHT = 2.5
DOOR_CLEAR_FLOOR_GAP = 0.0
GRID_UNIT = 5.0
FLOOR_BASE_TOP = FLOOR_THICKNESS - 0.04
SURFACE_TILE_THICKNESS = 0.04
DOOR_BOTTOM = FLOOR_THICKNESS + DOOR_CLEAR_FLOOR_GAP
DOOR_TOP = DOOR_BOTTOM + DOOR_HEIGHT

# 来源竞技场（只作追溯，不在本脚本里读取）：内关卡01 v003 的 190x90m Boss 竞技场。
SOURCE_ARENA_ASSET_ID = "ENV-BATTLE-L01-BOSS-ARENA"
SOURCE_ARENA_BLEND = (
    "source/art/whitebox/tower_zones/battle_level01/v003/blender/"
    "局内关卡01_白模_Boss竞技场_190x90m_v003.blend"
)
SOURCE_ARENA_SIZE_M = (190.0, 90.0)
ARENA_SIZE_M = (50.0, 40.0)

# 门位推导：把来源竞技场的门位按墙面比例投影到新尺寸，再吸附到「5m 整数倍槽位」
# 的净门心集合 {±(2.5 + 5k)}，使门槽前后仍由整 5m 件收口、不产生 FIXED_TRIM。
#   南墙（进 · boss_prep）：来源 offset +5.00 / 半墙 95.0 -> -0.0526 -> 半墙 25.0 -> +1.32 -> 吸附 +2.5
#   西墙（出 · boss_exit）：来源 offset -2.50 / 半墙 45.0 -> -0.0556 -> 半墙 20.0 -> -1.11 -> 吸附 -2.5
ARENA_PORTS = [
    {
        "target": "boss_prep",
        "side": "south",
        "offset_m": 2.5,
        "source_offset_m": 5.0,
        "note": "进入侧；远征01 版图尚无 Boss 房席位，target 沿用来源竞技场的语义标签。",
    },
    {
        "target": "boss_exit",
        "side": "west",
        "offset_m": -2.5,
        "source_offset_m": -2.5,
        "note": "退出侧；同上，标签沿用来源竞技场。",
    },
]

ASSETS = [
    {
        "kind": "room",
        "key": "boss",
        "asset_id": "ENV-EXPEDITION-L01-BOSS-ARENA",
        "chinese_name": "远征关卡01 Boss竞技场 50×40m 白模",
        "category": "boss_arena",
        "slug": "远征关卡01_白模_boss竞技场_50x40m",
        "filename_stem": "远征关卡01_白模_Boss竞技场_50x40m",
        "size": ARENA_SIZE_M,
        "height": VISUAL_WALL_HEIGHT,
        "role": "Boss竞技场",
        "ports": [
            {"target": port["target"], "side": port["side"], "offset_m": port["offset_m"]}
            for port in ARENA_PORTS
        ],
        "world_center_m": [0.0, 0.0],
    },
]


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["expedition01_whitebox_version"] = VERSION
    scene["battle_logical_wall_height_m"] = LOGICAL_WALL_HEIGHT
    scene["battle_visual_wall_height_m"] = VISUAL_WALL_HEIGHT
    scene["battle_component_policy"] = "independent_meshes_no_join"


def make_material(
    name: str,
    metallic: float,
    roughness: float,
    palette_cell: tuple[int, int],
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    output.name = "材质输出"
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.name = "Principled BSDF"
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1.0)
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])

    uv_map = nodes.new("ShaderNodeUVMap")
    uv_map.uv_map = "PaletteUV"
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(PALETTE_PATH), check_existing=True)
    texture.interpolation = "Closest"
    links.new(uv_map.outputs["UV"], texture.inputs["Vector"])
    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    material["palette_column_zero_based"] = palette_cell[0]
    material["palette_row_zero_based"] = palette_cell[1]
    return material


def assign_palette_uv(obj: bpy.types.Object, cell: tuple[int, int]) -> None:
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    layer = mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = layer
    layer.active_render = True

    column, row = cell
    center_u = (column + 0.5) / 10.0
    center_v = 1.0 - (row + 0.5) / 10.0
    radius = 0.022
    for polygon in mesh.polygons:
        loop_count = len(polygon.loop_indices)
        for index, loop_index in enumerate(polygon.loop_indices):
            angle = math.tau * index / max(1, loop_count)
            layer.data[loop_index].uv = (
                center_u + radius * math.cos(angle),
                center_v + radius * math.sin(angle),
            )


def create_box(
    name: str,
    world_center: tuple[float, float, float],
    size: tuple[float, float, float],
    origin_world: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    palette_cell: tuple[int, int],
    component_kind: str,
    component_role: str,
    group: str,
    bevel: float = 0.0,
) -> bpy.types.Object:
    center = Vector(world_center)
    origin = Vector(origin_world)
    half = Vector(size) * 0.5
    local_center = center - origin
    signs = [
        (-1.0, -1.0, -1.0),
        (1.0, -1.0, -1.0),
        (1.0, 1.0, -1.0),
        (-1.0, 1.0, -1.0),
        (-1.0, -1.0, 1.0),
        (1.0, -1.0, 1.0),
        (1.0, 1.0, 1.0),
        (-1.0, 1.0, 1.0),
    ]
    vertices = [
        tuple(local_center + Vector((sx * half.x, sy * half.y, sz * half.z)))
        for sx, sy, sz in signs
    ]
    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new(f"{name}_网格")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = origin
    obj.data.materials.append(material)
    assign_palette_uv(obj, palette_cell)
    obj["component_group"] = group
    obj["component_kind"] = component_kind
    obj["component_role"] = component_role
    obj["origin_contract"] = "world_origin_stored_on_object_location"
    obj["dimensions_m"] = [round(value, 4) for value in size]
    if bevel > 0.0:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("白模小倒角", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        assign_palette_uv(obj, palette_cell)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def create_floor_grid(
    width: float,
    depth: float,
    source_structure: bpy.types.Collection,
    source_floor: bpy.types.Collection,
    dark_material: bpy.types.Material,
    floor_material: bpy.types.Material,
    owner_id: str,
) -> list[bpy.types.Object]:
    objects = [
        create_box(
            "FLOOR_BASE",
            (0.0, 0.0, FLOOR_BASE_TOP * 0.5),
            (width, depth, FLOOR_BASE_TOP),
            (0.0, 0.0, 0.0),
            dark_material,
            source_floor,
            (9, 1),
            "floor_slab",
            "房间承重地坪",
            "floor",
        )
    ]
    count_x = int(round(width / GRID_UNIT))
    count_y = int(round(depth / GRID_UNIT))
    for row in range(count_y):
        for column in range(count_x):
            center_x = -width * 0.5 + GRID_UNIT * (column + 0.5)
            center_y = -depth * 0.5 + GRID_UNIT * (row + 0.5)
            objects.append(
                create_box(
                    f"FLOOR_TILE_R{row + 1:02d}_C{column + 1:02d}",
                    (
                        center_x,
                        center_y,
                        FLOOR_BASE_TOP + SURFACE_TILE_THICKNESS * 0.5,
                    ),
                    (
                        GRID_UNIT - 0.06,
                        GRID_UNIT - 0.06,
                        SURFACE_TILE_THICKNESS,
                    ),
                    (center_x, center_y, 0.0),
                    floor_material,
                    source_floor,
                    (9, 4),
                    "floor_tile",
                    "5m 可替换地砖",
                    "floor",
                    bevel=0.018,
                )
            )
    for obj in objects:
        obj["owner_id"] = owner_id
    return objects


def normalized_openings(
    side: str,
    lateral_size: float,
    ports: list[dict[str, object]],
) -> list[tuple[float, float]]:
    half_clear = lateral_size * 0.5 - DOOR_WIDTH * 0.5
    openings = [
        (
            max(-half_clear, min(half_clear, float(port["offset_m"]))),
            str(port["target"]),
        )
        for port in ports
    ]
    openings.sort(key=lambda item: item[0])
    if len(openings) > 2:
        raise RuntimeError(f"Unsupported >2 doors on {side}")
    return openings


def create_side_walls(
    side: str,
    width: float,
    depth: float,
    ports: list[dict[str, object]],
    source_structure: bpy.types.Collection,
    wall_material: bpy.types.Material,
) -> list[bpy.types.Object]:
    side_upper = side.upper()
    objects: list[bpy.types.Object] = []
    is_horizontal = side in ("north", "south")
    lateral_size = width if is_horizontal else depth
    wall_axis = (
        (depth - WALL_THICKNESS) * 0.5
        if side == "north"
        else -(depth - WALL_THICKNESS) * 0.5
        if side == "south"
        else (width - WALL_THICKNESS) * 0.5
        if side == "east"
        else -(width - WALL_THICKNESS) * 0.5
    )
    openings = normalized_openings(side, lateral_size, ports)
    side_min = -lateral_size * 0.5
    side_max = lateral_size * 0.5
    door_slots = [
        (center - GRID_UNIT * 0.5, center + GRID_UNIT * 0.5, center, target)
        for center, target in openings
    ]
    for index, slot in enumerate(door_slots):
        if slot[0] < side_min - 0.001 or slot[1] > side_max + 0.001:
            raise RuntimeError(f"{side} 5m门墙槽越出房间边界: {slot}")
        if index and slot[0] < door_slots[index - 1][1] - 0.001:
            raise RuntimeError(f"{side} 5m门墙槽互相重叠")

    def add_horizontal_segment(name: str, left: float, right: float, role: str) -> None:
        segment_width = right - left
        if segment_width <= 0.001:
            return
        center_x = (left + right) * 0.5
        objects.append(
            create_box(
                name,
                (
                    center_x,
                    wall_axis,
                    VISUAL_WALL_HEIGHT * 0.5,
                ),
                (segment_width, WALL_THICKNESS, VISUAL_WALL_HEIGHT),
                (center_x, wall_axis, 0.0),
                wall_material,
                source_structure,
                (9, 6),
                "wall",
                role,
                "structure",
            )
        )

    def add_vertical_segment(name: str, bottom: float, top: float, role: str) -> None:
        segment_depth = top - bottom
        if segment_depth <= 0.001:
            return
        center_y = (bottom + top) * 0.5
        objects.append(
            create_box(
                name,
                (
                    wall_axis,
                    center_y,
                    VISUAL_WALL_HEIGHT * 0.5,
                ),
                (WALL_THICKNESS, segment_depth, VISUAL_WALL_HEIGHT),
                (wall_axis, center_y, 0.0),
                wall_material,
                source_structure,
                (9, 6),
                "wall",
                role,
                "structure",
            )
        )

    lintel_height = VISUAL_WALL_HEIGHT - DOOR_TOP
    module_number = 0

    def add_closed_interval(start: float, end: float) -> None:
        nonlocal module_number
        length = end - start
        if length <= 0.001:
            return
        full_count = int(length // GRID_UNIT)
        trim_width = length - full_count * GRID_UNIT
        cursor = start
        if trim_width > 0.001:
            module_number += 1
            trim_end = cursor + trim_width
            name = f"WALL_{side_upper}_SLOT_{module_number:02d}_FIXED_TRIM"
            role = f"{side_upper} 固定边界收边{module_number:02d}"
            if is_horizontal:add_horizontal_segment(name,cursor,trim_end,role)
            else:add_vertical_segment(name,cursor,trim_end,role)
            objects[-1]["wall_module_type"] = "trim_fixed"
            objects[-1]["wall_slot_index"] = module_number
            objects[-1]["wall_slot_center_m"] = (cursor + trim_end) * 0.5
            cursor = trim_end
        for _ in range(full_count):
            module_number += 1
            module_end = cursor + GRID_UNIT
            name = f"WALL_{side_upper}_SLOT_{module_number:02d}_SOLID"
            role = f"{side_upper} 5m标准实墙槽{module_number:02d}"
            if is_horizontal:add_horizontal_segment(name,cursor,module_end,role)
            else:add_vertical_segment(name,cursor,module_end,role)
            objects[-1]["wall_module_type"] = "solid_5m"
            objects[-1]["wall_slot_index"] = module_number
            objects[-1]["wall_slot_center_m"] = (cursor + module_end) * 0.5
            cursor = module_end

    cursor = side_min
    for door_left, door_right, opening_center, target in door_slots:
        add_closed_interval(cursor, door_left)
        module_number += 1
        slot_number = module_number
        opening_left = opening_center - DOOR_WIDTH * 0.5
        opening_right = opening_center + DOOR_WIDTH * 0.5
        left_edge = door_left
        right_edge = door_right
        prefix = f"WALL_{side_upper}_SLOT_{slot_number:02d}_DOOR"
        if is_horizontal:
            add_horizontal_segment(prefix + "_LEFT", left_edge, opening_left, f"{side_upper} 5m门墙左柱")
            add_horizontal_segment(prefix + "_RIGHT", opening_right, right_edge, f"{side_upper} 5m门墙右柱")
            lintel = create_box(
                prefix + "_LINTEL",
                (opening_center, wall_axis, DOOR_TOP + lintel_height * 0.5),
                (DOOR_WIDTH, WALL_THICKNESS, lintel_height),
                (opening_center, wall_axis, DOOR_TOP),
                wall_material, source_structure, (9, 6), "door_wall",
                f"{side_upper} 5m门墙门楣", "structure",
            )
        else:
            add_vertical_segment(prefix + "_LEFT", left_edge, opening_left, f"{side_upper} 5m门墙左柱")
            add_vertical_segment(prefix + "_RIGHT", opening_right, right_edge, f"{side_upper} 5m门墙右柱")
            lintel = create_box(
                prefix + "_LINTEL",
                (wall_axis, opening_center, DOOR_TOP + lintel_height * 0.5),
                (WALL_THICKNESS, DOOR_WIDTH, lintel_height),
                (wall_axis, opening_center, DOOR_TOP),
                wall_material, source_structure, (9, 6), "door_wall",
                f"{side_upper} 5m门墙门楣", "structure",
            )
        objects.append(lintel)
        for obj in objects[-3:]:
            obj["wall_module_type"] = "door_5m"
            obj["wall_slot_index"] = slot_number
            obj["wall_slot_center_m"] = opening_center
            obj["door_target"] = target
        cursor = door_right
    add_closed_interval(cursor, side_max)
    return objects


def create_room_shell(
    width: float,
    depth: float,
    ports: list[dict[str, object]],
    source_structure: bpy.types.Collection,
    source_floor: bpy.types.Collection,
    dark_material: bpy.types.Material,
    floor_material: bpy.types.Material,
    wall_material: bpy.types.Material,
    owner_id: str,
) -> list[bpy.types.Object]:
    objects = create_floor_grid(
        width,
        depth,
        source_structure,
        source_floor,
        dark_material,
        floor_material,
        owner_id,
    )
    doors_by_side: dict[str, list[dict[str, object]]] = {
        "north": [],
        "south": [],
        "east": [],
        "west": [],
    }
    for port in ports:
        doors_by_side[str(port["side"])].append(port)
    for side in ("north", "south", "east", "west"):
        objects.extend(
            create_side_walls(
                side,
                width,
                depth,
                doors_by_side[side],
                source_structure,
                wall_material,
            )
        )
    for obj in objects:
        obj["owner_id"] = owner_id
    return objects


def clone_components(
    source_objects: list[bpy.types.Object],
    output_structure: bpy.types.Collection,
    output_floor: bpy.types.Collection,
) -> list[bpy.types.Object]:
    clones: list[bpy.types.Object] = []
    for source in source_objects:
        output_name = source.name
        source.name = f"AP_{output_name}"
        clone = source.copy()
        clone.data = source.data.copy()
        clone.name = output_name
        target = output_structure if source["component_group"] == "structure" else output_floor
        target.objects.link(clone)
        clones.append(clone)
    return clones


def make_camera(
    name: str,
    location: tuple[float, float, float],
    target: tuple[float, float, float],
    ortho_scale: float,
    preview_collection: bpy.types.Collection,
) -> bpy.types.Object:
    camera_data = bpy.data.cameras.new(name)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ortho_scale
    camera = bpy.data.objects.new(name, camera_data)
    preview_collection.objects.link(camera)
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    return camera


def setup_preview(
    size: tuple[float, float],
    height: float,
    preview_collection: bpy.types.Collection,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    width, depth = size
    extent = max(width, depth, height)
    target = (0.0, 0.0, height * 0.45)
    camera_direction = Vector((0.72, -1.12, 0.58)).normalized()
    camera_distance = max(6.0, extent * 2.0)
    camera_location = Vector(target) + camera_direction * camera_distance
    reference = make_camera(
        "参考镜头_固定",
        tuple(camera_location),
        target,
        extent * 1.28,
        preview_collection,
    )
    top = make_camera(
        "俯视结构镜头",
        (0.0, 0.0, max(width, depth) * 1.5 + 8.0),
        (0.0, 0.0, 0.0),
        max(width, depth) * 1.18,
        preview_collection,
    )
    for name, energy, color, light_size in (
        ("主光", 1800.0, (0.86, 0.92, 1.0), max(5.0, extent * 0.22)),
        ("暖侧光", 900.0, (1.0, 0.72, 0.48), max(4.0, extent * 0.16)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.color = color
        light_data.shape = "DISK"
        light_data.size = light_size
        light = bpy.data.objects.new(name, light_data)
        preview_collection.objects.link(light)
        light.location = (
            width * 0.55,
            -depth * 0.65,
            max(9.0, extent * 0.50),
        )
        light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()
    return reference, top


def configure_render(scene: bpy.types.Scene) -> None:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 2.0
    scene.world = bpy.data.worlds.new("白模低亮环境")
    scene.world.use_nodes = True
    background = next(
        node
        for node in scene.world.node_tree.nodes
        if node.bl_idname == "ShaderNodeBackground"
    )
    background.inputs[0].default_value = (0.055, 0.075, 0.11, 1.0)
    background.inputs[1].default_value = 0.65


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points: list[Vector] = []
    for obj in objects:
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("No output objects")
    return (
        Vector(
            (
                min(point.x for point in points),
                min(point.y for point in points),
                min(point.z for point in points),
            )
        ),
        Vector(
            (
                max(point.x for point in points),
                max(point.y for point in points),
                max(point.z for point in points),
            )
        ),
    )


def component_record(obj: bpy.types.Object) -> dict[str, object]:
    min_corner, max_corner = world_bounds([obj])
    record = {
        "name": obj.name,
        "collection": next(collection.name for collection in obj.users_collection),
        "kind": obj["component_kind"],
        "role": obj["component_role"],
        "origin_world_m": [round(value, 4) for value in obj.location],
        "origin_contract": obj["origin_contract"],
        "dimensions_m": [round(float(value), 4) for value in obj["dimensions_m"]],
        "bounds_world_m": {
            "min": [round(value, 4) for value in min_corner],
            "max": [round(value, 4) for value in max_corner],
        },
    }
    for key in ("wall_module_type", "wall_slot_index", "wall_slot_center_m", "door_target"):
        if key in obj:
            record[key] = obj[key]
    return record


def validate_outputs(
    output_objects: list[bpy.types.Object],
    expected_size: tuple[float, float],
    expected_height: float,
) -> dict[str, object]:
    failures: list[str] = []
    warnings: list[str] = []
    names = [obj.name for obj in output_objects]
    if len(names) != len(set(names)):
        failures.append("输出对象重名")
    for name in names:
        if name.endswith("_主体"):
            failures.append(f"仍存在合并主体对象: {name}")
        if ".001" in name or "_nort" in name or "_sout" in name:
            failures.append(f"对象名包含迭代或截断后缀: {name}")
    multi_owner = [
        obj.name for obj in output_objects if len(obj.users_collection) != 1
    ]
    if multi_owner:
        failures.append(f"对象多集合归属: {multi_owner}")
    if len(output_objects) <= 1:
        failures.append("每个资产必须有多个独立输出组件")

    for obj in output_objects:
        kind = str(obj["component_kind"])
        location_z = round(obj.location.z, 4)
        if any(abs(float(value) - 1.0) > 0.0001 for value in obj.scale):
            failures.append(f"{obj.name} Scale必须为1，实际{list(obj.scale)}")
        if kind in {"wall", "door_wall"}:
            horizontal_length = max(float(obj.dimensions.x), float(obj.dimensions.y))
            if horizontal_length > GRID_UNIT + 0.001:
                failures.append(f"{obj.name} 超过5m模块长度: {horizontal_length:.3f}m")
        if kind in {"floor_slab", "floor_tile", "floor_edge", "wall", "wall_edge"}:
            if abs(location_z) > 0.0001:
                failures.append(f"{obj.name} 原点Z应为0，实际 {location_z}")
        elif kind == "door_wall":
            if abs(location_z - DOOR_TOP) > 0.0001:
                failures.append(
                    f"{obj.name} 门楣原点Z应为{DOOR_TOP:.3f}，实际 {location_z}"
                )
        else:
            warnings.append(f"未识别组件类型: {obj.name} / {kind}")

    trim_count = sum(
        1 for obj in output_objects if str(obj.get("wall_module_type", "")) == "trim_fixed"
    )
    if trim_count:
        warnings.append(f"本资产出现 {trim_count} 件 FIXED_TRIM 收边（两轴本应为 5m 整数倍）")

    min_corner, max_corner = world_bounds(output_objects)
    measured = (
        max_corner.x - min_corner.x,
        max_corner.y - min_corner.y,
        max_corner.z - min_corner.z,
    )
    expected = (expected_size[0], expected_size[1], expected_height)
    for axis, actual, wanted in zip(("X", "Y", "Z"), measured, expected):
        if abs(actual - wanted) > 0.011:
            failures.append(
                f"{axis}包络错误: 期望{wanted:.3f}m，实际{actual:.3f}m"
            )
    return {
        "status": "PASS" if not failures else "FAIL",
        "failures": failures,
        "warnings": warnings,
        "object_count": len(output_objects),
        "mesh_count": sum(obj.type == "MESH" for obj in output_objects),
        "component_counts": {
            kind: sum(obj["component_kind"] == kind for obj in output_objects)
            for kind in sorted({str(obj["component_kind"]) for obj in output_objects})
        },
        "fixed_trim_count": trim_count,
        "bounds_world_m": {
            "min": [round(value, 4) for value in min_corner],
            "max": [round(value, 4) for value in max_corner],
        },
        "measured_dimensions_m": [round(value, 4) for value in measured],
    }


def build_asset(asset: dict[str, object]) -> dict[str, object]:
    reset_scene()
    scene = bpy.context.scene
    asset_name = str(asset["chinese_name"])
    asset_id = str(asset["asset_id"])
    category = str(asset["category"])
    filename_stem = str(asset["filename_stem"])
    size = tuple(float(value) for value in asset["size"])
    height = float(asset["height"])

    root_collection = bpy.data.collections.new(f"{asset_name}_资产管理")
    scene.collection.children.link(root_collection)
    source_collection = bpy.data.collections.new("01_制作组件_按设施拆分")
    output_collection = bpy.data.collections.new(f"02_游戏输出_独立资产包_{VERSION}")
    preview_collection = bpy.data.collections.new("90_展示与验收_灯光相机")
    root_collection.children.link(source_collection)
    root_collection.children.link(output_collection)
    root_collection.children.link(preview_collection)

    source_structure = bpy.data.collections.new("01_建筑结构")
    source_floor = bpy.data.collections.new("02_地面系统")
    source_collection.children.link(source_structure)
    source_collection.children.link(source_floor)
    output_structure = bpy.data.collections.new("01_建筑结构")
    output_floor = bpy.data.collections.new("02_地面系统")
    output_collection.children.link(output_structure)
    output_collection.children.link(output_floor)

    metal = make_material("01_精工金属_紫色骨架", 0.82, 0.30, (9, 7))
    matte = make_material("02_细腻哑光_青绿大面", 0.03, 0.72, (9, 5))
    dark = make_material("03_深色哑光_结构底面", 0.02, 0.78, (9, 2))

    if asset["kind"] != "room":
        raise ValueError(f"Unsupported asset kind: {asset['kind']}")
    source_objects = create_room_shell(
        size[0],
        size[1],
        list(asset["ports"]),
        source_structure,
        source_floor,
        dark,
        matte,
        metal,
        asset_id,
    )

    output_objects = clone_components(source_objects, output_structure, output_floor)
    for obj in output_objects:
        obj["asset_id"] = asset_id
        obj["asset_version"] = VERSION
        obj["owner_id"] = asset_id
    source_collection.hide_viewport = True
    source_collection.hide_render = True
    output_collection.hide_viewport = False
    output_collection.hide_render = False

    reference_camera, top_camera = setup_preview(size, height, preview_collection)
    configure_render(scene)
    scene.camera = reference_camera

    blend_path = BLEND_DIR / f"{filename_stem}_{VERSION}.blend"
    render_path = RENDER_DIR / f"{filename_stem}_{VERSION}_参考.png"
    top_render_path = RENDER_DIR / f"{filename_stem}_{VERSION}_俯视.png"

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    scene.camera = reference_camera
    scene.render.filepath = str(render_path)
    bpy.ops.render.render(write_still=True)
    scene.camera = top_camera
    scene.render.filepath = str(top_render_path)
    bpy.ops.render.render(write_still=True)
    scene.camera = reference_camera
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    validation = validate_outputs(output_objects, size, height)
    min_corner, max_corner = world_bounds(output_objects)
    component_records = [component_record(obj) for obj in output_objects]
    manifest = {
        "asset_id": asset_id,
        "name_zh": asset_name,
        "slug": asset["slug"],
        "category": category,
        "role": asset["role"],
        "version": VERSION,
        "level_id": "expedition_01",
        "block_id": "expedition",
        "design_scope": "scene_art",
        "asset_ledger": "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用",
        "source_blend": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
        "blender_collection": root_collection.name,
        "authoring_collection": source_collection.name,
        "output_collection": output_collection.name,
        "objects": [obj.name for obj in output_objects],
        "root_object": None,
        "component_count": len(output_objects),
        "component_policy": "fixed 5m wall slots; solid wall=one 5m mesh; door wall=one 5m slot with independent left/right piers and lintel; no scaling or joining",
        "origin": "asset floor underside Z=0; each wall/lintel stores its own bottom-center origin",
        "front": "Godot -Z",
        "dimensions_m": [round(size[0], 3), round(size[1], 3), round(height, 3)],
        "grid_units_per_axis": [
            int(round(size[0] / GRID_UNIT)),
            int(round(size[1] / GRID_UNIT)),
        ],
        "bounds_world_m": {
            "min": [round(value, 4) for value in min_corner],
            "max": [round(value, 4) for value in max_corner],
        },
        "logical_wall_height_m": LOGICAL_WALL_HEIGHT,
        "visual_wall_height_m": VISUAL_WALL_HEIGHT,
        "floor_thickness_m": FLOOR_THICKNESS,
        "door_contract": {
            "width_m": DOOR_WIDTH,
            "height_m": DOOR_HEIGHT,
            "clear_floor_gap_m": DOOR_CLEAR_FLOOR_GAP,
            "bottom_z_m": DOOR_BOTTOM,
            "lintel_bottom_z_m": DOOR_TOP,
        },
        "ports": list(asset["ports"]),
        "port_derivation": ARENA_PORTS,
        "world_slot_center_m": asset["world_center_m"],
        "materials": [metal.name, matte.name, dark.name],
        "palette_uv": "PaletteUV",
        "shared_palette": str(PALETTE_PATH.relative_to(ROOT)).replace("\\", "/"),
        "derivation": {
            "derived_from_asset": SOURCE_ARENA_ASSET_ID,
            "derived_from_blend": SOURCE_ARENA_BLEND,
            "method": "procedural_rebuild_on_5m_grid",
            "scaled_in_blender": False,
            "source_size_m": list(SOURCE_ARENA_SIZE_M),
            "target_size_m": [size[0], size[1]],
            "axis_ratio": [
                round(size[0] / SOURCE_ARENA_SIZE_M[0], 4),
                round(size[1] / SOURCE_ARENA_SIZE_M[1], 4),
            ],
            "note": (
                "1/3 线性缩放会落在 63.33×30m，X 轴不是 5m 整数倍，会逼出 3.33m 非标墙件并让地砖网格溢出包络；"
                "v003 又明令禁止缩放与合并，因此改为在 5m 槽位网格上按新的整数槽数（10×8）重建，"
                "并把门位吸附到净门心集合 {±(2.5+5k)}，使门槽前后仍由整 5m 件收口。"
            ),
        },
        "components": component_records,
        "render_reference": str(render_path.relative_to(ROOT)).replace("\\", "/"),
        "render_top": str(top_render_path.relative_to(ROOT)).replace("\\", "/"),
        "export_status": "blend_only; GLB and Godot integration not requested",
        "collision_status": "not authored",
        "runtime_status": "not connected",
        "notes": (
            "远征关卡01 设计源（source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json）"
            "目前没有 BOSS 房席位，也没有 50×40 的房型模板；本白模是美术侧先行的独立资产，"
            "接入运行时需要 A 段（09-level-plan-authoring）先补 Boss 房与模板。"
        ),
    }
    manifest_path = PACKAGE_DIR / category / str(asset["slug"]) / "asset_manifest.json"
    write_json(manifest_path, manifest)
    write_json(
        VALIDATION_DIR / f"{asset['slug']}_{VERSION}_validation.json",
        {
            "asset_id": asset_id,
            "source_blend": manifest["source_blend"],
            **validation,
        },
    )
    print(
        "EXPEDITION01_WHITEBOX_V001_ASSET_OK",
        json.dumps(
            {
                "asset_id": asset_id,
                "objects": len(output_objects),
                "validation": validation["status"],
                "blend": str(blend_path),
            },
            ensure_ascii=False,
        ),
    )
    return manifest


def write_catalog(manifests: list[dict[str, object]]) -> None:
    category_counts: dict[str, int] = {}
    for manifest in manifests:
        category = str(manifest["category"])
        category_counts[category] = category_counts.get(category, 0) + 1
    catalog = {
        "zone": "expedition_01",
        "display_name": "远征关卡01 白盒资产",
        "version": VERSION,
        "asset_count": len(manifests),
        "component_policy": "墙体严格按5m槽位拼装；实墙每槽单件，门墙每槽保留左右柱与门楣；禁止缩放与join",
        "scope_note": (
            "v001 只含 Boss 竞技场一件。远征01 的其余白盒（安全房/主路房/撤离房）尚未制作，"
            "制作时向本脚本 ASSETS 追加条目即可，不需改动框架。"
        ),
        "category_counts": category_counts,
        "assets": [
            {
                "asset_id": manifest["asset_id"],
                "name_zh": manifest["name_zh"],
                "category": manifest["category"],
                "slug": manifest["slug"],
                "source_blend": manifest["source_blend"],
                "dimensions_m": manifest["dimensions_m"],
                "component_count": manifest["component_count"],
                "component_counts": {
                    kind: sum(
                        component["kind"] == kind
                        for component in manifest["components"]
                    )
                    for kind in sorted(
                        {
                            str(component["kind"])
                            for component in manifest["components"]
                        }
                    )
                },
            }
            for manifest in manifests
        ],
    }
    write_json(PACKAGE_DIR / "catalog.json", catalog)

    lines = [
        f"expedition_01/{VERSION}",
        f"├─ blender/ ({len(manifests)} .blend)",
        "├─ data/",
        "│  ├─ level_plan.json / floors/ / room_templates/   ← A 段设计源（09-level-plan-authoring）",
        "│  ├─ component_packages/",
        "│  │  ├─ catalog.json",
        *[
            f"│  │  ├─ {category}/ ({count})"
            for category, count in sorted(category_counts.items())
        ],
        "│  └─ validation/",
        "└─ renders/",
    ]
    (PACKAGE_DIR / "tree.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
    VALIDATION_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    manifests = [build_asset(asset) for asset in ASSETS]
    write_catalog(manifests)
    failed = [
        manifest["asset_id"]
        for manifest in manifests
        if json.loads(
            (
                VALIDATION_DIR
                / f"{manifest['slug']}_{VERSION}_validation.json"
            ).read_text(encoding="utf-8")
        )["status"]
        != "PASS"
    ]
    write_json(
        VALIDATION_DIR / "task_level_validation.json",
        {
            "status": "PASS" if not failed else "FAIL",
            "asset_count": len(manifests),
            "failed_assets": failed,
            "checks": [
                "no join or merged 主体 object",
                "all room walls use fixed 5m slots; no wall mesh exceeds 5m",
                "door wall occupies one 5m slot with independent left/right piers and lintel",
                "all output object scales equal 1",
                "wall, floor slab, floor tile and door wall components stay separate",
                "wall and lintel origins are bottom-center",
                "floor origins are at underside Z=0",
                "object names contain no .001, _nort or _sout suffix",
                "each output object belongs to exactly one output collection",
                "asset bounds match the contract size",
                "both axes are whole multiples of the 5m grid unit (no FIXED_TRIM)",
            ],
        },
    )
    print(
        "EXPEDITION01_WHITEBOX_V001_READY",
        json.dumps(
            {
                "assets": len(manifests),
                "failed_assets": failed,
                "output": str(OUTPUT_ROOT),
                "package_catalog": str(PACKAGE_DIR / "catalog.json"),
            },
            ensure_ascii=False,
        ),
    )
    if failed:
        raise RuntimeError(f"Validation failed for: {failed}")


if __name__ == "__main__":
    main()
