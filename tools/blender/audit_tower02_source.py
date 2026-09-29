import bpy,json
from pathlib import Path
from mathutils import Vector
out=Path(bpy.data.filepath).parent
catalog=json.loads((out/'catalog.json').read_text(encoding='utf8'))
issues=[]; objects=[]
for p in catalog['packages']:
 c=bpy.data.collections.get(p['collection'])
 if not c or not c.objects: issues.append('empty:'+p['slug']); continue
 actual=sorted(o.name for o in c.objects)
 if actual!=sorted(p['objects']): issues.append('objects:'+p['slug'])
 disk=out/'component_packages'/p['category']/p['slug']/'asset_manifest.json'
 if not disk.exists(): issues.append('missing_manifest:'+p['slug'])
 for o in c.objects:
  objects.append(o)
  if len(o.users_collection)!=1: issues.append('multi_owner:'+o.name)
floor=bpy.data.objects['楼层_00_楼板柱梁']
coords=[floor.matrix_world@v.co for v in floor.data.vertices if v.co.z<=.501]
bounds=[max(v[j] for v in coords)-min(v[j] for v in coords) for j in range(2)]
if any(abs(a-b)>.001 for a,b in zip(bounds,[70,50])): issues.append('footprint')
allcoords=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
mn=[min(v[j] for v in allcoords) for j in range(3)]; mx=[max(v[j] for v in allcoords) for j in range(3)]
report=dict(passed=not issues,issues=issues,packages=len(catalog['packages']),output_objects=len(objects),triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects if o.type=='MESH'),material_count=len(bpy.data.materials),footprint_m=bounds,full_bounds_min=mn,full_bounds_max=mx,full_dimensions=[mx[j]-mn[j] for j in range(3)],source_hidden=bpy.data.collections['01_制作组件_按设施拆分'].hide_render,scope='new independent tower02 source; other assets untouched',runtime_integration=False)
(out/'qa/source_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8'); print(json.dumps(report,ensure_ascii=False)); assert not issues
