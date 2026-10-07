"""Create Tower03 v002 as a partitioned, independent optimization derivative.

Input: the already flattened v001 runtime output Blend.
Output: source/tower_03/export/v002/env_tower_03-v002-runtime_optimized.blend

The v001 source and v001 runtime derivative are never overwritten. Walkable rooftop
visuals use conservative ratios; hidden/low-visibility architecture uses deeper
ratios. This file only changes mesh data in the independent v002 derivative.
"""
from __future__ import annotations

import bpy
import hashlib
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
BASE = ROOT / "assets/art/environments/open_world"
SOURCE = BASE / "source/tower_03/export/v001/env_tower_03-v001-runtime.blend"
MANIFEST_PATH = BASE / "source/tower_03/export/v001/export_manifest.json"
OUT_DIR = BASE / "source/tower_03/export/v002"
OUT_BLEND = OUT_DIR / "env_tower_03-v002-runtime_optimized.blend"
QA_DIR = OUT_DIR / "qa"

# These ratios are deliberately per role, not one global knife.
# Rooftop walking/edge pieces are conservative; repeated facade and hidden
# equipment pieces carry the reduction budget.
RATIOS = {
    "floor": None,          # clean only; preserve walkable tile silhouettes
    "walk_critical": 0.82, # rails, stairs, vertical access, roof plant room
    "facade": 0.25,         # deep optimization; repeated/low-detail exterior panels
    "hvac": 0.34,
    "support_hidden": 0.30,
    "telecom": 0.40,
    "architecture": 0.45,
    "default": 0.40,
}

WALK_CRITICAL = {
    "lower_rail_0", "lower_rail_1", "lower_rail_2", "lower_rail_3",
    "upper_rail_0", "upper_rail_1", "upper_rail_2", "upper_rail_3",
    "left_service_stairs", "vertical_access", "plant_room", "plant_east_louvers",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    if not points:
        return [[], []]
    return ([min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)])


def category_ratio(slug: str, category: str):
    if category == "floor":
        return RATIOS["floor"]
    if slug in WALK_CRITICAL:
        return RATIOS["walk_critical"]
    if slug.startswith("facade_"):
        return RATIOS["facade"]
    if category == "hvac":
        return RATIOS["hvac"]
    if category == "support":
        return RATIOS["support_hidden"]
    if category == "telecom":
        return RATIOS["telecom"]
    if category == "architecture":
        return RATIOS["architecture"]
    return RATIOS["default"]


assert SOURCE.is_file(), SOURCE
assert MANIFEST_PATH.is_file(), MANIFEST_PATH
source_hash = sha256(SOURCE)
manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
assert manifest["asset_id"] == "ENV-OPENWORLD-TOWER03"
assert manifest["version"] == "v001"
assert len(manifest["records"]) == 217
assert Path(bpy.data.filepath).resolve() == SOURCE.resolve(), (bpy.data.filepath, SOURCE)

records_before = {}
all_objects = []
for record in manifest["records"]:
    objects = []
    for name in record["objects"]:
        obj = bpy.data.objects.get(name)
        assert obj is not None, (record["slug"], name)
        assert obj.type == "MESH", (record["slug"], name, obj.type)
        objects.append(obj)
        all_objects.append(obj)
    all_objects = list(dict.fromkeys(all_objects))
    records_before[record["slug"]] = {
        "triangles": sum(tri_count(obj) for obj in objects),
        "bounds": bounds(objects),
        "objects": [obj.name for obj in objects],
        "ratio": category_ratio(record["slug"], record["category"]),
    }

before_total = sum(item["triangles"] for item in records_before.values())
assert before_total == 212967, before_total

for record in manifest["records"]:
    ratio = records_before[record["slug"]]["ratio"]
    for name in records_before[record["slug"]]["objects"]:
        obj = bpy.data.objects[name]
        # Every output object goes through validation/cleanup. Only the explicitly
        # budgeted groups receive Decimate; floors remain visually intact.
        if ratio is not None and len(obj.data.polygons) >= 4:
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new(name="OPT_Tower03_v002", type="DECIMATE")
            modifier.decimate_type = "COLLAPSE"
            modifier.ratio = ratio
            modifier.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            obj.select_set(False)
        obj.data.validate(clean_customdata=False)
        obj.data.update()
        assert obj.data.uv_layers.get("PaletteUV") is not None or obj.data.uv_layers.get("UVMap") is not None, name

records_after = {}
after_total = 0
for record in manifest["records"]:
    objects = [bpy.data.objects[name] for name in record["objects"]]
    before = records_before[record["slug"]]
    after = sum(tri_count(obj) for obj in objects)
    new_bounds = bounds(objects)
    # Decimation may remove an extreme vertex, but it must not alter the component
    # envelope enough to affect the route wrapper's independent collision proxies.
    for a, b in zip(before["bounds"][0] + before["bounds"][1], new_bounds[0] + new_bounds[1]):
        assert abs(a - b) < 0.20, (record["slug"], a, b)
    records_after[record["slug"]] = {
        "triangles_before": before["triangles"],
        "triangles_after": after,
        "reduction_ratio": (before["triangles"] - after) / before["triangles"] if before["triangles"] else None,
        "ratio": before["ratio"],
        "bounds_before": before["bounds"],
        "bounds_after": new_bounds,
        "objects": before["objects"],
        "category": record["category"],
        "walk_critical": record["slug"] in WALK_CRITICAL,
    }
    after_total += after

assert after_total < 100000, after_total
OUT_DIR.mkdir(parents=True, exist_ok=True)
QA_DIR.mkdir(parents=True, exist_ok=True)
# Save first, then the caller reopens this exact file before export.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND))
assert OUT_BLEND.is_file()
report = {
    "passed": True,
    "asset_id": "ENV-OPENWORLD-TOWER03",
    "source": SOURCE.relative_to(ROOT).as_posix(),
    "source_sha256_before": source_hash,
    "source_sha256_after": sha256(SOURCE),
    "optimized_blend": OUT_BLEND.relative_to(ROOT).as_posix(),
    "optimized_blend_sha256": sha256(OUT_BLEND),
    "version": "v002",
    "records": 217,
    "triangles_before": before_total,
    "triangles_after": after_total,
    "reduction_ratio": (before_total - after_total) / before_total,
    "target_max_triangles": 100000,
    "ratios": RATIOS,
    "walk_critical_slugs": sorted(WALK_CRITICAL),
    "component_results": records_after,
    "source_unchanged": source_hash == sha256(SOURCE),
    "formal_layout_rewritten": False,
    "notes": [
        "Floor tiles are clean-only to preserve walkable rooftop visual continuity.",
        "Rails, stairs, vertical access, plant room and louvers use conservative reduction.",
        "Repeated facade panels and hidden equipment carry the deep reduction budget.",
        "Collision remains owned by cross_tower_route; visual tower Prefabs remain collision-free.",
        "Stable GLB/PackedScene paths are not touched in this stage.",
    ],
}
(QA_DIR / "optimization_v002.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: report[k] for k in ("passed", "version", "records", "triangles_before", "triangles_after", "reduction_ratio", "source_unchanged", "optimized_blend_sha256")}, ensure_ascii=False))
