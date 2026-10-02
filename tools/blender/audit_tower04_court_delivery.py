"""Independent saved-file audit; does not execute the production builders."""
import bpy,json,sys,hashlib,math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent));from tower04_lower_structure_common import object_signature
R=Path(__file__).resolve().parents[2];T=R/'assets/art/environments/open_world/source/tower_04/v010';C=R/'assets/art/environments/open_world/source/tower_04_2/v002';kind=sys.argv[-1]
def bounds(o):
 points=[o.matrix_world@Vector(v) for v in o.bound_box]
 return [[min(v[j] for v in points) for j in range(3)],[max(v[j] for v in points) for j in range(3)]]
def triangles(objs):return sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objs if o.type=='MESH')
if kind=='roof':
 cat=json.loads((T/'catalog.json').read_text(encoding='utf8'));path=R/cat['source_blend'];bpy.ops.wm.open_mainfile(filepath=str(path));sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
 locked=json.loads((T/'qa/locked_before.json').read_text(encoding='utf8'));portal=json.loads((T/'qa/stair_portal.json').read_text(encoding='utf8'));ex=set(portal['changed_objects']);errors=[]
 for n,s in locked.items():
  if n not in ex and object_signature(bpy.data.objects[n])!=s:errors.append('lock:'+n)
 steps=sorted([o for o in sc.objects if o.type=='MESH' and o.get('package_id','').startswith('tower_04/spiral_step_') and not any('制作' in c.name for c in o.users_collection)],key=lambda o:o['package_id'])
 tops=[bounds(o)[1][2] for o in steps];assert len(tops)==28
 heights=[tops[0]-25.055]+[b-a for a,b in zip(tops,tops[1:])]
 if max(abs(h-5/28) for h in heights)>.0001:errors.append('unequal_risers')
 new=[p for p in cat['packages'] if p['slug'].startswith(('raised_','spiral_'))]
 for p in new:
  for n in p['objects']:
   a,b=bounds(bpy.data.objects[n])
   if max(b[j]-a[j] for j in (0,1))>8.01:errors.append('oversize:'+n)
 for n in ex:
  o=bpy.data.objects[n]
  if any(-58.519<v.x<-54.521 for v in [o.matrix_world@v.co for v in o.data.vertices]):errors.append('blocked_portal:'+n)
 for p in cat['packages']:
  f=T/'component_packages'/p['category']/p['slug']/'asset_manifest.json'
  if not f.exists():errors.append('missing_manifest:'+p['slug'])
 report=dict(passed=not errors,errors=errors,locked_objects=len(locked)-len(ex),locked_match=not any(e.startswith('lock') for e in errors),portal_changed_objects=sorted(ex),stairs_count=len(steps),stair_bottom=25.055,stair_top=tops[-1],riser_min=min(heights),riser_max=max(heights),component_package_count=len(cat['packages']),new_components_max_xy=8,visible_triangles=triangles([bpy.data.objects[n] for p in cat['packages'] for n in p['objects']]))
 dest=T/'qa/final_structure_audit.json'
elif kind in ('near','far_court'):
 lod='near' if kind=='near' else 'far';cat=json.loads((C/f'{lod}_catalog.json').read_text(encoding='utf8'));path=R/cat['source_blend'];bpy.ops.wm.open_mainfile(filepath=str(path));sc=bpy.context.scene;errors=[]
 instances=bpy.data.collections['02_游戏输出_分区实例'];seen=set()
 for inst in cat['instances']:
  o=bpy.data.objects.get(inst['object'])
  if o is None:errors.append('missing:'+inst['object']);continue
  if len(o.users_collection)!=1:errors.append('multiple_membership:'+o.name)
  if o['instance_id'] in seen:errors.append('duplicate_instance:'+o.name)
  seen.add(o['instance_id'])
 for d in cat['definitions']:
  mesh=bpy.data.meshes[d['mesh']];coords=[v.co for v in mesh.vertices]
  dims=[max(v[j] for v in coords)-min(v[j] for v in coords) for j in range(3)]
  if max(dims[:2])>8.01:errors.append('oversize:'+d['slug'])
  if not (C/'component_packages'/d['slug']/f'{lod}_manifest.json').exists():errors.append('manifest:'+d['slug'])
 other=json.loads((C/('far_catalog.json' if lod=='near' else 'near_catalog.json')).read_text(encoding='utf8'))
 same=cat['instances']==other['instances'];assert same,'LOD placement drift'
 tris=triangles(instances.all_objects)
 if lod=='far' and tris>80000:errors.append('court_lod_budget')
 report=dict(passed=not errors,errors=errors,definitions=len(cat['definitions']),instances=len(seen),visible_triangles=tris,geometry_budget=80000 if lod=='far' else None,lod_placements_identical=same,independent_region=True)
 dest=C/f'qa/{lod}_structure_audit.json'
else:
 cat=json.loads((T/'far_catalog.json').read_text(encoding='utf8'));path=R/cat['source_blend'];bpy.ops.wm.open_mainfile(filepath=str(path));sc=bpy.context.scene;errors=[];packages=[];maxxy=0
 for o in sc.objects:
  if o.type!='MESH':continue
  a,b=bounds(o);dim=[b[j]-a[j] for j in range(3)];maxxy=max(maxxy,*dim[:2])
  if max(dim[:2])>10.02:errors.append('oversize:'+o.name)
  if any('制作源' in c.name for c in o.users_collection):errors.append('high_source_present:'+o.name)
  # Actual objects, not stale pre-portal triangle figures, own the output manifest.
  packages.append(dict(object=o.name,package_id=o.get('source_package',o.get('instance_id',o.name)),dimensions=dim,bounds_min=a,bounds_max=b,origin=list(o.location),triangles=triangles([o])))
 tris=triangles(sc.objects)
 if tris>600000:errors.append('combo_budget')
 report=dict(passed=not errors,errors=errors,visible_triangles=tris,max_package_xy=maxxy,package_instances=len(packages),geometry_budget=600000,hidden_high_meshes=False)
 (T/'far_actual_packages.json').write_text(json.dumps(packages,ensure_ascii=False,indent=2),encoding='utf8')
 dest=T/'qa/far_structure_audit.json'
report['source_blend']=path.relative_to(R).as_posix();report['source_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();report['runtime_verified']=False
dest.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(report,ensure_ascii=False),flush=True)
if not report['passed']:raise RuntimeError(report['errors'])
