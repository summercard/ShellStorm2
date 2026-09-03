#!/usr/bin/env python3
"""Task-level validation for Base 99 loft/stair high-fidelity pass v011."""

import hashlib
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
V010 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v010.blend"
V011 = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v011.blend"
ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v011"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v011/base_facility_runtime_layout_hq_v011_validation.json"
OUT10 = "02_游戏输出_独立资产包_v010"
OUT11 = "02_游戏输出_独立资产包_v011"
REQ = {
    "loft_bed_and_bedding", "loft_nightstand", "loft_bedside_lamp", "loft_bedside_rug",
    "loft_striped_privacy_curtain", "loft_lounge_sofa", "loft_coffee_table", "loft_lounge_rug",
    "loft_pouf_01", "loft_pouf_02", "loft_side_table", "loft_computer_workstation",
    "loft_office_chair", "loft_good_vibes_neon", "loft_medical_cabinet",
    "loft_battery_cabinet", "loft_food_cabinet", "loft_wall_utility_decor",
    "loft_hanging_plant", "loft_lighting_support", "east_upper_transition_stair",
    "northwest_l_stair",
}


def packages(root):
    out = []
    def walk(coll):
        if coll.get("资产包"):
            out.append(coll)
        for child in coll.children:
            walk(child)
    walk(root)
    return out


def signature(obj):
    data = None
    if obj.type == "MESH":
        coords = tuple(round(float(c), 6) for v in obj.data.vertices for c in v.co)
        data = (
            len(obj.data.vertices), len(obj.data.polygons),
            hashlib.sha256(repr(coords).encode()).hexdigest(),
            tuple(m.name if m else None for m in obj.data.materials),
            hashlib.sha256(bytes(p.material_index % 256 for p in obj.data.polygons)).hexdigest(),
        )
    anim = []
    if obj.animation_data and obj.animation_data.action:
        for fcurve in obj.animation_data.action.fcurves:
            anim.append((fcurve.data_path, fcurve.array_index, tuple((round(k.co.x, 4), round(k.co.y, 6)) for k in fcurve.keyframe_points)))
    return {
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "matrix": [round(float(c), 7) for row in obj.matrix_world for c in row],
        "dimensions": [round(float(c), 7) for c in obj.dimensions],
        "data": data,
        "animation": anim,
    }


def capture(path, outname, scope_key):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    root = bpy.data.collections[outname]
    result = {}
    for pkg in packages(root):
        for obj in pkg.objects:
            if not obj.get(scope_key):
                result[obj.name] = signature(obj)
    return result


def rounded(obj, attr):
    return [round(float(v), 3) for v in getattr(obj, attr)]


def main():
    before = capture(V010, OUT10, "v010_scope")
    after = capture(V011, OUT11, "v011_scope")
    errors = []
    changed = sorted(k for k in before.keys() & after.keys() if before[k] != after[k])
    added = sorted(after.keys() - before.keys())
    removed = sorted(before.keys() - after.keys())
    if changed or added or removed:
        errors.append(f"locked mismatch changed={changed[:10]} added={added[:10]} removed={removed[:10]}")

    root = bpy.data.collections[OUT11]
    packs = packages(root)
    slugs = [p.get("资产包键") for p in packs]
    if len(packs) != 101:
        errors.append(f"packages={len(packs)} expected=101")
    if len(slugs) != len(set(slugs)):
        errors.append("duplicate slugs")
    missing = sorted(REQ - set(slugs))
    if missing:
        errors.append(f"missing packages={missing}")
    empty = [p.name for p in packs if not p.objects]
    if empty:
        errors.append(f"empty packages={empty}")
    floor = sum(p.get("资产类别") == "floor" for p in packs)
    if floor != 36:
        errors.append(f"floor packages={floor}")
    owners = {}
    for pkg in packs:
        for obj in pkg.objects:
            owners.setdefault(obj.name, []).append(pkg.name)
    multi = {name: groups for name, groups in owners.items() if len(groups) != 1}
    if multi:
        errors.append(f"multi ownership={dict(list(multi.items())[:10])}")

    manifests = list(ROOT.glob("*/*/asset_manifest.json"))
    if len(manifests) != 101:
        errors.append(f"manifests={len(manifests)} expected=101")
    manifest_slugs = {json.loads(p.read_text(encoding="utf-8"))["asset_slug"] for p in manifests}
    if manifest_slugs != set(slugs):
        errors.append("manifest/catalog slug mismatch")

    expected = {
        "床垫_厚软包": ([.3, 11.25, 6.78], [4.52, 1.86, .38]),
        "沙发_低矮加厚底座": ([6.25, 12.28, 6.43], [4.05, 1.5, .5]),
        "茶几_红棕圆角台面": ([6.2, 9.38, 6.7], [2.85, 1.28, .17]),
        "工位_深色桌面": ([10.45, 13.7, 6.84], [3.75, 1.08, .17]),
        "L梯_西北转角平台": ([-13.8, 13.8, 2.925], [2.0, 2.0, .24]),
        "L梯_阁楼顶层接驳平台": ([-6.52, 13.8, 6.045], [3.44, 2.0, .09]),
        "东侧楼梯_底部接缝压板": ([13.28, 10.3, 6.085], [1.72, .26, .045]),
        "东侧楼梯_顶部接驳平台": ([13.28, 14.52, 8.68], [1.95, .8, .16]),
    }
    transforms = {}
    for name, (loc, dims) in expected.items():
        obj = bpy.data.objects.get(name)
        if not obj:
            errors.append(f"missing key object={name}")
            continue
        transforms[name] = {"location": rounded(obj, "location"), "dimensions": rounded(obj, "dimensions")}
        if transforms[name]["location"] != loc or transforms[name]["dimensions"] != dims:
            errors.append(f"transform mismatch {name}={transforms[name]} expected={(loc, dims)}")

    chair = bpy.data.objects.get("办公椅_坐垫")
    stair = bpy.data.objects.get("东侧楼梯_踏步_01")
    east_clearance = round((stair.location.x - stair.dimensions.x / 2) - (chair.location.x + chair.dimensions.x / 2), 3) if chair and stair else -1
    if east_clearance < 1.0:
        errors.append(f"workstation to east-stair clearance={east_clearance}")
    walkway = round(8.55 - 5.15, 3)
    if walkway < 3.0:
        errors.append(f"front circulation depth={walkway}")
    required_images = [
        "base_facility_runtime_layout_hq_v011_reference_match.png",
        "base_facility_runtime_layout_hq_v011_loft_detail.png",
        "base_facility_runtime_layout_hq_v011_stair_interfaces.png",
        "base_facility_runtime_layout_hq_v011_top.png",
    ]
    missing_images = [name for name in required_images if not (REPORT.parent / name).exists()]
    if missing_images:
        errors.append(f"missing verification images={missing_images}")

    report = {
        "asset_id": "ENV-BASE99-ART-LAYOUT-3D",
        "version": "v011",
        "scope": "second-floor facilities and stairs high-fidelity iteration only",
        "status": "PASS" if not errors else "FAIL",
        "locked_object_count_v010": len(before),
        "locked_object_count_v011": len(after),
        "locked_changed": changed,
        "locked_added": added,
        "locked_removed": removed,
        "package_count": len(packs),
        "floor_tile_package_count": floor,
        "manifest_count": len(manifests),
        "v011_scope_object_count": sum(bool(o.get("v011_scope")) for o in bpy.data.objects),
        "workstation_east_stair_clearance_m": east_clearance,
        "front_circulation_depth_m": walkway,
        "key_transforms": transforms,
        "verification_images": required_images,
        "errors": errors,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if errors:
        raise RuntimeError("v011 task validation failed")


if __name__ == "__main__":
    main()
