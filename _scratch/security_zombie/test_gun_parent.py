import bpy, math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2');ANIM=P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'
bpy.ops.wm.open_mainfile(filepath=str(ANIM));sc=bpy.context.scene;arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');arm.animation_data.action=bpy.data.actions['attack'];sc.frame_set(10);bpy.context.view_layer.update();root=bpy.data.objects['WeaponRoot'];support=bpy.data.objects['SupportHandSocket'];grip=bpy.data.objects['GripSocket'];print('before',root.matrix_world.translation[:],support.matrix_world.translation[:])
# unparent/reparent with explicit parent inverse
root.parent=None;root.parent_type='OBJECT';root.matrix_parent_inverse=Matrix.Identity(4);root.matrix_world=Matrix.Translation(Vector((0.1956,0.3095,0.8491)))@Matrix.Rotation(math.pi/2,4,'X');bpy.context.view_layer.update();print('object',root.matrix_world.translation[:],grip.matrix_world.translation[:],support.matrix_world.translation[:])
# bone parent set desired root world
D=root.matrix_world.copy();root.parent=arm;root.parent_type='BONE';root.parent_bone='L_Hand';bpy.context.view_layer.update();pw=arm.matrix_world@arm.pose.bones['L_Hand'].matrix;root.matrix_parent_inverse=pw.inverted()@D;root.matrix_basis=Matrix.Identity(4);bpy.context.view_layer.update();print('bone',root.matrix_world.translation[:],grip.matrix_world.translation[:],support.matrix_world.translation[:])
