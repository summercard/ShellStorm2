import bpy,json
from pathlib import Path
from mathutils import Vector
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
for name,n in {'stun_enter':42,'stun_loop':48,'stun_exit':30}.items():
 r.animation_data.action=bpy.data.actions[name];cache=[]
 for step in range(n*4+1):
  f=1+step/4;s.frame_set(int(f),subframe=f-int(f));u=max(0,min(1,(f-25)/10)) if name=='stun_enter' else 1 if name=='stun_loop' else 1-max(0,min(1,(f-8)/17));w=u*u*(3-2*u);cache.append((f,w,[r.pose.bones['cable_%02d'%j].matrix.copy() for j in range(1,17)]))
 for f,w,mats in cache:
  s.frame_set(int(f),subframe=f-int(f))
  for j,m in enumerate(mats,1):
   m.translation.z+=.09*w;p=r.pose.bones['cable_%02d'%j];p.matrix=m;bpy.context.view_layer.update()
   for attr in ['location','rotation_quaternion','scale']:p.keyframe_insert(attr,frame=f,group=p.name)
s.frame_set(1);r.animation_data.action=bpy.data.actions['stun_loop'];s.frame_end=49;bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v029.blend'));print('Cable floor clearance corrected')
