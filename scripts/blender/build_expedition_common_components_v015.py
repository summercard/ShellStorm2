"""远征关卡02 · 通用组件库 v015（低矮 3m 墙体系 + 封顶件）。

Run with:
    blender --background --python scripts/blender/build_expedition_common_components_v015.py

为什么要有这一版：战局通用组件库（`ENV-BATTLE-COMMON-WALL-STANDARD-5M`）是
**11.9 m 高**的墙，而远征02 的长廊 / 客房 / T 字横廊 / 支廊全部是 **3 m 净高**
（用户 2026-10-12 裁定：「下面的层级不会有挑高层，都是 3 米高的房间和走廊」）。
高度对不上，不能复用。本版补上 3 m 墙体系，并新增**封顶件** —— 按 `06 §7.3.1`
封顶件硬契约，顶盖必须带 layer=1 碰撞，否则「房间不受太阳照射」不成立。

组件清单（原点一律 = 底面中心，正面朝 Godot `-Z`）：

| slug | 结构尺寸（Blender XYZ） | 用途 |
|---|---|---|
| `wall_standard_5m_h3`   | 5.000 × 0.300 × 3.000 | 3 m 实墙，一槽一件 |
| `wall_door_5m_h3`       | 5.000 × 0.300 × 3.000（门洞 2.2 × 2.5）| 3 m 门墙，左/右门垛 + 门楣 |
| `wall_collapse_5m_h12`  | 5.000 × 0.300 × 11.900（洞 5.0 × 2.5）| 坍塌门洞，占满一整格 |
| `ceiling_deck_5m`       | 5.000 × 5.000 × 0.260 | 封顶模块（layer=1 碰撞）|
| `floor_base_5m`         | 5.000 × 5.000 × 0.260 | 地板底层模块 |

坐标口径与白盒 `build_expedition02_whitebox_v001.py` **逐值一致**，房间 TSCN 才能
直接消费白盒 manifest 的实例坐标。
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
VERSION = "v015"
LEVEL_ID = "expedition_02"
LIBRARY_ID = "ENV-EXPEDITION-COMMON-COMPONENT-LIBRARY"

SOURCE_DIR = ROOT / "art_source/environments/tower_zones/expedition/source/common_components" / VERSION
OPTIMIZED_DIR = SOURCE_DIR / "export" / VERSION
PACKAGE_DIR = SOURCE_DIR / f"component_packages_{VERSION}"
GLB_ROOT = ROOT / "assets/art/environments/tower_zones/expedition/components/common_components"
PALETTE_PATH = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

SOURCE_BLEND = SOURCE_DIR / f"expedition_common_components_source_{VERSION}.blend"
OPTIMIZED_BLEND = OPTIMIZED_DIR / f"expedition_common_components_source_{VERSION}_optimized.blend"

# ---- 全项目几何基准（唯一真源 TowerGeometry3D.gd，这里只读不改）-------------
GRID_UNIT = 5.0
WALL_THICKNESS = 0.30
FLOOR_THICKNESS = 0.30
SURFACE_TILE_THICKNESS = 0.04
FLOOR_BASE_TOP = FLOOR_THICKNESS - SURFACE_TILE_THICKNESS      # 0.26
WALK_PLANE_Z = FLOOR_THICKNESS                                  # 0.30

DOOR_WIDTH = 2.2
DOOR_HEIGHT = 2.5
DOOR_BOTTOM = WALK_PLANE_Z                                      # 0.30
DOOR_TOP = DOOR_BOTTOM + DOOR_HEIGHT                            # 2.80
PIER_WIDTH = (GRID_UNIT - DOOR_WIDTH) * 0.5                     # 1.40

WALL_H_LOW = 3.0                                                # 本关主体墙高
WALL_H_TALL = 11.9                                              # 挑高前厅 = 项目基线
COLLAPSE_WIDTH = GRID_UNIT                                      # 坍塌洞占满一整格
COLLAPSE_HEIGHT = 2.5

# 材质：结构面只有一个角色。纯方块几何，多材质只增加 draw call。
MATERIAL_ROLE = "01_哑光结构面"
PALETTE_CELL = (9, 5)          # 青绿大面
MATERIAL_METALLIC = 0.03
MATERIAL_ROUGHNESS = 0.72


class Component:
    """一个通用组件的结构定义。boxes 是 (名称后缀, 中心 XYZ, 尺寸 XYZ)。

    `slot_size_m` 是组件在 5m 网格上的**占位尺寸**（洞口也占位），
    `bounds_size_m` 是**可视几何包围盒**。两者只在「洞里没有实体」的件上不同
    —— 典型是坍塌门洞：占位 5.0×0.30×11.90，可视只有上方门楣 5.0×0.30×9.10。
    """

    def __init__(self, slug, asset_id, category, name_zh, boxes, note, slot_size=None):
        self.slug = slug
        self.asset_id = asset_id
        self.category = category
        self.name_zh = name_zh
        self.boxes = boxes
        self.note = note
        self.slot_size = [round(v, 6) for v in slot_size] if slot_size else None

    @property
    def bounds(self):
        lo = [min(b[1][i] - b[2][i] * 0.5 for b in self.boxes) for i in range(3)]
        hi = [max(b[1][i] + b[2][i] * 0.5 for b in self.boxes) for i in range(3)]
        return lo, hi

    @property
    def size(self):
        lo, hi = self.bounds
        return [round(hi[i] - lo[i], 6) for i in range(3)]

    @property
    def slot(self):
        return self.slot_size or self.size


def _box(name_suffix, cx, cy, cz, sx, sy, sz):
    return (name_suffix, (cx, cy, cz), (sx, sy, sz))


COMPONENTS: list[Component] = [
    Component(
        slug="wall_standard_5m_h3",
        asset_id="ENV-EXPEDITION-COMMON-WALL-STANDARD-5M-H3",
        category="08_墙壁组件",
        name_zh="通用标准墙 5.00×0.30×3.00m（低矮层）",
        boxes=[_box("主体", 0.0, 0.0, WALL_H_LOW * 0.5, GRID_UNIT, WALL_THICKNESS, WALL_H_LOW)],
        note="低矮层实墙。与战局 wall_standard_5m 同 5m 槽位、同 0.30 墙厚，只是墙高 3.00 而非 11.90。",
    ),
    Component(
        slug="wall_door_5m_h3",
        asset_id="ENV-EXPEDITION-COMMON-WALL-DOOR-5M-H3",
        category="08_墙壁组件",
        name_zh="通用门墙 5.00×0.30×3.00m（门洞 2.2×2.5，低矮层）",
        boxes=[
            _box("左门垛", -PIER_WIDTH * 0.5 - DOOR_WIDTH * 0.5, 0.0, WALL_H_LOW * 0.5,
                 PIER_WIDTH, WALL_THICKNESS, WALL_H_LOW),
            _box("右门垛", PIER_WIDTH * 0.5 + DOOR_WIDTH * 0.5, 0.0, WALL_H_LOW * 0.5,
                 PIER_WIDTH, WALL_THICKNESS, WALL_H_LOW),
            _box("门楣", 0.0, 0.0, (DOOR_TOP + WALL_H_LOW) * 0.5,
                 DOOR_WIDTH, WALL_THICKNESS, WALL_H_LOW - DOOR_TOP),
        ],
        note="3m 墙上门楣只有 0.20 高（3.00 − 2.80）。门洞 2.2×2.5 与 door_5m 门扇严格配对。",
    ),
    Component(
        slug="wall_collapse_5m_h12",
        asset_id="ENV-EXPEDITION-COMMON-WALL-COLLAPSE-5M-H12",
        category="08_墙壁组件",
        name_zh="坍塌门洞 5.00×0.30×11.90m（洞口 5.0×2.5）",
        boxes=[_box("门楣", 0.0, 0.0, (DOOR_BOTTOM + COLLAPSE_HEIGHT + WALL_H_TALL) * 0.5,
                    COLLAPSE_WIDTH, WALL_THICKNESS, WALL_H_TALL - DOOR_BOTTOM - COLLAPSE_HEIGHT)],
        note="洞口占满一整格 5m、无门垛，只有 2.5m 高（比标准门矮 0.5m）。只用在挑高前厅↔长廊。",
        slot_size=(GRID_UNIT, WALL_THICKNESS, WALL_H_TALL),
    ),
    Component(
        slug="wall_standard_5m_h12",
        asset_id="ENV-EXPEDITION-COMMON-WALL-STANDARD-5M-H12",
        category="08_墙壁组件",
        name_zh="通用标准墙 5.00×0.30×11.90m（通高层 · 挑高前厅）",
        boxes=[_box("主体", 0.0, 0.0, WALL_H_TALL * 0.5, GRID_UNIT, WALL_THICKNESS, WALL_H_TALL)],
        note=(
            "通高层实墙，高度恰为项目基线 WALL_VISUAL_HEIGHT_M（11.90）。"
            "本关只有挑高前厅（30×15）用它；其余房间全走 3m 的 wall_standard_5m_h3。"
        ),
    ),
    Component(
        slug="wall_door_5m_h12",
        asset_id="ENV-EXPEDITION-COMMON-WALL-DOOR-5M-H12",
        category="08_墙壁组件",
        name_zh="通用门墙 5.00×0.30×11.90m（门洞 2.2×2.5，通高层）",
        boxes=[
            _box("左门垛", -PIER_WIDTH * 0.5 - DOOR_WIDTH * 0.5, 0.0, WALL_H_TALL * 0.5,
                 PIER_WIDTH, WALL_THICKNESS, WALL_H_TALL),
            _box("右门垛", PIER_WIDTH * 0.5 + DOOR_WIDTH * 0.5, 0.0, WALL_H_TALL * 0.5,
                 PIER_WIDTH, WALL_THICKNESS, WALL_H_TALL),
            _box("门楣", 0.0, 0.0, (DOOR_TOP + WALL_H_TALL) * 0.5,
                 DOOR_WIDTH, WALL_THICKNESS, WALL_H_TALL - DOOR_TOP),
        ],
        note=(
            "11.9m 墙上的门墙：门垛与墙同高 11.90、门楣 9.10（11.90 − 2.80）。"
            "白盒里只有 1 扇（阳台安全屋 → 挑高前厅）。"
        ),
    ),
    Component(
        slug="floor_tile_5m",
        asset_id="ENV-EXPEDITION-COMMON-FLOOR-TILE-5M",
        category="09_顶面组件",
        name_zh="通用地砖 4.94×4.94×0.04m（5m 格内可替换面砖）",
        boxes=[_box("面砖", 0.0, 0.0, SURFACE_TILE_THICKNESS * 0.5,
                    GRID_UNIT - 0.06, GRID_UNIT - 0.06, SURFACE_TILE_THICKNESS)],
        note=(
            "铺在 floor_base_5m 顶面（0.26）之上到走面 0.30。四面各留 0.03 缝，"
            "相邻砖缝连成一条线。与战局 floor_tile_r01_c01/c02 同规格但独立成件 —— "
            "破败旅馆的磨损面砖要单独做旧，不复用办公/数据中心的干净面砖。"
        ),
    ),
    Component(
        slug="ceiling_deck_5m",
        asset_id="ENV-EXPEDITION-COMMON-CEILING-DECK-5M",
        category="09_顶面组件",
        name_zh="封顶模块 5.00×5.00×0.26m（层间楼板 / 房间天花板）",
        boxes=[_box("顶板", 0.0, 0.0, FLOOR_BASE_TOP * 0.5, GRID_UNIT, GRID_UNIT, FLOOR_BASE_TOP)],
        note=(
            "按 06 §7.3.1 封顶件硬契约：包装场景必须带 layer=1 碰撞盒 —— "
            "怪物身体采样点朝太阳打射线被它挡住，房间才判为「不受日照」。"
            "厚 0.26 与地板底层同模数（0.30 − 0.04 地砖）。"
        ),
    ),
    Component(
        slug="floor_base_5m",
        asset_id="ENV-EXPEDITION-COMMON-FLOOR-BASE-5M",
        category="09_顶面组件",
        name_zh="地板底层模块 5.00×5.00×0.26m",
        boxes=[_box("底板", 0.0, 0.0, FLOOR_BASE_TOP * 0.5, GRID_UNIT, GRID_UNIT, FLOOR_BASE_TOP)],
        note="与地砖（4.94×4.94×0.04）配套：底板顶面 0.26，地砖叠在上面到走面 0.30。",
    ),
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else ""


# ---- 场景与材质 -------------------------------------------------------------

def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def make_material() -> bpy.types.Material:
    material = bpy.data.materials.new(MATERIAL_ROLE)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    output.name = "材质输出"
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.name = "Principled BSDF"
    principled.inputs["Metallic"].default_value = MATERIAL_METALLIC
    principled.inputs["Roughness"].default_value = MATERIAL_ROUGHNESS
    principled.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1.0)
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])

    uv_map = nodes.new("ShaderNodeUVMap")
    uv_map.uv_map = "PaletteUV"
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(PALETTE_PATH), check_existing=True)
    texture.interpolation = "Closest"
    links.new(uv_map.outputs["UV"], texture.inputs["Vector"])
    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    material["palette_column_zero_based"] = PALETTE_CELL[0]
    material["palette_row_zero_based"] = PALETTE_CELL[1]
    return material


def assign_palette_uv(obj: bpy.types.Object) -> None:
    """每个面留一个有色格内的小 UV 岛（点 UV 不算数，必须是有面积的岛）。"""
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    layer = mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = layer
    layer.active_render = True

    column, row = PALETTE_CELL
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


def create_box(name, center, size, material, collection) -> bpy.types.Object:
    half = Vector(size) * 0.5
    origin = Vector(center)
    signs = [
        (-1.0, -1.0, -1.0), (1.0, -1.0, -1.0), (1.0, 1.0, -1.0), (-1.0, 1.0, -1.0),
        (-1.0, -1.0, 1.0), (1.0, -1.0, 1.0), (1.0, 1.0, 1.0), (-1.0, 1.0, 1.0),
    ]
    verts = [tuple(Vector((sx * half.x, sy * half.y, sz * half.z))) for sx, sy, sz in signs]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    mesh = bpy.data.meshes.new(f"{name}_网格")
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = origin
    obj.data.materials.append(material)
    assign_palette_uv(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    obj["dimensions_m"] = [round(v, 4) for v in size]
    return obj


# ---- 建库 -------------------------------------------------------------------

def build_library():
    reset_scene()
    scene = bpy.context.scene
    scene["library_id"] = LIBRARY_ID
    scene["library_version"] = VERSION
    scene["level_id"] = LEVEL_ID
    scene["grid_unit_m"] = GRID_UNIT
    scene["wall_thickness_m"] = WALL_THICKNESS
    scene["origin_contract"] = "bottom_center"
    scene["godot_forward_axis"] = "-Z"

    root = bpy.data.collections.new(f"远征通用组件库_{VERSION}_资产管理")
    scene.collection.children.link(root)
    material = make_material()

    built = {}
    for component in COMPONENTS:
        editable = bpy.data.collections.new(f"{component.slug}_制作源")
        output = bpy.data.collections.new(f"{component.slug}_输出")
        root.children.link(editable)
        root.children.link(output)

        # 制作源：可编辑散件
        for suffix, center, size in component.boxes:
            create_box(f"{component.slug}_{suffix}", center, size, material, editable)

        # 游戏输出：只放一个「主体」对象，几何合并且原点 = 底面中心。
        # 门墙那种多块结构用**多网格单对象**保留，避免导出后被拆成多个节点。
        merged = bpy.data.meshes.new(f"{component.slug}_视觉_网格")
        verts, faces = [], []
        for _, center, size in component.boxes:
            base = len(verts)
            half = Vector(size) * 0.5
            origin = Vector(center)
            signs = [
                (-1.0, -1.0, -1.0), (1.0, -1.0, -1.0), (1.0, 1.0, -1.0), (-1.0, 1.0, -1.0),
                (-1.0, -1.0, 1.0), (1.0, -1.0, 1.0), (1.0, 1.0, 1.0), (-1.0, 1.0, 1.0),
            ]
            verts.extend(
                tuple(origin + Vector((sx * half.x, sy * half.y, sz * half.z)))
                for sx, sy, sz in signs
            )
            faces.extend(
                tuple(base + i for i in f)
                for f in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
            )
        merged.from_pydata(verts, [], faces)
        merged.validate()
        merged.update()
        obj = bpy.data.objects.new(f"{component.slug}_视觉", merged)
        output.objects.link(obj)
        obj.location = (0.0, 0.0, 0.0)          # 原点 = 底面中心（几何已含偏移）
        obj.data.materials.append(material)
        assign_palette_uv(obj)
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
        obj["component_slug"] = component.slug
        obj["asset_id"] = component.asset_id
        obj["origin_contract"] = "bottom_center"
        obj["dimensions_m"] = component.size

        # 顶面 / 底面材质索引分离不需要（单材质），但记录面数
        component.triangle_count = len(merged.polygons) * 2
        built[component.slug] = obj
        editable.hide_viewport = True
        editable.hide_render = True

    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND))
    return root, built


def optimize_to_derived():
    """另存优化派生文件，并在其中执行 02b 要求的几何清理与三角化。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))

    stats = {}
    # 只保留游戏输出集合，删除制作源与相机灯光
    for collection in list(bpy.data.collections):
        if collection.name.endswith("_制作源"):
            for obj in list(collection.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.collections.remove(collection)

    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        before_polys = len(obj.data.polygons)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)

        # 1) 清理：重复/零面积面、孤立点边、无效几何
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=False)
        bpy.ops.mesh.dissolve_degenerate(threshold=1e-5)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")

        # 2) 合并重复顶点（不跨材质边界，单材质下安全）
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=1e-5)
        bpy.ops.object.mode_set(mode="OBJECT")

        # 3) 三角化（导出前与 GLB 口径一致）
        bpy.ops.object.modifier_add(type="TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=obj.modifiers[-1].name)

        after_polys = len(obj.data.polygons)
        # 口径修复：三角化前是四边形，三角形数 = 面数 × 2。**不得**把 polygon 数
        # 直接当 triangle 数（02b 明令禁止），否则会算出 −100% 这种假减面率。
        before_tris = before_polys * 2
        after_tris = after_polys
        stats[obj.name] = {
            "polygons_before": before_polys,
            "triangles_before": before_tris,
            "polygons_after": after_polys,
            "triangles_after": after_tris,
            "reduction_ratio": (
                round((before_tris - after_tris) / before_tris, 6) if before_tris else None
            ),
            "operations": [
                "delete_loose(verts,edges)",
                "dissolve_degenerate(1e-5)",
                "normals_make_consistent(outside)",
                "remove_doubles(1e-5)",
                "triangulate",
                "assign_palette_uv",
            ],
            "note": (
                "纯轴对齐方块几何：无重复面、无零面积面、无冗余细分 ⇒ 清理零处理量，"
                "三角化把 N 个四边形变成 2N 个三角形。减面率 0 是本件的正确结果，不是跳过优化。"
            ),
        }
        # UV 在清理后重贴一次，确保每个面都有有色岛
        assign_palette_uv(obj)

    OPTIMIZED_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED_BLEND))
    return stats


def export_from_optimized():
    """重新打开优化派生文件，逐组件导出 GLB（禁止从原始源直接导出）。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.open_mainfile(filepath=str(OPTIMIZED_BLEND))

    results = {}
    for component in COMPONENTS:
        obj = bpy.data.objects.get(f"{component.slug}_视觉")
        if obj is None:
            raise RuntimeError(f"优化文件里找不到 {component.slug}_视觉")
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj

        glb_dir = GLB_ROOT / component.slug
        glb_dir.mkdir(parents=True, exist_ok=True)
        glb_path = glb_dir / f"{component.slug}_visual_top3d.glb"
        bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            export_format="GLB",
            use_selection=True,
            export_apply=False,                 # 已在优化文件里烘焙
            export_yup=True,
            export_materials="EXPORT",
            export_image_format="NONE",         # 🔴 GLB 不得内嵌图片
            export_texcoords=True,
            export_normals=True,
            export_tangents=False,
            export_cameras=False,
            export_lights=False,
            export_extras=True,
        )
        results[component.slug] = {
            "glb": glb_path,
            "glb_sha256": digest(glb_path),
            "glb_bytes": glb_path.stat().st_size,
        }
    return results


def write_manifests(optimize_stats, export_results, source_sha_before, source_sha_after):
    """写每个组件的 asset_manifest.json + 组件树。"""
    catalog = []
    for component in COMPONENTS:
        lo, hi = component.bounds
        payload = {
            "asset_id": component.asset_id,
            "slug": component.slug,
            "name_zh": component.name_zh,
            "category": component.category,
            "library_id": LIBRARY_ID,
            "version": VERSION,
            "level_id": LEVEL_ID,
            "source_blend": str(SOURCE_BLEND),
            "optimized_blend": str(OPTIMIZED_BLEND),
            "source_sha256_before": source_sha_before,
            "source_sha256_after": source_sha_after,
            "source_unchanged": source_sha_before == source_sha_after,
            "blender_collection": f"{component.slug}_输出",
            "editable_collection": f"{component.slug}_制作源",
            "root_object": f"{component.slug}_视觉",
            "object_count": 1,
            "blender_forward_axis": "+Y",
            "blender_up_axis": "+Z",
            "origin_contract": "bottom_center",
            "godot_forward_axis": "-Z",
            "bounds_lo_m": [round(v, 6) for v in lo],
            "bounds_hi_m": [round(v, 6) for v in hi],
            "bounds_size_m": component.size,
            "visual_bounds_size_m": component.size,
            "slot_size_m": component.slot,
            "bounds_note": (
                "bounds_size_m / visual_bounds_size_m 是可视几何包围盒；"
                "slot_size_m 是 5m 网格占位（洞口也计入）。两者仅在坍塌门洞上不同。"
            ),
            "grid_unit_m": GRID_UNIT,
            "wall_thickness_m": WALL_THICKNESS,
            "material_roles": [MATERIAL_ROLE],
            "material_count": 1,
            "palette_uv_channel": "PaletteUV",
            "shared_palette": str(PALETTE_PATH),
            "optimization": optimize_stats.get(f"{component.slug}_视觉", {}),
            "export": {
                "glb": str(export_results[component.slug]["glb"]),
                "glb_sha256": export_results[component.slug]["glb_sha256"],
                "glb_bytes": export_results[component.slug]["glb_bytes"],
                "embedded_images": 0,
            },
            "collision": "owned by runtime prefab (layer=1 StaticBody3D)",
            "note": component.note,
        }
        out_dir = PACKAGE_DIR / component.slug
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "asset_manifest.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\r\n"
        )
        catalog.append(
            {
                "asset_id": component.asset_id,
                "slug": component.slug,
                "category": component.category,
                "bounds_size_m": component.size,
                "slot_size_m": component.slot,
                "path": f"{component.slug}/asset_manifest.json",
            }
        )

    (SOURCE_DIR / f"component_catalog_{VERSION}.json").write_text(
        json.dumps(
            {
                "schema": "shellstorm2.common_component_library",
                "library_id": LIBRARY_ID,
                "version": VERSION,
                "level_id": LEVEL_ID,
                "source_blend": str(SOURCE_BLEND),
                "optimized_blend": str(OPTIMIZED_BLEND),
                "components": catalog,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
        newline="\r\n",
    )
    return catalog


def main() -> None:
    source_sha_before = digest(SOURCE_BLEND)
    print("EXPEDITION_COMMON_V015_BUILD_BEGIN")
    build_library()
    source_sha_after = digest(SOURCE_BLEND)

    optimize_stats = optimize_to_derived()
    export_results = export_from_optimized()

    # 源保护断言：建库这一步写出的源文件，在这之后不得再被改写
    if SOURCE_BLEND.exists() and digest(SOURCE_BLEND) != source_sha_after:
        raise RuntimeError("原始库在优化/导出阶段被改写 —— 违反源保护门禁")
    if str(SOURCE_BLEND) == str(OPTIMIZED_BLEND):
        raise RuntimeError("优化派生文件与原始文件同路径")
    if not OPTIMIZED_BLEND.exists():
        raise RuntimeError("优化派生文件未落盘")

    catalog = write_manifests(optimize_stats, export_results, source_sha_after, digest(SOURCE_BLEND))

    print("EXPEDITION_COMMON_V015_BUILD_OK components=%d" % len(catalog))
    print(json.dumps(
        {
            "source_blend": str(SOURCE_BLEND),
            "optimized_blend": str(OPTIMIZED_BLEND),
            "source_sha256": source_sha_after,
            "components": [
                {
                    "slug": c["slug"],
                    "size_m": c["bounds_size_m"],
                    "triangles": optimize_stats.get(f"{c['slug']}_视觉", {}).get("triangles_after"),
                    "glb_bytes": export_results[c["slug"]]["glb_bytes"],
                }
                for c in catalog
            ],
        },
        ensure_ascii=False,
        indent=1,
    ))


main()
