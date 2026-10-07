import hashlib, json, shutil, subprocess, sys
from pathlib import Path
from PIL import Image
P = Path('I:/工作项目/shellstrom2/ShellStorm2')
O = P/'outputs/base99_radio_v004'
O.mkdir(exist_ok=True)
B=O/'backup_before'
B.mkdir(exist_ok=True)
paths = ['assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn','assets/art/environments/tower_zones/base/runtime/zone_base.tscn','assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png','assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import','assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v003.blend','assets/art/props/base_world_3d/source/base99_radio/export/v003/prp_base99_radio_optimized_v003.blend','assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb','assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb.import','assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn','src/base3d/Base99Radio3D.gd','tests/verification/verify_base99_radio.gd','assets/registry/ledger_split_baseline.json','assets/registry/ledgers/ShellStorm2_道具账本_v001.xlsx']
report={}
for rel in paths:
    p=P/rel; dest=B/rel
    if not dest.exists():
        dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,dest)
    report[rel]=hashlib.sha256(dest.read_bytes()).hexdigest()
(O/'before_hashes.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
for tag,args in [('full_props_before',['scripts/check_asset_registry.py','--project-root',str(P),'--scope','full','--ledger','props']),('structure_before',['scripts/check_asset_registry.py','--project-root',str(P),'--scope','structure']),('split_before',['tools/asset_pipeline/verify_ledger_split.py','--project-root',str(P)]),('naming_before',['scripts/check_asset_runtime_naming.py','--json']),('docs_before',['scripts/check_documentation_contracts.py'])]:
    r=subprocess.run([sys.executable,'-I',str(P/args[0]),*args[1:]],cwd=P,capture_output=True)
    (O/(tag+'.log')).write_bytes(r.stdout+r.stderr)
    print(tag,r.returncode)
im=Image.open(P/paths[2]).convert('RGB')
print('PALETTE_ROWS_FROM_BOTTOM',json.dumps([[im.getpixel((int((x+.5)*51.2),int((9-y+.5)*51.2))) for x in range(10)] for y in range(10)]))
