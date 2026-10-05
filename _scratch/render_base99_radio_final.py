import bpy
from pathlib import Path
from mathutils import Vector

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
BLEND = PROJECT / "assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v001.blend"
OUT = PROJECT / "outputs/base99_radio_v001"
bpy.ops.wm.open_mainfile(filepath=str(BLEND))
cam = bpy.data.objects.get("收音机近景相机")

def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

def render(name, loc, target):
    cam.location = loc
    look_at(cam, target)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(OUT / name)
    bpy.ops.render.render(write_still=True)

render('base99_radio_v001_closeup.png', (0.49, -0.68, 0.38), (0, 0, 0.20))
render('base99_radio_v001_threequarter.png', (0.58, -0.76, 0.32), (0, 0, 0.19))
render('base99_radio_v001_top.png', (0.34, -0.49, 0.70), (0, 0, 0.18))
