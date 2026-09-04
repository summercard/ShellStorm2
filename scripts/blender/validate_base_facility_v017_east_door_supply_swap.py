#!/usr/bin/env python3
"""Task-level acceptance for the v017 east door / SUPPLY 24H correction."""
from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/east_door_supply_swap_acceptance.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

door_package = bpy.data.collections.get("71_正式人员安全门_资产包")
access_package = bpy.data.collections.get("73_东墙门禁外围控制_资产包")
supply_package = bpy.data.collections.get("72_SUPPLY24H自动补给机_资产包")
door_source = bpy.data.collections.get("v017_源资产包_east_personnel_security_door")
access_source = bpy.data.collections.get("v017_源资产包_east_door_access_control")
supply_source = bpy.data.collections.get("v017_源资产包_east_supply_24h_station")
required_collections = (door_package, access_package, supply_package, door_source, access_source, supply_source)
if any(c is None for c in required_collections):
    raise RuntimeError("required output/source package collection missing")

door_mesh_names = ("东墙标准滑升门_主体_金属哑光反光", "东墙标准滑升门_状态灯_柔和自发光")
source_door_mesh_names = tuple(f"{name}__源" for name in door_mesh_names)
errors = []
for name in door_mesh_names:
    obj = bpy.data.objects.get(name)
    if obj is None or obj.name not in door_package.objects:
        errors.append(f"door mesh not exclusively in door package: {name}")
for name in source_door_mesh_names:
    obj = bpy.data.objects.get(name)
    if obj is None or obj.name not in door_source.objects:
        errors.append(f"door source mesh not in mirror package: {name}")

def world_bounds(objs):
    points = [obj.matrix_world @ Vector(corner) for obj in objs for corner in obj.bound_box]
    lo = [min(v[i] for v in points) for i in range(3)]
    hi = [max(v[i] for v in points) for i in range(3)]
    return [round((lo[i] + hi[i]) / 2, 4) for i in range(3)], [round(hi[i] - lo[i], 4) for i in range(3)]

door_meshes = [bpy.data.objects[name] for name in door_mesh_names]
center, dimensions = world_bounds(door_meshes)
if center != [13.52, 1.55, 1.25]:
    errors.append(f"door center mismatch: {center}")
if dimensions != [0.325, 2.2, 2.5]:
    errors.append(f"door dimensions mismatch: {dimensions}")

uv_report = {}
for name in door_mesh_names + source_door_mesh_names:
    mesh = bpy.data.objects[name].data
    layers = [layer.name for layer in mesh.uv_layers]
    layer = mesh.uv_layers.get("PaletteUV")
    bad_faces = []
    if layers != ["PaletteUV"] or mesh.uv_layers.active != layer or not layer.active_render:
        errors.append(f"palette layer contract mismatch: {name} {layers}")
    for poly in mesh.polygons:
        values = [layer.data[index].uv for index in poly.loop_indices]
        # Every loop must remain in one shared 10×10 palette-cell safe zone
        # and preserve a non-zero editable face island.
        columns = {min(9, max(0, int(uv.x * 10.0))) for uv in values}
        rows = {min(9, max(0, int(uv.y * 10.0))) for uv in values}
        safe = len(columns) == 1 and len(rows) == 1 and all(
            columns.copy().pop() / 10.0 + 0.01 <= uv.x <= (columns.copy().pop() + 1) / 10.0 - 0.01
            and rows.copy().pop() / 10.0 + 0.01 <= uv.y <= (rows.copy().pop() + 1) / 10.0 - 0.01
            for uv in values
        )
        area = abs(sum(values[i].x * values[(i + 1) % len(values)].y - values[(i + 1) % len(values)].x * values[i].y for i in range(len(values)))) * 0.5
        if not safe or area < 1e-7:
            bad_faces.append(poly.index)
    if bad_faces:
        errors.append(f"palette UV faces out of safe cell: {name} {bad_faces[:8]}")
    uv_report[name] = {"layers": layers, "polygons": len(mesh.polygons), "bad_faces": bad_faces}

body = bpy.data.objects.get("SUPPLY24H_主体外壳")
if body is None or (Vector(body.location) - Vector((14.22, -2.50, 1.78))).length > 0.001:
    errors.append(f"SUPPLY 24H body anchor mismatch: {list(body.location) if body else None}")

old_door_names = [
    obj.name for obj in bpy.data.objects
    if obj.name.startswith("东墙人员门_")
    and obj.name not in access_package.objects
    and obj.name not in access_source.objects
]
if old_door_names:
    errors.append(f"old noncanonical door geometry remains outside access package: {old_door_names}")
if len(door_package.objects) != 3 or len(access_package.objects) != 17:
    errors.append(f"unexpected package split: door={len(door_package.objects)} access={len(access_package.objects)}")
lamp = bpy.data.objects.get("东墙滑升门_状态照明")
lamp_source = bpy.data.objects.get("东墙滑升门_状态照明__源")
if lamp is None or lamp.type != "LIGHT" or lamp.name not in door_package.objects:
    errors.append("door state light is not owned by output door package")
if lamp_source is None or lamp_source.type != "LIGHT" or lamp_source.name not in door_source.objects:
    errors.append("door state source light is not owned by source door package")

source_mirror_counts = {
    "door": len(door_source.objects), "access": len(access_source.objects), "supply": len(supply_source.objects)
}
if source_mirror_counts["door"] != 3 or source_mirror_counts["access"] != 17:
    errors.append(f"unexpected door/access source mirror counts: {source_mirror_counts}")

data = json.loads(REPORT.read_text(encoding="utf-8"))
lock = data.get("lock", {})
if not lock.get("locked_match") or lock.get("locked_count") != 5855:
    errors.append("stored non-target scope lock is not passing")
data["final_task_validation"] = {
    "status": "pass" if not errors else "fail",
    "door_visual_center_m": center,
    "door_visual_dimensions_m": dimensions,
    "supply_body_location_m": [round(float(v), 4) for v in body.location] if body else None,
    "door_package_object_count": len(door_package.objects),
    "access_package_object_count": len(access_package.objects),
    "source_mirror_counts": source_mirror_counts,
    "palette_uv": uv_report,
    "light_owner": lamp.users_collection[0].name if lamp and lamp.users_collection else None,
    "errors": errors,
}
REPORT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(data["final_task_validation"], ensure_ascii=False))
if errors:
    raise RuntimeError("east-door/SUPPLY acceptance failed")
