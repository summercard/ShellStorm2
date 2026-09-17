"""把 08_墙壁组件 与 10_门组件 三件新资产正式落成：写 manifest、补 catalog 条目。

背景：
  * v003 通用组件库（ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY）此前只交付 Blender 源。
  * wall_standard_5m 的 manifest 停在 exported=false / collision=not_created；
    wall_door_5m 与 door_5m 连 manifest 与 catalog 条目都还没有。
  * 本轮三件的 GLB 已导出、prefab（范式 B）已生成、契约验证与验收图已通过，
    故在此把状态落实，并让 catalog.json 真正能当索引用。

写入内容：
  1. 08/wall_standard_5m/asset_manifest.json   —— 回填导出/碰撞/产物/验证
  2. 08/wall_door_5m/asset_manifest.json       —— 新建
  3. 10/door_5m/asset_manifest.json            —— 新建
  4. component_packages_v003/catalog.json      —— 补 wall_door_5m / door_5m 两条，
                                                 并回填三件的 exported / collision / 产物路径

尺寸与门洞净空全部取自项目权威常量（TowerGeometry3D / FloorPlanGenerator / RoomDoor3D），
与 qa/export_wall_door_5m_summary.json 的实测 AABB 交叉断言；不写任何美术估值。

幂等：manifest 内容一致则跳过；catalog 缺条目才插入，已存在只更新同步字段。
运行：
  "C:/Users/zhuangmenghong/.workbuddy/binaries/python/versions/3.13.12/python.exe" finalize_wall_door_packages.py
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent                 # .../v003/qa
V003 = HERE.parent                                     # .../v003
SOURCE_DIR = V003.parent.parent                         # .../source
BATTLE = SOURCE_DIR.parent                             # .../battle
ROOT = BATTLE.parents[4]                               # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

import sys

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

PKG = V003 / "component_packages_v003"
CATALOG = PKG / "catalog.json"
SUMMARY = HERE / "export_wall_door_5m_summary.json"

LIBRARY_ROOT = "assets/art/environments/tower_zones/battle"
COMPONENTS_REL = f"{LIBRARY_ROOT}/components/common_components"
RUNTIME_REL = f"{LIBRARY_ROOT}/runtime/common_components"

# ---- 项目权威常量（与 TowerGeometry3D.gd / FloorPlanGenerator.gd / RoomDoor3D.gd 对齐）----
GRID_UNIT_M = 5.0
WALL_THICKNESS_M = 0.3
WALL_VISUAL_HEIGHT_M = 11.9
WALL_LOGICAL_HEIGHT_M = 12.0
DOOR_CLEAR_WIDTH_M = 2.2
DOOR_CLEAR_HEIGHT_M = 2.5
PANEL_THICKNESS_M = 0.18
PIER_WIDTH_M = (GRID_UNIT_M - DOOR_CLEAR_WIDTH_M) / 2.0     # 1.4
LINTEL_HEIGHT_M = WALL_VISUAL_HEIGHT_M - DOOR_CLEAR_HEIGHT_M  # 9.4

MATERIAL_ROLES = [
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
    "04_柔和自发光_UI灯光",
]

VERIFY_SCENE = "res://tests/verification/verify_common_wall_door_components.tscn"
ACCEPTANCE_IMAGES = [
    "res://outputs/verification/common_wall_door_components.png",
    "res://outputs/verification/common_wall_door_components_door.png",
]

SPECS = {
    "wall_standard_5m": {
        "category": "08_墙壁组件",
        "package_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
        "name_zh": "战局通用标准墙 5×0.3×11.9m",
        "showcase_position": [4.0, -58.3444, 0.0],
        "objects": ["wall_standard_5m_主体_输出"],
        "bounds_size": [GRID_UNIT_M, WALL_THICKNESS_M, WALL_VISUAL_HEIGHT_M],
        "godot_bounds_size": [GRID_UNIT_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M],
        "source_component": "procedural_standard_wall",
        "collision": "self_contained_box_bottom_center",
        "collision_shape_count": 1,
        "collision_shapes": [
            {"name": "wall_standard_5m_1", "size": [GRID_UNIT_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M], "center": [0.0, WALL_VISUAL_HEIGHT_M / 2.0, 0.0]},
        ],
        "extra": {
            "wall_kind": "solid",
            "wall_thickness_m": WALL_THICKNESS_M,
            "wall_visual_height_m": WALL_VISUAL_HEIGHT_M,
            "wall_logical_height_m": WALL_LOGICAL_HEIGHT_M,
            "visual_top_clearance_m": round(WALL_LOGICAL_HEIGHT_M - WALL_VISUAL_HEIGHT_M, 4),
            "grid_unit_m": GRID_UNIT_M,
        },
        "ledger_row": 94,
    },
    "wall_door_5m": {
        "category": "08_墙壁组件",
        "package_id": "ENV-BATTLE-COMMON-WALL-DOOR-5M",
        "name_zh": "战局通用门墙 5×0.3×11.9m（门洞 2.2×2.5）",
        "showcase_position": [8.0, -58.3444, 0.0],
        "objects": ["wall_door_5m_门垛左_输出", "wall_door_5m_门垛右_输出", "wall_door_5m_门楣_输出"],
        "bounds_size": [GRID_UNIT_M, WALL_THICKNESS_M, WALL_VISUAL_HEIGHT_M],
        "godot_bounds_size": [GRID_UNIT_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M],
        "source_component": "wall_door_5m",
        "collision": "self_contained_three_box_bottom_center",
        "collision_shape_count": 3,
        "collision_shapes": [
            {"name": "wall_door_5m_pier_l", "size": [PIER_WIDTH_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M], "center": [-(DOOR_CLEAR_WIDTH_M / 2.0 + PIER_WIDTH_M / 2.0), WALL_VISUAL_HEIGHT_M / 2.0, 0.0]},
            {"name": "wall_door_5m_pier_r", "size": [PIER_WIDTH_M, WALL_VISUAL_HEIGHT_M, WALL_THICKNESS_M], "center": [DOOR_CLEAR_WIDTH_M / 2.0 + PIER_WIDTH_M / 2.0, WALL_VISUAL_HEIGHT_M / 2.0, 0.0]},
            {"name": "wall_door_5m_lintel", "size": [DOOR_CLEAR_WIDTH_M, LINTEL_HEIGHT_M, WALL_THICKNESS_M], "center": [0.0, DOOR_CLEAR_HEIGHT_M + LINTEL_HEIGHT_M / 2.0, 0.0]},
        ],
        "extra": {
            "wall_kind": "door_portal",
            "wall_thickness_m": WALL_THICKNESS_M,
            "wall_visual_height_m": WALL_VISUAL_HEIGHT_M,
            "wall_logical_height_m": WALL_LOGICAL_HEIGHT_M,
            "grid_unit_m": GRID_UNIT_M,
            "door_clear_width_m": DOOR_CLEAR_WIDTH_M,
            "door_clear_height_m": DOOR_CLEAR_HEIGHT_M,
            "pier_width_m": round(PIER_WIDTH_M, 4),
            "lintel_height_m": round(LINTEL_HEIGHT_M, 4),
        },
        "ledger_row": 95,
    },
    "door_5m": {
        "category": "10_门组件",
        "package_id": "ENV-BATTLE-COMMON-DOOR-5M",
        "name_zh": "战局通用门扇 2.2×0.18×2.5m",
        "showcase_position": [2.6, -69.3444, 0.0],
        "objects": ["door_5m_门扇_输出"],
        "bounds_size": [DOOR_CLEAR_WIDTH_M, PANEL_THICKNESS_M, DOOR_CLEAR_HEIGHT_M],
        "godot_bounds_size": [DOOR_CLEAR_WIDTH_M, DOOR_CLEAR_HEIGHT_M, PANEL_THICKNESS_M],
        "source_component": "door_5m",
        "collision": "self_contained_box_bottom_center",
        "collision_shape_count": 1,
        "collision_shapes": [
            {"name": "door_5m_1", "size": [DOOR_CLEAR_WIDTH_M, DOOR_CLEAR_HEIGHT_M, PANEL_THICKNESS_M], "center": [0.0, DOOR_CLEAR_HEIGHT_M / 2.0, 0.0]},
        ],
        "extra": {
            "door_clear_width_m": DOOR_CLEAR_WIDTH_M,
            "door_clear_height_m": DOOR_CLEAR_HEIGHT_M,
            "panel_thickness_m": PANEL_THICKNESS_M,
            "open_mode": "vertical_lift",
            "panel_origin_policy": "bottom_center",
        },
        "ledger_row": 96,
    },
}


def manifest_for(slug: str, spec: dict) -> dict:
    glb_rel = f"{COMPONENTS_REL}/{slug}/{grn.visual_glb_name(slug)}"
    scene_rel = f"{RUNTIME_REL}/{slug}/{grn.root_scene_name(slug)}"
    data = {
        "asset_id": "ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY",
        "package_id": spec["package_id"],
        "name_zh": spec["name_zh"],
        "slug": slug,
        "category": spec["category"],
        "version": "v003",
        "source_blend": "战局区块_通用组件库_v003.blend",
        "blender_collection": f"{slug}_通用包",
        "root_object": f"ROOT_{slug}_通用组件",
        "objects": spec["objects"],
        "local_origin": [0, 0, 0],
        "showcase_position": spec["showcase_position"],
        "bounds_size": spec["bounds_size"],
        "front_direction": "+Y",
        "source_component": spec["source_component"],
        "straightened_yaw_degrees": 0,
        "material_roles": MATERIAL_ROLES,
        "exported": True,
        "collision": spec["collision"],
        "visual_glb": f"res://{glb_rel}",
        "runtime_scene": f"res://{scene_rel}",
        "godot_bounds_size": spec["godot_bounds_size"],
        "origin_contract": "bottom_center",
        "forward_axis": "-Z",
        "up_axis": "+Y",
        "collision_owner": "self",
        "collision_shape_count": spec["collision_shape_count"],
        "collision_shapes": spec["collision_shapes"],
        "runtime_instantiation": "per_instance_prefab",
        "verified_by": f"res://{LIBRARY_ROOT}/source/common_components/v003/qa/build_wall_door_prefabs.py",
        "verification_scene": VERIFY_SCENE,
        "acceptance_images": ACCEPTANCE_IMAGES,
        "ledger": {
            "file": "assets/registry/ShellStorm2_美术资产台账_v001.xlsx",
            "sheet": "3D-场景通用",
            "row": spec["ledger_row"],
        },
    }
    data.update(spec["extra"])
    return data


def catalog_entry(slug: str, spec: dict) -> dict:
    return {
        "asset_id": "ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY",
        "package_id": spec["package_id"],
        "name_zh": spec["name_zh"],
        "slug": slug,
        "category": spec["category"],
        "version": "v003",
        "source_blend": "战局区块_通用组件库_v003.blend",
        "blender_collection": f"{slug}_通用包",
        "root_object": f"ROOT_{slug}_通用组件",
        "objects": spec["objects"],
        "local_origin": [0, 0, 0],
        "showcase_position": spec["showcase_position"],
        "bounds_size": spec["bounds_size"],
        "front_direction": "+Y",
        "source_component": spec["source_component"],
        "straightened_yaw_degrees": 0,
        "material_roles": MATERIAL_ROLES,
        "exported": True,
        "collision": spec["collision"],
        "visual_glb": f"res://{COMPONENTS_REL}/{slug}/{grn.visual_glb_name(slug)}",
        "runtime_scene": f"res://{RUNTIME_REL}/{slug}/{grn.root_scene_name(slug)}",
    }


def verify_against_export_summary(failures: list[str]) -> None:
    """用导出实测 AABB 交叉断言 manifest/catalog 的尺寸，避免口径各说各话。"""
    if not SUMMARY.is_file():
        failures.append(f"缺少导出摘要，无法交叉核对尺寸：{SUMMARY}")
        return
    measured = json.loads(SUMMARY.read_text(encoding="utf-8"))
    for slug, spec in SPECS.items():
        item = measured.get(slug)
        if item is None:
            failures.append(f"导出摘要缺少 {slug}")
            continue
        size = item["blender_size_xyz"]
        expected = spec["bounds_size"]
        for axis, (got, want) in enumerate(zip(size, expected)):
            if abs(got - want) > 1e-4:
                failures.append(
                    f"{slug} 尺寸第{axis}轴 = {got}，与权威常量 {want} 不符"
                )
        godot = item["godot_size_xyz"]
        for axis, (got, want) in enumerate(zip(godot, spec["godot_bounds_size"])):
            if abs(got - want) > 1e-4:
                failures.append(
                    f"{slug} Godot 尺寸第{axis}轴 = {got}，与期望 {want} 不符"
                )
        # 底面贴地必须成立（导出 AABB 的 Z 下限 / Godot Y 下限为 0）
        if abs(item["blender_aabb_min"][2]) > 1e-6:
            failures.append(f"{slug} Blender 底面不在 Z=0：{item['blender_aabb_min'][2]}")
        if abs(item["godot_aabb_min"][1]) > 1e-6:
            failures.append(f"{slug} Godot 底面不在 Y=0：{item['godot_aabb_min'][1]}")


def main() -> int:
    failures: list[str] = []
    verify_against_export_summary(failures)
    if failures:
        for f in failures:
            print(f"FAIL {f}")
        print("FINALIZE_WALL_DOOR_PACKAGES_FAIL")
        return 1

    # 1) manifest
    written, unchanged = [], []
    for slug, spec in SPECS.items():
        category_id = spec["category"].split("_")[0]
        target = PKG / category_id / slug / "asset_manifest.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        content = json.dumps(manifest_for(slug, spec), indent=2, ensure_ascii=False) + "\n"
        if target.is_file() and target.read_text(encoding="utf-8") == content:
            unchanged.append(slug)
            continue
        if target.is_file():
            shutil.copy2(target, target.with_suffix(".json.bak_finalize_wall_door"))
        target.write_text(content, encoding="utf-8")
        written.append(slug)
        print(f"MANIFEST {slug} -> {target}")

    # 2) catalog
    if not CATALOG.is_file():
        print(f"FAIL 找不到 catalog: {CATALOG}")
        return 1
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    by_slug = {entry["slug"]: entry for entry in catalog}
    catalog_changed = False

    # 补齐缺失的两条（wall_door_5m 插到 wall_standard_5m 之后，door_5m 追加到末尾）
    for slug in ("wall_door_5m", "door_5m"):
        if slug in by_slug:
            continue
        entry = catalog_entry(slug, SPECS[slug])
        if slug == "wall_door_5m":
            anchor = next(
                (i for i, e in enumerate(catalog) if e["slug"] == "wall_standard_5m"),
                len(catalog) - 1,
            )
            catalog.insert(anchor + 1, entry)
        else:
            catalog.append(entry)
        by_slug[slug] = entry
        catalog_changed = True
        print(f"CATALOG + {slug}")

    # 同步三件的导出状态
    for slug, spec in SPECS.items():
        entry = by_slug[slug]
        entry["exported"] = True
        entry["collision"] = spec["collision"]
        entry["visual_glb"] = f"res://{COMPONENTS_REL}/{slug}/{grn.visual_glb_name(slug)}"
        entry["runtime_scene"] = f"res://{RUNTIME_REL}/{slug}/{grn.root_scene_name(slug)}"
        catalog_changed = True

    if catalog_changed:
        shutil.copy2(CATALOG, CATALOG.with_suffix(".json.bak_finalize_wall_door"))
        CATALOG.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"CATALOG 已更新 -> {CATALOG}")

    exported = sum(1 for e in catalog if e.get("exported") is True)
    print(f"FINALIZE_REPORT manifests_written={written} manifests_unchanged={unchanged}")
    print(f"FINALIZE_WALL_DOOR_PACKAGES_OK catalog={len(catalog)} exported_true={exported}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
