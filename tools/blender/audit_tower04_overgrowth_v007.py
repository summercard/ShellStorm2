"""Saved-source verification for the reference-driven overgrown mall revision."""
import ast,bpy,hashlib,json,sys,math
from pathlib import Path
from collections import Counter
from mathutils import Vector
R=Path(__file__).resolve().parents[2];F=Path(bpy.data.filepath).parent
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely import wkt
from shapely.geometry import Polygon
from shapely.ops import unary_union
meta=json.loads((F/'catalog.json').read_text(encoding='utf8'))
lock=json.loads((F/'qa/locked_before.json').read_text(encoding='utf8'))
build=json.loads((F/'qa/overgrowth_build.json').read_text(encoding='utf8'))
MATS=[bpy.data.materials[n] for n in meta['material_roles']]
src=R/'tools/blender/refine_tower04_routes_v003.py'
nodes=[n for n in ast.parse(src.read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name in {'sha','floats','signature','material_signature'}]
exec(compile(ast.Module(body=nodes,type_ignores=[]),str(src),'exec'),globals())
errors=[];ownership=Counter();observed=[];structural=[];visual=[]
baseline_versions=json.loads((F/'qa/locked_baseline_versions.json').read_text(encoding='utf8')) if (F/'qa/locked_baseline_versions.json').exists() else {}
changed=[];version_updates=[]
for n,s in lock['objects'].items():
 o=bpy.data.objects.get(n)
 if o is None:changed.append(n);continue
 if signature(o)==s:continue
 if n in baseline_versions:
  current=o.get('version');old=baseline_versions[n]
  if current!=meta['version']:changed.append(n);continue
  if old is None:
   if 'version' in o:del o['version']
  else:o['version']=old
  same=signature(o)==s
  if current is None:
   if 'version' in o:del o['version']
  else:o['version']=current
  if same:version_updates.append(n)
  else:changed.append(n)
 else:changed.append(n)
if changed:errors.append('locked_objects_changed')
if len(bpy.data.materials)!=4 or material_signature()!=lock['materials']:errors.append('original_materials_changed')
for file,digest in lock['files'].items():
 if hashlib.sha256((R/file).read_bytes()).hexdigest()!=digest:errors.append('locked_file_changed:'+file)
ids={p['package_id'] for p in meta['packages']}
for p in meta['packages']:
 col=bpy.data.collections.get(p['collection']);path=F/'component_packages'/p['category']/p['slug']/'asset_manifest.json'
 if col is None or not col.objects:errors.append('empty:'+p['slug']);continue
 if not path.exists() or json.loads(path.read_text(encoding='utf8'))!=p:errors.append('manifest_drift:'+p['slug'])
 if set(p['objects'])!=set(o.name for o in col.objects):errors.append('object_list:'+p['slug'])
 if any(d not in ids for d in p.get('dependencies',[])):errors.append('dependency:'+p['slug'])
 vv=[]
 for o in col.objects:
  ownership[o.name]+=1
  if len(o.users_collection)!=1:errors.append('multiple_owners:'+o.name)
  if o.type!='MESH':errors.append('unexpected_type:'+o.name);continue
  vv.extend(tuple(o.matrix_world@v.co) for v in o.data.vertices)
 mn=[min(v[k] for v in vv) for k in range(3)];mx=[max(v[k] for v in vv) for k in range(3)]
 if max(abs(a-b) for a,b in zip(mn,p['bounds_min']))>.003 or max(abs(a-b) for a,b in zip(mx,p['bounds_max']))>.003:errors.append('bounds:'+p['slug'])
 if p.get('vegetation') and max(mx[k]-mn[k] for k in range(2))>8.0001:errors.append('vegetation_too_large:'+p['slug'])
 if p.get('vegetation') and (mn[0]<-77 or mx[0]>77 or mn[1]<-27 or mx[1]>27):errors.append('foliage_overhang_gt_2m:'+p['slug'])
 visual.extend(vv)
 if p['slug'].startswith(('oval_level_','wing_level_','terrace_shell')):structural.extend(vv)
 observed.append({'slug':p['slug'],'dimensions':[mx[k]-mn[k] for k in range(3)],'polygons':sum(len(o.data.polygons) for o in col.objects)})
game=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
if set(ownership)!=set(o.name for o in game.all_objects) or any(n!=1 for n in ownership.values()):errors.append('output_ownership')
if len(list((F/'component_packages').rglob('asset_manifest.json')))!=len(meta['packages']):errors.append('disk_package_count')
structmn=[min(v[k] for v in structural) for k in range(3)];structmx=[max(v[k] for v in structural) for k in range(3)]
if abs(structmx[0]-structmn[0]-150)>.01 or abs(structmx[1]-structmn[1]-50)>.01:errors.append('structural_envelope')
if len([p for p in meta['packages'] if p['slug'].startswith('tile_r')])!=694:errors.append('tile_count')
if len([p for p in meta['packages'] if p['slug'].startswith('oval_level_')])!=5:errors.append('five_storeys')
footprints={};layout=json.loads((F.parent/'v004/qa/surface_plan.json').read_text(encoding='utf8'))['frozen_layout']
for slug,z,key in [('terrace_shell',25,'deck'),('slow_lane',25.059,'route'),('lawn_court',25.127,'lawn_court')]:
 polys=[]
 for p in meta['packages']:
  if not(p['slug']==slug or p['slug'].startswith(slug+'_x')):continue
  for name in p['objects']:
   o=bpy.data.objects[name]
   for face in o.data.polygons:
    v=[o.matrix_world@o.data.vertices[i].co for i in face.vertices]
    if all(abs(q.z-z)<.0002 for q in v):
     g=Polygon([(q.x,q.y) for q in v])
     if g.is_valid and g.area>1e-7:polys.append(g)
 geom=unary_union(polys).buffer(.000015,join_style=2).buffer(-.000015,join_style=2)
 delta=geom.symmetric_difference(wkt.loads(layout[key]['wkt'])).area;footprints[key]={'delta_m2':delta,'area_m2':geom.area}
 if delta>.005:errors.append('layout_drift:'+key)
for p in meta['packages']:
 for name in p['objects']:
  for mat in bpy.data.objects[name].data.materials:
   for node in mat.node_tree.nodes:
    if node.type=='TEX_IMAGE' and node.image:
     if node.image.packed_file or Path(bpy.path.abspath(node.image.filepath)).resolve()!=(R/meta['shared_palette']).resolve():errors.append('palette_reference')
     if node.interpolation!='Closest':errors.append('palette_filter')
source=next(c for c in bpy.data.collections if c.name.startswith('01_制作组件'))
if not source.hide_render or not source.hide_viewport or game.hide_render or game.hide_viewport:errors.append('visibility')
report={'passed':not errors,'errors':errors,'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),'locked_object_count':len(lock['objects']),'changed_locked':changed,'package_count':len(meta['packages']),'new_vegetation_packages':len(build['new_foliage_packages']),'counts':build['counts'],'output_mesh_count':len(game.all_objects),'output_polygons':sum(p['polygons'] for p in observed),'structural_dimensions_m':[structmx[k]-structmn[k] for k in range(3)],'visual_dimensions_m':[max(v[k] for v in visual)-min(v[k] for v in visual) for k in range(3)],'footprints':footprints,'material_count':len(bpy.data.materials),'source_only':True,'runtime_verified':False}
report['allowed_metadata_only_version_updates']=version_updates
(F/'qa/overgrowth_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
assert not errors,errors
if '--render' in sys.argv:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for device in prefs.devices:device.use=device.type!='CPU'
 neutral=bpy.data.scenes['Scene'];mood=bpy.data.scenes['塔4_黄昏末世氛围']
 fixed=[('CAM_参考全景','01_塔4_参考全景.png'),('CAM_俯视轮廓','02_塔4_俯视轮廓.png'),('CAM_天台花园','03_塔4_天台花园.png'),('CAM_左翼转折','04_塔4_椭圆左翼.png'),('CAM_玻璃亭与格构','05_塔4_玻璃亭与遮阳棚.png'),('CAM_设备节点','06_塔4_近景设备与节点.png')]
 for scene,folder,views in [(neutral,'previews',fixed),(mood,'mood',[(o.name,o.name[4:]+'.png') for o in bpy.data.objects if o.type=='CAMERA' and o.name.startswith('CAM_末世_')])]:
  bpy.context.window.scene=scene;scene.cycles.device='GPU';scene.cycles.samples=48
  for name,file in views:
   scene.camera=bpy.data.objects[name];scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.filepath=str(F/folder/file)
   bpy.ops.render.render(write_still=True,scene=scene.name);print('RENDERED',file,flush=True)
