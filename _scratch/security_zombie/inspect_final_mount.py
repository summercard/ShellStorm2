import bpy, json
from pathlib import Path
from mathutils import Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'))
sc=bpy.context.scene;arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');act=bpy.data.actions['attack'];arm.animation_data_create();arm.animation_data.action=act;sc.frame_set(10);bpy.context.view_layer.update()
root=bpy.data.objects['WeaponRoot']; print('ROOT',tuple(round(x,4) for x in root.matrix_world.translation), [round(x,4) for x in root.matrix_world.to_euler()])
for n in ['GripSocket','SupportHandSocket','MuzzleSocket']:
 o=bpy.data.objects.get(n);o.hide_viewport=False;o.hide_render=False;bpy.context.view_layer.update();print(n,'mw',tuple(round(x,4) for x in o.matrix_world.translation),'loc',tuple(round(x,4) for x in o.location),'parent',o.parent.name if o.parent else None,'pmat',o.matrix_parent_inverse.translation[:])
for n in ['L_Hand','R_Hand']:
 pb=arm.pose.bones[n];print(n,'tail',tuple(round(x,4) for x in arm.matrix_world@pb.tail),'head',tuple(round(x,4) for x in arm.matrix_world@pb.head))
print('children root',[(o.name,o.type,tuple(round(x,3) for x in o.location)) for o in root.children])
