"""Compare the saved logistics 07 v005 source with v004 after HVAC reduction."""

import bpy
import hashlib
import json
import sys
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
ASSET_ROOT = PROJECT / "assets/art/environments/open_world/source/logistics_07"
OLD = ASSET_ROOT / "v004/env_logistics_07_source_v004.blend"
NEW = ASSET_ROOT / "v005/env_logistics_07_source_v005.blend"
HVAC_PREFIXES = ("roof_hvac_", "wall_ac_")


def file_sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def geometry_digest(objects):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda item: item.name):
        mesh = obj.data
        payload = {
            "name": obj.name,
            "matrix": [round(value, 6) for row in obj.matrix_world for value in row],
            "vertices": [[round(value, 6) for value in vert.co] for vert in mesh.vertices],
            "faces": [list(poly.vertices) for poly in mesh.polygons],
            "face_materials": [poly.material_index for poly in mesh.polygons],
            "slots": [slot.material.name for slot in obj.material_slots],
            "uv": [
                [round(value, 6) for value in loop.uv]
                for layer in mesh.uv_layers
                for loop in layer.data
            ],
        }
        digest.update(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf8"))
    return digest.hexdigest()


def bounds(objects):
    points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
    return {
        "min": [min(point[axis] for point in points) for axis in range(3)],
        "max": [max(point[axis] for point in points) for axis in range(3)],
    }


def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    catalog = json.loads((path.parent / "catalog.json").read_text(encoding="utf8"))
    packages = {}
    for entry in catalog["packages"]:
        objects = [bpy.data.objects[name] for name in entry["objects"]]
        packages[entry["slug"]] = {
            "triangles": sum(len(poly.vertices) - 2 for obj in objects for poly in obj.data.polygons),
            "polygons": sum(len(obj.data.polygons) for obj in objects),
            "vertices": sum(len(obj.data.vertices) for obj in objects),
            "bounds": bounds(objects),
            "geometry_sha256": geometry_digest(objects),
            "object_names": entry["objects"],
        }
    return packages


old_sha = file_sha(OLD)
before = snapshot(OLD)
after = snapshot(NEW)
errors = []
if set(before) != set(after):
    errors.append("package_set_changed")

optimized = []
unchanged = []
for slug in sorted(set(before) & set(after)):
    old, new = before[slug], after[slug]
    if slug.startswith(HVAC_PREFIXES):
        reduction = (old["triangles"] - new["triangles"]) / old["triangles"]
        bound_delta = max(
            abs(old["bounds"][side][axis] - new["bounds"][side][axis])
            for side in ("min", "max")
            for axis in range(3)
        )
        row = {
            "slug": slug,
            "triangles_before": old["triangles"],
            "triangles_after": new["triangles"],
            "triangle_reduction": round(reduction, 6),
            "polygons_before": old["polygons"],
            "polygons_after": new["polygons"],
            "max_bounds_delta_m": round(bound_delta, 6),
        }
        optimized.append(row)
        if reduction < 0.5:
            errors.append("hvac_reduction_below_half:" + slug)
        if bound_delta > 0.03:
            errors.append("hvac_bounds_drift:" + slug)
        if old["object_names"] != new["object_names"]:
            errors.append("hvac_object_names_changed:" + slug)
    else:
        unchanged.append(slug)
        if old["geometry_sha256"] != new["geometry_sha256"]:
            errors.append("non_hvac_geometry_changed:" + slug)

if len(optimized) != 11:
    errors.append("expected_eleven_hvac_units")
if len(after) != 334:
    errors.append("expected_334_packages")
if file_sha(OLD) != old_sha:
    errors.append("v004_source_changed_during_audit")

report = {
    "passed": not errors,
    "asset_id": "ENV-OPENWORLD-LOGISTICS07",
    "source_before": str(OLD),
    "source_after": str(NEW),
    "source_before_sha256": old_sha,
    "source_after_sha256": file_sha(NEW),
    "total_triangles_before": sum(item["triangles"] for item in before.values()),
    "total_triangles_after": sum(item["triangles"] for item in after.values()),
    "hvac_triangles_before": sum(before[row["slug"]]["triangles"] for row in optimized),
    "hvac_triangles_after": sum(after[row["slug"]]["triangles"] for row in optimized),
    "optimized_hvac_count": len(optimized),
    "unchanged_package_count": len(unchanged),
    "optimized_hvac": optimized,
    "errors": errors,
}
output = NEW.parent / "qa/optimization_v005.json"
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print("OPTIMIZATION_AUDIT=" + json.dumps({key: value for key, value in report.items() if key != "optimized_hvac"}, ensure_ascii=False))
sys.exit(0 if report["passed"] else 1)
