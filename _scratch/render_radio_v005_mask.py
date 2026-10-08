import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2');O=P/'outputs/base99_radio_v005'; V4=P/'assets/art/props/base_world_3d/source/base99_radio/export/v004/prp_base99_radio_optimized_v004.blend'; V5=P/'assets/art/props/base_world_3d/source/base99_radio/export/v005/prp_base99_radio_optimized_v005.blend'
def look(cam,target):cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
def run(blend,tag,state):
 bpy.ops.wm.open_mainfile(filepath=str(blend)); scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
 cam=bpy.data.objects.get('收音机近景相机') or bpy.data.objects.get('Camera');cam.data.lens=52;cam.location=(0.88,-1.22,1.15);look(cam,(0,0,0.36));scene.camera=cam
 for o in scene.objects:
  if o.type=='MESH':o.hide_render=True
 status=bpy.data.objects.get('StatusLight') or bpy.data.objects.get('StatusLight_UI灯光_柔和自发光');status.hide_render=False
 for m in status.data.materials:
  if m and m.use_nodes:
   bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
   if bs:bs.inputs['Emission Strength'].default_value=1.5;bs.inputs['Emission Color'].default_value=(0.65,0.02,0.01,1) if state=='off' else (0.02,0.75,0.08,1);bs.inputs['Base Color'].default_value=(0.65,0.02,0.01,1) if state=='off' else (0.02,0.75,0.08,1)
 p=O/f'{tag}_{state}_mask.png';scene.render.filepath=str(p);bpy.ops.render.render(write_still=True)
for b,t in [(V4,'before_v004'),(V5,'v005')]:
 for s in ['off','green']:run(b,t,s)
print('MASK_RENDER_OK')
