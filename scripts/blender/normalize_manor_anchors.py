import bpy,json
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');S=R/'art_source/environments/tower_zones/expedition/source/common_components/v017'
p=S/'component_catalog.json';doc=json.loads(p.read_text(encoding='utf-8'))
sc=bpy.data.scenes['组件母版画廊_独立可编辑'];bpy.context.window_manager.windows[0].scene=sc
for e in doc['components']:
 col=bpy.data.collections[e['collection']];sc.view_layers[0].update();dg=sc.view_layers[0].depsgraph;vv=[]
 for o in col.objects:
  if o.type=='MESH':vv.extend(Vector(v) for v in o.evaluated_get(dg).bound_box)
 low=Vector(tuple(min(v[k] for v in vv) for k in range(3)));high=Vector(tuple(max(v[k] for v in vv) for k in range(3)));shift=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
 for o in col.objects:
  if o.type=='MESH':
   for v in o.data.vertices:v.co-=shift
   o.data.update()
 e['bounds_size_m']=[round(v,6) for v in high-low]
 if e['component_family']=='wall':assert abs(e['bounds_size_m'][0]-5)<1e-5 and abs(e['bounds_size_m'][2]-2.8)<1e-5
p.write_text(json.dumps(doc,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.context.window_manager.windows[0].scene=bpy.data.scenes['复古公馆_组件实例参考_非正式关卡']
bpy.ops.wm.save_as_mainfile(filepath=str(S/'复古公馆_模块化组件母版_v017.blend'))
print('EVALUATED_SOURCE_ANCHORS_NORMALIZED')
