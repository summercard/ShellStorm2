#!/usr/bin/env python3
"""Read-only acceptance for the wall-owned north door frame in v017."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/north_door_wall_frame_package_validation.json"
ASSEMBLY = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017/component_sets/east_door_wall_set/assembly_manifest.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location("v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)

wall_pkg = reorg.package_by_slug("east_door_wall_module")
door_pkg = reorg.package_by_slug("east_personnel_security_door")
access_pkg = reorg.package_by_slug("east_door_access_control")
wall = bpy.data.objects["带门墙体_主体_金属哑光反光.002"]
source = bpy.data.objects["带门墙体_主体_金属哑光反光.002__源"]
door = bpy.data.objects["东墙标准滑升门_主体_金属哑光反光"]
errors = []

expected_wall = {"ENV-BASE99-WALL-DOOR-5X9_输出根节点.002", "保留东墙_03", "带门墙体_主体_金属哑光反光.002"}
if {obj.name for obj in wall_pkg.objects} != expected_wall:
    errors.append("wall package objects are not the isolated three-object wall module")
if "门框归属" not in wall or wall["门框归属"].split("（", 1)[0] != "east_door_wall_module":
    errors.append("wall frame ownership property missing")
if "门框归属" not in source or source["门框归属"] != wall.get("门框归属"):
    errors.append("source wall frame ownership mirror mismatch")
if len(wall.data.vertices) != len(source.data.vertices) or len(wall.data.polygons) != len(source.data.polygons):
    errors.append("source/output wall geometry count mismatch")
if [tuple(round(float(v), 6) for v in vertex.co) for vertex in wall.data.vertices] != [tuple(round(float(v), 6) for v in vertex.co) for vertex in source.data.vertices]:
    errors.append("source/output wall vertex mismatch")
for obj in (wall, source):
    uv = obj.data.uv_layers.get("PaletteUV")
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"] or obj.data.uv_layers.active != uv or not uv.active_render:
        errors.append(f"PaletteUV contract failed: {obj.name}")
    if len(obj.data.materials) != 3:
        errors.append(f"wall material role count failed: {obj.name}")

center, dims = reorg.bbox((wall,))
if center != [14.9503, 2.5, 4.5] or dims != [1.2706, 5.0, 9.0]:
    errors.append(f"wall visual envelope mismatch: {center}, {dims}")
door_center, door_dims = reorg.bbox((door,))
if door_center != [15.0, 2.5, 1.25] or door_dims != [0.325, 2.2, 2.5]:
    errors.append(f"door leaf interface changed: {door_center}, {door_dims}")
if any("门框" in obj.name for obj in door_pkg.objects):
    errors.append("door frame object leaked into door-leaf package")
if not any("门侧控制面板" in obj.name for obj in access_pkg.objects):
    errors.append("independent access-control package missing")

manifest = json.loads(ASSEMBLY.read_text(encoding="utf-8"))
frame = manifest.get("wall_owned_frame_contract", {})
if frame.get("owner") != "east_door_wall_module" or manifest.get("visual_revision") != "v017_north_door_wall_frame_refine_001":
    errors.append("assembly frame ownership contract missing")
owners = {obj.name: [collection.get("资产包键") for collection in obj.users_collection if collection.get("资产包")] for obj in bpy.data.objects}
multiple = {name: value for name, value in owners.items() if len(value) > 1}
if multiple:
    errors.append("multi-package object ownership found")

result = {
    "status": "pass" if not errors else "fail",
    "package_count": len(reorg.packages()),
    "wall_package_object_count": len(wall_pkg.objects),
    "source_package_object_count": len(bpy.data.collections["v017_源资产包_east_door_wall_module"].objects),
    "wall_visual_center_m": center,
    "wall_visual_dimensions_m": dims,
    "door_leaf_center_m": door_center,
    "door_leaf_dimensions_m": door_dims,
    "wall_frame_owner": frame.get("owner"),
    "door_leaf_owner": "east_personnel_security_door",
    "access_control_owner": "east_door_access_control",
    "multi_package_objects": multiple,
    "errors": errors,
}
REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
if errors:
    raise SystemExit(1)
