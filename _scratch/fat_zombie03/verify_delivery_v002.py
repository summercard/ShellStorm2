import subprocess,sys,json,re
from pathlib import Path
p=Path(__file__).parent;root=p.parents[1];results={}
commands={
 'ledger_structure':['scripts/check_asset_registry.py','--scope','structure'],
 'ledger_full':['scripts/check_asset_registry.py','--scope','full','--ledger','enemies','--json-output',str(p/'ledger_after_v002.json')],
 'ledger_split':['tools/asset_pipeline/verify_ledger_split.py'],
 'asset_guard':['scripts/asset_guard.py','assets/art/enemies/normal_enemy_3d/fat_zombie03','--classify','version_increment'],
 'runtime_naming':['scripts/check_asset_runtime_naming.py'],
 'documentation':['scripts/check_documentation_contracts.py'],
}
for name,args in commands.items():
 r=subprocess.run([sys.executable,*args],cwd=root,capture_output=True)
 stdout=r.stdout.decode('utf-8',errors='replace');stderr=r.stderr.decode('utf-8',errors='replace')
 (p/f'{name}_v002.log').write_text(stdout+stderr,encoding='utf-8');results[name]={'exit_code':r.returncode}
 print(name,'exit',r.returncode,flush=True)
before=json.loads((p/'ledger_before.json').read_text(encoding='utf-8'));after=json.loads((p/'ledger_after_v002.json').read_text(encoding='utf-8'));assert before['issues']==after['issues'];results['ledger_existing_issues_identical']=True
for name in ['ledger_structure','ledger_split','asset_guard']:assert results[name]['exit_code']==0,name
doc=(root/'docs/v0.1/design/胖子僵尸03动作设计.md').read_text(encoding='utf-8');assert len(doc)<5000
for action in ['idle','walking','running','attack','hurt','dead','awaken','alert','turn_l','turn_r','move_start','move_stop','hit_light']:assert action in doc
audit=json.loads((p/'godot_audit_v002.json').read_text(encoding='utf-8'));assert audit['bones']==66 and not audit['missing_core'] and audit['textures']==[[512,512]] and audit['root_parent']==-1 and audit['hip_parent']=='Root'
results['design_chars']=len(doc);results['planned_actions']=13;results['godot_rig_texture_passed']=True
assert 'fat_zombie03' not in (p/'runtime_naming_v002.log').read_text(encoding='utf-8')
(p/'delivery_verification_v002.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print('FAT_ZOMBIE03_V002_DELIVERY_OK',json.dumps(results))
