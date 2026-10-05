import bpy,math
from mathutils import Quaternion
from pathlib import Path
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
bpy.ops.wm.save_as_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/_scratch/boss027_before_polish.blend',copy=True)
a=bpy.data.actions['stun_enter'];r.animation_data.action=a;cache={}
for step in range(73,121):
 f=1+step/4;s.frame_set(int(f),subframe=f-int(f));cache[step]={p.name:p.rotation_quaternion.copy() for p in r.pose.bones if p.name.startswith(('arm_','hand_ctrl'))}
for step,qs in cache.items():
 t=step/4;f=1+t;env=math.sin(math.pi*(t-18)/12);wave=env*math.sin(math.tau*(t-18)/12)
 s.frame_set(int(f),subframe=f-int(f))
 for name,q in qs.items():
  p=r.pose.bones[name];side=1 if name.endswith('.L') else -1
  angle=math.radians(9 if name.startswith('hand_ctrl') else 2)*wave*side
  p.rotation_quaternion=q@Quaternion((0,1,0),angle);p.keyframe_insert('rotation_quaternion',frame=f,group=name)
for a in bpy.data.actions:
 if a.name.startswith('special_'):
  for fc in a.fcurves:
   if fc.data_path=='["expression_state"]':
    for k in fc.keyframe_points:k.co.y=2
# Narrow clean electric filaments, continuous blue body and advancing cyan pulses.
for name,col,strength in [('FX_Electric_Blue',(.025,.23,.8,1),1.4),('FX_Electric_Core',(.24,.72,1,1),1.8)]:
 n=next(n for n in bpy.data.materials[name].node_tree.nodes if n.type=='EMISSION');n.inputs[0].default_value=col;n.inputs[1].default_value=strength
for o in bpy.data.collections['BOSS002_DIZZY_ELECTRIC_PREVIEW'].objects:
 if not o.name.startswith('Cable current'):continue
 j=int(o.parent_bone[-2:]);lane=int(o.name.rsplit('.',1)[-1]);length=r.data.bones[o.parent_bone].length
 o.data.bevel_depth=.017 if lane==0 else .007
 for i,p in enumerate(o.data.splines[0].points):p.co=((.037 if i%2 else -.017)*(1 if lane==0 else -1),length*i/5,.047+lane*.008,1)
 for fc in o.animation_data.drivers:
  if fc.data_path in ['hide_render','hide_viewport']:fc.driver.expression='mode != 2 or active < .1'+(' or ((frame+%d)%%8)>2'%j if lane else '')+(' or True' if j<4 else '')
# Compact solid yellow impact shape, present for exactly one frame.
fx=bpy.data.collections['BOSS002_DIZZY_ELECTRIC_PREVIEW'];verts=[]
for i in range(16):
 theta=math.tau*i/16;radius=(.64 if i%4==0 else .43) if i%2==0 else .16;verts.append((radius*math.cos(theta),0,radius*math.sin(theta)))
me=bpy.data.meshes.new('Hit flash shape');me.from_pydata(verts,[],[tuple(range(16))]);me.materials.append(bpy.data.materials['FX_Dizzy_Gold']);o=bpy.data.objects.new('Dizzy hit flash',me);fx.objects.link(o);o.location=(1.22,1.35,.95);c=o.constraints.new('COPY_LOCATION');c.target=r;c.subtarget='rear_axle';c.use_offset=True;o['preview_only']=True;o['export']=False;o.visible_shadow=False
for prop in ['hide_render','hide_viewport']:
 d=o.driver_add(prop).driver;v=d.variables.new();v.name='hit';v.targets[0].id=r;v.targets[0].data_path='["stun_hit_flash"]';d.expression='hit < .5'
for name in ['idle','move','melee_keyboard','melee_cable','heavy_spin_slam','special_prepare','special_insert','special_channel','special_recover','hurt','stun_enter','stun_loop','stun_exit','turn_left','turn_right']:
 r.animation_data.action=bpy.data.actions[name]
 keys=[(1,0),(4,1),(5,0),(43,0)] if name=='stun_enter' else [(1,0)]
 for f,v in keys:r['stun_hit_flash']=v;r.keyframe_insert(data_path='["stun_hit_flash"]',frame=f)
 for fc in r.animation_data.action.fcurves:
  if fc.data_path=='["stun_hit_flash"]':
   for k in fc.keyframe_points:k.interpolation='CONSTANT'
r.animation_data.action=bpy.data.actions['stun_enter'];s.frame_set(1);s.frame_end=43;bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v027.blend'));print('polish saved')
