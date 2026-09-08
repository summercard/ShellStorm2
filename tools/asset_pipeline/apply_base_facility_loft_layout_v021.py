"""Record the v021 layout-only loft adjustment across Godot and source ledgers.

GLBs remain untouched; the Blender output meshes and runtime package transforms
apply the same rigid transforms.  This keeps the import ledger honest without
creating a needless export version for a placement-only change.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT / "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"
MANIFEST_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages/loft"
LEDGER = PROJECT / "assets/art/environments/base_facility_3d/source/env_base99_loft_layout_v021_manifest.json"
GLOBAL = PROJECT / "assets/art/asset_import_manifest_v001.json"
RUNTIME_ROOT = PROJECT / "assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v002.tscn"

PACKAGES = {
    "loft_bed_and_bedding": {
        "collection": "31_参考床架床品与床下收纳_资产包",
        "blender_pivot_xy_m": [0.3, 11.25], "blender_target_xy_m": [1.75, 11.55],
        "blender_rotation_z_rad": -1.57079632679,
        "godot_position_m": [-9.5, 0.0, -11.85], "godot_rotation_y_rad": -1.57079632679,
        "layout_bbox_blender": {"min": [0.475, 9.175], "max": [3.025, 13.925]},
        "instruction": "顺时针90度，枕头朝北，靠近门帘。",
    },
    "loft_nightstand": {
        "collection": "32_参考床头柜与生活物件_资产包",
        "blender_pivot_xy_m": [-3.235, 11.32], "blender_target_xy_m": [-3.7, 7.2],
        "blender_rotation_z_rad": 1.57079632679,
        "godot_position_m": [7.62, 0.0, -10.435], "godot_rotation_y_rad": 1.57079632679,
        "layout_bbox_blender": {"min": [-4.23, 6.165], "max": [-3.17, 8.235]},
        "instruction": "逆时针90度，移到南侧栏杆内侧，抽屉朝外。",
    },
    "loft_coffee_table": {
        "collection": "37_红棕茶几与生活物件_资产包",
        "blender_pivot_xy_m": [6.2, 9.38], "blender_target_xy_m": [3.6, 6.55],
        "blender_rotation_z_rad": 0.0,
        "godot_position_m": [-2.6, 0.0, 2.83], "godot_rotation_y_rad": 0.0,
        "layout_bbox_blender": {"min": [2.175, 5.91], "max": [5.025, 7.19]},
        "instruction": "向左下移动到休闲地毯南侧空位。",
    },
}


def rel(path: Path) -> str:
    return str(path.relative_to(PROJECT)).replace("\\", "/")


def write_package_manifests() -> None:
    for slug, layout in PACKAGES.items():
        path = MANIFEST_ROOT / slug / "asset_manifest.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["version"] = "v021"
        data["source_blend"] = rel(SOURCE_BLEND)
        data["layout_revision"] = "v021_loft_layout_adjustment_001"
        data["layout_only"] = True
        data["layout_instruction"] = layout["instruction"]
        data["layout_blender"] = {
            "pivot_xy_m": layout["blender_pivot_xy_m"],
            "target_xy_m": layout["blender_target_xy_m"],
            "rotation_z_rad": layout["blender_rotation_z_rad"],
            "bbox_xy_m": layout["layout_bbox_blender"],
        }
        data["godot_runtime_layout"] = {
            "scene": rel(RUNTIME_ROOT),
            "position_m": layout["godot_position_m"],
            "rotation_y_rad": layout["godot_rotation_y_rad"],
            "collision_policy": "existing package collision follows the same root transform",
        }
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if not SOURCE_BLEND.is_file():
        raise RuntimeError(f"Missing source blend: {SOURCE_BLEND}")
    if "v021_loft_layout_adjustment_001" not in RUNTIME_ROOT.read_text(encoding="utf-8"):
        raise RuntimeError("Godot runtime transforms have not been applied")
    write_package_manifests()
    data = {
        "asset_id": "ENV-BASE99-LOFT-LAYOUT-V021",
        "version": "v021",
        "revision": "v021_loft_layout_adjustment_001",
        "source_blend": rel(SOURCE_BLEND),
        "source_blend_sha256": hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest(),
        "runtime_scene": rel(RUNTIME_ROOT),
        "export_policy": "layout_only_no_glb_reexport",
        "packages": [{"slug": slug, **layout} for slug, layout in PACKAGES.items()],
    }
    LEDGER.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    global_data = json.loads(GLOBAL.read_text(encoding="utf-8"))
    global_data["base_facility_loft_layout_v021"] = {
        "asset_id": data["asset_id"], "version": "v021", "revision": data["revision"],
        "package_count": 3, "layout_ledger": rel(LEDGER), "runtime_scene": rel(RUNTIME_ROOT),
        "export_policy": data["export_policy"],
    }
    GLOBAL.write_text(json.dumps(global_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BASE99_LOFT_LAYOUT_V021_RECORDED: packages=3")


if __name__ == "__main__":
    main()
