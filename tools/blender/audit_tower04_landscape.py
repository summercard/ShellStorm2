"""Reopen delivered file and independently inspect evaluated instances and package contracts."""
import bpy,json,sys,runpy,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
O=Path(bpy.data.filepath).parent
c=json.loads((O/'catalog.json').read_text(encoding='utf8'));checks={};rows=[]
checks['source_hash']=hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()==c['source_sha256']
checks['five_independent_groups']=len(c['groups'])==5
manifest_paths=list((O/'component_packages').rglob('asset_manifest.json'))
checks['manifest_count']=len(manifest_paths)==len(c['instances'])
checks['reusable_definition_budget']=len(c['definitions'])<=50
checks['three_vine_variants']=len([x for x in c['definitions'] if x['id'] in ('curtain','cascade','carpet')])==3
all_objects=[]
for g in c['groups']:
 col=bpy.data.collections[g['collection']];obs=list(col.all_objects);all_objects+=obs
 s=next(s for s in bpy.data.scenes if s.get('asset_id')==g['asset_id'])
 bpy.context.window.scene=s;s.view_layers[0].update();dg=bpy.context.evaluated_depsgraph_get()
 triangles=0;polygons=0;points=[];degenerate=0
 for ob in obs:
  ev=ob.evaluated_get(dg);me=ev.to_mesh();me.calc_loop_triangles();triangles+=len(me.loop_triangles);polygons+=len(me.polygons);degenerate+=sum(t.area<1e-10 for t in me.loop_triangles)
  points += [ev.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear()
 lo=[min(v[j] for v in points) for j in range(3)];hi=[max(v[j] for v in points) for j in range(3)]
 checks[g['asset_id']+'_budget']=triangles<=3000 and triangles==g['triangles']
 checks[g['asset_id']+'_origin']=abs(lo[2])<1e-4 and (c['version']=='v003' or all(abs(lo[j]+hi[j])<1e-4 for j in (0,1)))
 checks[g['asset_id']+'_no_degenerate_triangles']=degenerate==0
 checks[g['asset_id']+'_unique_package_ownership']=all(len(ob.users_collection)==1 for ob in obs)
 rows.append({'asset_id':g['asset_id'],'triangles':triangles,'polygons':polygons,'bounds_min':lo,'bounds_max':hi,'dimensions':[hi[j]-lo[j] for j in range(3)],'instances':len(obs)})
for p in manifest_paths:
 m=json.loads(p.read_text(encoding='utf8'));co=bpy.data.collections.get(m['collection']);ob=bpy.data.objects.get(m['root_object'])
 checks[m['package_id']+'_manifest']=co is not None and ob is not None and list(co.objects)==[ob] and max(abs(ob.location[j]-m['world_position'][j]) for j in range(3))<1e-4
checks['linked_module_meshes']=len({o.data.name for o in all_objects})==c.get('output_definition_count',9)
checks['no_unapplied_modifiers']=all(not o.modifiers for o in all_objects)
checks['external_palette']=all(not im.packed_file for im in bpy.data.images if im.type=='IMAGE')
if c['version'] in ['v002','v003']:
 from mathutils.bvhtree import BVHTree
 import ast
 scope=json.loads((O/'qa/scope_lock.json').read_text(encoding='utf8'))
 parent=json.loads((O.parent/('v002' if c['version']=='v003' else 'v001')/'catalog.json').read_text(encoding='utf8'))
 checks['parent_source_unchanged']=hashlib.sha256((R/parent['source_blend']).read_bytes()).hexdigest()==scope['parent_sha256']
 checks['identical_group_triangle_counts']=[r['triangles'] for r in rows]==[g['triangles'] for g in parent['groups']]
 source=(R/'tools/blender/build_tower04_landscape_v002.py').read_text(encoding='utf8')
 node=next(n for n in ast.parse(source).body if isinstance(n,ast.FunctionDef) and n.name=='signature')
 exec(compile(ast.Module(body=[node],type_ignores=[]),'<signature>','exec'),globals())
 checks['unchanged_geometry_and_vegetation']=all(signature(bpy.data.objects[n])==s for n,s in scope['locked_objects'].items())
 checks['exactly_two_construction_buildings']=len(c['construction_buildings'])==2
 if c['version']=='v003':
  olddefs={d['id']:d for d in parent['definitions']}
  for ch in c['deformation_changes']:
   current=bpy.data.objects[ch['object']].data;previous=bpy.data.meshes[olddefs[ch['old_definition']]['mesh']]
   checks[ch['object']+'_topology_unchanged']=len(current.vertices)==len(previous.vertices) and [tuple(p.vertices) for p in current.polygons]==[tuple(p.vertices) for p in previous.polygons]
  checks['fixed_assembly_origins']=all(max(abs(bpy.data.objects[i['root_object']].location[j]-i['world_position'][j]) for j in range(3))<1e-5 for i in parent['instances'])
 probes=[]
 def bvh(objects):
  verts=[];faces=[]
  for ob in objects:
   offset=len(verts);verts.extend(ob.location+ob.rotation_euler.to_matrix()@v.co for v in ob.data.vertices)
   faces.extend(tuple(offset+i for i in p.vertices) for p in ob.data.polygons)
  return BVHTree.FromPolygons(verts,faces)
 for prefix in c['construction_buildings']:
  obs=[o for o in all_objects if o.name.startswith(prefix) and str(o.get('component_definition','')).startswith('frame_')]
  tree=bvh(obs);body=[o for o in obs if not str(o['component_definition']).startswith('frame_crown')]
  checks[prefix+'_no_glass_faces']=all(p.material_index!=2 for o in obs for p in o.data.polygons)
  for ob in body:
   width,depth=(25,14) if ob['component_definition']=='frame_wide' else (12,12)
   for floor in range(4):
    origin=ob.location+Vector((width*.19,-depth/2-1,floor*4+2))
    hit=tree.ray_cast(origin,Vector((0,1,0)),depth+2)[0]
    probes.append({'object':ob.name,'floor':floor,'no_hidden_wall_core':hit is None})
  checks[prefix+'_open_frame_all_floors']=all(p['no_hidden_wall_core'] for p in probes if p['object'].startswith(prefix))
 for change in c['damage_changes']:
  if change['new_definition'].startswith('frame'):continue
  ob=bpy.data.objects[change['object']];key=change['new_definition'];w,d=(16,14) if key.startswith('narrow') else (12,12)
  x=w*.32 if 'corner_loss' in key else 0
  origin=ob.location+Vector((x,-d/2-1,6.4))
  hit=bvh([ob]).ray_cast(origin,Vector((0,1,0)),d*.55)[0]
  checks[ob.name+'_real_cavity']=hit is None
 (O/'qa/openness_probes.json').write_text(json.dumps(probes,ensure_ascii=False,indent=2),encoding='utf8')
report={'passed':all(checks.values()),'checks':checks,'groups':rows,'status':'Blender source only; no runtime import or placement'}
(O/'qa/source_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('INDEPENDENT_SOURCE_AUDIT',report['passed'],[(g['asset_id'],g['triangles']) for g in rows],flush=True)
assert report['passed'],{k:v for k,v in checks.items() if not v}
# Standard validator sees every actual mesh instance in one temporary verification scene.
verify=bpy.data.scenes.new('临时全实例色盘验收')
for ob in all_objects:verify.collection.objects.link(ob)
bpy.context.window.scene=verify
script=Path('C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py')
sys.argv=[str(script),'--','--all-meshes','--max-materials','3','--shared-palette',str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),'--json',str(O/'qa/palette_validation.json')]
runpy.run_path(str(script),run_name='__main__')
