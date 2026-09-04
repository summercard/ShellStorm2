#!/usr/bin/env python3
"""Run the Blender Game Prop Standard palette checks on v016 additions only."""

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v016/v016_added_scope_palette_validation.json"
VALIDATOR = PROJECT / ".codex/skills/blender-game-prop-standard/scripts/validate_game_prop.py"

spec = importlib.util.spec_from_file_location("game_prop_validator", VALIDATOR)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

meshes = sorted(
    (o for o in bpy.context.scene.objects if o.type == "MESH" and o.get("v016_scope")),
    key=lambda o: o.name,
)
uv_reports = [validator.audit_palette_uv(obj) for obj in meshes]
material_report = validator.material_audit(meshes, PALETTE)
mixed_emission = []
bad_emissive_names = []
body_budget_failures = []
emissive_budget_failures = []
for obj in meshes:
    flags = {validator.material_is_emissive(m) for m in obj.data.materials if m}
    if len(flags) > 1:
        mixed_emission.append(obj.name)
    is_emissive = True in flags
    if is_emissive and not any(k in obj.name.lower() for k in ("自发光", "ui灯光", "emissive", "glow")):
        bad_emissive_names.append(obj.name)
    slots = len([m for m in obj.data.materials if m])
    if is_emissive and slots > 1:
        emissive_budget_failures.append(obj.name)
    if not is_emissive and slots > 3:
        body_budget_failures.append(obj.name)

missing_uv = [r["object"] for r in uv_reports if r["missing_palette_uv"]]
bad_faces = [r for r in uv_reports if r["valid_island_polygon_count"] != r["polygon_count"]]
bad_active = [r["object"] for r in uv_reports if r["active_uv"] != validator.PALETTE_UV]
bad_render = [r["object"] for r in uv_reports if r["active_render_uv"] != validator.PALETTE_UV]
extra_uv = {r["object"]: r["extra_uv_layers"] for r in uv_reports if r["extra_uv_layers"]}
checks = {
    "material_budget": len(material_report["used_materials"]) <= 12,
    "has_scoped_meshes": bool(meshes),
    "palette_uv_on_all_scoped_meshes": not missing_uv,
    "palette_uv_face_islands_within_single_cells": not bad_faces,
    "palette_uv_is_active_edit_layer": not bad_active,
    "palette_uv_is_active_render_layer": not bad_render,
    "no_undeclared_extra_uv_layers": not extra_uv,
    "materials_read_palette_uv": not material_report["bad_uv_map_nodes"] and not material_report["missing_uv_map_nodes"],
    "palette_images_use_closest": not material_report["bad_image_interpolation"],
    "palette_images_use_single_external_shared_file": not material_report["non_shared_palette_images"] and not material_report["packed_palette_images"],
    "emissive_not_mixed_with_body": not mixed_emission,
    "emissive_objects_clearly_named": not bad_emissive_names,
    "body_has_at_most_three_materials": not body_budget_failures,
    "emissive_has_one_material": not emissive_budget_failures,
}
report = {
    "blend": bpy.data.filepath,
    "scope": "objects tagged v016_scope only; inherited v015 objects are immutable",
    "passed": all(checks.values()),
    "checks": checks,
    "scoped_mesh_count": len(meshes),
    "polygon_count": sum(r["polygon_count"] for r in uv_reports),
    "valid_island_polygon_count": sum(r["valid_island_polygon_count"] for r in uv_reports),
    "material_audit": material_report,
    "extra_uv_layers": extra_uv,
    "poorly_named_emissive_objects": bad_emissive_names,
    "mixed_emission_objects": mixed_emission,
    "body_material_budget_failures": body_budget_failures,
    "emissive_material_budget_failures": emissive_budget_failures,
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False))
if not report["passed"]:
    raise SystemExit(1)
