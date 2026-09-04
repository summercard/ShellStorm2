#!/usr/bin/env python3
"""Render temporary exterior/interior inspection views of the west door wall."""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
OUTPUT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")


def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"

temp = bpy.data.collections.new("__TEMP_WEST_DOOR_DOUBLE_SIDED_RENDER__")
scene.collection.children.link(temp)
camera_data = bpy.data.cameras.new("__TEMP_WEST_DOOR_CAMERA__")
camera = bpy.data.objects.new("__TEMP_WEST_DOOR_CAMERA__", camera_data)
temp.objects.link(camera)
camera_data.lens = 42

for name, location, energy, size, color in (
    ("__TEMP_WEST_FILL__", (-19.5, 0.2, 6.5), 1050, 5.0, (0.25, 0.62, 1.0)),
    ("__TEMP_EAST_FILL__", (-10.7, 4.7, 5.8), 800, 4.0, (1.0, 0.30, 0.16)),
):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    lamp = bpy.data.objects.new(name, data)
    temp.objects.link(lamp)
    lamp.location = location
    point_at(lamp, (-15.0, 2.5, 2.4))

scene.camera = camera
for label, position, target in (
    ("west_door_wall_exterior_double_sided.png", (-23.0, -0.2, 5.1), (-15.0, 2.5, 2.55)),
    ("west_door_wall_interior_double_sided.png", (-8.8, 5.9, 4.7), (-15.0, 2.5, 2.45)),
):
    camera.location = position
    point_at(camera, target)
    scene.render.filepath = str(OUTPUT / label)
    bpy.ops.render.render(write_still=True)

# This script deliberately does not save the temporary cameras/lights.
print("Rendered west door wall double-sided inspection views")
