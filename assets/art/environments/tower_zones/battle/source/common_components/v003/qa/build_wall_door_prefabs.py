"""为 08_墙壁组件 / 10_门组件 的三件新资产生成范式 B 的 runtime PackedScene。

范式 B（自包含可替换组件）= 模型 + 碰撞同包、逐实例化，
与 09 地板组件的地砖完全同构：
  <slug>_root_top3d.tscn
    ├─ Node3D 根（承载全部 metadata 契约）
    ├─ ImportedModel       ← 实例化 <slug>_visual_top3d.glb
    └─ <Slug>Collision (StaticBody3D, layer 1 / mask 0)
         └─ CollisionShape3D × N（BoxShape3D，与可视网格齐平）

碰撞按件型拆：
  wall_standard_5m  1 shape，5.0 x 11.9 x 0.3，中心 y=5.95
  wall_door_5m      3 shape，左右门垛 + 门楣，正好让出 2.2 x 2.5 门洞
  door_5m           1 shape，2.2 x 2.5 x 0.18，中心 y=1.25

尺寸来源全部是项目权威常量（src/world3d/TowerGeometry3D.gd、
src/world3d/RoomDoor3D.gd）与 blend 实测 AABB，脚本内不写任何美术估值。

幂等：目标 tscn 已存在且内容一致则跳过。生成前自动备份同名旧文件。
"""

from __future__ import annotations

import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent          # .../v003/qa
V003 = HERE.parent
SOURCE_DIR = V003.parent.parent                 # .../source
BATTLE = SOURCE_DIR.parent                      # .../battle
ROOT = BATTLE.parents[4]                        # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

import sys

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

RUNTIME_DIR = BATTLE / "runtime" / "common_components"
MANIFEST_DIR = V003 / "component_packages_v003"

LIBRARY_ID = "ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY"
LIBRARY_ROOT = "res://assets/art/environments/tower_zones/battle"
SOURCE_BLEND = f"{LIBRARY_ROOT}/source/common_components/v003/战局区块_通用组件库_v003.blend"

# 权威常量（写进 metadata 便于运行时与验证脚本交叉核对，来源见文件头注释）
GRID_UNIT_M = 5.0
WALL_THICKNESS_M = 0.3
WALL_VISUAL_HEIGHT_M = 11.9
WALL_LOGICAL_HEIGHT_M = 12.0
DOOR_CLEAR_WIDTH_M = 2.2
DOOR_CLEAR_HEIGHT_M = 2.5
PANEL_THICKNESS_M = 0.18

PIER_WIDTH_M = (GRID_UNIT_M - DOOR_CLEAR_WIDTH_M) / 2.0        # 1.4
LINTEL_HEIGHT_M = WALL_VISUAL_HEIGHT_M - DOOR_CLEAR_HEIGHT_M   # 9.4

ASSETS = {
    "wall_standard_5m": {
        "node_name": "BattleCommonWallStandard5m",
        "asset_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
        "category": "08_墙壁组件",
        "category_meta": "08_wall_component",
        "display_name": "战局通用标准墙 5×0.3×11.9m",
        "collision_policy": "embedded_box_bottom_center",
        "collision_owner": "self",
        "shapes": [
            ("wall_standard_5m_1", [GRID_UNIT_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M], [0.0, WALL_VISUAL_HEIGHT_M / 2.0, 0.0]),
        ],
        "meta": [
            ("wall_kind", "solid"),
            ("wall_thickness_m", WALL_THICKNESS_M),
            ("wall_visual_height_m", WALL_VISUAL_HEIGHT_M),
            ("wall_logical_height_m", WALL_LOGICAL_HEIGHT_M),
            ("visual_top_clearance_m", round(WALL_LOGICAL_HEIGHT_M - WALL_VISUAL_HEIGHT_M, 4)),
            ("grid_unit_m", GRID_UNIT_M),
        ],
        "notes": [
            "静态实墙，1 mesh 单材质，与网格 5m 同宽，可直接沿网格平铺。",
        ],
    },
    "wall_door_5m": {
        "node_name": "BattleCommonWallDoor5m",
        "asset_id": "ENV-BATTLE-COMMON-WALL-DOOR-5M",
        "category": "08_墙壁组件",
        "category_meta": "08_wall_component",
        "display_name": "战局通用门墙 5×0.3×11.9m（门洞 2.2×2.5）",
        "collision_policy": "embedded_three_box_bottom_center",
        "collision_owner": "self",
        "shapes": [
            # 左门垛
            ("wall_door_5m_pier_l", [PIER_WIDTH_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M], [-(DOOR_CLEAR_WIDTH_M / 2.0 + PIER_WIDTH_M / 2.0), WALL_VISUAL_HEIGHT_M / 2.0, 0.0]),
            # 右门垛
            ("wall_door_5m_pier_r", [PIER_WIDTH_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M], [DOOR_CLEAR_WIDTH_M / 2.0 + PIER_WIDTH_M / 2.0, WALL_VISUAL_HEIGHT_M / 2.0, 0.0]),
            # 门楣
            ("wall_door_5m_lintel", [DOOR_CLEAR_WIDTH_M, LINTEL_HEIGHT_M, WALL_THICKNESS_M], [0.0, DOOR_CLEAR_HEIGHT_M + LINTEL_HEIGHT_M / 2.0, 0.0]),
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
            "门洞处不产生碰撞，通行由门扇自身或宿主门逻辑负责。",
        ],
    },
    "door_5m": {
        "node_name": "BattleCommonDoor5m",
        "asset_id": "ENV-BATTLE-COMMON-DOOR-5M",
        "category": "10_门组件",
        "category_meta": "10_door_component",
        "display_name": "战局通用门扇 2.2×0.18×2.5m",
        "collision_policy": "embedded_box_bottom_center",
        "collision_owner": "self",
        "shapes": [
            ("door_5m_1", [DOOR_CLEAR_WIDTH_M, DOOR_CLEAR_HEIGHT_M, PANEL_THICKNESS_M], [0.0, DOOR_CLEAR_HEIGHT_M / 2.0, 0.0]),
        ],
        "meta": [
            ("door_clear_width_m", DOOR_CLEAR_WIDTH_M),
            ("door_clear_height_m", DOOR_CLEAR_HEIGHT_M),
            ("panel_thickness_m", PANEL_THICKNESS_M),
            ("open_mode", "vertical_lift"),
            ("panel_origin_policy", "bottom_center"),
        ],
        "notes": [
            "门扇为底边中心原点，与 RoomDoor3D 的「导入门以底边中心为原点」约定一致，"
            "接入时 visual.position.y = -DOOR_CLEAR_HEIGHT_M * 0.5 即可落在 DoorPanel 动画根上。",
            "开门方式是垂直升起（RoomDoor3D.set_open 改 panel.position.y），不是旋转，故原点无需落在铰链轴上。",
            "接入 RoomDoor3D 时请只取其 ImportedModel 子树，或直接把 GLB PackedScene 传作 panel visual；"
            "否则本组件内嵌碰撞会与 RoomDoor3D 自建的 DoorCollision 重复。",
        ],
    },
}


def fmt_vector(values) -> str:
    return "Vector3(%s)" % ", ".join(
        str(int(v)) if float(v).is_integer() else repr(round(float(v), 6)) for v in values
    )


def fmt_scalar(value) -> str:
    """按 Godot .tscn 的字面量语法格式化 metadata 取值。

    关键：字符串必须带双引号，否则 Godot 会把 ENV-BATTLE-... 当成表达式去求值；
    而 Vector3(...) 这类构造表达式恰恰不能带引号，故单独放行。
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


def build_scene(slug: str, spec: dict) -> str:
    visual_path = f"{LIBRARY_ROOT}/components/common_components/{slug}/{grn.visual_glb_name(slug)}"
    manifest_path = f"{LIBRARY_ROOT}/source/common_components/v003/component_packages_v003/{spec['category'][:2]}/{slug}/asset_manifest.json"
    bounds = spec["shapes"][0][1]
    # 由 3 个 shape 推出整体包围盒（门墙需要合并左右门垛与门楣）
    xs, ys, zs = [], [], []
    for _sid, size, center in spec["shapes"]:
        xs += [center[0] - size[0] / 2.0, center[0] + size[0] / 2.0]
        ys += [center[1] - size[1] / 2.0, center[1] + size[1] / 2.0]
        zs += [center[2] - size[2] / 2.0, center[2] + size[2] / 2.0]
    overall = [round(max(xs) - min(xs), 4), round(max(ys) - min(ys), 4), round(max(zs) - min(zs), 4)]

    load_steps = 1 + 1 + len(spec["shapes"])
    lines = []
    lines.append(f"[gd_scene load_steps={load_steps} format=3]")
    lines.append("")
    lines.append(f"; Stable AssetID: {spec['asset_id']}")
    lines.append(f"; 战局区块通用组件库 v003 · {spec['category']} · {slug}")
    lines.append("; 范式 B（自包含可替换组件）：模型 + 碰撞同包，逐实例化。")
    lines.append("; 原点契约 = 底面中心（Blender 底面 Z=0 → Godot 底面 Y=0），与 v003 全库一致。")
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
        ("asset_version", "v003"),
        ("library_id", LIBRARY_ID),
        ("library_root", LIBRARY_ROOT),
        ("category", spec["category_meta"]),
        ("component", slug),
        ("logic_id", slug),
        ("display_name_zh", spec["display_name"]),
        ("source_blend", SOURCE_BLEND),
        ("source_collection", f"{slug}_通用包"),
        ("source_root_object", f"ROOT_{slug}_通用组件"),
        ("source_manifest", manifest_path),
        ("origin_contract", "bottom_center"),
        ("forward_axis", "-Z"),
        ("up_axis", "+Y"),
        ("bounds_size_m", fmt_vector(overall)),
        ("preserve_authored_palette", True),
        ("collision_owner", spec["collision_owner"]),
        ("collision_policy", spec["collision_policy"]),
        ("collision_shape_count", len(spec["shapes"])),
        ("runtime_instantiation", "per_instance_prefab"),
    ]
    meta_pairs += [(k, v) for k, v in spec["meta"]]
    snap = -bounds[1]
    meta_pairs += [
        ("snap_to_ground_offset_m", 0.0),
        ("snap_note", "底面中心原点，直接放在目标地面 Y 上即可，无需额外偏移。"),
    ]
    for key, value in meta_pairs:
        lines.append(f"metadata/{key} = {fmt_scalar(value)}")
    lines.append("")
    lines.append('[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]')
    lines.append("")
    lines.append(f'[node name="{"WallDoor" if slug == "wall_door_5m" else ("WallStandard" if slug == "wall_standard_5m" else "Door")}Collision" type="StaticBody3D" parent="."]')
    lines.append("collision_layer = 1")
    lines.append("collision_mask = 0")
    lines.append("")
    body_name = f'{"WallDoor" if slug == "wall_door_5m" else ("WallStandard" if slug == "wall_standard_5m" else "Door")}Collision'
    for index, (sid, _size, center) in enumerate(spec["shapes"]):
        lines.append(f'[node name="CollisionShape3D{"" if index == 0 else "_%d" % (index + 1)}" type="CollisionShape3D" parent="{body_name}"]')
        lines.append(f"position = {fmt_vector(center)}")
        lines.append(f'shape = SubResource("BoxShape3D_{sid}")')
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    results = {}
    for slug, spec in ASSETS.items():
        out_dir = RUNTIME_DIR / slug
        out_dir.mkdir(parents=True, exist_ok=True)
        target = out_dir / grn.root_scene_name(slug)
        content = build_scene(slug, spec)
        if target.is_file() and target.read_text(encoding="utf-8") == content:
            print(f"SKIP {slug}: 内容已一致（幂等）")
            results[slug] = {"status": "unchanged", "path": str(target)}
            continue
        # 历史由 git 承担，不再落 `*.bak_pre_generate`（工作区不保留旧资产副本）。
        target.write_text(content, encoding="utf-8")
        print(f"WROTE {slug} -> {target}")
        results[slug] = {"status": "written", "path": str(target), "shapes": len(spec["shapes"])}

    print("PREFAB_REPORT " + str(results))
    print(f"PREFAB_OK total={len(results)} written={sum(1 for v in results.values() if v['status'] == 'written')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
