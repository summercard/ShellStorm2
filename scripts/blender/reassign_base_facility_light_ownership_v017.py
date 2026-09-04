#!/usr/bin/env python3
"""Collection-only correction: local light objects live with their emitting fixture."""

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
REORG = PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py"

spec = importlib.util.spec_from_file_location("reorg_v017", REORG)
reorg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reorg)

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must start from v017")

before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects}
target = reorg.package_by_slug("loft_stay_curious_neon")
source_target = bpy.data.collections["v017_源资产包_loft_stay_curious_neon"]
changes = []
for name, destination in (
    ("STAY_CURIOUS_v013_暖红洗墙", target),
    ("STAY_CURIOUS_v013_暖红洗墙__源", source_target),
):
    obj = bpy.data.objects[name]
    reorg.move_object(obj, destination)
    changes.append({"light": name, "destination": destination.name})

after = {name: reorg.signature(bpy.data.objects[name]) for name in before if name in bpy.data.objects}
changed = sorted(name for name in before if name in after and before[name] != after[name])
removed = sorted(set(before) - set(after))
if changed or removed:
    raise RuntimeError(f"light ownership pass changed object data: {changed[:8]} removed={removed[:8]}")

catalog = reorg.write_catalog(reorg.packages())
report = json.loads(reorg.REPORT.read_text(encoding="utf-8"))
report["light_ownership_pass"] = {
    "policy": "local LIGHT objects are stored with their emitting fixture; only preview/global fill remains in display/support collections",
    "locked_match": before == after,
    "changes": changes,
    "package_count": catalog["package_count"],
}
reorg.REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_light_ownership_policy"] = "实体灯光随发光设施归属；预览与无实体补光独立支持"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(report["light_ownership_pass"], ensure_ascii=False))
