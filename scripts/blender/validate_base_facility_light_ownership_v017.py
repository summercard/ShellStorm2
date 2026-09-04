#!/usr/bin/env python3
"""Verify that emitting LIGHT objects are packaged with their physical fixture.

Global composition fills and preview-only verification lamps are explicit, auditable
exceptions; they do not represent a physical prop and therefore stay in support or
display collections.
"""

import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
OUT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/base_facility_light_ownership_validation_v017.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("Run this validator with the v017 Blend open")

packages = {c for c in bpy.data.collections if c.get("资产包")}
preview_names = {
    "地板验收柔光", "楼梯验收冷白主光", "楼梯验收暖色侧光",
    "预览冷白主光", "预览暖橙补光", "预览蓝紫轮廓光",
}
global_fill_names = {
    "二楼休闲区_柔和暖光", "二楼工位区_冷色面光",
    "二楼床区_暖白面光", "二楼整体_冷色轮廓光",
}
expected_output = {
    "STAY_CURIOUS_v013_暖红洗墙": "loft_stay_curious_neon",
    "床头灯_暖橙光": "loft_bedside_lamp",
    "武器台红色警示灯": "weapon_workshop_station",
    "东面圆形吊灯_局部冷白光": "east_round_pendant_light",
}
expected_sources = {f"{k}__源": v for k, v in expected_output.items() if bpy.data.objects.get(f"{k}__源")}

errors, rows = [], []
for obj in sorted((o for o in bpy.data.objects if o.type == "LIGHT"), key=lambda o: o.name):
    is_source = ("__源" in obj.name) or obj.name.endswith("_源组件")
    owners = [c for c in obj.users_collection if c in packages]
    keys = sorted(c.get("资产包键") for c in owners)
    collections = sorted(c.name for c in obj.users_collection)
    row = {
        "name": obj.name,
        "is_source": is_source,
        "package_keys": keys,
        "collections": collections,
        "classification": "fixture_local",
    }
    if obj.name in preview_names:
        row["classification"] = "preview_only_exception"
        if collections != ["90_展示环境_灯光相机"] or keys:
            errors.append(f"preview light incorrectly packaged: {obj.name}")
    elif obj.name in global_fill_names:
        row["classification"] = "global_fill_exception"
        if keys != ["loft_lighting_support"]:
            errors.append(f"global fill not in support package: {obj.name} -> {keys}")
    elif is_source:
        source_owners = [c for c in obj.users_collection if c.name.startswith("v017_源资产包_")]
        if len(source_owners) != 1:
            errors.append(f"source fixture light must be in one mirrored source package: {obj.name}")
        if obj.name in expected_sources and (not source_owners or source_owners[0].name != f"v017_源资产包_{expected_sources[obj.name]}"):
            errors.append(f"source fixture expected {expected_sources[obj.name]}: {obj.name}")
        row["classification"] = "fixture_source"
        row["source_package"] = source_owners[0].name if source_owners else None
    else:
        if len(keys) != 1:
            errors.append(f"fixture light must be in exactly one output facility package: {obj.name} -> {keys}")
        if obj.name in expected_output and keys != [expected_output[obj.name]]:
            errors.append(f"fixture expected {expected_output[obj.name]}: {obj.name} -> {keys}")
    rows.append(row)

summary = {
    "blend": str(BLEND),
    "policy": "实体灯光随发光设施归属；无实体全局补光和展示预览灯为显式例外",
    "light_count": len(rows),
    "fixture_local_count": sum(r["classification"] == "fixture_local" for r in rows),
    "fixture_source_count": sum(r["classification"] == "fixture_source" for r in rows),
    "global_fill_exception_count": sum(r["classification"] == "global_fill_exception" for r in rows),
    "preview_only_exception_count": sum(r["classification"] == "preview_only_exception" for r in rows),
    "errors": errors,
    "passed": not errors,
    "lights": rows,
}
OUT.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: summary[k] for k in summary if k != "lights"}, ensure_ascii=False))
if errors:
    raise SystemExit(1)
