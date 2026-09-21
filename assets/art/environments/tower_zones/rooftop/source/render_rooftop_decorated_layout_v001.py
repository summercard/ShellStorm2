"""Render readable overview and close-up images for the 100F decorated layout."""
import bpy
from pathlib import Path
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[6]
OUT = PROJECT / "outputs"
OUT.mkdir(exist_ok=True)
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

for image in bpy.data.images:
    if image.name.startswith("设施低亮多巴胺色盘"):
        image.filepath = str(PALETTE)
        image.reload()

scene = bpy.context.scene
camera = scene.camera
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1800
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 70
scene.render.image_settings.file_format = "PNG"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.65

def look_at(location, target, ortho_scale, output):
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = ortho_scale
    scene.render.filepath = str(OUT / output)
    bpy.ops.render.render(write_still=True)
    print("ROOFTOP_DECOR_RENDER_OK", scene.render.filepath, flush=True)

# 追踪点用 Blender 平面坐标：Godot 中心 (0, 5) ⇒ Blender (0, -5)（by = -gz）。
look_at((72, -92, 72), (0, -5, 3), 112, "rooftop_100f_decorated_layout_v001_overview.png")
look_at((35, -44, 30), (0, -5, 4), 48, "rooftop_100f_decorated_layout_v001_closeup.png")
# 天台自身中心仍是 Godot (-5, 5) ⇒ Blender (-5, -5)。
look_at((-5, -5, 110), (-5, -5, 0), 102, "rooftop_100f_decorated_layout_v001_top.png")
