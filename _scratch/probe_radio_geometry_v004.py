import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2'); bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v004.blend'))
sc=bpy.data.collections['01_制作组件_已统一材质']
res=[]
for o in sc.objects:
 if o.type!='MESH': continue
 pts=[o.matrix_world@v.co for v in o.data.vertices]
 mn=Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts)));mx=Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts)))
 if any(k in o.name for k in ['主体','底座','提手','状态','天线']): res.append({'name':o.name,'min':list(mn),'max':list(mx),'faces':len(o.data.polygons)})
print(json.dumps(res,ensure_ascii=False,indent=2))
