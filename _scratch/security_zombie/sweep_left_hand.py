import bpy, math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2');bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/model/enm_security_zombie_model_v001.blend'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');M=arm.matrix_world.copy();TR={b.name:b.matrix_local.copy() for b in arm.data.bones}
def reset():
 for pb in arm.pose.bones: pb.matrix_basis.identity()
 bpy.context.view_layer.update()
def solve(x):
 reset();side='L';ns=['L_Upperarm','L_Forearm','L_Hand'];target=Vector((x,.33,.88));pole=Vector((-.4,-.25,-.45));S=M@arm.data.bones[ns[0]].head_local;l1=arm.data.bones[ns[0]].length;l2=arm.data.bones[ns[1]].length;lh=arm.data.bones[ns[2]].length;fore=target-Vector((0,1,0))*lh;v=fore-S;d=min(max(v.length,abs(l1-l2)+1e-4),l1+l2-1e-4);u=v.normalized();pv=pole-u*pole.dot(u);pv.normalize();al=(l1*l1-l2*l2+d*d)/(2*d);h=max(0,l1*l1-al*al)**.5;E=S+u*al+pv*h
 for name,head,tail in [(ns[0],S,E),(ns[1],E,fore),(ns[2],fore,target)]:
  y=(tail-head).normalized();rest=M@arm.data.bones[name].matrix_local;xx=rest@Vector((1,0,0))-rest@Vector((0,0,0));xx=xx-y*xx.dot(y);xx.normalize();z=xx.cross(y).normalized();xx=y.cross(z).normalized();W=Matrix(((xx.x,xx.y,xx.z,0),(y.x,y.y,y.z,0),(z.x,z.y,z.z,0),(0,0,0,1)));W.translation=head; desired=M.inverted()@W;pb=arm.pose.bones[name];p=pb.parent
  if p is None:basis=pb.bone.matrix_local.inverted()@desired
  else:rel=p.bone.matrix_local.inverted()@pb.bone.matrix_local;basis=rel.inverted()@p.matrix.inverted()@desired
  pb.matrix_basis=basis;bpy.context.view_layer.update()
pb=arm.pose.bones['L_Hand'];tail=lambda:tuple(round(c,3) for c in M@pb.tail)
for x in [-.45,-.35,-.25,-.15,-.05,.05,.15]:
 solve(x);print('wantx',x,'tail',tail())
