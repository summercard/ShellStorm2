"""Run the formal Godot editor importer in a bounded project, preserving res paths."""
from pathlib import Path
import json,shutil,subprocess,os
R=Path(__file__).resolve().parents[1];O=R/'outputs/block00_story_rooms_20261009';P=O/'import_project';P.mkdir(exist_ok=True)
(P/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Block00ImportVerification"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf8')
m=json.loads((R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/export/v001/import_manifest.json').read_text('utf8'))
files=['tools/asset_pipeline/scene_facility_shared_palette_post_import.gd','assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png','assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import']
for d in m['components']:files.extend([d['glb_path'],d['glb_path']+'.import'])
for rel in files:
 dst=P/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/rel,dst)
env=os.environ.copy();env['APPDATA']='I:/ss2_probe_appdata/block00_import'
with (O/'isolated_import.log').open('w',encoding='utf8') as f:
 r=subprocess.run(['I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe','--headless','--editor','--import','--path',str(P)],stdout=f,stderr=subprocess.STDOUT,env=env,timeout=180)
assert r.returncode==0,r.returncode
for rel in files:
 if rel.endswith('.import'):shutil.copy2(P/rel,R/rel)
for f in (P/'.godot/imported').iterdir():
 if f.is_file():shutil.copy2(f,R/'.godot/imported'/f.name)
print('FORMAL_ISOLATED_IMPORT_OK',len(m['components']))
