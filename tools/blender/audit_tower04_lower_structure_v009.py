"""Saved-source, immutable-top, lower-structure and package audit."""
import ast,bpy,hashlib,json,sys,numpy as np
from pathlib import Path
from collections import Counter
from mathutils import Vector
R=Path(__file__).resolve().parents[2];F=Path(bpy.data.filepath).parent
sys.path.insert(0,str(Path(__file__).parent))
from tower04_lower_structure_common import object_signature
meta=json.loads((F/'catalog.json').read_text(encoding='utf8'));lock=json.loads((F/'qa/locked_before.json').read_text(encoding='utf8'));build=json.loads((F/'qa/lower_structure_build.json').read_text(encoding='utf8'))
MATS=[bpy.data.materials[n] for n in meta['material_roles']]
p=R/'tools/blender/refine_tower04_routes_v003.py';nodes=[n for n in ast.parse(p.read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name in {'sha','material_signature'}];exec(compile(ast.Module(body=nodes,type_ignores=[]),str(p),'exec'),globals())
errors=[];changed=[n for n,s in lock['objects'].items() if n not in bpy.data.objects or object_signature(bpy.data.objects[n])!=s]
if changed:errors.append('protected_top_or_camera_changed')
if len(bpy.data.materials)!=4 or material_signature()!=lock['materials']:errors.append('original_materials_changed')
for file,digest in lock['files'].items():
 if hashlib.sha256((R/file).read_bytes()).hexdigest()!=digest:errors.append('parent_or_palette_changed:'+file)
ids={p['package_id'] for p in meta['packages']};ownership=Counter();new=[];polygons=0;observed={}
for p in meta['packages']:
 c=bpy.data.collections.get(p['collection']);path=F/'component_packages'/p['category']/p['slug']/'asset_manifest.json'
 if c is None or not c.objects:errors.append('empty:'+p['slug']);continue
 if not path.exists() or json.loads(path.read_text(encoding='utf8'))!=p:errors.append('manifest:'+p['slug'])
 if set(p['objects'])!=set(o.name for o in c.objects):errors.append('object_list:'+p['slug'])
 if any(d not in ids for d in p.get('dependencies',[])):errors.append('dependency:'+p['slug'])
 mins=[];maxs=[]
 for o in c.objects:
  ownership[o.name]+=1
  if len(o.users_collection)!=1:errors.append('multiple_ownership:'+o.name)
  vv=np.empty(len(o.data.vertices)*3,dtype=np.float32);o.data.vertices.foreach_get('co',vv);vv=vv.reshape((-1,3)).astype(np.float64)
  matrix=np.asarray(o.matrix_world);vv=vv@matrix[:3,:3].T+matrix[:3,3]
  mins.append(vv.min(axis=0));maxs.append(vv.max(axis=0));polygons+=len(o.data.polygons)
 mn=np.min(mins,axis=0);mx=np.max(maxs,axis=0);observed[p['slug']]={'min':mn.tolist(),'max':mx.tolist()}
 if max(np.max(np.abs(mn-np.array(p['bounds_min']))),np.max(np.abs(mx-np.array(p['bounds_max']))))>.003:errors.append('bounds:'+p['slug'])
 if p.get('lower_structure'):
  new.append(p)
  if max(mx[:2]-mn[:2])>10.01:errors.append('new_structure_not_modular:'+p['slug'])
  if p['slug'].startswith('oval_') and not p['slug'].startswith('oval_pilotis') and mn[2]<8.34:errors.append('left_undercroft_filled:'+p['slug'])
game=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
if set(ownership)!=set(o.name for o in game.all_objects) or any(v!=1 for v in ownership.values()):errors.append('output_ownership')
if len(list((F/'component_packages').rglob('asset_manifest.json')))!=len(meta['packages']):errors.append('disk_package_count')
if any(p['slug'].startswith(('oval_level_','wing_level_','pier_')) or p['slug'] in ('oval_glazing','wing_glazing') for p in meta['packages']):errors.append('old_solid_storeys_still_present')
if len([p for p in meta['packages'] if p['slug'].startswith('tile_r')])!=694:errors.append('top_tile_count')
if len({p['component_definition'] for p in meta['packages']})>50:errors.append('component_definition_limit')
if (F/'route_centerlines.json').read_bytes()!=(F.parent/'v008/route_centerlines.json').read_bytes():errors.append('route_json_changed')
clear_points=[(-56.5,-5.16,4),(-28,-8,3),(-20,-6,5)]
probes=[]
for point in clear_points:
 blockers=[p['slug'] for p in new if all(observed[p['slug']]['min'][i]-.01<=point[i]<=observed[p['slug']]['max'][i]+.01 for i in range(3))]
 probes.append({'position':point,'structural_bbox_candidates':blockers})
 if blockers:errors.append('intended_open_space_blocked:'+str(point))
for p in new:
 if p['slug'].startswith('bridge_pilotis') and abs(observed[p['slug']]['max'][2]-23.8)>.001:errors.append('pier_top_interface')
 if p['slug'].startswith('oval_pilotis') and abs(observed[p['slug']]['max'][2]-8.5)>.001:errors.append('oval_pier_interface')
source=next(c for c in bpy.data.collections if c.name.startswith('01_制作组件'))
if not source.hide_render or not source.hide_viewport or game.hide_render or game.hide_viewport:errors.append('collection_visibility')
for m in MATS:
 for n in m.node_tree.nodes:
  if n.type=='TEX_IMAGE':
   if n.image.packed_file or Path(bpy.path.abspath(n.image.filepath)).resolve()!=(R/meta['shared_palette']).resolve() or n.interpolation!='Closest':errors.append('palette_reference')
report={'passed':not errors,'errors':errors,'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),'protected_object_count':len(lock['objects']),'protected_changed':changed,'top_unchanged':not changed,'materials_unchanged':material_signature()==lock['materials'],'package_count':len(meta['packages']),'new_lower_structure_packages':len(new),'output_mesh_count':len(game.all_objects),'output_polygons':polygons,'material_count':len(bpy.data.materials),'definitions':len({p['component_definition'] for p in meta['packages']}),'open_space_probes':probes,'interface_z_m':{'roof':25,'existing_deck_bottom':23.8,'left_slabs':[9,14.3,19.6],'left_pier_top':8.5,'right_slabs':[.45,7.8,15.8,23.8],'lower_gallery':9,'gallery_ramp_end':7.8},'source_only':True,'runtime_verified':False}
(F/'qa/lower_structure_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
assert not errors,errors
if '--render' in sys.argv:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for d in prefs.devices:d.use=d.type!='CPU'
 sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;sc.cycles.device='GPU';sc.cycles.samples=48
 for name in ['CAM_参考全景','CAM_俯视轮廓','CAM_下部_左楼架空与退台','CAM_下部_右翼窗墙','CAM_下部_中央架空']:
  sc.camera=bpy.data.objects[name];sc.render.resolution_x=1600;sc.render.resolution_y=1000;sc.render.resolution_percentage=100;sc.render.filepath=str(F/'previews'/(name[4:]+'.png'));bpy.ops.render.render(write_still=True,scene=sc.name);print('RENDERED',name,flush=True)
