import bpy,json,hashlib,ast,sys,runpy
from pathlib import Path
from mathutils import Vector
ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle/source/common_components/v005')
SCRIPT=ROOT/'qa/build_wall08_v005.py'
# Reuse only pure signature definitions, never execute the builder during acceptance.
tree=ast.parse(SCRIPT.read_text(encoding='utf-8'))
for node in tree.body:
 if isinstance(node,ast.FunctionDef) and node.name in ['digest','q','rna_props','signature']:
  exec(compile(ast.Module(body=[node],type_ignores=[]),str(SCRIPT),'exec'))
bpy.context.view_layer.update()
old=json.loads((ROOT/'qa/scope_lock_before.json').read_text(encoding='utf-8'))
new={n:signature(bpy.data.objects[n]) for n in old}
# Blender assigns session_uid afresh on reopening; it is not authored asset data.
for dataset in [old,new]:
 for item in dataset.values():
  if 'data' in item['details']:item['details']['data'].pop('session_uid',None)
  item['sha256']=digest(item['details'])
changed=[n for n in old if old[n]['sha256']!=new[n]['sha256']]
if changed:
 for n in changed:
  a=old[n]['details'];b=new[n]['details']
  print('LOCK_DIFF',n,[(k,a.get(k),b.get(k)) for k in a if a.get(k)!=b.get(k)],flush=True)
assert not changed,changed
catalog=json.loads((ROOT/'component_catalog.json').read_text(encoding='utf-8'))
all_packages=[bpy.data.collections[e['blender_collection']] for e in catalog]
for c in all_packages:
 for o in c.objects:
  assert sum(o.name in p.objects for p in all_packages)==1,(o.name,'multiple packages')
 assert any(o.type=='MESH' for o in c.objects),c.name
assert len(list((ROOT/'component_packages_v005').glob('*/*/asset_manifest.json')))==len(catalog)
report=json.loads((ROOT/'qa/task_validation.json').read_text(encoding='utf-8'))
report['reopened_locked_match']=True
report['reopened_locked_count']=len(old)
report['package_membership_checked']=True
report['output_geometry']={}
for s in ['wall_standard_5m','wall_door_5m']:
 c=bpy.data.collections[s+'_通用包'];r=bpy.data.objects['ROOT_'+s+'_通用组件'];inv=r.matrix_world.inverted()
 meshes=[o for o in c.objects if o.type=='MESH'];pts=[inv@(o.matrix_world@v.co) for o in meshes for v in o.data.vertices]
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 for o in meshes:o.data.calc_loop_triangles()
 report['output_geometry'][s]={'bounds_lo':lo,'bounds_hi':hi,'triangles':sum(len(o.data.loop_triangles) for o in meshes),'polygons':sum(len(o.data.polygons) for o in meshes),'objects':len(meshes),'active_modifiers':sum(len(o.modifiers) for o in meshes)}
 assert abs(lo[0]+2.5)<.00001 and abs(hi[0]-2.5)<.00001 and abs(lo[2])<.00001 and abs(hi[2]-11.9)<.00001
 # Test aperture with vertices and triangle centroids; flat wall panel triangles are separated around the opening.
 if 'door' in s:
  for o in meshes:
   for tri in o.data.loop_triangles:
    v=[inv@(o.matrix_world@o.data.vertices[i].co) for i in tri.vertices]
    cent=sum(v,Vector())/3
    assert not (-1.0999<cent.x<1.0999 and .0001<cent.z<2.4999),(o.name,tuple(cent))
report['interface_notes'][0]='Original roots, 5m span, Z=0..11.9m and 2.2x2.5m aperture retained. Actual surface-relief bounds are measured in output_geometry.'
(ROOT/'qa/task_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('REOPEN_SCOPE_INTERFACE_PACKAGES_OK',flush=True)
# Official strict audit over every mesh in the full original master scene.
sys.argv=['validate','--','--all-meshes','--max-materials','4','--shared-palette','I:/工作项目/shellstrom2/ShellStorm2/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png','--json',str(ROOT/'qa/full_library_validation.json')]
try:runpy.run_path('C:/Users/zhuangmenghong/.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py',run_name='__main__')
except SystemExit as e:print('FULL_LIBRARY_STRICT_EXIT',e.code)
full=json.loads((ROOT/'qa/full_library_validation.json').read_text(encoding='utf-8'))
expected=['floor_tile_r01_c01_砖面美术_24','floor_tile_r01_c01_砖面美术_25','floor_tile_r01_c02_砖面美术_21','floor_tile_r01_c02_砖面美术_22']
assert full['poorly_named_emissive_objects']==expected,full['poorly_named_emissive_objects']
assert all(v for k,v in full['checks'].items() if k!='emissive_objects_clearly_named')
# Scope audit using the same validator functions, retaining the whole library for unused-material checking.
ns=runpy.run_path('C:/Users/zhuangmenghong/.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py',run_name='wall08_scope_validator')
targets=[o for s in ['wall_standard_5m','wall_door_5m'] for c in [bpy.data.collections[s+'_通用包'],bpy.data.collections[s+'_制作源']] for o in c.objects if o.type=='MESH']
uvs=[ns['audit_palette_uv'](o) for o in targets]
assert all(r['valid_island_polygon_count']==r['polygon_count'] and r['active_uv']=='PaletteUV' and r['active_render_uv']=='PaletteUV' and not r['extra_uv_layers'] for r in uvs)
assert not [o.name for o in targets if any(ns['material_is_emissive'](m) for m in o.data.materials) and not any(t in o.name for t in ['自发光','UI灯光'])]
r={'passed':True,'mesh_count':len(targets),'polygon_count':sum(r['polygon_count'] for r in uvs),'valid_island_polygon_count':sum(r['valid_island_polygon_count'] for r in uvs),'uv_reports':uvs,'full_library_existing_naming_warnings':expected}
(ROOT/'qa/wall08_scope_validation.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
print('WALL08_SCOPE_STRICT_OK',r['mesh_count'],r['polygon_count'],flush=True)
