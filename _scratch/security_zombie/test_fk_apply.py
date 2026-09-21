import bpy, math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/model/enm_security_zombie_model_v001.blend'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE'); M=arm.matrix_world.copy(); arm.data.pose_position='POSE'
TR={b.name:b.matrix_local.copy() for b in arm.data.bones}; TP={b.name:(b.parent.name if b.parent else None) for b in arm.data.bones}; order=['L_Upperarm','L_Forearm','L_Hand']
def apply_chain(side,target,pole):
 ns=[side+'_Upperarm',side+'_Forearm',side+'_Hand']; S=M@arm.data.bones[ns[0]].head_local; l1=arm.data.bones[ns[0]].length;l2=arm.data.bones[ns[1]].length;lh=arm.data.bones[ns[2]].length; target=Vector(target); fore=target-Vector((0,1,0))*lh;v=fore-S;d=min(max(v.length,abs(l1-l2)+1e-4),l1+l2-1e-4);u=v.normalized();pv=Vector(pole)-u*Vector(pole).dot(u);pv.normalize();along=(l1*l1-l2*l2+d*d)/(2*d);h=max(0,l1*l1-along*along)**.5;E=S+u*along+pv*h
 desired=[(S,E),(E,fore),(fore,target)]; worlds={}
 for name,(head,tail) in zip(ns,desired):
  y=(tail-head).normalized(); rest=M@arm.data.bones[name].matrix_local; x=rest@Vector((1,0,0))-rest@Vector((0,0,0));x=x-y*x.dot(y);x.normalize();z=x.cross(y).normalized();x=y.cross(z).normalized();W=Matrix(((x.x,x.y,x.z,0),(y.x,y.y,y.z,0),(z.x,z.y,z.z,0),(0,0,0,1)));W.translation=head; worlds[name]=M.inverted()@W
 for name in ns:
  p=TP[name]
  if p is None: basis=TR[name].inverted()@worlds[name]
  else:
   rel=TR[p].inverted()@TR[name]; basis=rel.inverted()@worlds[p].inverted()@worlds[name]
  pb=arm.pose.bones[name];pb.location=basis.to_translation();pb.rotation_mode='QUATERNION';pb.rotation_quaternion=basis.to_quaternion()
  bpy.context.view_layer.update()
 print(side,'target',target)
 for n in ns:
  pb=arm.pose.bones[n];print(n,'h',tuple(round(x,3) for x in M@pb.head),'t',tuple(round(x,3) for x in M@pb.tail))
apply_chain('L',(-.04,.33,.88),(-.4,-.25,-.45));apply_chain('R',(-.04,.57,.88),(.4,-.25,-.45))
