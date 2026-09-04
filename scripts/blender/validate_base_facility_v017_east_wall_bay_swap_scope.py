#!/usr/bin/env python3
"""Strict PaletteUV/material validation for the four assets changed by the east-wall bay swap."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/east_wall_bay_swap_scope_palette_validation.json"
VALIDATOR = PROJECT / ".codex/skills/blender-game-prop-standard/scripts/validate_game_prop.py"
SLUGS = (
    "east_door_wall_module",
    "east_personnel_security_door",
    "east_door_access_control",
    "east_supply_24h_station",
)

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location("game_prop_validator", VALIDATOR)
validator = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(validator)

collections = []
for slug in SLUGS:
    output = next((c for c in bpy.data.collections if c.get("资产包键") == slug and not c.name.startswith("v017_源资产包_")), None)
    source = bpy.data.collections.get(f"v017_源资产包_{slug}")
    if output is None or source is None:
        raise RuntimeError(f"missing output/source pair for {slug}")
    collections.extend((output, source))

meshes = sorted({obj for collection in collections for obj in collection.objects if obj.type == "MESH"}, key=lambda obj: obj.name)
uv_reports = [validator.audit_palette_uv(obj) for obj in meshes]
materials = validator.material_audit(meshes, PALETTE)
missing = [report["object"] for report in uv_reports if report["missing_palette_uv"]]
bad_faces = [report for report in uv_reports if report["valid_island_polygon_count"] != report["polygon_count"]]
bad_active = [report["object"] for report in uv_reports if report["active_uv"] != validator.PALETTE_UV]
bad_render = [report["object"] for report in uv_reports if report["active_render_uv"] != validator.PALETTE_UV]
extra = {report["object"]: report["extra_uv_layers"] for report in uv_reports if report["extra_uv_layers"]}
mixed = []
bad_emissive_names = []
budget = []
for obj in meshes:
    flags = {validator.material_is_emissive(mat) for mat in obj.data.materials if mat}
    if len(flags) > 1:
        mixed.append(obj.name)
    if True in flags and not any(token in obj.name.lower() for token in ("自发光", "ui灯光", "emissive", "glow", "状态灯")):
        bad_emissive_names.append(obj.name)
    slots = len([mat for mat in obj.data.materials if mat])
    if (True in flags and slots > 1) or (True not in flags and slots > 3):
        budget.append(obj.name)

checks = {
    "scope_meshes_present": bool(meshes),
    "material_budget_le_12": len(materials["used_materials"]) <= 12,
    "palette_uv_present": not missing,
    "palette_uv_per_face_single_safe_cell_with_area": not bad_faces,
    "palette_uv_active": not bad_active,
    "palette_uv_render_active": not bad_render,
    "no_extra_uv": not extra,
    "materials_read_palette_uv": not materials["bad_uv_map_nodes"] and not materials["missing_uv_map_nodes"],
    "palette_is_shared_external_and_closest": not materials["bad_image_interpolation"] and not materials["non_shared_palette_images"] and not materials["packed_palette_images"],
    "no_mixed_body_emission": not mixed,
    "emissive_meshes_named": not bad_emissive_names,
    "material_slots_within_role_budget": not budget,
}
result = {
    "blend": str(BLEND),
    "scope": list(SLUGS),
    "passed": all(checks.values()),
    "checks": checks,
    "mesh_count": len(meshes),
    "polygon_count": sum(report["polygon_count"] for report in uv_reports),
    "valid_island_polygon_count": sum(report["valid_island_polygon_count"] for report in uv_reports),
    "missing_palette_uv": missing,
    "bad_face_objects": [{"object": report["object"], "examples": report["bad_polygon_examples"]} for report in bad_faces],
    "extra_uv_layers": extra,
    "bad_emissive_names": bad_emissive_names,
    "material_audit": materials,
}
REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
if not result["passed"]:
    raise SystemExit(1)
