import bpy,json
from pathlib import Path
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/model/enm_security_zombie_model_v001.blend'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.data.objects if o.type=='MESH')
rows=[]
for side in ('L','R'):
 for finger in ('Thumb','Index','Middle','Ring','Pinky'):
  for i in range(1,5):
   n=f'{side}_{finger}{i}';g=mesh.vertex_groups.get(n)
   if g is None: rows.append({'group':n,'exists':False,'verts':0,'weight_sum':0});continue
   hits=0;ws=0
   for v in mesh.data.vertices:
    for x in v.groups:
     if x.group==g.index and x.weight>0.001:hits+=1;ws+=x.weight
   rows.append({'group':n,'exists':True,'verts':hits,'weight_sum':round(ws,4)})
print(json.dumps({'mesh':mesh.name,'groups':[g.name for g in mesh.vertex_groups],'finger_rows':rows},ensure_ascii=False,indent=2))
