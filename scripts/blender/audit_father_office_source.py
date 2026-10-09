import bpy,json,hashlib,sys,importlib.util
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];O=R/'assets/art/environments/master_office_3d/source/env_father_office/v002'
P=json.loads((O/'component_plan.json').read_text(encoding='utf8'))
cat=json.loads((O/'component_catalog.json').read_text(encoding='utf8'))
instances=json.loads((O/'component_instances.json').read_text(encoding='utf8'))['instances']
errors=[];bounds={};allmin=Vector((1e5,)*3);allmax=-allmin
for d in cat:
 c=bpy.data.collections[d['collection']];pts=[v.co for ob in c.objects for v in ob.data.vertices]
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 bounds[d['slug']]=(lo,hi)
 if not pts:errors.append('empty:'+d['slug'])
 if abs(lo[2])>1e-5 or max(abs(lo[i]+hi[i]) for i in [0,1])>1e-5:errors.append('origin:'+d['slug'])
 for ob in c.objects:
  if len(ob.users_collection)!=1:errors.append('ownership:'+ob.name)
  if tuple(ob.location)!=(0,0,0) or tuple(ob.scale)!=(1,1,1):errors.append('transform:'+ob.name)
for i in instances:
 ob=bpy.data.objects[i['instance_id']]; c=ob.instance_collection
 pts=[ob.matrix_basis@v.co for child in c.objects for v in child.data.vertices]
 lo=Vector(tuple(min(p[k] for p in pts) for k in range(3)));hi=Vector(tuple(max(p[k] for p in pts) for k in range(3)))
 for k in range(3):allmin[k]=min(allmin[k],lo[k]);allmax[k]=max(allmax[k],hi[k])
 if i['slug'] in ['floor_panel','floor_fractured']:
  if lo.x < -40.001 or hi.x > -24.999 or lo.y < -10.001 or hi.y >10.001:errors.append('floor_envelope:'+ob.name)
 elif i['slug'] not in ['wall_panel','wall_fractured','wall_door']:
  if lo.x < -39.86 or hi.x > -25.14 or lo.y < -9.85 or hi.y >9.86:errors.append('footprint:'+ob.name+str((list(lo),list(hi))))
  if hi.x>-26.9 and lo.x<-24.8 and hi.y>1.1 and lo.y<3.9 and lo.z<3:errors.append('door_clearance:'+ob.name)
 if i['slug'] in ['wall_panel','wall_fractured','wall_door'] and (lo.z<-.001 or hi.z>11.901):errors.append('wall_height:'+ob.name+str(hi.z))
 if ob.instance_collection.name!=next(d['collection'] for d in cat if d['slug']==i['slug']):errors.append('instance_mapping:'+ob.name)
f=R/P['whitebox_source']
assert hashlib.sha256(f.read_bytes()).hexdigest()==P['whitebox_sha256']
# Link output masters into an excluded audit collection so the standard validator includes
# both authored meshes and baked output meshes, without relying on instance traversal.
audit=bpy.data.collections.new('99_临时审计输出母版');bpy.context.scene.collection.children.link(audit)
for d in cat:audit.children.link(bpy.data.collections[d['collection']])
spec=importlib.util.spec_from_file_location('standard','C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
uv=[m.audit_palette_uv(ob) for ob in bpy.context.scene.objects if ob.type=='MESH']
bad=[r for r in uv if r['valid_island_polygon_count']!=r['polygon_count']]
if bad:errors.append('palette_uv_bad')
report=dict(errors=errors,passed=not errors,unique_components=len(cat),instances=len(instances),material_count=len(bpy.data.materials),bounds_world=[list(allmin),list(allmax)],component_bounds=bounds,uv_faces=sum(a['polygon_count'] for a in uv),valid_uv_faces=sum(a['valid_island_polygon_count'] for a in uv),whitebox_signature_unchanged=True,runtime_modified=False)
(O/'task_acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('TASK_AUDIT',json.dumps(report,ensure_ascii=False),flush=True)
sys.argv=['blender','--','--all-meshes','--max-materials','4','--shared-palette',str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),'--json',str(O/'material_acceptance.json')]
m.main()
