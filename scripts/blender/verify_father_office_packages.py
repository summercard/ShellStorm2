import bpy,json,importlib.util,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2];O=R/'assets/art/environments/master_office_3d/source/env_father_office/v002'
if '--story' in sys.argv:O=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/v001'
files=json.loads((O/'package_delivery.json').read_text(encoding='utf8'))
spec=importlib.util.spec_from_file_location('standard','C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
report=[]
for d in files:
 bpy.ops.wm.open_mainfile(filepath=str(R/d['path']))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];bad=[]
 for ob in meshes:
  r=m.audit_palette_uv(ob)
  if r['valid_island_polygon_count']!=r['polygon_count']:bad.append(ob.name)
 images=[i for i in bpy.data.images if i.source=='FILE']
 if any(i.packed_file or Path(bpy.path.abspath(i.filepath,library=i.library)).resolve()!= (R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png').resolve() for i in images):bad.append('palette_path')
 if not meshes:bad.append('empty_scene')
 report.append({'slug':d['slug'],'reopened':True,'mesh_count':len(meshes),'uv_pass':not bad,'errors':bad})
(O/'package_acceptance.json').write_text(json.dumps({'passed':all(not r['errors'] for r in report),'packages':report},ensure_ascii=False,indent=2),encoding='utf8')
print('PACKAGES_REOPENED',len(report),'PASS',all(not r['errors'] for r in report))
