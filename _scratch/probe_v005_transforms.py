import bpy,json
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2'); bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v005.blend'))
root=bpy.data.objects['ItemRoot']
print('ROOT',list(root.location),list(root.scale),list(root.matrix_world.translation))
for n in ['Visual','Antenna','StatusLight','StatusLight_UI灯光_柔和自发光']:
 o=bpy.data.objects.get(n)
 if not o: continue
 pts=[o.matrix_world@v.co for v in o.data.vertices]
 mn=Vector((min(p[i] for p in pts) for i in range(3))); mx=Vector((max(p[i] for p in pts) for i in range(3)))
 print(n,'parent',o.parent.name if o.parent else None,'loc',list(o.location),'matrix_t',list(o.matrix_world.translation),'bounds',list(mn),list(mx))
