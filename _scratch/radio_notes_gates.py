from pathlib import Path
import subprocess,sys,json,re,hashlib
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/base99_radio_music_notes'
for rel in ['docs/v0.1/MODULE_INDEX.md','docs/v0.1/14.6_特效系统与制作规范.md']:
 p=R/rel;p.write_bytes(p.read_bytes().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'))
gates={'structure':['scripts/check_asset_registry.py','--project-root',str(R),'--scope','structure'],'props':['scripts/check_asset_registry.py','--project-root',str(R),'--scope','full','--ledger','props'],'vfx':['scripts/check_asset_registry.py','--project-root',str(R),'--scope','full','--ledger','vfx'],'split':['tools/asset_pipeline/verify_ledger_split.py','--project-root',str(R)],'naming':['scripts/check_asset_runtime_naming.py','--json'],'docs':['scripts/check_documentation_contracts.py']}
result={}
for name,args in gates.items():
 args[0]=str(R/args[0]);p=subprocess.run([sys.executable,'-P',*args],cwd=R/'_scratch/ledger_gate_cwd',capture_output=True)
 (O/f'testlogs/{name}_after.log').write_bytes(p.stdout+p.stderr);result[name]=p.returncode
print(result)
(O/'testlogs/gates_after.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
