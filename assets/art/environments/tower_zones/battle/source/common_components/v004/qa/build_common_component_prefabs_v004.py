"""为战局通用组件库生成范式 B 的 runtime PackedScene（五件）。

范式 B（自包含可替换组件）= 模型 + 碰撞同包、逐实例化：
  <slug>_root_top3d.tscn
    ├─ Node3D 根（承载全部 metadata 契约）
    ├─ ImportedModel       <- 实例化 <slug>_visual_top3d.glb
    └─ <Slug>Collision (StaticBody3D, layer 1 / mask 0)
         └─ CollisionShape3D × N（BoxShape3D）

版本号默认取本脚本所在版本目录名，也可用 `--version vNNN` 指定；版本号只写进
`metadata/asset_version` 与摘要，**Godot 侧路径恒定、不含版本号**。

碰撞按「结构」而非「美术」：
  这次并进组件的是房内装甲壁板 / 地砖装饰 / 门禁，都是**表面装饰**，
  不改变组件的结构体积。故碰撞盒与 v003 完全一致——
    wall_standard_5m  1 shape，5.0 x 11.9 x 0.3，中心 y=5.95
    wall_door_5m      3 shape，左右门垛 + 门楣，让出 2.2 x 2.5 门洞
    door_5m           1 shape，2.2 x 2.5 x 0.18，中心 y=1.25
    floor_tile_r01_c01 1 shape，4.94 x 0.056 x 4.94，中心 y=0.028
    floor_tile_r01_c02 1 shape，4.94 x 0.081 x 4.94，中心 y=0.0405
  另把实测「美术包围盒」写成 visual_bounds_size_m 供核对，二者不可混用。

尺寸来源是本目录 qa/export_common_library_v004_summary.json 的实测 AABB
（其本身来自 blend 实测）与 v003 既有包的结构常量，脚本内不写美术估值。

幂等：目标 tscn 已存在且内容一致则跳过。生成前自动备份同名旧文件。
运行：
  "C:/Users/zhuangmenghong/.workbuddy/binaries/python/versions/3.13.12/python.exe" build_common_component_prefabs_v004.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent          # .../<版本>/qa
VERSION_DIR = HERE.parent                       # .../<版本>
SOURCE_DIR = VERSION_DIR.parent.parent          # .../source
BATTLE = SOURCE_DIR.parent                      # .../battle
ROOT = BATTLE.parents[4]                        # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

# 版本号只写进 metadata 与摘要；Godot 侧 runtime 路径恒定、不含版本号。
VERSION = grn.version_from_argv(VERSION_DIR.name)
RUNTIME_DIR = BATTLE / "runtime" / "common_components"
SUMMARY = HERE / f"export_common_library_{VERSION}_summary.json"

LIBRARY_ID = "ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY"
LIBRARY_ROOT = "res://assets/art/environments/tower_zones/battle"

# 权威常量（写进 metadata 便于运行时与验证脚本交叉核对）
GRID_UNIT_M = 5.0
WALL_THICKNESS_M = 0.3
WALL_VISUAL_HEIGHT_M = 11.9
WALL_LOGICAL_HEIGHT_M = 12.0
DOOR_CLEAR_WIDTH_M = 2.2
DOOR_CLEAR_HEIGHT_M = 2.5
PANEL_THICKNESS_M = 0.18
PIER_WIDTH_M = (GRID_UNIT_M - DOOR_CLEAR_WIDTH_M) / 2.0        # 1.4
LINTEL_HEIGHT_M = WALL_VISUAL_HEIGHT_M - DOOR_CLEAR_HEIGHT_M   # 9.4

# slug: 出包子目录（地砖两件共用 floor_tile_5m）
OUT_SUBDIR = {
    "wall_standard_5m": "wall_standard_5m",
    "wall_door_5m": "wall_door_5m",
    "door_5m": "door_5m",
    "floor_tile_r01_c01": "floor_tile_5m",
    "floor_tile_r01_c02": "floor_tile_5m",
}

ASSETS = {
    "wall_standard_5m": {
        "node_name": "BattleCommonWallStandard5m",
        "asset_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
        "category": "08_墙壁组件",
        "category_meta": "08_wall_component",
        "display_name": "战局通用标准墙 5×0.3×11.9m（含 5m 槽位装甲壁板）",
        "body": "WallStandardCollision",
        "collision_policy": "embedded_box_bottom_center",
        "shapes": [("wall_standard_5m_1", [GRID_UNIT_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M],
                    [0.0, WALL_VISUAL_HEIGHT_M / 2.0, 0.0])],
        "meta": [
            ("wall_kind", "solid"),
            ("wall_thickness_m", WALL_THICKNESS_M),
            ("wall_visual_height_m", WALL_VISUAL_HEIGHT_M),
            ("wall_logical_height_m", WALL_LOGICAL_HEIGHT_M),
            ("visual_top_clearance_m", round(WALL_LOGICAL_HEIGHT_M - WALL_VISUAL_HEIGHT_M, 4)),
            ("grid_unit_m", GRID_UNIT_M),
        ],
        "notes": [
            "静态实墙，与网格 5m 同宽，可直接沿网格平铺。",
            "美术已并进房内同款「内嵌装甲壁板」（2.4m 壁板 ×2 + 板缝压条），"
            "在组件局部 +Y（朝房内那面）离面约 15mm；任何 5m 槽位/朝向都自动对齐。",
        ],
    },
    "wall_door_5m": {
        "node_name": "BattleCommonWallDoor5m",
        "asset_id": "ENV-BATTLE-COMMON-WALL-DOOR-5M",
        "category": "08_墙壁组件",
        "category_meta": "08_wall_component",
        "display_name": "战局通用门墙 5×0.3×11.9m（门洞 2.2×2.5，含装甲门禁）",
        "body": "WallDoorCollision",
        "collision_policy": "embedded_three_box_bottom_center",
        "shapes": [
            ("wall_door_5m_pier_l", [PIER_WIDTH_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M],
             [-(DOOR_CLEAR_WIDTH_M / 2.0 + PIER_WIDTH_M / 2.0), WALL_VISUAL_HEIGHT_M / 2.0, 0.0]),
            ("wall_door_5m_pier_r", [PIER_WIDTH_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M],
             [DOOR_CLEAR_WIDTH_M / 2.0 + PIER_WIDTH_M / 2.0, WALL_VISUAL_HEIGHT_M / 2.0, 0.0]),
            ("wall_door_5m_lintel", [DOOR_CLEAR_WIDTH_M, LINTEL_HEIGHT_M, WALL_THICKNESS_M],
             [0.0, DOOR_CLEAR_HEIGHT_M + LINTEL_HEIGHT_M / 2.0, 0.0]),
        ],
        "meta": [
            ("wall_kind", "door_portal"),
            ("wall_thickness_m", WALL_THICKNESS_M),
            ("wall_visual_height_m", WALL_VISUAL_HEIGHT_M),
            ("wall_logical_height_m", WALL_LOGICAL_HEIGHT_M),
            ("grid_unit_m", GRID_UNIT_M),
            ("door_clear_width_m", DOOR_CLEAR_WIDTH_M),
            ("door_clear_height_m", DOOR_CLEAR_HEIGHT_M),
            ("pier_width_m", round(PIER_WIDTH_M, 4)),
            ("lintel_height_m", round(LINTEL_HEIGHT_M, 4)),
        ],
        "notes": [
            "墙体由左门垛、右门垛、门楣三块组成，中间正好让出 2.2×2.5 门洞。",
            "门洞尺寸取自 TowerGeometry3D.DOOR_CLEAR_WIDTH_M / DOOR_CLEAR_HEIGHT_M，与 door_5m 门扇严格配对。",
            "美术已并进房内同款「装甲门禁」（门框立柱 + 门楣装甲 + 门扇面 + 状态灯 + 门禁屏），"
            "12 件装饰随组件走；门洞处不产生碰撞，通行由门扇或宿主门逻辑负责。",
        ],
    },
    "door_5m": {
        "node_name": "BattleCommonDoor5m",
        "asset_id": "ENV-BATTLE-COMMON-DOOR-5M",
        "category": "10_门组件",
        "category_meta": "10_door_component",
        "display_name": "战局通用门扇 2.2×0.18×2.5m",
        "body": "DoorCollision",
        "collision_policy": "embedded_box_bottom_center",
        "shapes": [("door_5m_1", [DOOR_CLEAR_WIDTH_M, DOOR_CLEAR_HEIGHT_M, PANEL_THICKNESS_M],
                    [0.0, DOOR_CLEAR_HEIGHT_M / 2.0, 0.0])],
        "meta": [
            ("door_clear_width_m", DOOR_CLEAR_WIDTH_M),
            ("door_clear_height_m", DOOR_CLEAR_HEIGHT_M),
            ("panel_thickness_m", PANEL_THICKNESS_M),
            ("open_mode", "vertical_lift"),
            ("panel_origin_policy", "bottom_center"),
        ],
        "notes": [
            "门扇为底边中心原点，接入时 visual.position.y = -DOOR_CLEAR_HEIGHT_M * 0.5 即可落在 DoorPanel 动画根上。",
            "开门方式是垂直升起（RoomDoor3D.set_open 改 panel.position.y），不是旋转，故原点无需落在铰链轴上。",
            "本件美术未变（房间没有给门扇附加件）；装甲门禁在 wall_door_5m 上。",
        ],
    },
    "floor_tile_r01_c01": {
        "node_name": "BattleCommonFloorTileR01C01",
        "asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
        "category": "09_地板组件",
        "category_meta": "09_floor_component",
        "display_name": "战局通用地砖 4.94×4.94m（含压边/拼缝/标识/检修格栅）",
        "body": "FloorTileCollision",
        "collision_policy": "embedded_box_bottom_center",
        "shapes": [("floor_tile_r01_c01", [4.94, 0.056, 4.94], [0.0, 0.028, 0.0])],
        "meta": [
            ("footprint_m", 4.94),
            ("thickness_m", 0.056),
            ("runtime_grid_unit_m", GRID_UNIT_M),
            ("tile_gap_m", 0.06),
            ("runtime_owner", "TowerFloorStage3D"),
            # 注意：不能叫 runtime_instantiation —— 基线 meta 已用该键声明「逐实例化 prefab」，
            # 名字撞了会让地板把自己的整层拼装口径覆盖掉基线契约。故用专属键名。
            ("runtime_floor_composition", "multi_mesh_ab_chessboard"),
            ("runtime_floor_thickness_m", 0.3),
            ("runtime_walk_plane_y", 0.0),
            ("runtime_collision_owner", "TowerFloorStage3D._build_support"),
            ("runtime_collision_note",
             "运行时地砖是整层矩形承重碰撞；本组件内嵌逐砖碰撞，接入前须与 _build_support() 去重。"),
            # snap_note 不在此处写死：由 builder 依据本偏移统一生成，避免同键写两遍。
            ("snap_to_walk_plane_offset_m", -0.056),
        ],
        "notes": [
            "c01 = 棋盘格角块与中心块；四边 5 块一律带「检修格栅」装饰，是唯一干净的一版。",
            "结构（砖体 0..0.04 + 内嵌上板 0.035..0.056）与房间 FLOORSLOT_* + FLOORSLOT_*_INSET 逐面相同，"
            "v004 只把砖面装饰并了进来。",
        ],
    },
    "floor_tile_r01_c02": {
        "node_name": "BattleCommonFloorTileR01C02",
        "asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
        "category": "09_地板组件",
        "category_meta": "09_floor_component",
        "display_name": "战局通用地砖 4.94×4.94m（含压边/拼缝/标识/方形检修盖）",
        "body": "FloorTileCollision",
        "collision_policy": "embedded_box_bottom_center",
        "shapes": [("floor_tile_r01_c02", [4.94, 0.081, 4.94], [0.0, 0.0405, 0.0])],
        "meta": [
            ("footprint_m", 4.94),
            ("thickness_m", 0.081),
            ("runtime_grid_unit_m", GRID_UNIT_M),
            ("tile_gap_m", 0.06),
            ("runtime_owner", "TowerFloorStage3D"),
            # 见 c01 处说明：地板专属口径走独立键名，不覆盖基线的 runtime_instantiation。
            ("runtime_floor_composition", "multi_mesh_ab_chessboard"),
            ("runtime_floor_thickness_m", 0.3),
            ("runtime_walk_plane_y", 0.0),
            ("runtime_collision_owner", "TowerFloorStage3D._build_support"),
            ("runtime_collision_note",
             "运行时地砖是整层矩形承重碰撞；本组件内嵌逐砖碰撞，接入前须与 _build_support() 去重。"),
            ("snap_to_walk_plane_offset_m", -0.081),
        ],
        "notes": [
            "c02 = 棋盘格边中块；房内 4 块里 2 块带「方形检修盖」、2 块不带，"
            "本组件统一取带盖的一版（与 v003 c02 内嵌上板同一版，未删任何已画美术）。",
        ],
    },
}


def fmt_vector(values) -> str:
    return "Vector3(%s)" % ", ".join(
        str(int(v)) if float(v).is_integer() else repr(round(float(v), 6)) for v in values
    )


def fmt_num(value) -> str:
    """把数值渲染成人话（整数去掉小数点，小数保留原样），供拼接说明文字用。"""
    number = float(value)
    return str(int(number)) if number.is_integer() else repr(round(number, 6))


def fmt_scalar(value) -> str:
    """按 Godot .tscn 的字面量语法格式化 metadata 取值。

    字符串必须带双引号，否则 Godot 会把 ENV-BATTLE-... 当表达式求值；
    Vector3(...) 这类构造表达式恰恰不能带引号，故单独放行。
    """
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else repr(value)
    text = str(value)
    if text.startswith("Vector3("):
        return text
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def build_scene(slug: str, spec: dict, visual_bounds: list, blend_name: str) -> str:
    sub = OUT_SUBDIR[slug]
    visual_path = (f"{LIBRARY_ROOT}/components/common_components/{sub}/"
                   f"{grn.visual_glb_name(slug)}")
    manifest_path = (f"{LIBRARY_ROOT}/source/common_components/{VERSION}/component_packages_{VERSION}/"
                     f"{spec['category'][:2]}/{slug}/asset_manifest.json")
    source_blend = f"{LIBRARY_ROOT}/source/common_components/{VERSION}/{blend_name}"

    xs, ys, zs = [], [], []
    for _sid, size, center in spec["shapes"]:
        xs += [center[0] - size[0] / 2.0, center[0] + size[0] / 2.0]
        ys += [center[1] - size[1] / 2.0, center[1] + size[1] / 2.0]
        zs += [center[2] - size[2] / 2.0, center[2] + size[2] / 2.0]
    structure = [round(max(xs) - min(xs), 4), round(max(ys) - min(ys), 4), round(max(zs) - min(zs), 4)]

    load_steps = 1 + 1 + len(spec["shapes"])
    lines = []
    lines.append(f"[gd_scene load_steps={load_steps} format=3]")
    lines.append("")
    lines.append(f"; Stable AssetID: {spec['asset_id']}")
    lines.append(f"; 战局区块通用组件库 {VERSION} · {spec['category']} · {slug}")
    lines.append("; 范式 B（自包含可替换组件）：模型 + 碰撞同包，逐实例化。")
    lines.append("; 原点契约 = 底面中心（Blender 底面 Z=0 → Godot 底面 Y=0），与全库一致。")
    lines.append(f"; 本版把 entry_safe_room v006 的墙/地/门美术并进组件；不按方位区分，任意槽位自动对齐。")
    for note in spec["notes"]:
        lines.append(f"; {note}")
    lines.append("")
    lines.append(f'[ext_resource type="PackedScene" path="{visual_path}" id="1_visual"]')
    lines.append("")
    for sid, size, _center in spec["shapes"]:
        lines.append(f'[sub_resource type="BoxShape3D" id="BoxShape3D_{sid}"]')
        lines.append(f"size = {fmt_vector(size)}")
        lines.append("")

    lines.append(f'[node name="{spec["node_name"]}" type="Node3D"]')
    meta_pairs = [
        ("asset_id", spec["asset_id"]),
        ("asset_version", VERSION),
        ("library_id", LIBRARY_ID),
        ("library_root", LIBRARY_ROOT),
        ("category", spec["category_meta"]),
        ("component", slug),
        ("logic_id", slug),
        ("display_name_zh", spec["display_name"]),
        ("source_blend", source_blend),
        ("source_collection", f"{slug}_通用包"),
        ("source_root_object", f"ROOT_{slug}_通用组件"),
        ("source_manifest", manifest_path),
        ("origin_contract", "bottom_center"),
        ("forward_axis", "-Z"),
        ("up_axis", "+Y"),
        ("bounds_size_m", fmt_vector(structure)),
        ("visual_bounds_size_m", fmt_vector(visual_bounds)),
        ("bounds_note", "bounds_size_m 是结构/碰撞包围盒；visual_bounds_size_m 是并入美术后的实测可视包围盒。"),
        ("preserve_authored_palette", True),
        ("collision_owner", "self"),
        ("collision_policy", spec["collision_policy"]),
        ("collision_shape_count", len(spec["shapes"])),
        ("collision_structure_note", "碰撞按结构不按美术：装饰件不改变组件体积，碰撞盒与 v003 一致。"),
        ("runtime_instantiation", "per_instance_prefab"),
        ("supersedes", "v003"),
        ("carries_room_art_from", "assets/art/environments/tower_zones/battle/source/room_instances/entry_safe_room/v006"),
    ]
    meta_pairs += [(k, v) for k, v in spec["meta"]]
    if slug.startswith("floor_tile"):
        # 落位偏移从 spec 里那一条 snap_to_walk_plane_offset_m 取真实值再拼句子，
        # 不再从「最后一条 meta」反推（那正是上一版拼出双重句子的原因）。
        walk_offset = dict(spec["meta"])["snap_to_walk_plane_offset_m"]
        meta_pairs += [
            ("snap_note",
             "底面中心原点；若要求地砖结构顶面与行走面 Y=0 齐平，实例另加 y=%s。" % fmt_num(walk_offset)),
        ]
    else:
        meta_pairs += [
            ("snap_to_ground_offset_m", 0.0),
            ("snap_note", "底面中心原点，直接放在目标地面 Y 上即可，无需额外偏移。"),
        ]
    # 同一个 metadata 键写两遍会让后者静默覆盖前者：契约会以「最后一条」为准，
    # 排查时极难发现。故在这里硬拦，宁可构建失败也不放出语义含糊的场景。
    seen_keys: set = set()
    duplicated = []
    for key, _value in meta_pairs:
        if key in seen_keys:
            duplicated.append(key)
        seen_keys.add(key)
    if duplicated:
        raise SystemExit(
            "asset %s 的 metadata 出现重复键 %s；请让每个键只声明一次" % (slug, sorted(set(duplicated)))
        )
    grn.require_version_metadata(meta_pairs, VERSION, script=Path(__file__).name)
    for key, value in meta_pairs:
        lines.append(f"metadata/{key} = {fmt_scalar(value)}")
    lines.append("")
    lines.append('[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]')
    lines.append("")
    lines.append(f'[node name="{spec["body"]}" type="StaticBody3D" parent="."]')
    lines.append("collision_layer = 1")
    lines.append("collision_mask = 0")
    lines.append("")
    for index, (sid, _size, center) in enumerate(spec["shapes"]):
        suffix = "" if index == 0 else "_%d" % (index + 1)
        lines.append(f'[node name="CollisionShape3D{suffix}" type="CollisionShape3D" parent="{spec["body"]}"]')
        lines.append(f"position = {fmt_vector(center)}")
        lines.append(f'shape = SubResource("BoxShape3D_{sid}")')
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    for sub in sorted(set(OUT_SUBDIR.values())):
        grn.guard_no_legacy_versioned(
            RUNTIME_DIR / sub, script=Path(__file__).name, allow=grn.allow_legacy_from_argv()
        )
    summary = json.loads(SUMMARY.read_text(encoding="utf8"))
    blend_name = f"战局区块_通用组件库_{VERSION}.blend"
    results = {}
    for slug, spec in ASSETS.items():
        if slug not in summary:
            raise SystemExit(f"导出摘要里缺少 {slug}，先跑 export_common_library_{VERSION}.py")
        visual_bounds = summary[slug]["godot_size_xyz"]
        out_dir = RUNTIME_DIR / OUT_SUBDIR[slug]
        out_dir.mkdir(parents=True, exist_ok=True)
        target = out_dir / grn.root_scene_name(slug)
        content = build_scene(slug, spec, visual_bounds, blend_name)
        if target.is_file() and target.read_text(encoding="utf-8") == content:
            print(f"SKIP {slug}: 内容已一致（幂等）")
            results[slug] = {"status": "unchanged", "path": str(target)}
            continue
        target.write_text(content, encoding="utf-8")
        print(f"WROTE {slug} -> {target}")
        results[slug] = {"status": "written", "path": str(target), "shapes": len(spec["shapes"])}

    invalid = [s for s in results if not (RUNTIME_DIR / OUT_SUBDIR[s] /
                                         grn.root_scene_name(s)).is_file()]
    if invalid:
        raise SystemExit(f"生成后仍缺文件: {invalid}")
    print("PREFAB_REPORT " + str(results))
    print(f"PREFAB_OK total={len(results)} written={sum(1 for v in results.values() if v['status'] == 'written')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
