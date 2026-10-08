import bpy, json
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2')
blend=P/'assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v004.blend'
bpy.ops.wm.open_mainfile(filepath=str(blend))
def stats(o):
    return {'name':o.name,'type':o.type,'parent':o.parent.name if o.parent else None,'loc':list(o.location),'scale':list(o.scale),'dims':list(o.dimensions),'verts':len(o.data.vertices) if o.type=='MESH' else None,'faces':len(o.data.polygons) if o.type=='MESH' else None,'props':{k:str(v) for k,v in o.items()}}
out={}
for c in bpy.data.collections:
    if 'radio' in c.name.lower() or '制作组件' in c.name or '游戏输出' in c.name or '状态灯' in c.name:
        out[c.name]=[stats(o) for o in c.objects]
out['root']=stats(bpy.data.objects.get('ItemRoot'))
out['all_objects']=[stats(o) for o in bpy.data.objects if o.name in ['ItemRoot','Visual','Antenna','StatusLight'] or o.get('runtime_interface_name')]
print(json.dumps(out,ensure_ascii=False,indent=2))
