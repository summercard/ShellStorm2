#!/usr/bin/env python3
"""Render a temporary inspection image of the east copy of the west door set."""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
OUTPUT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/east_door_wall_copied_from_west.png"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
temp = bpy.data.collections.new("__TEMP_EAST_DOOR_COPY_RENDER__")
scene.collection.children.link(temp)
camera = bpy.data.objects.new("__TEMP_EAST_DOOR_COPY_CAMERA__", bpy.data.cameras.new("__TEMP_EAST_DOOR_COPY_CAMERA__"))
temp.objects.link(camera)
camera.data.lens = 42
camera.location = (23.0, -0.2, 5.1)
look_at(camera, (15.0, 2.5, 2.55))
for name, location, energy, color in (
    ("__TEMP_EAST_COPY_FILL__", (19.5, 0.2, 6.5), 1050, (0.25, 0.62, 1.0)),
    ("__TEMP_EAST_COPY_RIM__", (10.8, 4.7, 5.8), 800, (1.0, 0.30, 0.16)),
):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = 5.0
    data.color = color
    lamp = bpy.data.objects.new(name, data)
    temp.objects.link(lamp)
    lamp.location = location
    look_at(lamp, (15.0, 2.5, 2.4))
scene.camera = camera
scene.render.filepath = str(OUTPUT)
bpy.ops.render.render(write_still=True)
print(f"Rendered {OUTPUT}")
