import bpy
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03';out=root/'outputs/fat_zombie03_reduction'
views=[('front','idle',0,(0,8,1.7),(0,0,1.5),4.6),('side','idle',0,(8,0,1.7),(0,0,1.5),4.6),('run_top','running',9,(0,0,9),(0,0,0),5.2),('clap','attack',36,(4,7,4),(0,.3,1.4),4.6),('dead_side','dead',60,(7,0,2),(0,.7,.6),4.8),('dead_top','dead',60,(0,0,9),(0,.7,0),4.8)]
for tag,version in [('before','008'),('after','009')]:
 bpy.ops.wm.open_mainfile(filepath=str(pkg/f'source/animation/enm_normal_fat_zombie03_animation_v{version}.blend'))
 s=bpy.context.scene;rig=next(o for o in s.objects if o.type=='ARMATURE');m=next(o for o in s.objects if o.type=='MESH');keys=m.data.shape_keys;shape=bpy.data.actions['dead_contact']
 s.render.engine='BLENDER_EEVEE_NEXT';s.eevee.taa_render_samples=24;s.render.resolution_x=640;s.render.resolution_y=640;s.render.resolution_percentage=100;s.render.film_transparent=True
 if not s.world:s.world=bpy.data.worlds.new('QAWorld')
 s.world.color=(.3,.3,.3)
 for loc in [(3,4,6),(-4,-2,5)]:
  bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=650;bpy.context.object.data.size=5;bpy.context.object.rotation_euler=(Vector((0,0,1.5))-bpy.context.object.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO'
 for name,clip,frame,pos,target,size in views:
  rig.animation_data.action=bpy.data.actions[clip];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
  keys.animation_data.action=shape if clip=='dead' else None
  if clip=='dead':keys.animation_data.action_slot=shape.slots[0]
  else:keys.key_blocks['BellyGroundCompression'].value=0
  s.frame_set(frame);cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=size
  s.render.filepath=str(out/f'{tag}_{name}.png');bpy.ops.render.render(write_still=True)
print('COMPARISON_RENDER_OK',flush=True)
