import bpy,json,sys,hashlib,importlib.util
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
out=work_path('items_reference_20261014/ground/validation.json')
spec=importlib.util.spec_from_file_location('v',ROOT/'skills_drafts/blender-game-prop-standard/scripts/validate_game_prop.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
report=json.loads((out.parent/'report.json').read_text('utf8'));checks=[]
for r in report:
 assert hashlib.sha256((ROOT/r['preview_source']).read_bytes()).hexdigest()==r['preview_sha256']
 bpy.ops.wm.open_mainfile(filepath=str(ROOT/r['ground_source']))
 objects=v.output_meshes();assert len(objects)==1
 o=objects[0];o.data.calc_loop_triangles();assert 100<=len(o.data.loop_triangles)<=200
 assert all(len(p.vertices)==3 for p in o.data.polygons)
 a=v.audit_palette_uv(o);assert a['valid_island_polygon_count']==a['polygon_count'],a
 c=json.loads(((ROOT/r['preview_source']).parent.parent/'asset_contract.json').read_text('utf8'))
 size=[max(v.co[i] for v in o.data.vertices)-min(v.co[i] for v in o.data.vertices) for i in range(3)]
 for i,k in enumerate(['width','depth','height']):assert abs(size[i]-c['dimensions_m'][k])<.00001,(r['slug'],size,c['dimensions_m'])
 assert tuple(o.scale)==(1,1,1) and tuple(bpy.data.objects['ItemRoot'].scale)==(1,1,1)
 for m in bpy.data.materials:
  assert m.name in c['material_roles']
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE':assert not n.image.packed_file and n.interpolation=='Closest' and n.image.size[:]==(512,512)
 assert hashlib.sha256((ROOT/r['ground_source']).read_bytes()).hexdigest()==r['ground_sha256']
 checks.append({'asset_id':r['asset_id'],'triangles':len(o.data.loop_triangles),'bounds':size,'uv_pass':True,'high_unchanged':True})
out.write_text(json.dumps({'passed':True,'checks':checks},ensure_ascii=False,indent=2),encoding='utf8');print('GROUND_SOURCE_VALIDATION_OK',len(checks))
