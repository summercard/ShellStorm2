"""Build the Battle level 01 room and corridor whitebox package.

Run with:
    blender --background --python scripts/blender/build_battle_level01_whitebox_v001.py

The script creates one maintainable .blend per room slot. Room envelopes are
centered on X/Y with the floor underside at Z=0. Wall visuals use the Battle
contract of 12 m logical height and 11.9 m visible height.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = ROOT / "source/art/whitebox/tower_zones/battle_level01/v001"
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
    ports: dict[str, list[dict[str, object]]] = {
        key: [] for key in ROOM_LAYOUT
    }
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
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["battle_level01_whitebox_version"] = VERSION
    scene["battle_logical_wall_height_m"] = LOGICAL_WALL_HEIGHT
    scene["battle_visual_wall_height_m"] = VISUAL_WALL_HEIGHT


def make_material(name: str, metallic: float, roughness: float, palette_cell: tuple[int, int]):
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
    location: tuple[float, float, float],
    size: tuple[float, float, float],
    material: bpy.types.Material,
    source_collection: bpy.types.Collection,
    palette_cell: tuple[int, int],
    bevel: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("白模小倒角", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    source_collection.objects.link(obj)
    obj.data.materials.append(material)
    assign_palette_uv(obj, palette_cell)
    return obj


def create_floor_grid(
    width: float,
    depth: float,
    source_collection: bpy.types.Collection,
    dark_material: bpy.types.Material,
    floor_material: bpy.types.Material,
    prefix: str,
) -> list[bpy.types.Object]:
    objects: list[bpy.types.Object] = []
    objects.append(
        create_box(
            f"{prefix}_基底_250mm",
            (0.0, 0.0, FLOOR_THICKNESS * 0.5 - 0.01),
            (width, depth, FLOOR_THICKNESS - 0.04),
            dark_material,
            source_collection,
            (9, 1),
        )
    )
    count_x = int(round(width / GRID_UNIT))
    count_y = int(round(depth / GRID_UNIT))
    for row in range(count_y):
        for column in range(count_x):
            center_x = -width * 0.5 + GRID_UNIT * (column + 0.5)
            center_y = -depth * 0.5 + GRID_UNIT * (row + 0.5)
            objects.append(
                create_box(
                    f"{prefix}_地砖_{row + 1:02d}_{column + 1:02d}",
                    (center_x, center_y, FLOOR_THICKNESS - 0.02),
                    (GRID_UNIT - 0.06, GRID_UNIT - 0.06, 0.04),
                    floor_material,
                    source_collection,
                    (9, 4),
                    bevel=0.018,
                )
            )
    return objects


def wall_segments_for_side(
    side: str,
    width: float,
    depth: float,
    door: dict[str, object] | None,
) -> list[tuple[tuple[float, float, float], tuple[float, float, float]]]:
    wall_z_bottom = 0.0
    wall_z_top = VISUAL_WALL_HEIGHT
    wall_center_z = (wall_z_bottom + wall_z_top) * 0.5

    if side in ("north", "south"):
        lateral_size = width
        wall_y = (depth - WALL_THICKNESS) * 0.5
        if side == "south":
            wall_y *= -1.0
        if door is None:
            return [((0.0, wall_y, wall_center_z), (width, WALL_THICKNESS, VISUAL_WALL_HEIGHT))]

        opening_center = float(door["offset_m"])
        half_clear = width * 0.5 - DOOR_WIDTH * 0.5
        opening_center = max(-half_clear, min(half_clear, opening_center))
        left_edge = -width * 0.5
        right_edge = width * 0.5
        opening_left = opening_center - DOOR_WIDTH * 0.5
        opening_right = opening_center + DOOR_WIDTH * 0.5
        segments = []
        if opening_left > left_edge:
            segment_width = opening_left - left_edge
            segments.append(
                (
                    (left_edge + segment_width * 0.5, wall_y, wall_center_z),
                    (segment_width, WALL_THICKNESS, VISUAL_WALL_HEIGHT),
                )
            )
        if right_edge > opening_right:
            segment_width = right_edge - opening_right
            segments.append(
                (
                    (opening_right + segment_width * 0.5, wall_y, wall_center_z),
                    (segment_width, WALL_THICKNESS, VISUAL_WALL_HEIGHT),
                )
            )
        lintel_bottom = FLOOR_THICKNESS + DOOR_CLEAR_FLOOR_GAP + DOOR_HEIGHT
        lintel_height = VISUAL_WALL_HEIGHT - lintel_bottom
        segments.append(
            (
                (
                    opening_center,
                    wall_y,
                    lintel_bottom + lintel_height * 0.5,
                ),
                (DOOR_WIDTH, WALL_THICKNESS, lintel_height),
            )
        )
        return segments

    lateral_size = depth
    wall_x = (width - WALL_THICKNESS) * 0.5
    if side == "west":
        wall_x *= -1.0
    if door is None:
        return [((wall_x, 0.0, wall_center_z), (WALL_THICKNESS, depth, VISUAL_WALL_HEIGHT))]

    opening_center = float(door["offset_m"])
    half_clear = depth * 0.5 - DOOR_WIDTH * 0.5
    opening_center = max(-half_clear, min(half_clear, opening_center))
    bottom_edge = -depth * 0.5
    top_edge = depth * 0.5
    opening_bottom = opening_center - DOOR_WIDTH * 0.5
    opening_top = opening_center + DOOR_WIDTH * 0.5
    segments = []
    if opening_bottom > bottom_edge:
        segment_depth = opening_bottom - bottom_edge
        segments.append(
            (
                (wall_x, bottom_edge + segment_depth * 0.5, wall_center_z),
                (WALL_THICKNESS, segment_depth, VISUAL_WALL_HEIGHT),
            )
        )
    if top_edge > opening_top:
        segment_depth = top_edge - opening_top
        segments.append(
            (
                (wall_x, opening_top + segment_depth * 0.5, wall_center_z),
                (WALL_THICKNESS, segment_depth, VISUAL_WALL_HEIGHT),
            )
        )
    lintel_bottom = FLOOR_THICKNESS + DOOR_CLEAR_FLOOR_GAP + DOOR_HEIGHT
    lintel_height = VISUAL_WALL_HEIGHT - lintel_bottom
    segments.append(
        (
            (wall_x, opening_center, lintel_bottom + lintel_height * 0.5),
            (WALL_THICKNESS, DOOR_WIDTH, lintel_height),
        )
    )
    return segments


def create_room_shell(
    width: float,
    depth: float,
    ports: list[dict[str, object]],
    source_collection: bpy.types.Collection,
    dark_material: bpy.types.Material,
    floor_material: bpy.types.Material,
    wall_material: bpy.types.Material,
    prefix: str,
) -> list[bpy.types.Object]:
    objects = create_floor_grid(
        width,
        depth,
        source_collection,
        dark_material,
        floor_material,
        prefix,
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
        side_ports = doors_by_side[side]
        if len(side_ports) > 2:
            raise RuntimeError(f"{prefix}: more than two doors on {side}")
        if not side_ports:
            segments = wall_segments_for_side(side, width, depth, None)
            for segment_index, (location, size) in enumerate(segments):
                objects.append(
                    create_box(
                        f"{prefix}_墙体_{side}_U{segment_index + 1:02d}",
                        location,
                        size,
                        wall_material,
                        source_collection,
                        (9, 6),
                    )
                )
            continue

        # A room never has more than two linked doors on one side in this plan.
        # If it does, merge the opening spans into one clear zone rather than
        # accidentally creating overlapping wall segments.
        if len(side_ports) == 1:
            opening = side_ports[0]
        else:
            ordered = sorted(side_ports, key=lambda item: float(item["offset_m"]))
            opening = {
                "side": side,
                "offset_m": (
                    float(ordered[0]["offset_m"]) + float(ordered[1]["offset_m"])
                )
                * 0.5,
            }
        segments = wall_segments_for_side(side, width, depth, opening)
        for segment_index, (location, size) in enumerate(segments):
            objects.append(
                create_box(
                    f"{prefix}_墙体_{side}_门洞段{segment_index + 1:02d}",
                    location,
                    size,
                    wall_material,
                    source_collection,
                    (9, 6),
                )
            )
    return objects


def make_corridor_floor(
    source_collection: bpy.types.Collection,
    dark_material: bpy.types.Material,
    floor_material: bpy.types.Material,
    frame_material: bpy.types.Material,
) -> list[bpy.types.Object]:
    objects = [
        create_box(
            "走廊地砖_基底",
            (0.0, 0.0, 0.14),
            (5.0, 5.0, 0.28),
            dark_material,
            source_collection,
            (9, 1),
        ),
        create_box(
            "走廊地砖_通行面",
            (0.0, 0.0, 0.29),
            (4.74, 4.74, 0.02),
            floor_material,
            source_collection,
            (9, 4),
            bevel=0.02,
        ),
    ]
    for x in (-2.45, 2.45):
        objects.append(
            create_box(
                "走廊地砖_收边",
                (x, 0.0, 0.15),
                (0.10, 5.0, 0.30),
                frame_material,
                source_collection,
                (9, 7),
                bevel=0.008,
            )
        )
    for y in (-2.45, 2.45):
        objects.append(
            create_box(
                "走廊地砖_收边",
                (0.0, y, 0.15),
                (5.0, 0.10, 0.30),
                frame_material,
                source_collection,
                (9, 7),
                bevel=0.008,
            )
        )
    return objects


def make_corridor_wall(
    source_collection: bpy.types.Collection,
    wall_material: bpy.types.Material,
    frame_material: bpy.types.Material,
) -> list[bpy.types.Object]:
    objects = [
        create_box(
            "走廊墙壁_主体",
            (0.0, 0.0, VISUAL_WALL_HEIGHT * 0.5),
            (5.0, WALL_THICKNESS, VISUAL_WALL_HEIGHT),
            wall_material,
            source_collection,
            (9, 6),
        )
    ]
    for x in (-2.46, 2.46):
        objects.append(
            create_box(
                "走廊墙壁_模块收边",
                (x, 0.0, VISUAL_WALL_HEIGHT * 0.5),
                (0.08, WALL_THICKNESS + 0.02, VISUAL_WALL_HEIGHT - 0.08),
                frame_material,
                source_collection,
                (9, 8),
                bevel=0.008,
            )
        )
    objects.append(
        create_box(
            "走廊墙壁_顶部收边",
            (0.0, 0.0, VISUAL_WALL_HEIGHT - 0.06),
            (5.0, WALL_THICKNESS + 0.02, 0.12),
            frame_material,
            source_collection,
            (9, 8),
        )
    )
    return objects


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


def merge_game_output(
    objects: list[bpy.types.Object],
    output_collection: bpy.types.Collection,
    object_name: str,
) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for obj in objects:
        clone = obj.copy()
        clone.data = obj.data.copy()
        output_collection.objects.link(clone)
        clone.select_set(True)
        copies.append(clone)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = object_name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    for polygon in merged.data.polygons:
        polygon.use_smooth = False
    return merged


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
    source_collection = bpy.data.collections.new("01_制作组件_已统一材质")
    output_collection = bpy.data.collections.new("02_游戏输出_整合模型")
    preview_collection = bpy.data.collections.new("90_展示环境_灯光相机")
    root_collection.children.link(source_collection)
    root_collection.children.link(output_collection)
    root_collection.children.link(preview_collection)

    metal = make_material("01_精工金属_白模框架", 0.82, 0.30, (9, 7))
    matte = make_material("02_细腻哑光_白模体块", 0.03, 0.72, (9, 5))
    dark = make_material("03_精细哑光_白模底色", 0.02, 0.78, (9, 2))

    if asset["kind"] == "room":
        components = create_room_shell(
            size[0],
            size[1],
            list(asset["ports"]),
            source_collection,
            dark,
            matte,
            metal,
            asset_name,
        )
        output_name = f"{asset_name}_主体"
    elif asset["kind"] == "floor_tile":
        components = make_corridor_floor(
            source_collection,
            dark,
            matte,
            metal,
        )
        output_name = "走廊地砖_5m_主体"
    elif asset["kind"] == "wall_module":
        components = make_corridor_wall(
            source_collection,
            matte,
            metal,
        )
        output_name = "走廊墙壁_5m_主体"
    else:
        raise ValueError(f"Unsupported asset kind: {asset['kind']}")

    source_collection.hide_viewport = True
    source_collection.hide_render = True
    merged = merge_game_output(components, output_collection, output_name)
    reference_camera, top_camera = setup_preview(size, height, preview_collection)
    configure_render(scene)
    scene.camera = reference_camera

    merged["asset_id"] = asset_id
    merged["asset_version"] = VERSION
    merged["asset_role"] = str(asset["role"])
    merged["dimensions_m"] = [round(size[0], 3), round(size[1], 3), round(height, 3)]
    merged["logical_wall_height_m"] = LOGICAL_WALL_HEIGHT if asset["kind"] == "room" else 0.0
    merged["visual_wall_height_m"] = (
        VISUAL_WALL_HEIGHT
        if asset["kind"] in ("room", "wall_module")
        else FLOOR_THICKNESS
    )
    merged["door_contract"] = {
        "width_m": DOOR_WIDTH,
        "height_m": DOOR_HEIGHT,
        "bottom_at_floor_top": True,
    }
    merged["ports"] = list(asset["ports"])
    if asset_id == "ENV-BATTLE-L01-BOSS-ARENA":
        merged["contract_override"] = (
            "User override 190x90m. Code and docs still declare 90x90m; "
            "runtime placement and exit safe-room coordinates require resync."
        )

    blend_path = BLEND_DIR / f"{filename_stem}_{VERSION}.blend"
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    render_path = RENDER_DIR / f"{filename_stem}_{VERSION}_参考.png"
    top_render_path = RENDER_DIR / f"{filename_stem}_{VERSION}_俯视.png"
    RENDER_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    scene.camera = reference_camera
    scene.render.filepath = str(render_path)
    bpy.ops.render.render(write_still=True)
    scene.camera = top_camera
    scene.render.filepath = str(top_render_path)
    bpy.ops.render.render(write_still=True)
    scene.camera = reference_camera
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    bounds = [merged.matrix_world @ Vector(corner) for corner in merged.bound_box]
    min_corner = Vector(
        (
            min(point.x for point in bounds),
            min(point.y for point in bounds),
            min(point.z for point in bounds),
        )
    )
    max_corner = Vector(
        (
            max(point.x for point in bounds),
            max(point.y for point in bounds),
            max(point.z for point in bounds),
        )
    )
    triangle_count = sum(len(polygon.vertices) - 2 for polygon in merged.data.polygons)
    manifest = {
        "asset_id": asset_id,
        "name_zh": asset_name,
        "slug": asset["slug"],
        "category": category,
        "role": asset["role"],
        "version": VERSION,
        "source_blend": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
        "blender_collection": root_collection.name,
        "output_collection": output_collection.name,
        "objects": [merged.name],
        "root_object": merged.name,
        "origin": "center_x_y; floor_bottom_z_0",
        "front": "Godot -Z",
        "dimensions_m": [round(size[0], 3), round(size[1], 3), round(height, 3)],
        "bounds_local_m": {
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
        },
        "ports": list(asset["ports"]),
        "world_slot_center_m": asset["world_center_m"],
        "materials": [metal.name, matte.name, dark.name],
        "palette_uv": "PaletteUV",
        "shared_palette": str(PALETTE_PATH.relative_to(ROOT)).replace("\\", "/"),
        "triangles": triangle_count,
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
    print(
        "BATTLE_LEVEL01_WHITEBOX_ASSET_OK",
        json.dumps(
            {
                "asset_id": asset_id,
                "blend": str(blend_path),
                "triangles": triangle_count,
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
        "category_counts": category_counts,
        "normal_topology": {
            "node_count": len(ROOM_LAYOUT) - 3,
            "tree_edge_count": len(CONNECTIONS),
            "connections": [
                {"from": parent, "to": child} for parent, child in CONNECTIONS
            ],
            "corridor_asset_contract": (
                "One 5x5x0.30m floor tile and one 5x0.30x11.9m wall module "
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
            }
            for manifest in manifests
        ],
    }
    write_json(PACKAGE_DIR / "catalog.json", catalog)

    lines = [
        "battle_level01/v001",
        f"├─ blender/ ({len(manifests)} .blend)",
        "├─ data/component_packages/",
        f"│  ├─ catalog.json",
        *[
            f"│  ├─ {category}/ ({count})"
            for category, count in sorted(category_counts.items())
        ],
        "├─ data/validation/",
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
    write_json(
        OUTPUT_ROOT / "data/unit_plan.json",
        {
            "source": "src/map/FloorPlanGenerator.gd",
            "normal_room_count": 14,
            "safe_room_count": 2,
            "boss_arena_count": 1,
            "corridor_component_count": 2,
            "blend_count": len(manifests),
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
        },
    )
    print(
        "BATTLE_LEVEL01_WHITEBOX_READY",
        json.dumps(
            {
                "assets": len(manifests),
                "output": str(OUTPUT_ROOT),
                "package_catalog": str(PACKAGE_DIR / "catalog.json"),
            },
            ensure_ascii=False,
        ),
    )


if __name__ == "__main__":
    main()
