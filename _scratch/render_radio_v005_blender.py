import bpy, json, math
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2');O=P/'outputs/base99_radio_v005'; PALETTE=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
V4=P/'assets/art/props/base_world_3d/source/base99_radio/export/v004/prp_base99_radio_optimized_v004.blend'; V5=P/'assets/art/props/base_world_3d/source/base99_radio/export/v005/prp_base99_radio_optimized_v005.blend'
def look(cam,target):cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
def render(blend,tag,state):
 bpy.ops.wm.open_mainfile(filepath=str(blend)); scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE'; scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
 cam=bpy.data.objects.get('收音机近景相机') or bpy.data.objects.get('Camera')
 if cam is None: cam=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',cam);bpy.context.collection.objects.link(cam)
 cam.data.lens=52;cam.data.type='PERSP';cam.location=(0.88,-1.22,1.15);look(cam,(0,0,0.36));scene.camera=cam
 world=scene.world or bpy.data.worlds.new('World');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(0.018,0.028,0.05,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=0.35
 for o in list(scene.objects):
  if o.type=='LIGHT':bpy.data.objects.remove(o,do_unlink=True)
 ld=bpy.data.lights.new('Key','AREA');lo=bpy.data.objects.new('Key',ld);bpy.context.collection.objects.link(lo);lo.location=(1.2,-1.6,2.4);ld.energy=420;ld.shape='DISK';ld.size=3
 status=bpy.data.objects.get('StatusLight') or bpy.data.objects.get('StatusLight_UI灯光_柔和自发光')
 if status:
  for p in status.data.polygons:
   pass
  for m in status.data.materials:
   if m and m.use_nodes:
    bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if bs: bs.inputs['Emission Strength'].default_value=1.5; bs.inputs['Emission Color'].default_value=(0.65,0.02,0.01,1) if state=='off' else (0.02,0.75,0.08,1); bs.inputs['Base Color'].default_value=(0.65,0.02,0.01,1) if state=='off' else (0.02,0.75,0.08,1)
 out=O/f'{tag}_{state}.png';scene.render.filepath=str(out);bpy.ops.render.render(write_still=True);return out
for blend,tag in [(V4,'before_v004_closeup'),(V5,'v005_closeup')]:
 for state in ['off','green']:render(blend,tag,state)
print('BLENDER_NATIVE_RENDER_OK')
