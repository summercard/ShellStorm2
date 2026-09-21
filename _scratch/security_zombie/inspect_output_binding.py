import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
path=P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v003.blend'
bpy.ops.wm.open_mainfile(filepath=str(path))
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'); mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
lo=Vector((1e9,)*3);hi=Vector((-1e9,)*3)
for v in mesh.data.vertices:
 p=mesh.matrix_world@v.co;lo=Vector((min(lo.x,p.x),min(lo.y,p.y),min(lo.z,p.z)));hi=Vector((max(hi.x,p.x),max(hi.y,p.y),max(hi.z,p.z)))
rows=[]
for n in ['Root','Hip','Pelvis','Spine02','NeckTwist01','NeckTwist02','Head','L_Clavicle','L_Upperarm','L_Forearm','L_Hand','R_Clavicle','R_Upperarm','R_Forearm','R_Hand','L_Thigh','L_Calf','L_Foot','R_Thigh','R_Calf','R_Foot']:
 b=arm.data.bones[n]; rows.append({'name':n,'head_local':list(b.head_local),'tail_local':list(b.tail_local),'head_arm':list(arm.matrix_world@b.head_local),'tail_arm':list(arm.matrix_world@b.tail_local),'parent':b.parent.name if b.parent else None})
print(json.dumps({'mesh_lo':list(lo),'mesh_hi':list(hi),'arm_matrix':[list(x) for x in arm.matrix_world],'mesh_matrix':[list(x) for x in mesh.matrix_world],'parent':mesh.parent.name if mesh.parent else None,'modifiers':[(m.type,m.object.name if m.object else None) for m in mesh.modifiers],'rows':rows},ensure_ascii=False,indent=2))
