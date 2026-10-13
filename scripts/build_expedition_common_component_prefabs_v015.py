#!/usr/bin/env python3
"""为远征关卡02 通用组件库 v015 生成 Godot 包装场景（*_root_top3d.tscn）。

Run with:
    python scripts/build_expedition_common_component_prefabs_v015.py

口径与远征01 / 战局的组件包装**逐字一致**（见
`assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/`）：

    [gd_scene] → [ext_resource 视觉 GLB] → [sub_resource BoxShape3D...]
    → [node 根 Node3D（带 metadata）]
    → [node ImportedModel instance=GLB]
    → [node CollisionBody StaticBody3D layer=1] → [CollisionShape3D...]

坐标换算（Blender Z-up → Godot Y-up，导出时 `export_yup=True`）：

    Godot.x = Blender.x ; Godot.y = Blender.z ; Godot.z = -Blender.y

墙厚在 Blender 沿 Y，所以到 Godot 后落在 **Z** 轴 ⇒ `bounds = Vector3(5, H, 0.3)`，
与战局 `wall_standard_5m` 的 `Vector3(5, 11.9, 0.3)` 同口径，`forward_axis = "-Z"`。

🔴 封顶件（`ceiling_deck_5m`）的碰撞盒 **必须 layer=1** —— 这是 `06 §7.3.1`
封顶件硬契约：怪物身体采样点朝太阳打射线被它挡住，房间才判为「不受日照」。
少一个 layer=1 的顶盖，整层会漏光，而且**画面上看不出来**。
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "v015"
LEVEL_ID = "expedition_02"
LIBRARY_ID = "ENV-EXPEDITION-COMMON-COMPONENT-LIBRARY"

SOURCE_DIR = ROOT / "art_source/environments/tower_zones/expedition/source/common_components" / VERSION
PACKAGE_DIR = SOURCE_DIR / f"component_packages_{VERSION}"
PALETTE_REL = "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
PALETTE_POST_IMPORT = "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"

# ---- 封顶装配高度（2026-10-12 业主裁定）--------------------------------------
# 3m 墙的顶盖**不**贴墙顶，而是抬到 4.0 —— 保留 1.0m 管线空腔（吊顶/走线/风管）。
# 数值体系（世界 Y，墙底 = 0；走面 WALK_PLANE_Z = 0.30）：
#     墙顶        3.00
#     顶盖底面    4.00   ← 装配时把 ceiling_deck_5m 放在这个 Y
#     顶盖上表面  4.26
#     ⇒ 走面到顶盖底净高 = 4.00 − 0.30 = **3.70 m**
#     ⇒ 墙顶到顶盖底空腔 = 4.00 − 3.00 = **1.00 m**
# 约束核查：净高 3.70 > 楣底 2.80（门能过）✓；> 刷怪净空假设 2.60（DungeonRoom3D.gd）✓。
CEILING_ASSEMBLY_BOTTOM_Y = 4.0
CEILING_PLENUM_M = 1.0
WALK_PLANE_Z = 0.3
CEILING_HEADROOM_M = round(CEILING_ASSEMBLY_BOTTOM_Y - WALK_PLANE_Z, 4)   # 3.7
## 门楣底（TowerGeometry3D：门槛底 0.30 + 门净高 2.50）。封顶净高必须高于它，否则门过不去。
DOOR_LINTEL_BOTTOM = 2.8

GLB_REL = "res://assets/art/environments/tower_zones/expedition/components/common_components"
RUNTIME_REL = "res://assets/art/environments/tower_zones/expedition/runtime/common_components"
LIBRARY_ROOT_REL = "res://assets/art/environments/tower_zones/expedition"

# ---- 每个组件的包装定义 -----------------------------------------------------
# root_class 用中文语义名；collision 是 [(盒名, Godot 中心, Godot 尺寸), ...]
PREFABS = [
    {
        "slug": "wall_standard_5m_h3",
        "root_class": "ExpeditionCommonWallStandard5mH3",
        "component": "wall_standard_5m_h3",
        "logic_id": "wall_standard_5m",
        "wall_kind": "solid",
        "hint": "低矮层实墙：5.00×0.30×3.00m，一槽一件，可直接沿 5m 网格平铺。",
        "collision": [("BoxShape3D_wall_standard_5m_h3", (0.0, 1.5, 0.0), (5.0, 3.0, 0.3))],
        "collision_policy": "embedded_box_bottom_center",
    },
    {
        "slug": "wall_door_5m_h3",
        "root_class": "ExpeditionCommonWallDoor5mH3",
        "component": "wall_door_5m_h3",
        "logic_id": "wall_door_5m",
        "wall_kind": "door_portal",
        "hint": (
            "低矮层门墙：5.00×0.30×3.00m，左/右门垛 + 门楣，正好让出 2.2×2.5 门洞。"
            "⚠️ 3m 墙上楣底 2.80 ⇒ 门楣只有 0.20 高，不是错值。"
        ),
        "collision": [
            ("BoxShape3D_wall_door_5m_h3_pier_l", (-1.8, 1.5, 0.0), (1.4, 3.0, 0.3)),
            ("BoxShape3D_wall_door_5m_h3_pier_r", (1.8, 1.5, 0.0), (1.4, 3.0, 0.3)),
            ("BoxShape3D_wall_door_5m_h3_lintel", (0.0, 2.9, 0.0), (2.2, 0.2, 0.3)),
        ],
        "collision_policy": "embedded_three_box_bottom_center",
    },
    {
        "slug": "wall_collapse_5m_h12",
        "root_class": "ExpeditionCommonWallCollapse5mH12",
        "component": "wall_collapse_5m_h12",
        "logic_id": "wall_collapse_5m",
        "wall_kind": "collapse_portal",
        "hint": (
            "坍塌门洞：占位 5.00×0.30×11.90m，只有上方门楣有实体（5.00×0.30×9.10）。"
            "洞口占满一整格、无门垛、高 2.5m（比标准门矮 0.5m）。只用在挑高前厅↔长廊。"
        ),
        "collision": [("BoxShape3D_wall_collapse_5m_h12", (0.0, 7.35, 0.0), (5.0, 9.1, 0.3))],
        "collision_policy": "embedded_box_bottom_center",
    },
    {
        "slug": "wall_standard_5m_h12",
        "root_class": "ExpeditionCommonWallStandard5mH12",
        "component": "wall_standard_5m_h12",
        "logic_id": "wall_standard_5m",
        "wall_kind": "solid",
        "hint": "通高层实墙：5.00×0.30×11.90m，高度 = 项目基线 WALL_VISUAL_HEIGHT_M。只用在挑高前厅。",
        "collision": [("BoxShape3D_wall_standard_5m_h12", (0.0, 5.95, 0.0), (5.0, 11.9, 0.3))],
        "collision_policy": "embedded_box_bottom_center",
        "wall_visual_height": 11.9,
    },
    {
        "slug": "wall_door_5m_h12",
        "root_class": "ExpeditionCommonWallDoor5mH12",
        "component": "wall_door_5m_h12",
        "logic_id": "wall_door_5m",
        "wall_kind": "door_portal",
        "hint": (
            "通高层门墙：5.00×0.30×11.90m，门垛与墙同高、门楣 9.10（11.90 − 2.80）。"
            "白盒里只有 1 扇（阳台安全屋 → 挑高前厅）。"
        ),
        "collision": [
            ("BoxShape3D_wall_door_5m_h12_pier_l", (-1.8, 5.95, 0.0), (1.4, 11.9, 0.3)),
            ("BoxShape3D_wall_door_5m_h12_pier_r", (1.8, 5.95, 0.0), (1.4, 11.9, 0.3)),
            ("BoxShape3D_wall_door_5m_h12_lintel", (0.0, 7.35, 0.0), (2.2, 9.1, 0.3)),
        ],
        "collision_policy": "embedded_three_box_bottom_center",
        "wall_visual_height": 11.9,
        "door_portal": True,
    },
    {
        "slug": "floor_tile_5m",
        "root_class": "ExpeditionCommonFloorTile5m",
        "component": "floor_tile_5m",
        "logic_id": "floor_tile",
        "wall_kind": "",
        "hint": "通用地砖：4.94×4.94×0.04m，铺在 floor_base_5m 顶面（0.26）到走面 0.30。四面留 0.03 缝。",
        "collision": [],
        "collision_policy": "visual_only_no_collision",
        "no_collision": True,
    },
    {
        "slug": "ceiling_deck_5m",
        "root_class": "ExpeditionCommonCeilingDeck5m",
        "component": "ceiling_deck_5m",
        "logic_id": "ceiling_deck",
        "wall_kind": "",
        "hint": (
            "封顶模块：5.00×5.00×0.26m。按 06 §7.3.1 封顶件硬契约，"
            "碰撞盒 layer=1 —— 挡住朝太阳的采样射线，房间才判为「不受日照」。"
        ),
        "collision": [("BoxShape3D_ceiling_deck_5m", (0.0, 0.13, 0.0), (5.0, 0.26, 5.0))],
        "collision_policy": "embedded_box_bottom_center",
        "sun_occlusion": True,
        "slot_role": "top_cover",
        # 摄像机竖直夹镜：本件是房间顶盖，必须参与 TowerDescent3D 的
        # 「头顶楼板压低镜头」逻辑，否则默认相机(9.99m)停在顶盖(3.2m)之上，
        # 画面被顶盖顶面挡住、看不见角色。
        "camera_ceiling_occluder": True,
    },
    {
        "slug": "floor_base_5m",
        "root_class": "ExpeditionCommonFloorBase5m",
        "component": "floor_base_5m",
        "logic_id": "floor_base",
        "wall_kind": "",
        "hint": "地板底层模块：5.00×5.00×0.26m，顶面 0.26，地砖（0.04）叠在上面到走面 0.30。",
        "collision": [("BoxShape3D_floor_base_5m", (0.0, 0.13, 0.0), (5.0, 0.26, 5.0))],
        "collision_policy": "embedded_box_bottom_center",
    },
]


def vec3(v) -> str:
    return "Vector3(%s)" % ", ".join("%g" % x for x in v)


def build_tscn(spec: dict, manifest: dict) -> str:
    slug = spec["slug"]
    visual_rel = f"{GLB_REL}/{slug}/{slug}_visual_top3d.glb"
    slot = manifest["slot_size_m"]                     # Blender XYZ
    visual = manifest["visual_bounds_size_m"]          # Blender XYZ
    # Blender (X, Y, Z) → Godot (X, Z, Y')
    slot_godot = (slot[0], slot[2], slot[1])
    visual_godot = (visual[0], visual[2], visual[1])
    boxes = spec["collision"]

    out: list[str] = []
    out.append("[gd_scene load_steps=%d format=3]" % (len(boxes) + 2))
    out.append("")
    out.append(f"; Stable AssetID: {manifest['asset_id']}")
    out.append(f"; 远征关卡02 通用组件库 {VERSION} · {manifest['category']} · {slug}")
    out.append("; 范式 B（自包含可替换组件）：视觉 GLB + 碰撞同包，逐实例化。")
    out.append("; 原点契约 = 底面中心（Blender 底面 Z=0 → Godot 底面 Y=0），与全库一致。")
    out.append("; Godot 朝向 = -Z（墙长沿 X、墙厚沿 Z），与战局通用组件同口径。")
    out.append(f"; {spec['hint']}")
    out.append(";")
    out.append(f"; 共享色盘：{PALETTE_REL}")
    out.append(f"; 导入后处理：{PALETTE_POST_IMPORT}")
    out.append(f"; GLB 内嵌图片数 = 0（导出时 export_image_format=NONE）")
    out.append("")
    out.append(f'[ext_resource type="PackedScene" path="{visual_rel}" id="1_visual"]')
    out.append("")
    for name, center, size in boxes:
        out.append(f'[sub_resource type="BoxShape3D" id="{name}"]')
        out.append(f"size = {vec3(size)}")
        out.append("")
    out.append(f'[node name="{spec["root_class"]}" type="Node3D"]')
    out.append(f'metadata/asset_id = "{manifest["asset_id"]}"')
    out.append(f'metadata/asset_version = "{VERSION}"')
    out.append(f'metadata/library_id = "{LIBRARY_ID}"')
    out.append(f'metadata/library_root = "{LIBRARY_ROOT_REL}"')
    out.append(f'metadata/level_id = "{LEVEL_ID}"')
    out.append(f'metadata/category = "{manifest["category"]}"')
    out.append(f'metadata/component = "{slug}"')
    out.append(f'metadata/logic_id = "{spec["logic_id"]}"')
    out.append(f'metadata/display_name_zh = "{manifest["name_zh"]}"')
    # 🔴 必须写 res:// 形式：tscn 字符串里的 Windows 反斜杠会被当成转义符，
    #    写成绝对路径 Godot 会读成乱码（`\工` 是无效转义）。
    source_rel = _res(manifest["source_blend"])
    out.append(f'metadata/source_blend = "{source_rel}"')
    out.append(f'metadata/source_manifest = "{_res(str(PACKAGE_DIR))}/{slug}/asset_manifest.json"')
    out.append('metadata/origin_contract = "bottom_center"')
    out.append('metadata/forward_axis = "-Z"')
    out.append('metadata/up_axis = "+Y"')
    out.append(f"metadata/bounds_size_m = {vec3(slot_godot)}")
    out.append(f"metadata/visual_bounds_size_m = {vec3(visual_godot)}")
    out.append(f"metadata/slot_size_m = {vec3(slot_godot)}")
    if slot != visual:
        out.append('metadata/bounds_note = "bounds_size_m/slot_size_m 是 5m 网格占位（洞口计入）；visual_bounds_size_m 是可视几何包围盒。两者在本件上不同（洞口无实体）。"')
    out.append('metadata/preserve_authored_palette = true')
    out.append(f'metadata/shared_palette = "{PALETTE_REL}"')
    out.append(f'metadata/palette_post_import = "{PALETTE_POST_IMPORT}"')
    out.append(f'metadata/collision_owner = "{"none" if not boxes else "self"}"')
    out.append(f'metadata/collision_policy = "{spec["collision_policy"]}"')
    out.append(f'metadata/collision_shape_count = {len(boxes)}')
    out.append('metadata/runtime_instantiation = "per_instance_prefab"')
    out.append('metadata/grid_unit_m = 5')
    if spec["wall_kind"]:
        out.append(f'metadata/wall_kind = "{spec["wall_kind"]}"')
        out.append('metadata/wall_thickness_m = 0.3')
    if spec.get("wall_visual_height"):
        height = spec["wall_visual_height"]
        out.append(f"metadata/wall_visual_height_m = {height:g}")
        out.append(f"metadata/wall_logical_height_m = {height:g}")
    if spec.get("door_portal"):
        out.append("metadata/door_clear_width_m = 2.2")
        out.append("metadata/door_clear_height_m = 2.5")
        out.append("metadata/pier_width_m = 1.4")
        out.append(f"metadata/lintel_height_m = {11.9 - 2.8:g}")
        out.append('metadata/lintel_note = "11.90 墙高 − 2.80 楣底 = 9.10 过梁。"')
    if slug == "wall_door_5m_h3":
        out.append("metadata/door_clear_width_m = 2.2")
        out.append("metadata/door_clear_height_m = 2.5")
        out.append("metadata/pier_width_m = 1.4")
        out.append("metadata/lintel_height_m = 0.2")
        out.append('metadata/lintel_note = "3.00 墙高 − 2.80 楣底 = 0.20 过梁。数值小是既有门契约（TowerGeometry3D.DOOR_CLEAR_HEIGHT_M）决定的，不是错值。"')
    if slug == "wall_collapse_5m_h12":
        out.append("metadata/collapse_clear_width_m = 5.0")
        out.append("metadata/collapse_clear_height_m = 2.5")
        out.append('metadata/collapse_note = "洞口占满一整格、无门垛；只有 2.5m 高，比标准门矮 0.5m。"')
    if spec.get("no_collision"):
        out.append('metadata/no_collision_reason = "纯视觉面砖：底面由 floor_base_5m 承重，本件不参与阻挡，也不参与遮光判定。"')
    if spec.get("sun_occlusion"):
        out.append('metadata/slot_role = "top_cover"')
        out.append('metadata/top_cover_occluder = true')
        out.append(f"metadata/assembly_bottom_y_m = {CEILING_ASSEMBLY_BOTTOM_Y:g}")
        out.append(f"metadata/assembly_plenum_m = {CEILING_PLENUM_M:g}")
        out.append(f"metadata/headroom_above_walk_plane_m = {CEILING_HEADROOM_M:g}")
        out.append('metadata/assembly_note = "装配高度契约（2026-10-12 业主裁定）：顶盖底面放在世界 Y = 3.2，不贴墙顶(3.0)，让出 0.2m 管线空腔。走面(0.30)到顶盖底净高 = 2.90m；2.90 > 楣底 2.80 ⇒ 门能过；> 刷怪净空假设 2.60 ⇒ 安全。"')
        out.append('metadata/assembly_height_owner = "房间 tscn 装配时施加；本组件自身原点仍是底面中心（放在目标 Y 上即可）。"')
        out.append('metadata/sun_occlusion_contract = "06 §7.3.1：顶盖必须带 layer=1 碰撞。CollisionBody.collision_layer=1 是本件成立「封顶=不受日照」的硬条件，不得改成 0。"')
        out.append('metadata/top_cover_note = "水平顶盖不是墙：不写 wall_kind、不进墙/门槽 lane 台账。口径对齐 generate_expedition_room_type_prefabs.TOP_COVER_OCCLUDER_SLUGS（那份表只扫 room_type_components，本件在 common_components，故在本脚本里另有对等断言）。"')
        out.append('metadata/sun_occlusion_verified_by = "src/enemy3d/EnemyIllumination3D._evaluate_sunlight（向太阳打射线，被本碰撞盒挡住即判为非日照）"')
    out.append('metadata/snap_to_ground_offset_m = 0')
    out.append('metadata/snap_note = "底面中心原点，直接放在目标地面 Y 上即可，无需额外偏移。"')
    out.append("")
    out.append('[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]')
    out.append("")
    if boxes:
        out.append('[node name="CollisionBody" type="StaticBody3D" parent="."]')
        out.append("collision_layer = 1")
        out.append("collision_mask = 0")
        # ⚠️ 摄像机探针读的是**射线命中的 CollisionObject3D**，所以这类标记
        # 必须写在 CollisionBody 上，写在根节点上读不到。
        if spec.get("wall_kind"):
            # 墙件都可能成为「镜头后墙」：远征02 是自由朝向的 3D 关卡，
            # 不像楼梯间（固定朝向、只标南墙）。缺这个标记，相机在玩家贴墙时
            # 会退到墙外 —— 顶盖把镜头压到 2.62m 之后这一点尤其明显。
            #   `wall_standard_5m_h3` / `-h12`     实墙
            #   `wall_door_5m_h3` / `-h12`         门墙（门垛与门楣同为后墙）
            #   `wall_collapse_5m_h12`             坍塌门洞（只剩门楣）
            out.append("metadata/camera_lower_wall = true")
            out.append(
                'metadata/camera_lower_wall_note = '
                '"TowerDescent3D._find_lower_camera_wall_distance 水平打射线（高度 1.09m、'
                '长 7.47m），命中本碰撞体的 cam 变体即抬高并收镜。'
                '远征02 自由朝向 ⇒ 所有墙件都标，不做南北筛选。"'
            )
        if spec.get("camera_ceiling_occluder"):
            out.append("metadata/camera_ceiling_occluder = true")
            out.append(
                'metadata/camera_ceiling_occluder_role = "room_ceiling"'
            )
            out.append(
                'metadata/camera_ceiling_occluder_note = '
                '"TowerDescent3D._find_stair_slab_camera_clearance_height 向上打射线，'
                '命中本碰撞体即把镜头竖直压到顶盖下方（clearance 0.28m、下限 1.25m）。'
                '缺这个标记，默认相机(9.99m)会停在顶盖(3.2m)之上，画面被顶盖挡住。"'
            )
        out.append("")
        for index, (name, center, size) in enumerate(boxes):
            node_name = "CollisionShape3D" if index == 0 else f"CollisionShape3D_{index + 1}"
            out.append(f'[node name="{node_name}" type="CollisionShape3D" parent="CollisionBody"]')
            out.append(f"position = {vec3(center)}")
            out.append(f'shape = SubResource("{name}")')
            out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def _res(abs_path: str) -> str:
    """把绝对 Windows 路径折成 res:// 形式，只用于注释性 metadata。"""
    p = Path(abs_path)
    try:
        return "res://" + p.relative_to(ROOT).as_posix()
    except ValueError:
        return abs_path.replace("\\", "/")


def patch_import(path: Path) -> bool:
    """把色盘后处理脚本与 embedded_image_handling=0 写进 GLB 的 .import。

    口径与 `scripts/generate_expedition_room_type_prefabs.py::patch_import` 逐字一致
    （项目里 220 个 GLB 的 .import 都带这两项，新件漏掉就会在 Godot 里显示成无贴图灰块，
    且**不会报错**）。`.import` 属于可复现导入契约，必须进版本控制。
    """
    if not path.is_file():
        raise FileNotFoundError(path)
    text = path.read_text(encoding="utf-8")
    if 'import_script/path=""' in text:
        text = text.replace('import_script/path=""', f'import_script/path="{PALETTE_POST_IMPORT}"')
    elif "import_script/path=" not in text:
        raise RuntimeError(f"missing import_script/path in {path}")
    else:
        text = "\n".join(
            f'import_script/path="{PALETTE_POST_IMPORT}"' if line.startswith("import_script/path=") else line
            for line in text.splitlines()
        ) + "\n"
    text = text.replace("gltf/embedded_image_handling=1", "gltf/embedded_image_handling=0")
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
    return True


def assert_top_cover_contract(spec: dict, text: str, slot_godot: tuple) -> list[str]:
    """封顶遮光契约的对等断言（覆盖 common_components 范围）。

    `generate_expedition_room_type_prefabs.assert_top_cover_contract` 只扫
    `room_type_components`，本件在 `common_components` ⇒ 漏在它的网外。这里补上同口径的三条，
    任何一条失败都硬报错：

      1. 顶盖件必须在 prefab 里内嵌 `collision_layer = 1` 的碰撞体
         —— 「封顶天花板画面上有影、僵尸照样晒太阳」的根因永远是这条缺失，而它**不报错**。
      2. 碰撞盒必须覆盖**整个 slot**（水平全包络），不能只盖一部分。
      3. 顶盖不得写 `wall_kind` —— 水平顶盖不是墙，不该进墙/门槽 lane 台账。
      4. 顶盖必须带 `camera_ceiling_occluder`（写在 **CollisionBody** 上）
         —— 少了它，默认相机(9.99m)会停在顶盖(3.2m)之上，画面被顶盖挡住、
         看不见角色。这条同样**不会报任何错**，只会"玩的时候才发现"。
    """
    problems: list[str] = []
    if "collision_layer = 1" not in text:
        problems.append("顶盖件缺 layer=1 碰撞体 —— 封顶会漏光（太阳射线直接穿过）")
    # 判据必须看**行首的 metadata 行**，不能裸搜子串：本文件注释里就写着「不写 wall_kind」，
    # 裸搜会把说明文字当成违规（这个断言自己第一版就踩了）。
    if any(line.startswith("metadata/wall_kind =") for line in text.splitlines()):
        problems.append("顶盖件写了 wall_kind —— 水平顶盖不是墙，不该进墙/门槽 lane 台账")
    # 摄像机标记必须落在 CollisionBody 段内 —— 写在根节点上，射线命中的是
    # CollisionBody，读不到，等于没写。
    if "metadata/camera_ceiling_occluder = true" not in text:
        problems.append(
            "顶盖件缺 camera_ceiling_occluder 标记 —— 相机会停在顶盖之上，"
            "画面被顶盖挡住、看不见角色"
        )
    else:
        body_at = text.find('[node name="CollisionBody"')
        mark_at = text.find("metadata/camera_ceiling_occluder = true")
        if body_at < 0 or mark_at < body_at:
            problems.append(
                "camera_ceiling_occluder 没写在 CollisionBody 段内 —— "
                "射线命中的是 CollisionBody，写在根节点上读不到"
            )
    expect = "size = Vector3(%s)" % ", ".join("%g" % v for v in slot_godot)
    if expect not in text:
        problems.append("顶盖碰撞盒未覆盖整个 slot（期望 %s）" % expect)

    # 装配高度契约：净高必须真的能让标准门通过，且空腔必须为正。
    # 这两条一旦不成立，房间装配出来就是「门框顶到天花板」或「顶盖嵌进墙里」，
    # 而两者都不会让任何既有校验报错。
    if CEILING_HEADROOM_M <= DOOR_LINTEL_BOTTOM:
        problems.append(
            "顶盖装配净高 %.2fm 不高于门楣底 %.2fm —— 标准门会被天花板卡住"
            % (CEILING_HEADROOM_M, DOOR_LINTEL_BOTTOM)
        )
    if CEILING_PLENUM_M <= 0:
        problems.append("顶盖与墙顶的空腔 %.2fm 不为正 —— 没有管线空间，违反本次裁定" % CEILING_PLENUM_M)
    if f"metadata/assembly_bottom_y_m = {CEILING_ASSEMBLY_BOTTOM_Y:g}" not in text:
        problems.append("顶盖件缺 metadata/assembly_bottom_y_m —— 装配高度没有单一真源")
    return problems


def assert_camera_markers(spec: dict, text: str) -> list[str]:
    """摄像机遮挡标记契约。

    两类标记都必须落在 **CollisionBody 段内** —— 射线命中返回的是
    CollisionObject3D，写在根节点上读不到，等于没写（这是静默失败）。

      · 墙件   → `camera_lower_wall`        （镜头后墙，抬高 + 收镜）
      · 顶盖   → `camera_ceiling_occluder`  （头顶楼板，竖直夹镜）
      · 地板/地砖 → 两者都不得带            （它们既不是后墙也不是顶盖）
    """
    problems: list[str] = []
    body_at = text.find('[node name="CollisionBody"')

    def marker_in_body(mark: str) -> bool:
        at = text.find(mark)
        return at >= 0 and body_at >= 0 and at > body_at

    if spec.get("wall_kind"):
        if not marker_in_body("metadata/camera_lower_wall = true"):
            problems.append(
                "墙件缺 camera_lower_wall 标记（或没写在 CollisionBody 上）"
                " —— 玩家贴墙时相机会退到墙外"
            )
    elif spec.get("camera_ceiling_occluder"):
        if not marker_in_body("metadata/camera_ceiling_occluder = true"):
            problems.append(
                "顶盖件缺 camera_ceiling_occluder 标记（或没写在 CollisionBody 上）"
                " —— 相机会停在顶盖之上，画面被顶盖挡住"
            )
    else:
        for mark in ("metadata/camera_lower_wall = true",
                     "metadata/camera_ceiling_occluder = true"):
            if mark in text:
                problems.append(
                    "非墙非顶盖件带了摄像机遮挡标记（%s）" % mark.split("/")[1].split(" =")[0]
                )
    return problems


def main() -> int:
    written, patched = [], []
    failures: list[str] = []
    for spec in PREFABS:
        manifest_path = PACKAGE_DIR / spec["slug"] / "asset_manifest.json"
        if not manifest_path.exists():
            raise SystemExit("找不到组件清单，先跑 build_expedition_common_components_v015.py：%s" % manifest_path)
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        text = build_tscn(spec, manifest)

        if spec.get("sun_occlusion"):
            slot = manifest["slot_size_m"]
            failures += [
                "%s: %s" % (spec["slug"], p)
                for p in assert_top_cover_contract(spec, text, (slot[0], slot[2], slot[1]))
            ]
        failures += [
            "%s: %s" % (spec["slug"], p)
            for p in assert_camera_markers(spec, text)
        ]

        out_dir = ROOT / "assets/art/environments/tower_zones/expedition/runtime/common_components" / spec["slug"]
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / f"{spec['slug']}_root_top3d.tscn"
        out_path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
        written.append(out_path)

        # .import 由 Godot 首次导入生成；生成后才谈得上打色盘契约。
        import_path = (
            ROOT / "assets/art/environments/tower_zones/expedition/components/common_components"
            / spec["slug"] / f"{spec['slug']}_visual_top3d.glb.import"
        )
        if import_path.is_file():
            patch_import(import_path)
            patched.append(import_path)

    if failures:
        raise SystemExit("组件契约失败：\n  - " + "\n  - ".join(failures))

    report = {"written": [p.as_posix() for p in written], "import_patched": len(patched)}
    print("EXPEDITION_COMMON_PREFABS_OK count=%d import_patched=%d "
          "top_cover_contract=OK camera_markers=OK"
          % (len(written), len(patched)))
    print("  ceiling assembly: bottom_y=%.2f plenum=%.2f headroom=%.2f (lintel %.2f)"
          % (CEILING_ASSEMBLY_BOTTOM_Y, CEILING_PLENUM_M, CEILING_HEADROOM_M, DOOR_LINTEL_BOTTOM))
    for path in written:
        print("  tscn  %s" % path.relative_to(ROOT).as_posix())
    for path in patched:
        print("  impl  %s" % path.relative_to(ROOT).as_posix())
    if len(patched) != len(written):
        print("NOTE: 有组件尚未生成 .import —— 先跑 godot --headless --import，再重跑本脚本")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
