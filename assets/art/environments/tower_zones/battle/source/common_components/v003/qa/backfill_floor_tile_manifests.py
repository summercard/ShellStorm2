"""回填 v003 通用组件库 09_地板组件 的导出/碰撞状态。

背景：v003 README 原先写明「未生成GLB、碰撞或Godot场景」，manifest 里
exported=false / collision=not_created。本轮按 L 型转角范式把两块 5m 地砖
做成自包含可替换组件后回填实际状态，并登记产物路径与验证探针。

字段风格沿用本项目既有习惯：exported 为布尔，collision 为描述性字符串
（参见 scripts/blender/rebuild_base99_mezzanine_platform_v003.py 等）。

运行：
  "C:\\Users\\zhuangmenghong\\.workbuddy\\binaries\\python\\versions\\3.13.12\\python.exe" backfill_floor_tile_manifests.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent                       # .../v003/qa
V003 = HERE.parent                                           # .../v003
BATTLE = V003.parent.parent.parent                           # .../battle
ROOT = BATTLE.parents[4]                                     # .../ShellStorm2

import sys

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

PKG = V003 / "component_packages_v003" / "09"
COMPONENTS_REL = "assets/art/environments/tower_zones/battle/components/common_components/floor_tile_5m"
RUNTIME_REL = "assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m"
PROBE_REL = "assets/art/environments/tower_zones/battle/source/common_components/v003/qa/probe_floor_tile_components.gd"

# slug: (Godot 口径尺寸 XYZ, 厚度, manifest bounds_size Blender 口径)
CASES = {
    "floor_tile_r01_c01": ([4.94, 0.056, 4.94], 0.056),
    "floor_tile_r01_c02": ([4.94, 0.081, 4.94], 0.081),
}

for slug, (godot_size, thickness) in CASES.items():
    manifest_path = PKG / slug / "asset_manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"缺少 manifest: {manifest_path}")

    data = json.loads(manifest_path.read_text(encoding="utf-8"))

    # 校验 Blender 口径与 Godot 口径一致，防止导出脚本和 manifest 各说各话
    bx, by, bz = data["bounds_size"]
    assert abs(bz - thickness) < 1e-6, f"{slug} 厚度不符: manifest {bz} vs 期望 {thickness}"
    assert abs(bx - 4.94) < 1e-6 and abs(by - 4.94) < 1e-6, f"{slug} footprint 不符: {data['bounds_size']}"

    data["exported"] = True
    data["collision"] = "self_contained_box_bottom_center"
    data["visual_glb"] = f"res://{COMPONENTS_REL}/{grn.visual_glb_name(slug)}"
    data["runtime_scene"] = f"res://{RUNTIME_REL}/{grn.root_scene_name(slug)}"
    data["godot_bounds_size"] = godot_size
    data["origin_contract"] = "bottom_center"
    data["forward_axis"] = "-Z"
    data["runtime_grid_unit_m"] = 5.0
    data["tile_gap_m"] = round(5.0 - 4.94, 4)
    data["runtime_collision_owner"] = "TowerFloorStage3D._build_support"
    data["verified_by"] = f"res://{PROBE_REL}"

    manifest_path.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"UPDATED {manifest_path}")
    print(f"  exported={data['exported']} collision={data['collision']} godot_size={godot_size}")

print("BACKFILL_OK")
