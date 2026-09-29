"""Render both authored ladder states for quick visual QA (not a runtime asset)."""
from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
assert Path(bpy.data.filepath).name == "prp_base99_telescopic_ladder_source_v002.blend"
out = root / "_scratch/base99_telescopic_ladder_preview"
out.mkdir(parents=True, exist_ok=True)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.render.resolution_x = 640
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.color = (0.08, 0.08, 0.08)

camera_data = bpy.data.cameras.new("QA_Camera")
camera = bpy.data.objects.new("QA_Camera", camera_data)
scene.collection.objects.link(camera)
camera.location = (5.4, -8.5, 4.2)
direction = Vector((0.0, 0.0, 3.0)) - camera.location
camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
camera_data.type = "ORTHO"
camera_data.ortho_scale = 7.5
scene.camera = camera

for name, loc, power in (("QA_Key", (3, -4, 7), 1100), ("QA_Fill", (-4, 2, 5), 650)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = 4.0
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = loc
    light.rotation_euler = (Vector((0, 0, 3)) - light.location).to_track_quat("-Z", "Y").to_euler()

lower = bpy.data.objects["LowerVisual_滑动下段"]
lower.animation_data_clear()
for label, position in (("retracted", 2.5), ("deployed", 0.0)):
    lower.location.z = position
    scene.render.filepath = str(out / f"base99_telescopic_ladder_{label}.png")
    bpy.ops.render.render(write_still=True)
    print("LADDER_PREVIEW", label, scene.render.filepath)
