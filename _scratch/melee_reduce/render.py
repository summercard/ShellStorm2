import bpy,json
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/melee_chaser';out=root/'outputs/melee_zombie_reduction';t=json.loads((pkg/'runtime/character_transfer_ledger.json').read_text(encoding='utf-8'))
for tag,path in [('before',t['animation']),('after',str(pkg/'source/animation/enm_melee_fungboar01_animation_v004.blend'))]:
 bpy.ops.wm.open_mainfile(filepath=path);s=bpy.context.scene;rig=next(o for o in s.objects if o.type=='ARMATURE')
 s.render.engine='BLENDER_EEVEE_NEXT';s.eevee.taa_render_samples=32;s.render.resolution_x=600;s.render.resolution_y=600;s.render.resolution_percentage=100;s.render.film_transparent=True
 if not s.world:s.world=bpy.data.worlds.new('QA')
 s.world.color=(.3,.3,.3)
 for loc in [(3,4,5),(-3,-2,3)]:
  bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=450;bpy.context.object.data.size=4;bpy.context.object.rotation_euler=(Vector((0,0,1))-bpy.context.object.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO'
 for name,clip,frame,pos,target,size in [('front','idle',1,(0,5,1),(0,0,.9),2.6),('side','idle',1,(5,0,1),(0,0,.9),2.6),('run','running',7,(3,5,3),(0,0,.9),2.7),('attack','attack',25,(3,5,3),(0,0,.9),2.7),('dead','dead',65,(3,4,3),(0,-.4,.4),3.2),('hands','idle',1,(0,5,1.5),(0,0,1),2.0)]:
  act=bpy.data.actions[next(c['action'] for c in t['clips'] if c['id']==clip) if tag=='before' else clip];rig.animation_data.action=act
  if act.slots:rig.animation_data.action_slot=act.slots[0]
  s.frame_set(frame);cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=size;s.render.filepath=str(out/f'{tag}_{name}.png');bpy.ops.render.render(write_still=True)
print('MELEE_RENDER_OK')
