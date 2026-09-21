import bpy, json
from pathlib import Path
from mathutils import Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');arm.animation_data.action=bpy.data.actions['armed_idle'];bpy.context.scene.frame_set(25);bpy.context.view_layer.update()
for side in ('L','R'):
 print('SIDE',side)
 for finger in ('Thumb','Index','Middle','Pinky','Ring'):
  for i in (1,2,3,4):
   n=f'{side}_{finger}{i}'; b=arm.data.bones.get(n)
   if not b: continue
   pb=arm.pose.bones[n]; h=arm.matrix_world@pb.head;t=arm.matrix_world@pb.tail; d=(t-h).normalized();
   print(n,'parent',b.parent.name if b.parent else None,'head',tuple(round(x,3) for x in h),'tail',tuple(round(x,3) for x in t),'dir',tuple(round(x,3) for x in d),'len',round((t-h).length,3),'localrot',tuple(round(x,3) for x in pb.rotation_quaternion))
