import bpy,json,hashlib,ast,sys,runpy,math
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle/source/common_components/v006')
SCRIPT=ROOT.parent/'v005/qa/build_wall08_v005.py'
for node in ast.parse(SCRIPT.read_text(encoding='utf-8')).body:
 if isinstance(node,ast.FunctionDef) and node.name in ['digest','q','rna_props','signature']:
  exec(compile(ast.Module(body=[node],type_ignores=[]),str(SCRIPT),'exec'))
bpy.context.view_layer.update();master=bpy.context.scene
old=json.loads((ROOT/'qa/locked_before.json').read_text(encoding='utf-8'))
new={n:signature(bpy.data.objects[n]) for n in old}
for dataset in [old,new]:
 for item in dataset.values():
  if 'data' in item['details']:item['details']['data'].pop('session_uid',None)
  item['sha256']=digest(item['details'])
changed=[n for n in old if old[n]['sha256']!=new[n]['sha256']]
assert not changed,changed
catalog=json.loads((ROOT/'component_catalog.json').read_text(encoding='utf-8'))
packages=[bpy.data.collections[e['blender_collection']] for e in catalog]
for c,e in zip(packages,catalog):
 assert any(o.type=='MESH' for o in c.objects),c.name
 for o in c.objects:assert sum(o.name in p.objects for p in packages)==1,(o.name,'multiple packages')
 manifest=ROOT/'component_packages_v006'/e['category'][:2]/e['slug']/'asset_manifest.json'
 assert json.loads(manifest.read_text(encoding='utf-8'))==e
assert len(list((ROOT/'component_packages_v006').glob('*/*/asset_manifest.json')))==len(catalog)
report=json.loads((ROOT/'qa/anchor_and_door_validation.json').read_text(encoding='utf-8'))
assert hashlib.sha256(Path(report['source']).read_bytes()).hexdigest()==report['source_sha256']
report.update(reopened_locked_match=True,reopened_locked_count=len(old),package_membership_checked=True,empty_package_count=0,multiple_package_object_count=0)
report['output_geometry']={}
for s in ['wall_door_5m','door_5m']:
 c=bpy.data.collections[s+'_通用包'];r=bpy.data.objects['ROOT_'+s+'_通用组件'];inv=r.matrix_world.inverted()
 assert (c.instance_offset-r.matrix_world.translation).length<1e-5
 meshes=[o for o in c.objects if o.type=='MESH'];pts=[inv@(o.matrix_world@v.co) for o in meshes for v in o.data.vertices]
 for o in meshes:
  o.data.calc_loop_triangles()
  assert o.location.length<1e-5 and o.parent==r
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 report['output_geometry'][s]={'bounds_lo':lo,'bounds_hi':hi,'triangles':sum(len(o.data.loop_triangles) for o in meshes),'polygons':sum(len(o.data.polygons) for o in meshes),'objects':len(meshes),'active_modifiers':sum(len(o.modifiers) for o in meshes)}
 if s=='wall_door_5m':
  for o in meshes:
   for tri in o.data.loop_triangles:
    cent=sum((inv@(o.matrix_world@o.data.vertices[i].co) for i in tri.vertices),Vector())/3
    assert not (-1.0999<cent.x<1.0999 and .0001<cent.z<2.4999),(o.name,tuple(cent))
# Re-opened collection evaluation at actual placement, not just metadata.
probe=bpy.data.scenes.new('TEMP_anchor_reopen_test');bpy.context.window.scene=probe;results=[]
for s in ['wall_door_5m','door_5m']:
 for angle in [0,90,180,270]:
  ob=bpy.data.objects.new('probe',None);probe.collection.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=bpy.data.collections[s+'_通用包'];ob.location=(17,-8,2);ob.rotation_euler.z=math.radians(angle)
  bpy.context.view_layer.update();inv=ob.matrix_world.inverted();points=[]
  for inst in bpy.context.evaluated_depsgraph_get().object_instances:
   if inst.is_instance and inst.parent and inst.parent.original==ob and inst.object.type=='MESH':points.extend(inv@(inst.matrix_world@v.co) for v in inst.object.data.vertices)
  assert points
  lo=[min(v[i] for v in points) for i in range(3)];hi=[max(v[i] for v in points) for i in range(3)]
  err=max(abs((lo[0]+hi[0])/2),abs(lo[2]))
  if s=='door_5m':err=max(err,abs((lo[1]+hi[1])/2))
  assert err<.0001
  results.append({'asset':s,'rotation':angle,'error_m':err,'passed':True})
  bpy.data.objects.remove(ob,do_unlink=True)
bpy.context.window.scene=master;bpy.data.scenes.remove(probe)
report['reopened_anchor_tests']=results
sys.argv=['validate','--','--all-meshes','--max-materials','4','--shared-palette','I:/工作项目/shellstrom2/ShellStorm2/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png','--json',str(ROOT/'qa/full_library_validation.json')]
try:runpy.run_path('C:/Users/zhuangmenghong/.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py',run_name='__main__')
except SystemExit as e:print('FULL_LIBRARY_STRICT_EXIT',e.code)
full=json.loads((ROOT/'qa/full_library_validation.json').read_text(encoding='utf-8'))
expected=['floor_tile_r01_c01_砖面美术_24','floor_tile_r01_c01_砖面美术_25','floor_tile_r01_c02_砖面美术_21','floor_tile_r01_c02_砖面美术_22']
assert full['poorly_named_emissive_objects']==expected,full['poorly_named_emissive_objects']
assert all(v for k,v in full['checks'].items() if k!='emissive_objects_clearly_named'),full['checks']
ns=runpy.run_path('C:/Users/zhuangmenghong/.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py',run_name='scope_validator')
targets=[o for s in ['wall_door_5m','door_5m'] for c in [bpy.data.collections[s+'_通用包'],bpy.data.collections[s+'_制作源']] for o in c.objects if o.type=='MESH']
uvs=[ns['audit_palette_uv'](o) for o in targets]
assert all(r['valid_island_polygon_count']==r['polygon_count'] and r['active_uv']=='PaletteUV' and r['active_render_uv']=='PaletteUV' and not r['extra_uv_layers'] for r in uvs)
assert not [o.name for o in targets if any(ns['material_is_emissive'](m) for m in o.data.materials) and not any(t in o.name for t in ['自发光','UI灯光'])]
scope={'passed':True,'mesh_count':len(targets),'polygon_count':sum(r['polygon_count'] for r in uvs),'valid_island_polygon_count':sum(r['valid_island_polygon_count'] for r in uvs),'uv_reports':uvs,'full_library_existing_naming_warnings':expected}
(ROOT/'qa/door_scope_validation.json').write_text(json.dumps(scope,ensure_ascii=False,indent=2),encoding='utf-8')
report['scope_validation_passed']=True;report['full_library_checks_except_existing_naming_passed']=True;report['existing_naming_warning_count']=4
(ROOT/'qa/anchor_and_door_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('REOPEN_DOOR_ANCHOR_SCOPE_PACKAGES_OK',len(old),scope['polygon_count'],flush=True)
