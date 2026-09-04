#!/usr/bin/env python3
"""Strict scoped acceptance for v017 loft bed, lounge rug, and loft floor finish."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/loft_bed_rug_floor_refinement_acceptance.json"
CATALOG = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/base_facility_component_catalog_v017.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

validator_spec = importlib.util.spec_from_file_location(
    "prop_validator", PROJECT / ".codex/skills/blender-game-prop-standard/scripts/validate_game_prop.py"
)
validator = importlib.util.module_from_spec(validator_spec)
assert validator_spec.loader is not None
validator_spec.loader.exec_module(validator)


def pack(slug):
    result = next((c for c in bpy.data.collections if c.get("资产包键") == slug), None)
    if result is None:
        raise RuntimeError(f"missing output package {slug}")
    return result


def source(slug):
    result = bpy.data.collections.get(f"v017_源资产包_{slug}")
    if result is None:
        raise RuntimeError(f"missing source package {slug}")
    return result


def meshes(coll):
    return [obj for obj in coll.objects if obj.type == "MESH"]


def cell(obj):
    value = str(obj.get("色盘UV", ""))
    return value.removeprefix("PaletteUV cell ")


bed = pack("loft_bed_and_bedding")
rug = pack("loft_lounge_rug")
floor = pack("loft_floor_finish")
target_slugs = ("loft_bed_and_bedding", "loft_lounge_rug", "loft_floor_finish")
target = [bed, rug, floor]
checks = {}
checks["all_three_output_packages_exist"] = len(target) == 3
checks["all_three_source_packages_exist"] = all(source(slug) for slug in target_slugs)
checks["output_source_object_counts_match"] = all(len(pack(slug).objects) == len(source(slug).objects) for slug in target_slugs)
checks["bed_reference_length_restored_to_4_75m"] = round(bpy.data.objects["床架_长边_10.28"].dimensions.x, 3) == 4.75 and round(bpy.data.objects["床架_长边_12.22"].dimensions.x, 3) == 4.75
checks["bed_widened_on_y_to_2_55m"] = round(bpy.data.objects["床架_短边_-2.0"].dimensions.y, 3) == 2.55 and round(bpy.data.objects["床架_短边_2.6"].dimensions.y, 3) == 2.55
checks["mattress_width_is_2_30m"] = round(bpy.data.objects["床垫_厚软包"].dimensions.y, 3) == 2.30 and round(bpy.data.objects["床垫_厚软包"].dimensions.x, 3) == 4.52
checks["rug_has_multicolour_design"] = len({cell(o) for o in meshes(rug)}) >= 5
checks["rug_has_13_objects"] = len(rug.objects) == 13
checks["floor_is_independent_package"] = len(floor.objects) == 11 and "二楼地板_红棕生活基底" in floor.objects
mezz = pack("east_mezzanine_structure")
checks["floor_not_mixed_with_mezzanine_structure"] = "二楼地板_红棕生活基底" not in mezz.objects and "楼中楼_深色木纹生活面" not in mezz.objects
checks["floor_has_multizone_design"] = len({cell(o) for o in meshes(floor)}) >= 5
checks["floor_has_no_green_primary_panels"] = all("青绿" not in o.name and cell(o) not in {"0.25,0.55", "0.45,0.55", "0.25,0.65", "0.45,0.65"} for o in meshes(floor))
checks["rug_uses_reference_red_purple_brown_family"] = all("青绿" not in o.name for o in meshes(rug))
checks["floor_details_do_not_cover_rug"] = max(o.location.z + o.dimensions.z / 2 for o in meshes(floor) if o.name != "二楼地板_红棕生活基底") < bpy.data.objects["休闲区低饱和地毯_软质基底"].location.z + bpy.data.objects["休闲区低饱和地毯_软质基底"].dimensions.z / 2

uv_reports = []
for coll in target:
    for mesh in meshes(coll):
        audit = validator.audit_palette_uv(mesh)
        uv_reports.append(audit)
checks["target_meshes_have_strict_palette_uv"] = all(
    audit["valid_island_polygon_count"] == audit["polygon_count"]
    and audit["active_uv"] == "PaletteUV"
    and audit["active_render_uv"] == "PaletteUV"
    and not audit["extra_uv_layers"]
    for audit in uv_reports
)
material_report = validator.material_audit([mesh for coll in target for mesh in meshes(coll)])
checks["target_materials_read_palette_uv"] = not material_report["bad_uv_map_nodes"] and not material_report["missing_uv_map_nodes"]

owners = {}
for coll in (c for c in bpy.data.collections if c.get("资产包")):
    for object_name in coll.objects.keys():
        owners.setdefault(object_name, []).append(str(coll.get("资产包键")))
duplicates = {name: values for name, values in owners.items() if len(values) > 1}
checks["no_output_object_has_multiple_asset_owners"] = not duplicates
catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
entries = {entry.get("asset_slug"): entry for entry in catalog.get("packages", [])}
checks["catalog_includes_new_floor_package"] = catalog.get("package_count") == 115 and entries.get("loft_floor_finish", {}).get("object_count") == 11

report = {
    "status": "pass" if all(checks.values()) else "fail",
    "checks": checks,
    "bed_length_m": round(bpy.data.objects["床架_长边_10.28"].dimensions.x, 3),
    "bed_width_m": round(bpy.data.objects["床架_短边_-2.0"].dimensions.y, 3),
    "mattress_width_m": round(bpy.data.objects["床垫_厚软包"].dimensions.y, 3),
    "package_counts": {slug: len(pack(slug).objects) for slug in target_slugs},
    "source_package_counts": {slug: len(source(slug).objects) for slug in target_slugs},
    "target_uv_reports": uv_reports,
    "target_material_audit": material_report,
    "duplicate_output_owners": duplicates,
    "scope_lock": "未变动楼梯、栏杆、沙发、工位、咖啡桌本体及一楼资产。",
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False))
raise SystemExit(0 if report["status"] == "pass" else 1)
