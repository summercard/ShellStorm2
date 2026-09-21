import bpy, math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2');bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');root=bpy.data.objects['WeaponRoot'];arm.animation_data.action=bpy.data.actions['attack'];bpy.context.scene.frame_set(10);bpy.context.view_layer.update();D=Matrix.Translation(Vector((.16,.33,.87)))@Matrix.Rotation(math.pi/2,4,'X');pb=arm.pose.bones['L_Hand'];PW=arm.matrix_world@pb.matrix.copy()
for mode in range(3):
 r=root.copy();r.data=root.data.copy() if root.data else None;bpy.context.scene.collection.objects.link(r);r.name='TEST'+str(mode);r.parent=None;r.matrix_world=D.copy();bpy.context.view_layer.update();
 if mode==0:
  r.parent=arm;r.parent_type='BONE';r.parent_bone='L_Hand';r.matrix_world=D.copy()
 if mode==1:
  r.parent=arm;r.parent_type='BONE';r.parent_bone='L_Hand';r.matrix_parent_inverse=PW.inverted();r.matrix_world=D.copy()
 if mode==2:
  r.parent=arm;r.parent_type='BONE';r.parent_bone='L_Hand';r.matrix_parent_inverse=PW.inverted()@D;r.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update();print(mode,'D',tuple(round(x,3) for x in D.translation),'got',tuple(round(x,3) for x in r.matrix_world.translation),'mpi',tuple(round(x,3) for x in r.matrix_parent_inverse.translation))
