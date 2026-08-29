"""Render a focused cutaway QA preview of the normalized v009 stairwell."""

from pathlib import Path

import bpy
from mathutils import Vector


SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_PATH = (
    SOURCE_DIR.parents[4]
    / "outputs/verification/tower_source/env_tower_stairwell_v009_5m_cutaway.png"
)
OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
ROOT_NAME = "Stair_Generic_Rotatable_ROOT"


def descendants(root):
    result = {root}
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        result.add(obj)
        stack.extend(obj.children)
    return result


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


root = bpy.data.objects.get(ROOT_NAME)
if root is None:
    raise RuntimeError(f"Missing {ROOT_NAME}")
visible = descendants(root)
for obj in bpy.data.objects:
    obj.hide_render = obj not in visible

# Open the near two sides for an unambiguous inspection of both landings.
for suffix in ("EnclosureWall_DoorSide", "EnclosureWall_Outer"):
    for obj in visible:
        if obj.name.endswith(suffix):
            obj.hide_render = True

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1200
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = (0.012, 0.018, 0.028)

camera_data = bpy.data.cameras.new("StairV009QACameraData")
camera = bpy.data.objects.new("StairV009QACamera", camera_data)
scene.collection.objects.link(camera)
camera.location = (70.0, -37.0, 7.0)
camera.data.lens = 52
look_at(camera, (40.0, 11.0, -13.5))
scene.camera = camera

sun_data = bpy.data.lights.new("StairV009QASunData", "SUN")
sun_data.energy = 2.0
sun_data.color = (0.72, 0.84, 1.0)
sun = bpy.data.objects.new("StairV009QASun", sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (0.55, -0.45, -0.7)

area_data = bpy.data.lights.new("StairV009QAAreaData", "AREA")
area_data.energy = 1400.0
area_data.shape = "DISK"
area_data.size = 18.0
area_data.color = (0.25, 0.8, 1.0)
area = bpy.data.objects.new("StairV009QAArea", area_data)
scene.collection.objects.link(area)
area.location = (40.0, 8.0, 4.0)
look_at(area, (40.0, 12.0, -14.0))

camera.hide_render = False
sun.hide_render = False
area.hide_render = False
scene.render.filepath = str(OUTPUT_PATH)
bpy.ops.render.render(write_still=True)
print(f"STAIRWELL_V009_RENDER_OK output={OUTPUT_PATH}")
