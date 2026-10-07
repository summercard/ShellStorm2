import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2')
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v003.blend'))
def mat(o):
 return o.matrix_basis if not o.parent else mat(o.parent)@o.matrix_parent_inverse@o.matrix_basis
r=[]
for o in bpy.data.objects:
 if o.type!='MESH':continue
 pts=[mat(o)@v.co for v in o.data.vertices]
 r.append({'name':o.name,'collections':[c.name for c in o.users_collection],'parent':o.parent.name if o.parent else None,'faces':len(o.data.polygons),'min':[min(v[i] for v in pts) for i in range(3)],'max':[max(v[i] for v in pts) for i in range(3)],'materials':[m.name for m in o.data.materials],'props':dict(o.items())})
print(json.dumps(r,ensure_ascii=False,indent=2))
(P/'outputs/base99_radio_v004/current_blend_objects.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
