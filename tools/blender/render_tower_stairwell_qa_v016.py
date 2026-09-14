import bpy
from mathutils import Vector
from pathlib import Path

blend=Path(r'I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments\tower_descent_3d\source\stairwell_hq_v016\env_tower_stairwell_hq_v016.blend')
out=blend.parent
bpy.ops.wm.open_mainfile(filepath=str(blend))
scene=bpy.context.scene
for o in bpy.data.objects:
    if o.name.startswith('WallPanel_') and ('-2.2' in o.name): o.hide_render=True
cam=bpy.data.objects.get('Stairwell_Reference_Camera'); cam.location=(28,-29,27); cam.rotation_euler=(Vector((7.5,12,-3.8))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.lens=52; scene.camera=cam
scene.world.color=(0.001,0.003,0.008)
scene.view_settings.look='AgX - Medium High Contrast'
scene.render.resolution_x=1000; scene.render.resolution_y=1100; scene.render.resolution_percentage=100; scene.render.filepath=str(out/'stairwell_qa_cutaway.png')
bpy.ops.render.render(write_still=True)
scene.render.resolution_x=900; scene.render.resolution_y=700; scene.render.filepath=str(out/'stairwell_qa_overview.png'); cam.location=(31,-34,18); cam.rotation_euler=(Vector((7.5,12,-4))-cam.location).to_track_quat('-Z','Y').to_euler(); bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
print('QA_RENDER_OK',out)
