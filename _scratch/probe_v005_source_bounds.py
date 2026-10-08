import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v005.blend'))
for coll_name in ['01_制作组件_已统一材质','02_游戏输出_独立资产包_v005']:
 c=bpy.data.collections.get(coll_name)
 if not c: continue
 out=[]
 for o in c.objects:
  if o.type!='MESH': continue
  pts=[o.matrix_world@v.co for v in o.data.vertices]
  mn=Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts))); mx=Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts)))
  out.append({'name':o.name,'min':list(mn),'max':list(mx),'size':list(mx-mn),'faces':len(o.data.polygons)})
 print(coll_name,json.dumps(out,ensure_ascii=False))
