import bpy,json
from pathlib import Path
out=Path('I:/工作项目/shellstrom2/ShellStorm2/_scratch/xiaojunzhu_intake')
m=next(o for o in bpy.context.scene.objects if o.type=='MESH'); a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
uv=m.data.uv_layers.active
D={'mesh':m.name,'matrix': [list(r) for r in m.matrix_world], 'bones':[{'name':b.name,'head':list(b.head_local),'tail':list(b.tail_local),'parent':b.parent.name if b.parent else None} for b in a.data.bones], 'vertices':[list(v.co) for v in m.data.vertices], 'faces':[list(p.vertices) for p in m.data.polygons], 'uv':[[list(uv.data[i].uv) for i in p.loop_indices] for p in m.data.polygons], 'groups':[g.name for g in m.vertex_groups], 'weights':[[[g.group,g.weight] for g in v.groups] for v in m.data.vertices], 'images':[{'name':i.name,'path':i.filepath,'size':list(i.size)} for i in bpy.data.images]}
(out/'uv_rig_source.json').write_text(json.dumps(D),encoding='utf-8')
print(json.dumps({k:v for k,v in D.items() if k not in ['vertices','faces','uv','weights']},indent=2))
