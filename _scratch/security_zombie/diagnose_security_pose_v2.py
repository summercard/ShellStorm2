import bpy, json, math
from pathlib import Path
from mathutils import Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM=P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'
bpy.ops.wm.open_mainfile(filepath=str(ANIM)); sc=bpy.context.scene
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE'); act=bpy.data.actions.get('armed_idle'); arm.animation_data_create();arm.animation_data.action=act
for f in [1,25,48]:
 sc.frame_set(f);bpy.context.view_layer.update(); print('FRAME',f)
 for n in ['L_Hand','R_Hand']:
  pb=arm.pose.bones[n]; print(n,'head',tuple(round(x,4) for x in (arm.matrix_world@pb.head)),'tail',tuple(round(x,4) for x in (arm.matrix_world@pb.tail)))
 gun=bpy.data.objects.get('WeaponRoot'); print('gun root',tuple(round(x,4) for x in gun.matrix_world.translation), 'rot',tuple(round(x,4) for x in gun.matrix_world.to_euler()))
 for n in ['GripSocket','SupportHandSocket','MuzzleSocket']:
  o=bpy.data.objects.get(n); print(n,'world',tuple(round(x,4) for x in o.matrix_world.translation), 'hidden',o.hide_viewport)
 for o in bpy.data.objects:
  if o.type=='MESH' and o.name.startswith('wpn_security_short_shotgun_'):
   pts=[o.matrix_world@Vector(c) for c in o.bound_box];lo=Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts)));hi=Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts)));print('geo',o.name,'lo',tuple(round(x,3) for x in lo),'hi',tuple(round(x,3) for x in hi))
