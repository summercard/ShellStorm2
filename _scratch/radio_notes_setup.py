from pathlib import Path
import json, shutil, subprocess, hashlib
import openpyxl
R=Path('I:/工作项目/shellstrom2/ShellStorm2')
O=R/'outputs/base99_radio_music_notes'
O.mkdir(exist_ok=True)
(O/'.gdignore').write_bytes(b'')
(O/'testlogs').mkdir(exist_ok=True)
(O/'backup').mkdir(exist_ok=True)
paths=['src/base3d/Base99Radio3D.gd','tests/verification/verify_base99_radio.gd','assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn','assets/registry/ledgers/ShellStorm2_道具账本_v001.xlsx','assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx','assets/registry/ledger_split_baseline.json','docs/v0.1/14.6_特效系统与制作规范.md']
for p in paths:
    dst=O/'backup'/p
    dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(R/p,dst)
protected=['assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb','assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v005.blend','assets/art/props/base_world_3d/source/base99_radio/export/v005/prp_base99_radio_optimized_v005.blend','assets/art/environments/tower_zones/base/runtime/zone_base.tscn','assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn']
(O/'protected_before.json').write_text(json.dumps({p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in protected},indent=2),encoding='utf-8')
wb=openpyxl.load_workbook(R/'assets/registry/ShellStorm2_美术资产台账_v001.xlsx',data_only=False)
info={}
for name in ['分类与编码','命名与查重']:
    info[name]=[[c.value for c in row] for row in wb[name] if any(c.value is not None for c in row)]
for domain in ['道具','特效']:
    b=openpyxl.load_workbook(R/f'assets/registry/ledgers/ShellStorm2_{domain}账本_v001.xlsx')
    info[domain]={s:[[c.value for c in row] for row in b[s] if any(c.value is not None for c in row)] for s in ['资产主表','3D-'+domain,'总览','域变更日志']}
(O/'ledger_context.json').write_text(json.dumps(info,ensure_ascii=False,indent=2,default=str),encoding='utf-8')
print('SETUP_OK',O)
import sys
PY=sys.executable
gates={'structure':['scripts/check_asset_registry.py','--project-root',str(R),'--scope','structure'],'props':['scripts/check_asset_registry.py','--project-root',str(R),'--scope','full','--ledger','props'],'vfx':['scripts/check_asset_registry.py','--project-root',str(R),'--scope','full','--ledger','vfx'],'split':['tools/asset_pipeline/verify_ledger_split.py','--project-root',str(R)],'naming':['scripts/check_asset_runtime_naming.py','--json'],'docs':['scripts/check_documentation_contracts.py']}
result={}
for name,args in gates.items():
    args[0]=str(R/args[0])
    p=subprocess.run([PY,*args],cwd=str(R/'_scratch/ledger_gate_cwd'),capture_output=True)
    (O/f'testlogs/{name}_before.log').write_bytes(p.stdout+p.stderr)
    result[name]=p.returncode
(O/'testlogs/gates_before.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(result)
