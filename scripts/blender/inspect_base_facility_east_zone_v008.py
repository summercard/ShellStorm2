#!/usr/bin/env python3
"""Read-only inventory and measurements for the v008 east facility zone."""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path("/Users/summercards/ShellStorm2")
OUT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v009/east_zone_inventory_v008.json"
KEYWORDS = (
    "门", "补给", "贩卖", "SUPPLY", "配电", "POWER", "垃圾", "FLAMMABLE",
    "RECYCLE", "WASTE", "维修", "工具", "储物", "植物", "海报", "资料板",
    "吊灯", "工作台", "接线", "管线", "线管", "沙发", "长凳", "座椅",
)


def bbox_world(obj):
    if not getattr(obj, "bound_box", None):
        return None
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return {
        "min": [round(v, 5) for v in lo],
        "max": [round(v, 5) for v in hi],
        "center": [round((lo[i] + hi[i]) * 0.5, 5) for i in range(3)],
        "size": [round(hi[i] - lo[i], 5) for i in range(3)],
    }


output = bpy.data.collections.get("02_游戏输出_独立资产包_v008")
if output is None:
    raise RuntimeError("v008 output collection missing")

packages = []
for category in output.children:
    for package in category.children:
        names = [obj.name for obj in package.objects]
        if any(any(keyword.lower() in name.lower() for keyword in KEYWORDS) for name in names + [package.name]):
            packages.append({
                "category": category.name,
                "package": package.name,
                "slug": package.get("资产包键"),
                "objects": [
                    {
                        "name": obj.name,
                        "type": obj.type,
                        "location": [round(float(v), 5) for v in obj.matrix_world.translation],
                        "rotation": [round(float(v), 5) for v in obj.rotation_euler],
                        "dimensions": [round(float(v), 5) for v in obj.dimensions],
                        "bbox": bbox_world(obj),
                    }
                    for obj in sorted(package.objects, key=lambda item: item.name)
                ],
            })

wall_doors = []
for obj in sorted(bpy.data.objects, key=lambda item: item.name):
    if "带门墙体" in obj.name or "WALL-DOOR" in obj.name:
        wall_doors.append({
            "name": obj.name,
            "type": obj.type,
            "location": [round(float(v), 5) for v in obj.matrix_world.translation],
            "rotation": [round(float(v), 5) for v in obj.rotation_euler],
            "dimensions": [round(float(v), 5) for v in obj.dimensions],
            "bbox": bbox_world(obj),
            "collections": sorted(c.name for c in obj.users_collection),
        })

east_spatial_objects = []
for category in output.children:
    for package in category.children:
        if category.name in {"10_建筑结构", "20_统一地面系统_36块独立地砖", "30_阁楼生活设施"}:
            continue
        for obj in package.objects:
            box = bbox_world(obj)
            if box and box["center"][0] >= 9.0 and box["center"][2] <= 6.2:
                east_spatial_objects.append({
                    "category": category.name,
                    "package": package.name,
                    "slug": package.get("资产包键"),
                    "name": obj.name,
                    "type": obj.type,
                    "location": [round(float(v), 5) for v in obj.matrix_world.translation],
                    "rotation": [round(float(v), 5) for v in obj.rotation_euler],
                    "dimensions": [round(float(v), 5) for v in obj.dimensions],
                    "bbox": box,
                })

payload = {
    "blend": bpy.data.filepath,
    "packages": packages,
    "wall_door_candidates": wall_doors,
    "east_spatial_objects": sorted(east_spatial_objects, key=lambda item: (item["slug"] or "", item["name"])),
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

preview_collection = bpy.data.collections.get("90_展示环境_灯光相机") or bpy.context.scene.collection
camera_data = bpy.data.cameras.new("v008东面诊断相机")
camera = bpy.data.objects.new("v008东面诊断相机", camera_data)
preview_collection.objects.link(camera)
camera.location = (1.5, -14.5, 10.5)
target = Vector((14.0, -4.5, 2.6))
camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 19.5
bpy.context.scene.camera = camera
bpy.context.scene.render.filepath = str(OUT.parent / "base_facility_runtime_layout_hq_v008_east_diagnostic.png")
bpy.context.scene.render.resolution_x = 1600
bpy.context.scene.render.resolution_y = 1000
bpy.context.scene.render.resolution_percentage = 100
bpy.ops.render.render(write_still=True)
print(f"EAST_ZONE_INVENTORY {OUT}")
