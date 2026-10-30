import bpy,json
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');S=R/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=R.parent/'ShellStorm2-work/manor_v017'
doc=json.loads((S/'component_instances.json').read_text(encoding='utf-8'));cat=json.loads((S/'component_catalog.json').read_text(encoding='utf-8'))['components'];byid={e['component_id']:e for e in cat}
for i in doc['instances']:
 o=bpy.data.objects[i['source_object']];assert o.instance_type=='COLLECTION';assert o.instance_collection.name==byid[i['component_id']]['collection'];assert (o.location-Vector(i['position_m'])).length<1e-6;assert o.scale==Vector((1,1,1));assert o.instance_collection.instance_offset.length==0
bpy.context.window_manager.windows[0].scene=bpy.data.scenes['复古公馆_组件实例参考_非正式关卡'];dg=bpy.context.evaluated_depsgraph_get();vv=[];count=0
for ins in dg.object_instances:
 if ins.is_instance and ins.object.type=='MESH':
  mat=ins.matrix_world.copy();vv.extend(mat@Vector(v) for v in ins.object.bound_box);count+=1
low=[min(v[k] for v in vv) for k in range(3)];high=[max(v[k] for v in vv) for k in range(3)];report=dict(instances=len(doc['instances']),render_mesh_instances=count,bbox_blender=dict(min=low,max=high,size=[high[k]-low[k] for k in range(3)]),instances_match=True,collection_offsets_zero=True)
(W/'blender_replay_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
