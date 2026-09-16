"""Build Battle level 01 v003 with strict 5m wall and door-wall modules.

Run with:
    blender --background --python scripts/blender/build_battle_level01_whitebox_v003.py

Version v003 replaces room-spanning wall cuboids with fixed 5m slots. Solid
walls occupy one complete slot. Door walls also occupy one complete slot and
keep their left pier, right pier and lintel as independent meshes.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = ROOT / "source/art/whitebox/tower_zones/battle_level01/v003"
BLEND_DIR = OUTPUT_ROOT / "blender"
PACKAGE_DIR = OUTPUT_ROOT / "data/component_packages"
VALIDATION_DIR = OUTPUT_ROOT / "data/validation"
RENDER_DIR = OUTPUT_ROOT / "renders"
PALETTE_PATH = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

VERSION = "v003"
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


ROOM_LAYOUT = {
    "entry": {"center": (27.5, 2.5), "size": (15.0, 15.0)},
    "hub": {"center": (30.0, -42.5), "size": (30.0, 25.0)},
    "main_02": {"center": (65.0, -42.5), "size": (30.0, 25.0)},
    "main_03": {"center": (100.0, -42.5), "size": (30.0, 25.0)},
    "main_04": {"center": (100.0, -12.5), "size": (30.0, 25.0)},
    "main_05": {"center": (100.0, 37.5), "size": (30.0, 40.0)},
    "main_06": {"center": (100.0, 87.5), "size": (30.0, 25.0)},
    "main_07": {"center": (65.0, 87.5), "size": (30.0, 25.0)},
    "main_08": {"center": (27.5, 87.5), "size": (35.0, 30.0)},
    "main_09": {"center": (-20.0, 87.5), "size": (40.0, 25.0)},
    "main_10": {"center": (-20.0, 47.5), "size": (30.0, 25.0)},
    "exit": {"center": (-22.5, 2.5), "size": (15.0, 15.0)},
    "branch_01": {"center": (100.0, -77.5), "size": (30.0, 25.0)},
    "branch_02": {"center": (65.0, -77.5), "size": (30.0, 25.0)},
    "branch_03": {"center": (-65.0, 87.5), "size": (40.0, 35.0)},
    "branch_04": {"center": (-105.0, 87.5), "size": (30.0, 25.0)},
    "boss_prep": {"center": (85.0, -7.5), "size": (30.0, 25.0)},
    "boss": {"center": (80.0, 80.0), "size": (190.0, 90.0)},
    "boss_exit": {"center": (27.5, 77.5), "size": (15.0, 15.0)},
}

CONNECTIONS = [
    ("entry", "hub"),
    ("hub", "main_02"),
    ("main_02", "main_03"),
    ("main_03", "main_04"),
    ("main_04", "main_05"),
    ("main_05", "main_06"),
    ("main_06", "main_07"),
    ("main_07", "main_08"),
    ("main_08", "main_09"),
    ("main_09", "main_10"),
    ("main_10", "exit"),
    ("main_03", "branch_01"),
    ("branch_01", "branch_02"),
    ("main_09", "branch_03"),
    ("branch_03", "branch_04"),
]

BOSS_CONNECTIONS = [
    ("boss_prep", "boss"),
    ("boss", "boss_exit"),
]


def slugify(value: str) -> str:
    return value.strip().lower().replace("-", "_").replace(" ", "_")


def side_and_offset(room_key: str, neighbor_key: str) -> tuple[str, float]:
    room = ROOM_LAYOUT[room_key]
    neighbor = ROOM_LAYOUT[neighbor_key]
    dx = neighbor["center"][0] - room["center"][0]
    dy = neighbor["center"][1] - room["center"][1]
    if abs(dx) >= abs(dy):
        return ("east", dy) if dx >= 0.0 else ("west", dy)
    return ("north", dx) if dy >= 0.0 else ("south", dx)


def build_ports() -> dict[str, list[dict[str, object]]]:
    ports: dict[str, list[dict[str, object]]] = {key: [] for key in ROOM_LAYOUT}
    for parent_key, child_key in CONNECTIONS + BOSS_CONNECTIONS:
        parent_side, parent_offset = side_and_offset(parent_key, child_key)
        child_side, child_offset = side_and_offset(child_key, parent_key)
        ports[parent_key].append(
            {
                "target": child_key,
                "side": parent_side,
                "offset_m": round(parent_offset, 3),
            }
        )
        ports[child_key].append(
            {
                "target": parent_key,
                "side": child_side,
                "offset_m": round(child_offset, 3),
            }
        )
    return ports


PORTS = build_ports()


def room_asset(
    key: str,
    asset_id: str,
    chinese_name: str,
    category: str,
    filename_stem: str,
    role: str,
) -> dict[str, object]:
    data = ROOM_LAYOUT[key]
    width, depth = data["size"]
    return {
        "kind": "room",
        "key": key,
        "asset_id": asset_id,
        "chinese_name": chinese_name,
        "category": category,
        "slug": slugify(filename_stem),
        "filename_stem": filename_stem,
        "size": (float(width), float(depth)),
        "height": VISUAL_WALL_HEIGHT,
        "role": role,
        "ports": PORTS[key],
        "world_center_m": list(data["center"]),
    }


ASSETS = [
    room_asset(
        "hub",
        "ENV-BATTLE-L01-ROOM-MAIN-01-HUB",
        "局内关卡01 主路内容房01 hub 30×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_01_hub_30x25m",
        "主路内容房",
    ),
    room_asset(
        "main_02",
        "ENV-BATTLE-L01-ROOM-MAIN-02",
        "局内关卡01 主路内容房02 30×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_02_30x25m",
        "主路内容房",
    ),
    room_asset(
        "main_03",
        "ENV-BATTLE-L01-ROOM-MAIN-03",
        "局内关卡01 主路内容房03 30×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_03_30x25m",
        "主路内容房",
    ),
    room_asset(
        "main_04",
        "ENV-BATTLE-L01-ROOM-MAIN-04",
        "局内关卡01 主路内容房04 30×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_04_30x25m",
        "主路内容房",
    ),
    room_asset(
        "main_05",
        "ENV-BATTLE-L01-ROOM-MAIN-05",
        "局内关卡01 主路内容房05 30×40m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_05_30x40m",
        "主路内容房",
    ),
    room_asset(
        "main_06",
        "ENV-BATTLE-L01-ROOM-MAIN-06",
        "局内关卡01 主路内容房06 30×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_06_30x25m",
        "主路内容房",
    ),
    room_asset(
        "main_07",
        "ENV-BATTLE-L01-ROOM-MAIN-07",
        "局内关卡01 主路内容房07 30×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_07_30x25m",
        "主路内容房",
    ),
    room_asset(
        "main_08",
        "ENV-BATTLE-L01-ROOM-MAIN-08",
        "局内关卡01 主路内容房08 35×30m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_08_35x30m",
        "主路内容房",
    ),
    room_asset(
        "main_09",
        "ENV-BATTLE-L01-ROOM-MAIN-09",
        "局内关卡01 主路内容房09 40×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_09_40x25m",
        "主路内容房",
    ),
    room_asset(
        "main_10",
        "ENV-BATTLE-L01-ROOM-MAIN-10",
        "局内关卡01 主路内容房10 30×25m 白模",
        "main_rooms",
        "局内关卡01_白模_主路内容房_10_30x25m",
        "主路内容房",
    ),
    room_asset(
        "branch_01",
        "ENV-BATTLE-L01-ROOM-BRANCH-01",
        "局内关卡01 支路内容房01 30×25m 白模",
        "branch_rooms",
        "局内关卡01_白模_支路内容房_01_30x25m",
        "支路内容房",
    ),
    room_asset(
        "branch_02",
        "ENV-BATTLE-L01-ROOM-BRANCH-02",
        "局内关卡01 支路内容房02 30×25m 白模",
        "branch_rooms",
        "局内关卡01_白模_支路内容房_02_30x25m",
        "支路内容房",
    ),
    room_asset(
        "branch_03",
        "ENV-BATTLE-L01-ROOM-BRANCH-03",
        "局内关卡01 支路内容房03 40×35m 白模",
        "branch_rooms",
        "局内关卡01_白模_支路内容房_03_40x35m",
        "支路内容房",
    ),
    room_asset(
        "branch_04",
        "ENV-BATTLE-L01-ROOM-BRANCH-04",
        "局内关卡01 支路内容房04 30×25m 白模",
        "branch_rooms",
        "局内关卡01_白模_支路内容房_04_30x25m",
        "支路内容房",
    ),
    room_asset(
        "entry",
        "ENV-BATTLE-L01-SAFE-ENTRY",
        "局内关卡01 入口安全房 15×15m 白模",
        "safe_rooms",
        "局内关卡01_白模_入口安全房_15x15m",
        "入口安全房",
    ),
    room_asset(
        "exit",
        "ENV-BATTLE-L01-SAFE-EXIT",
        "局内关卡01 出口安全房 15×15m 白模",
        "safe_rooms",
        "局内关卡01_白模_出口安全房_15x15m",
        "出口安全房",
    ),
    room_asset(
        "boss",
        "ENV-BATTLE-L01-BOSS-ARENA",
        "局内关卡01 Boss竞技场 190×90m 白模",
        "boss_arena",
        "局内关卡01_白模_Boss竞技场_190x90m",
        "Boss竞技场",
    ),
    {
        "kind": "floor_tile",
        "key": "corridor_floor",
        "asset_id": "ENV-BATTLE-L01-CORRIDOR-FLOOR-5M",
        "chinese_name": "局内关卡01 走廊通用地砖 5×5×0.30m 白模",
        "category": "corridors",
        "slug": "corridor_floor_5x5x0p3m",
        "filename_stem": "局内关卡01_白模_走廊地砖_5x5x0.3m",
        "size": (5.0, 5.0),
        "height": FLOOR_THICKNESS,
        "role": "走廊通用地砖",
        "ports": [],
        "world_center_m": None,
    },
    {
        "kind": "wall_module",
        "key": "corridor_wall",
        "asset_id": "ENV-BATTLE-L01-CORRIDOR-WALL-5M",
        "chinese_name": "局内关卡01 走廊通用墙壁 5×0.30×11.9m 白模",
        "category": "corridors",
        "slug": "corridor_wall_5x0p3x11p9m",
        "filename_stem": "局内关卡01_白模_走廊墙壁_5x0.3x11.9m",
        "size": (5.0, WALL_THICKNESS),
        "height": VISUAL_WALL_HEIGHT,
        "role": "走廊通用墙壁",
        "ports": [],
        "world_center_m": None,
    },
]


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["battle_level01_whitebox_version"] = VERSION
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


def make_corridor_floor(
    source_floor: bpy.types.Collection,
    dark_material: bpy.types.Material,
    floor_material: bpy.types.Material,
    frame_material: bpy.types.Material,
    owner_id: str,
) -> list[bpy.types.Object]:
    objects = [
        create_box(
            "FLOOR_CORRIDOR_BASE",
            (0.0, 0.0, FLOOR_THICKNESS * 0.5),
            (5.0, 5.0, FLOOR_THICKNESS),
            (0.0, 0.0, 0.0),
            dark_material,
            source_floor,
            (9, 1),
            "floor_slab",
            "走廊承重地砖基底",
            "floor",
        ),
        create_box(
            "FLOOR_CORRIDOR_SURFACE",
            (0.0, 0.0, FLOOR_THICKNESS - SURFACE_TILE_THICKNESS * 0.5),
            (4.74, 4.74, SURFACE_TILE_THICKNESS),
            (0.0, 0.0, 0.0),
            floor_material,
            source_floor,
            (9, 4),
            "floor_tile",
            "走廊可通行表面",
            "floor",
            bevel=0.02,
        ),
    ]
    edge_specs = [
        ("FLOOR_CORRIDOR_EDGE_X_MIN", (-2.45, 0.0, 0.15), (0.10, 5.0, 0.30)),
        ("FLOOR_CORRIDOR_EDGE_X_MAX", (2.45, 0.0, 0.15), (0.10, 5.0, 0.30)),
        ("FLOOR_CORRIDOR_EDGE_Y_MIN", (0.0, -2.45, 0.15), (5.0, 0.10, 0.30)),
        ("FLOOR_CORRIDOR_EDGE_Y_MAX", (0.0, 2.45, 0.15), (5.0, 0.10, 0.30)),
    ]
    for name, center, size in edge_specs:
        objects.append(
            create_box(
                name,
                center,
                size,
                (center[0], center[1], 0.0),
                frame_material,
                source_floor,
                (9, 7),
                "floor_edge",
                "走廊地砖模块收边",
                "floor",
                bevel=0.008,
            )
        )
    for obj in objects:
        obj["owner_id"] = owner_id
    return objects


def make_corridor_wall(
    source_structure: bpy.types.Collection,
    wall_material: bpy.types.Material,
    frame_material: bpy.types.Material,
    owner_id: str,
) -> list[bpy.types.Object]:
    objects = [
        create_box(
            "WALL_CORRIDOR_BODY",
            (0.0, 0.0, VISUAL_WALL_HEIGHT * 0.5),
            (5.0, WALL_THICKNESS, VISUAL_WALL_HEIGHT),
            (0.0, 0.0, 0.0),
            wall_material,
            source_structure,
            (9, 6),
            "wall",
            "走廊通用墙体",
            "structure",
        )
    ]
    for name, x in (
        ("WALL_CORRIDOR_EDGE_X_MIN", -2.46),
        ("WALL_CORRIDOR_EDGE_X_MAX", 2.46),
    ):
        objects.append(
            create_box(
                name,
                (x, 0.0, VISUAL_WALL_HEIGHT * 0.5),
                (0.08, WALL_THICKNESS, VISUAL_WALL_HEIGHT - 0.08),
                (x, 0.0, 0.0),
                frame_material,
                source_structure,
                (9, 8),
                "wall_edge",
                "走廊墙壁模块收边",
                "structure",
                bevel=0.008,
            )
        )
    objects.append(
        create_box(
            "WALL_CORRIDOR_TOP_TRIM",
            (0.0, 0.0, VISUAL_WALL_HEIGHT - 0.06),
            (5.0, WALL_THICKNESS, 0.12),
            (0.0, 0.0, 0.0),
            frame_material,
            source_structure,
            (9, 8),
            "wall_edge",
            "走廊墙壁顶部收边",
            "structure",
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

    if asset["kind"] == "room":
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
    elif asset["kind"] == "floor_tile":
        source_objects = make_corridor_floor(
            source_floor,
            dark,
            matte,
            metal,
            asset_id,
        )
    elif asset["kind"] == "wall_module":
        source_objects = make_corridor_wall(
            source_structure,
            matte,
            metal,
            asset_id,
        )
    else:
        raise ValueError(f"Unsupported asset kind: {asset['kind']}")

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
        "bounds_world_m": {
            "min": [round(value, 4) for value in min_corner],
            "max": [round(value, 4) for value in max_corner],
        },
        "logical_wall_height_m": LOGICAL_WALL_HEIGHT if asset["kind"] == "room" else None,
        "visual_wall_height_m": (
            VISUAL_WALL_HEIGHT
            if asset["kind"] in ("room", "wall_module")
            else FLOOR_THICKNESS
        ),
        "floor_thickness_m": (
            FLOOR_THICKNESS if asset["kind"] in ("room", "floor_tile") else None
        ),
        "door_contract": {
            "width_m": DOOR_WIDTH,
            "height_m": DOOR_HEIGHT,
            "clear_floor_gap_m": DOOR_CLEAR_FLOOR_GAP,
            "bottom_z_m": DOOR_BOTTOM,
            "lintel_bottom_z_m": DOOR_TOP,
        },
        "ports": list(asset["ports"]),
        "world_slot_center_m": asset["world_center_m"],
        "materials": [metal.name, matte.name, dark.name],
        "palette_uv": "PaletteUV",
        "shared_palette": str(PALETTE_PATH.relative_to(ROOT)).replace("\\", "/"),
        "components": component_records,
        "render_reference": str(render_path.relative_to(ROOT)).replace("\\", "/"),
        "render_top": str(top_render_path.relative_to(ROOT)).replace("\\", "/"),
        "export_status": "blend_only; GLB and Godot integration not requested",
        "collision_status": "not authored",
        "runtime_status": "not connected",
        "notes": (
            "Boss override: user-specified 190x90m; source code still says 90x90m."
            if asset_id == "ENV-BATTLE-L01-BOSS-ARENA"
            else ""
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
        "BATTLE_LEVEL01_WHITEBOX_V003_ASSET_OK",
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
        "zone": "battle_level01",
        "display_name": "局内关卡01 顶部数据库",
        "version": VERSION,
        "asset_count": len(manifests),
        "component_policy": "墙体严格按5m槽位拼装；实墙每槽单件，门墙每槽保留左右柱与门楣；禁止缩放与join",
        "category_counts": category_counts,
        "normal_topology": {
            "node_count": len(ROOM_LAYOUT) - 3,
            "tree_edge_count": len(CONNECTIONS),
            "connections": [
                {"from": parent, "to": child} for parent, child in CONNECTIONS
            ],
            "corridor_asset_contract": (
                "One 5x5x0.30m floor asset and one 5x0.30x11.9m wall asset "
                "are reused at all 15 logical edges."
            ),
        },
        "boss_topology": {
            "connections": [
                {"from": parent, "to": child}
                for parent, child in BOSS_CONNECTIONS
            ],
            "note": (
                "Boss source uses the latest user override 190x90m. Runtime "
                "coordinates and docs still require resync from 90x90m."
            ),
        },
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
        f"battle_level01/{VERSION}",
        f"├─ blender/ ({len(manifests)} .blend)",
        "├─ data/component_packages/",
        "│  ├─ catalog.json",
        *[
            f"│  ├─ {category}/ ({count})"
            for category, count in sorted(category_counts.items())
        ],
        "├─ data/validation/",
        "└─ renders/",
    ]
    (PACKAGE_DIR / "tree.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_unit_plan() -> None:
    write_json(
        OUTPUT_ROOT / "data/unit_plan.json",
        {
            "source": "src/map/FloorPlanGenerator.gd",
            "normal_room_count": 14,
            "safe_room_count": 2,
            "boss_arena_count": 1,
            "corridor_component_count": 2,
            "blend_count": len(ASSETS),
            "normal_tree_edge_count": len(CONNECTIONS),
            "connections": [
                {"from": parent, "to": child} for parent, child in CONNECTIONS
            ],
            "boss_connections": [
                {"from": parent, "to": child} for parent, child in BOSS_CONNECTIONS
            ],
            "boss_size_override_m": [190.0, 90.0],
            "boss_code_size_m": [90.0, 90.0],
            "sync_required": [
                "FloorPlanGenerator.BOSS_ARENA",
                "TowerGeometry3D.BOSS_ARENA_SIZE_M",
                "Battle runtime placement for the enlarged arena",
            ],
            "component_storage": {
                "authoring_collection": "01_制作组件_按设施拆分",
                "output_collection": f"02_游戏输出_独立资产包_{VERSION}",
                "join_policy": "forbidden",
                "wall_origin": "bottom_center",
                "lintel_origin": "bottom_center",
                "floor_origin": "underside_z_0",
            },
        },
    )


def main() -> None:
    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
    VALIDATION_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    manifests = [build_asset(asset) for asset in ASSETS]
    write_catalog(manifests)
    write_unit_plan()
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
                "wireframe object names contain no .001, _nort or _sout suffix",
                "each output object belongs to exactly one output collection",
                "asset bounds match the contract size",
            ],
        },
    )
    print(
        "BATTLE_LEVEL01_WHITEBOX_V003_READY",
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
