import bpy,json
from pathlib import Path
p=Path(__file__).parent;pkg=p.parents[1]/'assets/art/enemies/normal_enemy_3d/fat_zombie03'
bpy.ops.wm.open_mainfile(filepath=str(pkg/'source/model/enm_normal_fat_zombie03_model_v002.blend'))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
d={b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'length':b.length} for b in a.data.bones if b.name in ['Hip','L_Thigh','L_Calf','L_Foot','R_Thigh','R_Calf','R_Foot','L_Hand','R_Hand']}
(p/'walk_contract.json').write_text(json.dumps(d,indent=2),encoding='utf-8');print(json.dumps(d))
