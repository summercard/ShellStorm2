#!/usr/bin/env python3
"""Task-specific acceptance for additive v016 built from the user's v015."""

import hashlib
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
V015 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v015.blend"
V016 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v016.blend"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v016"
REPORT = VERIFY / "base_facility_runtime_layout_hq_v016_validation.json"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v016"


def signature(obj):
    mesh = None
    if obj.type == "MESH":
        coords = tuple(round(float(c), 6) for v in obj.data.vertices for c in v.co)
        mesh = {
            "vertices": len(obj.data.vertices),
            "edges": len(obj.data.edges),
            "polygons": len(obj.data.polygons),
            "coordinates": hashlib.sha256(repr(coords).encode()).hexdigest(),
            "materials": [m.name if m else None for m in obj.data.materials],
            "face_materials": hashlib.sha256(bytes(p.material_index % 256 for p in obj.data.polygons)).hexdigest(),
        }
    animation = []
    if obj.animation_data and obj.animation_data.action:
        for fc in obj.animation_data.action.fcurves:
            animation.append((fc.data_path, fc.array_index, tuple((round(k.co.x, 4), round(k.co.y, 6)) for k in fc.keyframe_points)))
    return {
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "collections": sorted(c.name for c in obj.users_collection),
        "location": [round(float(c), 7) for c in obj.location],
        "rotation_mode": obj.rotation_mode,
        "rotation_euler": [round(float(c), 7) for c in obj.rotation_euler],
        "rotation_quaternion": [round(float(c), 7) for c in obj.rotation_quaternion],
        "scale": [round(float(c), 7) for c in obj.scale],
        "delta_location": [round(float(c), 7) for c in obj.delta_location],
        "delta_rotation_euler": [round(float(c), 7) for c in obj.delta_rotation_euler],
        "delta_scale": [round(float(c), 7) for c in obj.delta_scale],
        "mesh": mesh,
        "modifiers": [(m.name, m.type, tuple(sorted((k, repr(v)) for k, v in m.items()))) for m in obj.modifiers],
        "animation": animation,
    }


def capture():
    return {obj.name: signature(obj) for obj in bpy.data.objects}


def asset_packages():
    return [c for c in bpy.data.collections if c.get("资产包")]


def rounded(values):
    return [round(float(v), 3) for v in values]


bpy.ops.wm.open_mainfile(filepath=str(V015), load_ui=False)
baseline = capture()
bpy.ops.wm.open_mainfile(filepath=str(V016), load_ui=False)
current = {name: signature(bpy.data.objects[name]) for name in baseline if name in bpy.data.objects}
changed = sorted(name for name in baseline if name in current and baseline[name] != current[name])
removed = sorted(set(baseline) - set(current))

packages = asset_packages()
empty_packages = sorted(c.name for c in packages if not c.objects)
v016_outputs = [o for o in bpy.data.objects if o.get("v016_scope") and not o.name.endswith("__源")]
v016_sources = [o for o in bpy.data.objects if o.get("v016_scope") and o.name.endswith("__源")]
bad_output_owners = {}
for obj in v016_outputs:
    owners = [c.name for c in obj.users_collection if c.get("资产包")]
    if len(owners) != 1:
        bad_output_owners[obj.name] = owners
bad_source_owners = {}
for obj in v016_sources:
    owners = [c.name for c in obj.users_collection if c.name.startswith("v016_源资产包_")]
    if len(owners) != 1 or len(obj.users_collection) != 1:
        bad_source_owners[obj.name] = [c.name for c in obj.users_collection]

required = [
    "v016_床罩脚端折叠毯",
    "v016_隔断帘金属吊环_01",
    "v016_沙发扶手折叠毯",
    "v016_茶几下层置物板",
    "v016_工位任务灯灯头_自发光",
    "v016_MEDICAL箱_十字横",
    "v016_BATTERY箱_电池轮廓",
    "v016_FOOD箱_餐盘图标",
    "v016_FOOD箱_餐盘高光_自发光",
    "v016_西梯顶层接缝螺栓_01",
    "v016_东梯接口螺栓_01",
]
missing_required = [name for name in required if name not in bpy.data.objects]

interfaces = {
    "L梯_西北转角平台": ([ -13.8, 13.8, 2.925], [2.0, 2.0, 0.24]),
    "L梯_阁楼顶层接驳平台": ([-6.52, 13.8, 6.045], [3.44, 2.0, 0.09]),
    "东侧楼梯_底部接缝压板": ([13.28, 10.3, 6.085], [1.72, 0.26, 0.045]),
    "东侧楼梯_顶部接驳平台": ([13.28, 14.52, 8.68], [1.95, 0.8, 0.16]),
}
interface_checks = {}
for name, (expected_loc, expected_dim) in interfaces.items():
    obj = bpy.data.objects.get(name)
    interface_checks[name] = {
        "exists": obj is not None,
        "location": rounded(obj.location) if obj else None,
        "expected_location": expected_loc,
        "dimensions": rounded(obj.dimensions) if obj else None,
        "expected_dimensions": expected_dim,
        "pass": bool(obj and rounded(obj.location) == expected_loc and rounded(obj.dimensions) == expected_dim),
    }

manifest_paths = list(PACKAGE_ROOT.rglob("asset_manifest.json")) if PACKAGE_ROOT.exists() else []
floor_packages = [c for c in packages if c.get("资产类别") == "floor"]
four_materials = sorted(m.name for m in bpy.data.materials)
checks = {
    "v015_object_count_is_5870": len(baseline) == 5870,
    "all_v015_objects_unchanged": not changed and not removed and len(current) == len(baseline),
    "package_count_is_101": len(packages) == 101,
    "floor_package_count_is_36": len(floor_packages) == 36,
    "manifest_count_is_101": len(manifest_paths) == 101,
    "no_empty_asset_packages": not empty_packages,
    "new_outputs_unique_facility_owner": not bad_output_owners,
    "new_sources_unique_mirrored_owner": not bad_source_owners,
    "new_source_output_pairs_match": len(v016_outputs) == len(v016_sources),
    "required_detail_objects_exist": not missing_required,
    "stair_interfaces_exact": all(v["pass"] for v in interface_checks.values()),
    "shared_material_count_is_4": len(four_materials) == 4,
}
report = {
    "schema": "shellstorm2.base_facility.v016.task_acceptance.v1",
    "input_baseline": str(V015.relative_to(PROJECT)),
    "output": str(V016.relative_to(PROJECT)),
    "result": "PASS" if all(checks.values()) else "FAIL",
    "checks": checks,
    "counts": {
        "v015_locked_objects": len(baseline),
        "v016_existing_objects_matched": len(current),
        "v016_added_output_objects": len(v016_outputs),
        "v016_added_editable_sources": len(v016_sources),
        "asset_packages": len(packages),
        "floor_packages": len(floor_packages),
        "disk_manifests": len(manifest_paths),
        "materials": len(four_materials),
    },
    "changed_v015_objects": changed,
    "removed_v015_objects": removed,
    "empty_asset_packages": empty_packages,
    "bad_output_owners": bad_output_owners,
    "bad_source_owners": bad_source_owners,
    "missing_required": missing_required,
    "stair_interfaces": interface_checks,
    "materials": four_materials,
}
VERIFY.mkdir(parents=True, exist_ok=True)
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False))
if report["result"] != "PASS":
    raise SystemExit(2)
