"""Read every saved source independently; verify physical bounds and per-face palette UV."""
import bpy, json, sys, importlib.util, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
OUT=work_path('items_reference_20261014/validation.json')
spec=importlib.util.spec_from_file_location('prop_validator',ROOT/'skills_drafts/blender-game-prop-standard/scripts/validate_game_prop.py')
validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
contracts=sorted((ROOT/'art_source/items_weapons').glob('*/ */asset_contract.json'))
contracts=[]
for domain in ['props','weapons']:
 for p in (ROOT/'art_source/items_weapons'/domain).glob('*/asset_contract.json'):
  c=json.loads(p.read_text('utf8'))
  if c.get('dimension_basis',{}).get('snapshot_date')=='2026-10-14':contracts.append((p,c))
results=[]
for p,c in contracts:
 bpy.ops.wm.open_mainfile(filepath=str(ROOT/c['source_blend']))
 issues=[];objects=validator.output_meshes();points=[];faces=0;triangles=0
 assert len(objects)==1,(c['asset_id'],len(objects))
 for o in objects:
  assert tuple(o.scale)==(1,1,1)
  a=validator.audit_palette_uv(o)
  assert a['valid_island_polygon_count']==a['polygon_count'],a
  assert not a['extra_uv_layers'] and a['active_uv']=='PaletteUV' and a['active_render_uv']=='PaletteUV'
  faces+=len(o.data.polygons);o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
  points.extend(o.matrix_world@Vector(v) for v in o.bound_box)
 size=[max(v[i] for v in points)-min(v[i] for v in points) for i in range(3)]
 for i,key in enumerate(['width','depth','height']):assert abs(size[i]-c['dimensions_m'][key])<.00001,(size,c['dimensions_m'])
 axis=c['dimension_basis']['locked_axis_blender'];assert abs(size[axis]-c['dimension_basis']['locked_length_m'])<.0001
 assert sorted(m.name for m in bpy.data.materials)==sorted(c['material_roles'])
 images=[]
 for m in bpy.data.materials:
  tex=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE'];assert len(tex)==1
  t=tex[0];assert t.interpolation=='Closest' and not t.image.packed_file
  assert t.image.filepath.startswith('//')
  assert Path(bpy.path.abspath(t.image.filepath)).resolve()==(ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png').resolve()
  assert tuple(t.image.size)==(512,512);images.append(t.image.as_pointer())
 assert len(set(images))==1
 assert len(bpy.data.armatures)==0 and not any(o.animation_data for o in bpy.data.objects)
 assert tuple(bpy.data.objects['ItemRoot'].scale)==(1,1,1)
 assert bpy.data.collections['01_制作组件_已统一材质'].hide_render
 assert bpy.data.collections['01_制作组件_已统一材质'].hide_viewport
 manifest=json.loads((p.parent/'source_manifest.json').read_text('utf8'))
 assert manifest['source_sha256']==hashlib.sha256((ROOT/c['source_blend']).read_bytes()).hexdigest()
 results.append({'asset_id':c['asset_id'],'source':c['source_blend'],'bounds_blender_xyz_m':size,'output_meshes':len(objects),'polygons':faces,'triangles':triangles,'all_face_uv_pass':True,'four_shared_materials_pass':True,'unpacked_palette_reopened_pass':True,'scale_1_pass':True,'stage':'source_only'})
assert len(results)==8
OUT.write_text(json.dumps({'passed':True,'sources':results},ensure_ascii=False,indent=2),encoding='utf8')
print('REFERENCE_ITEMS_SOURCE_VALIDATION_OK',len(results))
