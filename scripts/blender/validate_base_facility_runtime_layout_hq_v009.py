#!/usr/bin/env python3
"""Task-level acceptance for Base 99 east-facility pass v009."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bpy


PROJECT = Path("/Users/summercards/ShellStorm2")
V008 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v008.blend"
V009 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v009.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v009"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v009/base_facility_runtime_layout_hq_v009_validation.json"
OUT8 = "02_游戏输出_独立资产包_v008"
OUT9 = "02_游戏输出_独立资产包_v009"
TARGET_OLD_SLUGS = {
    "supply_vending_station", "east_power_box", "sorting_bin_group", "maintenance_workstation",
}
REQUIRED_SLUGS = {
    "east_personnel_security_door", "east_supply_24h_station", "east_power_distribution",
    "east_industrial_pipeline_system", "east_waste_bin", "east_flammable_bin", "east_recycle_bin",
    "east_maintenance_workstation", "east_low_storage_bench", "east_work_together_poster",
    "east_small_safety_devices", "east_plant_group", "east_round_pendant_light",
}


def leaf_packages(root):
    result = []
    def walk(coll):
        if coll.get("资产包"):
            result.append(coll)
        for child in coll.children:
            walk(child)
    walk(root)
    return result


def sig(obj):
    data = None
    if obj.type == "MESH":
        coords = tuple(round(float(c), 6) for v in obj.data.vertices for c in v.co)
        data = {
            "vertices": len(obj.data.vertices),
            "polygons": len(obj.data.polygons),
            "vertex_hash": hashlib.sha256(repr(coords).encode()).hexdigest(),
            "materials": [m.name if m else None for m in obj.data.materials],
            "material_indices": hashlib.sha256(bytes(p.material_index % 256 for p in obj.data.polygons)).hexdigest(),
        }
    animation = []
    if obj.animation_data and obj.animation_data.action:
        for curve in obj.animation_data.action.fcurves:
            animation.append((curve.data_path, curve.array_index,
                              tuple((round(p.co.x, 4), round(p.co.y, 6)) for p in curve.keyframe_points)))
    return {
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "matrix": [round(float(c), 7) for row in obj.matrix_world for c in row],
        "dimensions": [round(float(c), 7) for c in obj.dimensions],
        "data": data,
        "animation": animation,
    }


def capture_locked(blend, output_name, old_target_names=None):
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    root = bpy.data.collections[output_name]
    packages = leaf_packages(root)
    target_names = set(old_target_names or ())
    if output_name == OUT8:
        for package in packages:
            if package.get("资产包键") in TARGET_OLD_SLUGS:
                target_names.update(obj.name for obj in package.objects)
    payload = {}
    for package in packages:
        for obj in package.objects:
            if obj.name in target_names or obj.get("v009_scope"):
                continue
            payload[obj.name] = sig(obj)
    return payload, target_names


def rounded(obj, attr):
    return [round(float(v), 3) for v in getattr(obj, attr)]


def main():
    before, target_names = capture_locked(V008, OUT8)
    after, _ = capture_locked(V009, OUT9, target_names)
    errors = []
    changed = sorted(name for name in before.keys() & after.keys() if before[name] != after[name])
    added = sorted(after.keys() - before.keys())
    removed = sorted(before.keys() - after.keys())
    if changed or added or removed:
        errors.append(f"locked scope mismatch changed={changed[:12]} added={added[:12]} removed={removed[:12]}")

    output = bpy.data.collections[OUT9]
    packages = leaf_packages(output)
    slugs = [p.get("资产包键") for p in packages]
    if len(packages) != 91:
        errors.append(f"package_count={len(packages)} expected=91")
    if len(set(slugs)) != len(slugs):
        errors.append("duplicate asset slugs")
    missing = sorted(REQUIRED_SLUGS - set(slugs))
    if missing:
        errors.append(f"missing east packages={missing}")
    empty = sorted(p.name for p in packages if not p.objects)
    if empty:
        errors.append(f"empty packages={empty}")
    floor_count = sum(p.get("资产类别") == "floor" for p in packages)
    if floor_count != 36:
        errors.append(f"floor_tile_package_count={floor_count} expected=36")

    memberships = {}
    for package in packages:
        for obj in package.objects:
            memberships.setdefault(obj.name, []).append(package.name)
    multi = {name: owners for name, owners in memberships.items() if len(owners) != 1}
    if multi:
        errors.append(f"multi-package ownership={dict(list(multi.items())[:12])}")

    manifest_paths = list(PACKAGE_ROOT.glob("*/*/asset_manifest.json"))
    if len(manifest_paths) != len(packages):
        errors.append(f"manifest_count={len(manifest_paths)} package_count={len(packages)}")
    manifest_slugs = set()
    for path in manifest_paths:
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest_slugs.add(manifest.get("asset_slug"))
        if manifest.get("version") != "v009":
            errors.append(f"manifest wrong version={path}")
    if manifest_slugs != set(slugs):
        errors.append("manifest slugs do not match Collection slugs")

    expected = {
        "东墙人员门_厚重外门框": ([14.38, -2.5, 1.32], [0.46, 2.42, 2.64]),
        "SUPPLY24H_主体外壳": ([13.52, 1.55, 1.78], [1.82, 2.18, 3.56]),
        "东墙POWER配电柜_主箱体": ([14.15, -5.55, 2.35], [0.34, 1.55, 2.15]),
        "分类垃圾设施_WASTE_主体": ([10.8, -5.2, 0.7], [1.05, 1.05, 1.3]),
        "分类垃圾设施_FLAMMABLE_主体": ([10.8, -6.65, 0.7], [1.05, 1.05, 1.3]),
        "分类垃圾设施_RECYCLE_主体": ([10.8, -8.1, 0.7], [1.05, 1.05, 1.3]),
        "东面维修工作台_主柜体": ([6.2, -13.25, 0.92], [4.7, 1.15, 1.5]),
    }
    key_transforms = {}
    for name, (location, dimensions) in expected.items():
        obj = bpy.data.objects.get(name)
        if not obj:
            errors.append(f"missing key object={name}")
            continue
        actual = (rounded(obj, "location"), rounded(obj, "dimensions"))
        key_transforms[name] = {"location": actual[0], "dimensions": actual[1]}
        if actual != (location, dimensions):
            errors.append(f"key transform mismatch {name}: {actual} expected={(location, dimensions)}")

    supply = bpy.data.objects.get("SUPPLY24H_主体外壳")
    if supply and supply.location.y - supply.dimensions.y / 2 <= 0.4:
        errors.append("SUPPLY 24H violates personnel-door north-side clearance")
    old_residue = sorted(obj.name for obj in bpy.data.objects if obj.name.startswith(("复古工业自动贩卖机_", "分类垃圾箱_", "南仓工具")))
    if old_residue:
        errors.append(f"old misread objects remain={old_residue[:20]}")

    scope_objects = [o for o in bpy.data.objects if o.get("v009_scope")]
    label_wrong = []
    for obj in scope_objects:
        if any(t in obj.name for t in ("文字", "标牌", "安全标签", "检修标签", "接线盒标签", "顶部标识", "火焰警告", "回收标志", "消防提示")):
            if round(float(obj.rotation_euler.z), 4) != round(-3.141592653589793 / 2, 4):
                label_wrong.append(obj.name)
    if label_wrong:
        errors.append(f"east labels not facing inward={label_wrong}")

    report = {
        "asset_id": "ENV-BASE99-ART-LAYOUT-3D",
        "version": "v009",
        "scope": "east facility zone only",
        "status": "PASS" if not errors else "FAIL",
        "locked_object_count_v008": len(before),
        "locked_object_count_v009": len(after),
        "locked_changed": changed,
        "locked_added": added,
        "locked_removed": removed,
        "package_count": len(packages),
        "floor_tile_package_count": floor_count,
        "manifest_count": len(manifest_paths),
        "east_required_packages": sorted(REQUIRED_SLUGS),
        "v009_scope_object_count": len(scope_objects),
        "key_transforms": key_transforms,
        "errors": errors,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if errors:
        raise RuntimeError("v009 task-level validation failed")


if __name__ == "__main__":
    main()
