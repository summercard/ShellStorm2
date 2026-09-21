import bpy
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/model/enm_security_zombie_model_v001.blend'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');M=arm.matrix_world.copy();arm.animation_data_clear();arm.data.pose_position='POSE'
for pb in arm.pose.bones: pb.matrix_basis.identity()
bpy.context.view_layer.update()
def wb(name):
 b=arm.data.bones[name];return M@b.matrix_local
for side,target,pole in [('L',Vector((-.02,.10,.88)),Vector((-.40,-.25,-.45))),('R',Vector((-.02,.34,.88)),Vector((.40,-.25,-.45)))]:
 ns=[side+'_Upperarm',side+'_Forearm',side+'_Hand']; S=M@arm.data.bones[ns[0]].head_local; l1=arm.data.bones[ns[0]].length;l2=arm.data.bones[ns[1]].length;lh=arm.data.bones[ns[2]].length
 fore=target-Vector((0,1,0))*lh;v=fore-S;d=min(max(v.length,abs(l1-l2)+1e-4),l1+l2-1e-4);u=v.normalized();pv=Vector(pole)-u*Vector(pole).dot(u);pv.normalize();along=(l1*l1-l2*l2+d*d)/(2*d);h=max(0,l1*l1-along*along)**.5;E=S+u*along+pv*h
 for name,head,tail in [(ns[0],S,E),(ns[1],E,fore),(ns[2],fore,target)]:
  y=(tail-head).normalized();rest=M@arm.data.bones[name].matrix_local;x=(rest@Vector((1,0,0))-rest@Vector((0,0,0)));x=x-y*x.dot(y);x.normalize();z=x.cross(y).normalized();x=y.cross(z).normalized();W=Matrix(((x.x,x.y,x.z,0),(y.x,y.y,y.z,0),(z.x,z.y,z.z,0),(0,0,0,1)));W.translation=head
  arm.pose.bones[name].matrix=M.inverted()@W
  bpy.context.view_layer.update()
 print(side,'want',target)
 for n in ns:
  pb=arm.pose.bones[n]; print(n,'head',tuple(round(x,3) for x in (M@pb.head)),'tail',tuple(round(x,3) for x in (M@pb.tail)))
