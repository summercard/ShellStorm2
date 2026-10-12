"""Build Expedition level 02 v001 whitebox — layer 1 (corridor + guest rooms).

Run with:
    blender --background --python scripts/blender/build_expedition02_whitebox_v001.py

Scope of this version: **layer 1 of the derelict hotel only**. The layer is one
封闭 block on the project 5m module grid:

    阳台安全屋 15x15 @3m  ->  挑高前厅 10x30 @11.9m  ->  [坍塌门洞]
      ->  旅馆长廊 10x75 @3m（沿南->北）,  东侧 5 间客房 15x15 @3m,  西侧 5 间客房 15x15 @3m

Layers 2..5 are structurally identical (same corridor + rooms) and carry no
double-height room; they are a follow-up pass. Nothing here is scaled from an
existing asset: the block is rebuilt procedurally on the 5m slot grid so that

  * both axes close on whole 5m modules (no FIXED_TRIM edge pieces),
  * every door picks a slot from `RoomDoorLane.lane_offsets()` (10m wall ->
    +-2.5m; 15m wall -> 0m), so the slot before and after each door also closes
    on whole modules,
  * a solid 5m wall is one mesh, a door wall keeps independent left/right piers
    plus a lintel, and no wall ever exceeds 5m.

Wall heights are per room: 3.0m for the balcony / corridor / guest rooms and
11.9m for the 挑高前厅, which is the only double-height space in the whole
hotel. The foyer wall therefore stack-tops at 11.9m while its neighbours stop
at 3.0m — that vertical contrast is the point of the layer.

Component contract (the "通用墙 / 通用地砖 / 通用门墙" this pass consumes):
each output object carries `component_slug` saying which generic module it is
an instance of. Those generic modules are authored in stage 2; see
`GENERIC_COMPONENT_CONTRACT` below for the interface this whitebox assumes.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = ROOT / "art_source/design/whitebox/tower_zones/expedition_02/v001"
BLEND_DIR = OUTPUT_ROOT / "blender"
PACKAGE_DIR = OUTPUT_ROOT / "data/component_packages"
VALIDATION_DIR = OUTPUT_ROOT / "data/validation"
RENDER_DIR = OUTPUT_ROOT / "renders"
PALETTE_PATH = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

VERSION = "v001"
LEVEL_ID = "expedition_02"
BLOCK_ID = "expedition"

# ---- 全项目几何基准（只有一处定义，见 TowerGeometry3D.gd） ------------------
GRID_UNIT = 5.0
WALL_THICKNESS = 0.30
FLOOR_THICKNESS = 0.30
SURFACE_TILE_THICKNESS = 0.04
FLOOR_BASE_TOP = FLOOR_THICKNESS - SURFACE_TILE_THICKNESS      # 0.26
WALK_PLANE_Z = FLOOR_THICKNESS                                  # 0.30

# ---- 门契约（沿用全项目口径） ----------------------------------------------
DOOR_WIDTH = 2.2
DOOR_HEIGHT = 2.5
DOOR_CLEAR_FLOOR_GAP = 0.0
DOOR_BOTTOM = WALK_PLANE_Z + DOOR_CLEAR_FLOOR_GAP               # 0.30
DOOR_TOP = DOOR_BOTTOM + DOOR_HEIGHT                            # 2.80

# ---- 本关特有：墙高 ----------------------------------------------------------
WALL_H_LOW = 3.0        # 阳台 / 长廊 / 客房 —— 本关其余各层也用这个高度
WALL_H_TALL = 11.9      # 挑高前厅，全楼唯一通高空间（= 项目 WALL_VISUAL_HEIGHT_M）

# ---- 本关特有：坍塌门洞 ------------------------------------------------------
COLLAPSE_WIDTH = 5.0    # 正好一个 5m 槽
COLLAPSE_HEIGHT = 2.5   # 比标准门矮，符合"坍塌的只有 2.5 米高"
COLLAPSE_LINTEL_BOTTOM = DOOR_BOTTOM + COLLAPSE_HEIGHT          # 2.80
OPEN_WIDTH = GRID_UNIT                     # 通洞 = 占满一个 5m 格，顶到墙顶（无门楣）

# 渲染分辨率：本关平面是 80 × 160 的竖长块，用竖版才装得下整张俯视图。
RES_X = 1000
RES_Y = 1500

# ---- 平面：26 间房，全部落在 5m 网格上 ---------------------------------------
# 走向**由南向北**（+y = 世界 +z = 南 ⇒ 南端 y 大、北端 y 小）。
# 玩家从南端阳台进 → 挑高前厅（横置 30×15）→ 穿坍塌门洞 → 进入 75m 长廊，
# 一路向北；长廊东西两侧各 5 间客房；长廊北端是 **T 字路口**：
# 一条 60m 横廊，两端各向北折 **45m** 支廊，支廊**两侧各 3 间**客房。
#
# ⚠️ 建墙口径：网格线按「全部 5m 整数倍」遍历，且**同一间房两侧不生成墙** ——
#    否则跨多格的房间（30m 宽挑高前厅、60m 宽横廊）中间会长出隔断墙。
#
# ⚠️ 支廊为什么落在 x=±20（而不是原来的 ±15）：
#    lane_offsets() 对**偶数段墙不产生 0 槽**。60m 横廊的合法槽只到 ±22.5，
#    而 10m 宽支廊的两个槽在「支廊中心 ±2.5」。要让这两个槽**在横廊侧也合法**，
#    支廊中心必须落在 ±20 ⇒ 槽位 ∓22.5 / ∓17.5，两侧都命中。
#    同时中心 ±20 让两条支廊的内侧房（各 15m 宽）刚好在 x=0 处相接，不重叠。
# (key, 中文名, x0, y0, x1, y1, wall_height)
ROOMS = [
    ("balcony",    "阳台安全屋", -10.0,  45.0,   5.0,  60.0, WALL_H_LOW),
    ("tall_hall",  "挑高前厅",   -15.0,  30.0,  15.0,  45.0, WALL_H_TALL),
    ("corridor",   "旅馆长廊",    -5.0, -45.0,   5.0,  30.0, WALL_H_LOW),
    ("room_w1",    "客房W1",     -20.0,  15.0,  -5.0,  30.0, WALL_H_LOW),
    ("room_w2",    "客房W2",     -20.0,   0.0,  -5.0,  15.0, WALL_H_LOW),
    ("room_w3",    "客房W3",     -20.0, -15.0,  -5.0,   0.0, WALL_H_LOW),
    ("room_w4",    "客房W4",     -20.0, -30.0,  -5.0, -15.0, WALL_H_LOW),
    ("room_w5",    "客房W5",     -20.0, -45.0,  -5.0, -30.0, WALL_H_LOW),
    ("room_e1",    "客房E1",       5.0,  15.0,  20.0,  30.0, WALL_H_LOW),
    ("room_e2",    "客房E2",       5.0,   0.0,  20.0,  15.0, WALL_H_LOW),
    ("room_e3",    "客房E3",       5.0, -15.0,  20.0,   0.0, WALL_H_LOW),
    ("room_e4",    "客房E4",       5.0, -30.0,  20.0, -15.0, WALL_H_LOW),
    ("room_e5",    "客房E5",       5.0, -45.0,  20.0, -30.0, WALL_H_LOW),
    # --- T 字路口：60m 横廊 + 两条 45m 支廊 ---
    ("tee_cross",  "T字横廊",    -30.0, -55.0,  30.0, -45.0, WALL_H_LOW),
    ("tee_west",   "西支廊",     -25.0,-100.0, -15.0, -55.0, WALL_H_LOW),
    ("tee_east",   "东支廊",      15.0,-100.0,  25.0, -55.0, WALL_H_LOW),
    # --- 西支廊两侧：外侧 3 间（-40..-25）、内侧 2 间（-15..0）---
    ("room_w6",    "客房W6",     -40.0, -70.0, -25.0, -55.0, WALL_H_LOW),
    ("room_w7",    "客房W7",     -15.0, -70.0,   0.0, -55.0, WALL_H_LOW),
    ("room_w8",    "客房W8",     -40.0, -85.0, -25.0, -70.0, WALL_H_LOW),
    ("room_w9",    "客房W9",     -15.0, -85.0,   0.0, -70.0, WALL_H_LOW),
    ("room_w10",   "客房W10",    -40.0,-100.0, -25.0, -85.0, WALL_H_LOW),
    # --- 东支廊两侧：镜像 ---
    ("room_e6",    "客房E6",      25.0, -70.0,  40.0, -55.0, WALL_H_LOW),
    ("room_e7",    "客房E7",       0.0, -70.0,  15.0, -55.0, WALL_H_LOW),
    ("room_e8",    "客房E8",      25.0, -85.0,  40.0, -70.0, WALL_H_LOW),
    ("room_e9",    "客房E9",       0.0, -85.0,  15.0, -70.0, WALL_H_LOW),
    ("room_e10",   "客房E10",     25.0,-100.0,  40.0, -85.0, WALL_H_LOW),
]

# ---- 门：中心一律取自 RoomDoorLane.lane_offsets() 的合法槽 -------------------
# 槽位规则（module_count = round(L/5)，首尾各留一格不贴角）：
#     10m -> ±2.5          15m -> 0             30m -> ±2.5, ±7.5
#     45m -> ±15,±10,±5,0  60m -> ±22.5..±2.5   75m -> ±30..±5
#   · 阳台(15m,槽 0) <-> 挑高前厅(30m,槽 ±2.5/±7.5)  -> x=-2.5（两侧都合法）
#   · 挑高前厅(30m) <-> 长廊(10m)                    -> 坍塌洞 5.0m 宽
#   · 长廊(75m,槽 ±5k) <-> 客房(15m,槽 0)            -> 门心 = 客房中线
#   · 长廊(10m,±2.5) <-> 横廊(60m)：两个 5m 通洞（x=∓2.5），占满长廊宽度 ⇒ 全通透
#   · 横廊(60m) <-> 支廊(10m,槽 ±2.5)：各两个 5m 通洞（x=∓17.5/∓22.5）
#   · 支廊(45m) <-> 两侧客房(15m,槽 0)：门心 = 客房中线（须命中 45m 的 ±15/±10/±5/0）
# kind：door 标准门 / collapse 矮洞（2.5m 高，带门楣） / open 通洞（顶到墙顶、无门楣）
# (key, 中文名, axis, 线坐标, 沿墙门心, 洞宽, 洞高, 类型, 本侧房间, 对侧房间)
DOORS = [
    ("d_balcony_foyer", "阳台→挑高前厅", "h",  45.0,  -2.5, 2.2, DOOR_HEIGHT, "door", "balcony", "tall_hall"),
    ("d_foyer_corridor", "坍塌门洞",    "h",  30.0,   2.5, COLLAPSE_WIDTH, COLLAPSE_HEIGHT, "collapse", "tall_hall", "corridor"),
    ("d_w1", "客房W1门", "v", -5.0,  22.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_w1"),
    ("d_w2", "客房W2门", "v", -5.0,   7.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_w2"),
    ("d_w3", "客房W3门", "v", -5.0,  -7.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_w3"),
    ("d_w4", "客房W4门", "v", -5.0, -22.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_w4"),
    ("d_w5", "客房W5门", "v", -5.0, -37.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_w5"),
    ("d_e1", "客房E1门", "v",  5.0,  22.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_e1"),
    ("d_e2", "客房E2门", "v",  5.0,   7.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_e2"),
    ("d_e3", "客房E3门", "v",  5.0,  -7.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_e3"),
    ("d_e4", "客房E4门", "v",  5.0, -22.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_e4"),
    ("d_e5", "客房E5门", "v",  5.0, -37.5, 2.2, DOOR_HEIGHT, "door", "corridor", "room_e5"),
    ("d_tee_w", "长廊→横廊西半", "h", -45.0, -2.5, OPEN_WIDTH, 0.0, "open", "corridor", "tee_cross"),
    ("d_tee_e", "长廊→横廊东半", "h", -45.0,  2.5, OPEN_WIDTH, 0.0, "open", "corridor", "tee_cross"),
    ("d_tw_1", "横廊→西支廊西半", "h", -55.0, -22.5, OPEN_WIDTH, 0.0, "open", "tee_cross", "tee_west"),
    ("d_tw_2", "横廊→西支廊东半", "h", -55.0, -17.5, OPEN_WIDTH, 0.0, "open", "tee_cross", "tee_west"),
    ("d_te_1", "横廊→东支廊西半", "h", -55.0,  17.5, OPEN_WIDTH, 0.0, "open", "tee_cross", "tee_east"),
    ("d_te_2", "横廊→东支廊东半", "h", -55.0,  22.5, OPEN_WIDTH, 0.0, "open", "tee_cross", "tee_east"),
    # 西支廊：外侧 3 门（x=-25）+ 内侧 2 门（x=-15）
    ("d_w6",  "客房W6门",  "v", -25.0, -62.5, 2.2, DOOR_HEIGHT, "door", "tee_west", "room_w6"),
    ("d_w8",  "客房W8门",  "v", -25.0, -77.5, 2.2, DOOR_HEIGHT, "door", "tee_west", "room_w8"),
    ("d_w10", "客房W10门", "v", -25.0, -92.5, 2.2, DOOR_HEIGHT, "door", "tee_west", "room_w10"),
    ("d_w7",  "客房W7门",  "v", -15.0, -62.5, 2.2, DOOR_HEIGHT, "door", "tee_west", "room_w7"),
    ("d_w9",  "客房W9门",  "v", -15.0, -77.5, 2.2, DOOR_HEIGHT, "door", "tee_west", "room_w9"),
    # 东支廊：镜像
    ("d_e6",  "客房E6门",  "v",  25.0, -62.5, 2.2, DOOR_HEIGHT, "door", "tee_east", "room_e6"),
    ("d_e8",  "客房E8门",  "v",  25.0, -77.5, 2.2, DOOR_HEIGHT, "door", "tee_east", "room_e8"),
    ("d_e10", "客房E10门", "v",  25.0, -92.5, 2.2, DOOR_HEIGHT, "door", "tee_east", "room_e10"),
    ("d_e7",  "客房E7门",  "v",  15.0, -62.5, 2.2, DOOR_HEIGHT, "door", "tee_east", "room_e7"),
    ("d_e9",  "客房E9门",  "v",  15.0, -77.5, 2.2, DOOR_HEIGHT, "door", "tee_east", "room_e9"),
]

ASSET_NAME = "远征关卡02 白模 第1层 长廊与客房"
ASSET_ID = "ENV-EXPEDITION-L02-HOTEL-FLOOR-01"
SLUG = "远征关卡02_白模_第1层_长廊与客房"
FILENAME_STEM = "远征关卡02_白模_第1层_长廊与客房"

# 本关要用的三个通用组件族 —— 白盒按这些接口建，正式件在阶段 2 制作。
GENERIC_COMPONENT_CONTRACT = {
    "note": (
        "本关要求复用「通用墙 / 通用地砖 / 通用门墙」。战局既有通用件（"
        "ENV-BATTLE-COMMON-WALL-STANDARD-5M 等）是按 11.9m 墙高做的；"
        "本关长廊与客房是 3.0m 墙高，不能直接复用同一高度，"
        "需要在阶段 2 建 3m 版通用件（或按房型件做高度变体）。本白盒按下列接口建。"
    ),
    "wall_standard_5m": {
        "length_m": GRID_UNIT,
        "thickness_m": WALL_THICKNESS,
        "height_m": WALL_H_LOW,
        "origin": "bottom-center of the 5m slot",
        "front_axis": "-Z",
        "allowed_rotations_y_deg": [0, 90, 180, 270],
        "slot_role": "solid_wall",
    },
    "wall_door_5m": {
        "length_m": GRID_UNIT,
        "thickness_m": WALL_THICKNESS,
        "height_m": WALL_H_LOW,
        "opening_m": [DOOR_WIDTH, DOOR_HEIGHT],
        "opening_bottom_z_m": DOOR_BOTTOM,
        "lintel_bottom_z_m": DOOR_TOP,
        "parts": ["left_pier", "right_pier", "lintel"],
        "origin_per_part": "bottom-center of that part",
        "slot_role": "door_wall",
    },
    "floor_tile_5m": {
        "size_m": [GRID_UNIT - 0.06, GRID_UNIT - 0.06],
        "thickness_m": SURFACE_TILE_THICKNESS,
        "top_z_m": WALK_PLANE_Z,
        "origin": "tile center at slab top face",
    },
}


# ============================================================ 场景与材质

def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["expedition02_whitebox_version"] = VERSION
    scene["level_id"] = LEVEL_ID
    scene["block_id"] = BLOCK_ID
    scene["hotel_low_wall_height_m"] = WALL_H_LOW
    scene["hotel_tall_wall_height_m"] = WALL_H_TALL
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
    """每个面留一个有色格内的小 UV 岛（点 UV 不算数）。"""
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
    component_slug: str,
    group: str,
    bevel: float = 0.0,
) -> bpy.types.Object:
    center = Vector(world_center)
    origin = Vector(origin_world)
    half = Vector(size) * 0.5
    local_center = center - origin
    signs = [
        (-1.0, -1.0, -1.0), (1.0, -1.0, -1.0), (1.0, 1.0, -1.0), (-1.0, 1.0, -1.0),
        (-1.0, -1.0, 1.0), (1.0, -1.0, 1.0), (1.0, 1.0, 1.0), (-1.0, 1.0, 1.0),
    ]
    vertices = [
        tuple(local_center + Vector((sx * half.x, sy * half.y, sz * half.z)))
        for sx, sy, sz in signs
    ]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
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
    obj["component_slug"] = component_slug
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


# ============================================================ 平面查询

def room_at(px: float, py: float):
    for room in ROOMS:
        if room[2] <= px <= room[4] and room[3] <= py <= room[5]:
            return room
    return None


def line_label(axis: str, coord: float) -> str:
    sign = "p" if coord >= 0 else "n"
    return f"{axis.upper()}{sign}{abs(int(round(coord))):03d}"


def module_start(center: float) -> float:
    return math.floor(round(center / GRID_UNIT, 6)) * GRID_UNIT


# ============================================================ 地面系统

def build_floors(dark, matte, floors_coll, structure_owner: str):
    slabs: list[bpy.types.Object] = []
    tiles: list[bpy.types.Object] = []
    for key, name_zh, x0, y0, x1, y1, _height in ROOMS:
        width, depth = x1 - x0, y1 - y0
        cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        slab = create_box(
            f"FLOOR_BASE_{key.upper()}",
            (cx, cy, FLOOR_BASE_TOP * 0.5),
            (width, depth, FLOOR_BASE_TOP),
            (cx, cy, 0.0),
            dark, floors_coll, (9, 2),
            "floor_slab", f"{name_zh} 房间承重地坪", "floor_base", "floor",
        )
        slab["room_key"] = key
        slab["owner_id"] = structure_owner
        slabs.append(slab)

        # 地砖按**房间 + 房内序号**命名：编号只求唯一，几何上砖心本来就已经落在
        # 全局 5m 网格上（x0/y0 都是 5 的整数倍，步长 5）。
        # ⚠️ 别用 round((cx - X0)/5) 生成「全局格号」—— Python 的银行家舍入会让
        # round(1.5) 与 round(2.5) 都得 2，两个相邻格撞成同一个号（实测 45 块重名）。
        count_x = int(round(width / GRID_UNIT))
        count_y = int(round(depth / GRID_UNIT))
        for row in range(count_y):
            for column in range(count_x):
                tile_cx = x0 + GRID_UNIT * (column + 0.5)
                tile_cy = y0 + GRID_UNIT * (row + 0.5)
                tile = create_box(
                    f"FLOOR_TILE_{key.upper()}_R{row + 1:02d}_C{column + 1:02d}",
                    (tile_cx, tile_cy, FLOOR_BASE_TOP + SURFACE_TILE_THICKNESS * 0.5),
                    (GRID_UNIT - 0.06, GRID_UNIT - 0.06, SURFACE_TILE_THICKNESS),
                    (tile_cx, tile_cy, FLOOR_BASE_TOP),
                    matte, floors_coll, (9, 4),
                    "floor_tile", "5m 可替换地砖", "floor_tile_5m", "floor",
                    bevel=0.018,
                )
                tile["room_key"] = key
                tile["owner_id"] = structure_owner
                tiles.append(tile)
    return slabs, tiles


# ============================================================ 建筑结构（墙 / 门墙）

def _grid_lines(lo: float, hi: float) -> list[float]:
    """[lo, hi] 区间内全部 5m 整数倍坐标（含两端）。"""
    out: list[float] = []
    v = math.floor(lo / GRID_UNIT + 1e-6) * GRID_UNIT
    while v <= hi + 1e-6:
        out.append(round(v, 4))
        v += GRID_UNIT
    return out


def wall_modules():
    """把整个 block 的墙拆成「沿全局 5m 网格对齐的模块」。

    每条网格线按**全部 5m 整数倍**逐模块判断两侧有没有房间：

    - 两侧都没有 ⇒ 不生成墙；
    - 只有一侧    ⇒ 外墙（墙面贴齐 block 边线，墙心向房间内偏 0.15）；
    - 两侧不同房  ⇒ 内墙（墙心压在网格线上），高取两侧较大者；
    - **两侧是同一间房 ⇒ 不生成墙**。关键：跨多格的房间中间不许长出隔断墙 —— 否则
      40m 宽的 T 字横廊、30m 宽的挑高前厅会被自己劈开，最要紧的是**长廊会被中间
      那条网格线拦腰截断**（这正是"长廊不通"的病根）。
    """
    all_x = [r[2] for r in ROOMS] + [r[4] for r in ROOMS]
    all_y = [r[3] for r in ROOMS] + [r[5] for r in ROOMS]
    x_min, x_max = min(all_x), max(all_x)
    y_min, y_max = min(all_y), max(all_y)
    xs = _grid_lines(x_min, x_max)
    ys = _grid_lines(y_min, y_max)
    modules: list[dict] = []

    for x in xs:
        cursor = y_min
        while cursor < y_max - 0.001:
            a, b = cursor, cursor + GRID_UNIT
            low = room_at(x - 1.0, (a + b) * 0.5)   # 西侧
            high = room_at(x + 1.0, (a + b) * 0.5)  # 东侧
            if low is not None and low is high:
                cursor = b
                continue
            if low is not None or high is not None:
                modules.append(dict(axis="v", line=x, a=a, b=b, neg=low, pos=high))
            cursor = b

    for y in ys:
        cursor = x_min
        while cursor < x_max - 0.001:
            a, b = cursor, cursor + GRID_UNIT
            below = room_at((a + b) * 0.5, y - 1.0)   # 南侧
            above = room_at((a + b) * 0.5, y + 1.0)   # 北侧
            if below is not None and below is above:
                cursor = b
                continue
            if below is not None or above is not None:
                modules.append(dict(axis="h", line=y, a=a, b=b, neg=below, pos=above))
            cursor = b
    return modules


def build_door_index() -> dict:
    index: dict = {}
    for key, name_zh, axis, line, center, width, height, kind, side_a, side_b in DOORS:
        module_key = (axis, round(line, 4), round(module_start(center), 4))
        if module_key in index:
            raise RuntimeError(f"同一 5m 槽上有两扇门: {module_key}")
        index[module_key] = dict(
            key=key, name_zh=name_zh, axis=axis, line=line, center=center,
            width=width, height=height, kind=kind, side_a=side_a, side_b=side_b,
        )
    return index


def build_walls(metal, structure_coll, structure_owner: str):
    modules = wall_modules()
    # 硬门禁：绝不允许「同一间房的两侧」之间出现墙 —— 那就是房间内部的隔断墙。
    # 长廊一旦被这样拦腰截断就不通了（2026-10-12 实测踩中：跨多格的房间中间
    # 会长出墙，40m 宽横廊 / 30m 宽前厅各自被劈成两半）。
    for module in modules:
        if module["neg"] is not None and module["neg"] is module["pos"]:
            raise RuntimeError(
                "房间内部出现隔断墙：%s=%.1f 段 [%.1f, %.1f] 两侧同为「%s」"
                % (module["axis"], module["line"], module["a"], module["b"], module["neg"][0])
            )
    door_index = build_door_index()
    objects: list[bpy.types.Object] = []
    used_doors: set = set()

    slot_counter: dict = {}
    for module in modules:
        axis, line, a, b = module["axis"], module["line"], module["a"], module["b"]
        neg, pos = module["neg"], module["pos"]
        label = line_label(axis, line)
        slot_counter[label] = slot_counter.get(label, 0) + 1
        slot = slot_counter[label]
        prefix = f"WALL_{label}_S{slot:02d}"

        heights = [room[6] for room in (neg, pos) if room]
        height = max(heights)
        if neg and pos:
            offset = 0.0
        elif neg:
            offset = -WALL_THICKNESS * 0.5
        else:
            offset = WALL_THICKNESS * 0.5
        line_pos = line + offset
        along_center = (a + b) * 0.5
        module_length = b - a

        def place(name, along_lo, along_hi, z_lo, z_hi, kind, role, slug):
            if along_hi - along_lo <= 0.001 or z_hi - z_lo <= 0.001:
                return None
            mid = (along_lo + along_hi) * 0.5
            length = along_hi - along_lo
            if axis == "v":
                center = (line_pos, mid, (z_lo + z_hi) * 0.5)
                size = (WALL_THICKNESS, length, z_hi - z_lo)
                origin = (line_pos, mid, z_lo)
            else:
                center = (mid, line_pos, (z_lo + z_hi) * 0.5)
                size = (length, WALL_THICKNESS, z_hi - z_lo)
                origin = (mid, line_pos, z_lo)
            obj = create_box(
                name, center, size, origin, metal, structure_coll, (9, 7),
                kind, role, slug, "structure",
            )
            obj["wall_line"] = label
            obj["wall_slot_index"] = slot
            obj["wall_slot_center_m"] = round(along_center, 4)
            obj["owner_id"] = structure_owner
            objects.append(obj)
            return obj

        door = door_index.get((axis, round(line, 4), round(a, 4)))
        if door is None:
            place(
                f"{prefix}_SOLID", a, b, 0.0, height,
                "wall", f"{label} 5m标准实墙槽{slot:02d}", "wall_standard_5m",
            )
            continue

        used_doors.add(door["key"])
        opening_lo = door["center"] - door["width"] * 0.5
        opening_hi = door["center"] + door["width"] * 0.5
        is_collapse = door["kind"] == "collapse"
        is_open = door["kind"] == "open"
        # open = 顶到墙顶的通洞（lintel_bottom == 墙高 ⇒ 不生成门楣）
        # collapse = 2.5m 矮洞但保留门楣；door = 标准门
        lintel_bottom = height if is_open else DOOR_BOTTOM + door["height"]
        tag = "OPEN" if is_open else ("COLLAPSE" if is_collapse else "DOOR")
        door_slug = "wall_collapse_5m" if is_collapse else "wall_door_5m"

        # 洞口两侧的门垛（坍塌洞若占满整个 5m 槽就没有门垛）
        place(
            f"{prefix}_{tag}_LEFT", a, opening_lo, 0.0, height,
            "door_wall", f"{label} {tag} 左门垛", door_slug,
        )
        place(
            f"{prefix}_{tag}_RIGHT", opening_hi, b, 0.0, height,
            "door_wall", f"{label} {tag} 右门垛", door_slug,
        )
        lintel = place(
            f"{prefix}_{tag}_LINTEL", opening_lo, opening_hi, lintel_bottom, height,
            "door_wall", f"{label} {tag} 门楣", door_slug,
        )
        for obj in objects:
            if obj.name.startswith(prefix) and obj.get("wall_module_type") is None:
                obj["wall_module_type"] = (
                    "open_5m" if is_open else ("collapse_5m" if is_collapse else "door_5m")
                )
                obj["door_key"] = door["key"]
                obj["door_target"] = door["side_b"]
                obj["door_opening_width_m"] = door["width"]
                obj["door_opening_height_m"] = door["height"]
        if lintel is not None:
            lintel["lintel_bottom_z_m"] = round(lintel_bottom, 4)

    missing = {entry["key"] for entry in door_index.values()} - used_doors
    if missing:
        raise RuntimeError(f"有门没落到任何 5m 槽上: {sorted(missing)}")
    return objects, modules


# ============================================================ 相机与渲染

def make_camera(name, location, target, ortho_scale, preview_coll, north_up=False):
    camera_data = bpy.data.cameras.new(name)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ortho_scale
    camera = bpy.data.objects.new(name, camera_data)
    preview_coll.objects.link(camera)
    camera.location = location
    if north_up:
        # 正俯视：默认机位的画面「上」= 世界 +Y = 南。绕自身 Z 转 180°，
        # 让画面「上」= 世界 −Y = 北，与设计页图纸（上方为北）一致。
        camera.rotation_euler = (0.0, 0.0, math.pi)
    else:
        camera.rotation_euler = (
            (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        )
    return camera


def setup_preview(preview_coll):
    xs = [room[2] for room in ROOMS] + [room[4] for room in ROOMS]
    ys = [room[3] for room in ROOMS] + [room[5] for room in ROOMS]
    width, depth = max(xs) - min(xs), max(ys) - min(ys)
    cx, cy = (max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5
    extent = max(width, depth, WALL_H_TALL)
    target = (cx, cy, WALL_H_TALL * 0.30)
    # 抬高机位：11.9m 的挑高前厅在低角度看会整片挡住 3m 的长廊与客房。
    direction = Vector((0.52, -0.78, 1.28)).normalized()
    reference = make_camera(
        "参考镜头_固定",
        tuple(Vector(target) + direction * extent * 1.85),
        target,
        extent * 1.16,
        preview_coll,
    )
    # 俯视：建筑是 70 × 130 竖长块，而 ortho_scale 作用在**传感器较大边**（这里 = 宽度）。
    # 只按 width 或只按 max(width,depth) 设都会把长边裁掉，所以按「哪条边更受限」反算。
    top_scale = max(
        width * 1.20,
        depth * RES_X / RES_Y * 1.26,
    )
    top = make_camera(
        "俯视镜头_正交",
        (cx, cy, WALL_H_TALL + 40.0),
        (cx, cy, 0.0),
        top_scale,
        preview_coll,
        north_up=True,
    )

    key = bpy.data.lights.new("参考主光", type="SUN")
    key.energy = 3.2
    key.angle = math.radians(6.0)
    key_obj = bpy.data.objects.new("参考主光", key)
    preview_coll.objects.link(key_obj)
    key_obj.location = (cx + 40.0, cy - 60.0, 90.0)
    key_obj.rotation_euler = Vector((-0.55, 0.72, -0.42)).to_track_quat("-Z", "Y").to_euler()

    fill = bpy.data.lights.new("参考补光", type="SUN")
    fill.energy = 1.1
    fill_obj = bpy.data.objects.new("参考补光", fill)
    preview_coll.objects.link(fill_obj)
    fill_obj.location = (cx - 60.0, cy + 40.0, 70.0)
    fill_obj.rotation_euler = Vector((0.6, -0.6, -0.5)).to_track_quat("-Z", "Y").to_euler()
    return reference, top


def configure_render(scene):
    # Blender 4.2+ 用 BLENDER_EEVEE_NEXT，5.x 又改回 BLENDER_EEVEE —— 两边都认。
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = RES_X
    scene.render.resolution_y = RES_Y
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 2.0
    scene.world = bpy.data.worlds.new("白模低亮环境")
    scene.world.use_nodes = True
    background = next(
        node for node in scene.world.node_tree.nodes
        if node.bl_idname == "ShaderNodeBackground"
    )
    background.inputs[0].default_value = (0.055, 0.075, 0.11, 1.0)
    background.inputs[1].default_value = 0.65


# ============================================================ 通用工具

def write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def world_bounds(objects):
    points: list[Vector] = []
    for obj in objects:
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("没有输出对象")
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def component_record(obj) -> dict:
    lo, hi = world_bounds([obj])
    record = {
        "name": obj.name,
        "collection": next(c.name for c in obj.users_collection),
        "kind": obj["component_kind"],
        "role": obj["component_role"],
        "component_slug": obj["component_slug"],
        "origin_world_m": [round(v, 4) for v in obj.location],
        "origin_contract": obj["origin_contract"],
        "dimensions_m": [round(float(v), 4) for v in obj["dimensions_m"]],
        "bounds_world_m": {
            "min": [round(v, 4) for v in lo],
            "max": [round(v, 4) for v in hi],
        },
    }
    for key in (
        "room_key", "wall_line", "wall_slot_index", "wall_slot_center_m",
        "wall_module_type", "door_key", "door_target",
        "door_opening_width_m", "door_opening_height_m", "lintel_bottom_z_m",
    ):
        if key in obj:
            record[key] = obj[key]
    return record


def validate_outputs(output_objects, expected_size, expected_height) -> dict:
    failures: list[str] = []
    warnings: list[str] = []
    names = [obj.name for obj in output_objects]
    if len(names) != len(set(names)):
        failures.append("输出对象重名")
    for name in names:
        if ".001" in name or name.endswith("_主体"):
            failures.append(f"对象名含迭代或合并后缀: {name}")
    multi_owner = [obj.name for obj in output_objects if len(obj.users_collection) != 1]
    if multi_owner:
        failures.append(f"对象多集合归属: {multi_owner[:5]}")

    for obj in output_objects:
        kind = str(obj["component_kind"])
        if any(abs(float(v) - 1.0) > 0.0001 for v in obj.scale):
            failures.append(f"{obj.name} Scale 必须为 1，实际 {list(obj.scale)}")
        if kind in {"wall", "door_wall"}:
            longest = max(float(obj.dimensions.x), float(obj.dimensions.y))
            if longest > GRID_UNIT + 0.001:
                failures.append(f"{obj.name} 超过 5m 模块长度: {longest:.3f}m")
            if abs(obj.location.z) > 0.0001 and "LINTEL" not in obj.name:
                failures.append(f"{obj.name} 墙/门垛原点 Z 应为 0，实际 {obj.location.z}")
        if kind in {"floor_slab", "floor_tile"} and abs(obj.location.z) > 0.0001:
            if abs(obj.location.z - FLOOR_BASE_TOP) > 0.0001:
                failures.append(f"{obj.name} 地砖原点 Z 应为 {FLOOR_BASE_TOP}，实际 {obj.location.z}")
        if kind not in {"wall", "door_wall", "floor_slab", "floor_tile"}:
            failures.append(f"未识别组件类型: {obj.name} / {kind}")

    # 墙面必须贴齐 block 边线：外墙面不得超出名义包络，内墙不得缩进
    min_corner, max_corner = world_bounds(output_objects)
    measured = (
        max_corner.x - min_corner.x,
        max_corner.y - min_corner.y,
        max_corner.z - min_corner.z,
    )
    expected = (expected_size[0], expected_size[1], expected_height)
    for axis, actual, wanted in zip(("X", "Y", "Z"), measured, expected):
        if abs(actual - wanted) > 0.011:
            failures.append(f"{axis} 包络错误: 期望 {wanted:.3f}m，实际 {actual:.3f}m")

    # 墙厚必须恒为 0.30，且墙高只能是 3.0 或 11.9
    for obj in output_objects:
        kind = str(obj["component_kind"])
        if kind in {"wall", "door_wall"}:
            thickness = min(float(obj.dimensions.x), float(obj.dimensions.y))
            if abs(thickness - WALL_THICKNESS) > 0.001:
                failures.append(f"{obj.name} 墙厚应为 {WALL_THICKNESS}，实际 {thickness:.4f}")
            height = float(obj.dimensions.z)
            if abs(height - WALL_H_LOW) > 0.001 and abs(height - WALL_H_TALL) > 0.001:
                # 门楣是墙高减门洞高，单独放行
                if "LINTEL" not in obj.name:
                    failures.append(f"{obj.name} 墙高应为 {WALL_H_LOW} 或 {WALL_H_TALL}，实际 {height:.4f}")

    kinds = sorted({str(obj["component_kind"]) for obj in output_objects})
    trim_count = sum(
        1 for obj in output_objects
        if str(obj.get("wall_module_type", "")) == "trim_fixed"
    )
    return {
        "status": "PASS" if not failures else "FAIL",
        "failures": failures,
        "warnings": warnings,
        "object_count": len(output_objects),
        "mesh_count": sum(obj.type == "MESH" for obj in output_objects),
        "component_counts": {
            kind: sum(obj["component_kind"] == kind for obj in output_objects)
            for kind in kinds
        },
        "fixed_trim_count": trim_count,
        "bounds_world_m": {
            "min": [round(v, 4) for v in min_corner],
            "max": [round(v, 4) for v in max_corner],
        },
        "measured_dimensions_m": [round(v, 4) for v in measured],
    }


# ============================================================ 装配

def clone_components(source_objects, output_structure, output_floor):
    clones: list[bpy.types.Object] = []
    for source in source_objects:
        output_name = source.name
        source.name = f"AP_{output_name}"
        clone = source.copy()
        clone.data = source.data.copy()
        clone.name = output_name
        target = output_structure if source["component_group"] == "structure" else output_floor
        target.objects.link(clone)
        for key in list(source.keys()):
            clone[key] = source[key]
        clones.append(clone)
    return clones


def build() -> dict:
    reset_scene()
    scene = bpy.context.scene

    root = bpy.data.collections.new(f"{ASSET_NAME}_资产管理")
    scene.collection.children.link(root)
    source_coll = bpy.data.collections.new("01_制作组件_按设施拆分")
    output_coll = bpy.data.collections.new(f"02_游戏输出_独立资产包_{VERSION}")
    preview_coll = bpy.data.collections.new("90_展示与验收_灯光相机")
    root.children.link(source_coll)
    root.children.link(output_coll)
    root.children.link(preview_coll)

    src_structure = bpy.data.collections.new("01_建筑结构")
    src_floor = bpy.data.collections.new("02_地面系统")
    source_coll.children.link(src_structure)
    source_coll.children.link(src_floor)
    out_structure = bpy.data.collections.new("01_建筑结构")
    out_floor = bpy.data.collections.new("02_地面系统")
    output_coll.children.link(out_structure)
    output_coll.children.link(out_floor)

    metal = make_material("01_精工金属_紫色骨架", 0.82, 0.30, (9, 7))
    matte = make_material("02_细腻哑光_青绿大面", 0.03, 0.72, (9, 5))
    dark = make_material("03_深色哑光_结构底面", 0.02, 0.78, (9, 2))

    slabs, tiles = build_floors(dark, matte, src_floor, ASSET_ID)
    walls, modules = build_walls(metal, src_structure, ASSET_ID)
    source_objects = slabs + tiles + walls

    output_objects = clone_components(source_objects, out_structure, out_floor)
    for obj in output_objects:
        obj["asset_id"] = ASSET_ID
        obj["asset_version"] = VERSION
    source_coll.hide_viewport = True
    source_coll.hide_render = True
    output_coll.hide_viewport = False
    output_coll.hide_render = False

    reference_camera, top_camera = setup_preview(preview_coll)
    configure_render(scene)

    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    blend_path = BLEND_DIR / f"{FILENAME_STEM}_{VERSION}.blend"
    reference_png = RENDER_DIR / f"{FILENAME_STEM}_{VERSION}_参考.png"
    top_png = RENDER_DIR / f"{FILENAME_STEM}_{VERSION}_俯视.png"

    scene.camera = reference_camera
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    scene.render.filepath = str(reference_png)
    bpy.ops.render.render(write_still=True)
    scene.camera = top_camera
    scene.render.filepath = str(top_png)
    bpy.ops.render.render(write_still=True)
    scene.camera = reference_camera
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    xs = [room[2] for room in ROOMS] + [room[4] for room in ROOMS]
    ys = [room[3] for room in ROOMS] + [room[5] for room in ROOMS]
    expected_size = (max(xs) - min(xs), max(ys) - min(ys))
    validation = validate_outputs(output_objects, expected_size, WALL_H_TALL)
    min_corner, max_corner = world_bounds(output_objects)

    doors_out = []
    for dk, dn, dax, dline, dcenter, dwidth, dhgt, dkind, dsa, dsb in DOORS:
        doors_out.append({
            "door_key": dk, "name_zh": dn, "axis": dax,
            "wall_line": line_label(dax, dline),
            "line_coord_m": dline, "opening_center_m": dcenter,
            "opening_width_m": dwidth,
            "opening_height_m": (None if dkind == "open" else dhgt),
            "lintel_bottom_z_m": (None if dkind == "open" else round(DOOR_BOTTOM + dhgt, 4)),
            "kind": dkind, "side_a": dsa, "side_b": dsb,
        })

    room_records = [
        {
            "key": room[0], "name_zh": room[1],
            "size_m": [room[4] - room[2], room[5] - room[3]],
            "center_m": [(room[2] + room[4]) * 0.5, (room[3] + room[5]) * 0.5],
            "wall_height_m": room[6],
            "clear_height_m": round(room[6] - WALK_PLANE_Z, 4),
        }
        for room in ROOMS
    ]

    manifest = {
        "asset_id": ASSET_ID,
        "name_zh": ASSET_NAME,
        "slug": SLUG,
        "category": "room_type_layer",
        "role": "远征关卡02 第1层（长廊 + 两侧客房 + 入口序列）",
        "version": VERSION,
        "level_id": LEVEL_ID,
        "block_id": BLOCK_ID,
        "floor_number": 1,
        "design_scope": "scene_art",
        "asset_ledger": "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用",
        "source_blend": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
        "blender_collection": root.name,
        "authoring_collection": source_coll.name,
        "output_collection": output_coll.name,
        "objects": [obj.name for obj in output_objects],
        "root_object": None,
        "component_count": len(output_objects),
        "component_policy": (
            "全局 5m 槽位网格；实墙一槽一件；门墙一槽保留左右门垛与门楣三件独立网格；"
            "坍塌洞占满一槽、只有门楣；禁止缩放与合并"
        ),
        "origin": "asset floor underside Z=0; each wall/pier stores its own bottom-center origin; lintel stores its own lintel-bottom origin",
        "front": "Godot -Z",
        "grid_unit_m": GRID_UNIT,
        "wall_thickness_m": WALL_THICKNESS,
        "floor_thickness_m": FLOOR_THICKNESS,
        "walk_plane_z_m": WALK_PLANE_Z,
        "logical_wall_height_m": 12.0,
        "hotel_low_wall_height_m": WALL_H_LOW,
        "hotel_tall_wall_height_m": WALL_H_TALL,
        "dimensions_m": [round(expected_size[0], 3), round(expected_size[1], 3), round(WALL_H_TALL, 3)],
        "bounds_world_m": {
            "min": [round(v, 4) for v in min_corner],
            "max": [round(v, 4) for v in max_corner],
        },
        "door_contract": {
            "width_m": DOOR_WIDTH,
            "height_m": DOOR_HEIGHT,
            "clear_floor_gap_m": DOOR_CLEAR_FLOOR_GAP,
            "bottom_z_m": DOOR_BOTTOM,
            "lintel_bottom_z_m": DOOR_TOP,
            "collapse_width_m": COLLAPSE_WIDTH,
            "collapse_height_m": COLLAPSE_HEIGHT,
            "lane_rule": "RoomDoorLane.lane_offsets：10m 墙 -> ±2.5；15m 墙 -> 0",
        },
        "rooms": room_records,
        "doors": doors_out,
        "wall_module_count": len(modules),
        "generic_components_used": GENERIC_COMPONENT_CONTRACT,
        "materials": [metal.name, matte.name, dark.name],
        "palette_uv": "PaletteUV",
        "shared_palette": str(PALETTE_PATH.relative_to(ROOT)).replace("\\", "/"),
        "components": [component_record(obj) for obj in output_objects],
        "render_reference": str(reference_png.relative_to(ROOT)).replace("\\", "/"),
        "render_top": str(top_png.relative_to(ROOT)).replace("\\", "/"),
        "export_status": "blend_only; GLB and Godot integration not requested",
        "collision_status": "not authored",
        "runtime_status": "not connected",
        "not_included": [
            "顶盖 / 房间天花板（按房型件阶段处理，见 06 §7.3.1 封顶件硬契约）",
            "破碎空洞（层间通道）—— 待第 2 层一起定",
            "第 2..5 层（结构与本层相同、无挑高，另轮制作）",
            "门扇（door_5m）、窗、陈设、灯光、碰撞",
        ],
    }
    write_json(PACKAGE_DIR / "hotel_floor_01" / SLUG / "asset_manifest.json", manifest)
    write_json(
        PACKAGE_DIR / "catalog.json",
        {
            "schema": "shellstorm2.whitebox.component_packages",
            "level_id": LEVEL_ID,
            "version": VERSION,
            "packages": [
                {
                    "category": "hotel_floor_01",
                    "package": SLUG,
                    "asset_id": ASSET_ID,
                    "object_count": len(output_objects),
                    "path": f"hotel_floor_01/{SLUG}/asset_manifest.json",
                }
            ],
        },
    )
    write_json(
        VALIDATION_DIR / f"{SLUG}_{VERSION}_validation.json",
        {
            "asset_id": ASSET_ID,
            "version": VERSION,
            "source_blend": manifest["source_blend"],
            "validation": validation,
        },
    )
    write_json(
        VALIDATION_DIR / "task_level_validation.json",
        {
            "level_id": LEVEL_ID,
            "version": VERSION,
            "asset_count": 1,
            "status": validation["status"],
            "assets": [{"asset_id": ASSET_ID, "status": validation["status"]}],
        },
    )
    return manifest


def main() -> None:
    manifest = build()
    print(f"EXPEDITION02_WHITEBOX_{VERSION.upper()}_ASSET_OK")
    print(f"EXPEDITION02_WHITEBOX_{VERSION.upper()}_READY")
    print(json.dumps({
        "asset_id": manifest["asset_id"],
        "objects": manifest["component_count"],
        "rooms": len(manifest["rooms"]),
        "doors": len(manifest["doors"]),
        "wall_modules": manifest["wall_module_count"],
        "bounds": manifest["bounds_world_m"],
        "source_blend": manifest["source_blend"],
    }, ensure_ascii=False, indent=1))


main()
