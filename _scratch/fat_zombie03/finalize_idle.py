import json,subprocess,sys
from pathlib import Path
p=Path(__file__).parent;root=p.parents[1];record='docs/v0.1/development/2026-10-03_fat_zombie03_idle.md'
f=root/'docs/v0.1/feature_registry.json';lines=f.read_text(encoding='utf-8').splitlines(keepends=True)
for i,line in enumerate(lines):
 if '"feature_id":"ENEMY-AI"' not in line and '"feature_id":"ASSET-PIPELINE"' not in line:continue
 data=json.loads(line.strip().rstrip(','))
 if record not in data['development_records']:data['development_records'].append(record)
 lines[i]='    '+json.dumps(data,ensure_ascii=False,separators=(',',':'))+',\n'
f.write_text(''.join(lines),encoding='utf-8')
f=root/'docs/v0.1/MODULE_INDEX.md';s=f.read_text(encoding='utf-8');s=s.replace('Action与状态绑定待制作，未投放；见[交付记录](development/2026-10-03_fat_zombie03_rig_and_action_design.md)。','idle已制作并验收、独立Prefab默认循环；其他12段及完整状态绑定待制作，未投放；见[待机交付](development/2026-10-03_fat_zombie03_idle.md)。');f.write_text(s,encoding='utf-8')
f=root/'docs/v0.1/development/CHANGELOG.md';s=f.read_text(encoding='utf-8');entry='- 2026-10-03：胖子僵尸03制作3.2秒idle待机，双母版骨架一致，两轮循环与Godot验证通过，独立Prefab默认循环播放；账本推进idle已验收、其余12段待制作。见[待机记录](2026-10-03_fat_zombie03_idle.md)。\n'
if entry not in s:f.write_text(s+'\n'+entry,encoding='utf-8')
commands={'structure':['scripts/check_asset_registry.py','--scope','structure'],'full':['scripts/check_asset_registry.py','--scope','full','--ledger','enemies','--json-output',str(p/'idle_ledger_after.json')],'split':['tools/asset_pipeline/verify_ledger_split.py'],'guard':['scripts/asset_guard.py','assets/art/enemies/normal_enemy_3d/fat_zombie03','--classify','version_increment'],'naming':['scripts/check_asset_runtime_naming.py'],'docs':['scripts/check_documentation_contracts.py']}
results={}
for name,args in commands.items():
 r=subprocess.run([sys.executable,*args],cwd=root,capture_output=True);results[name]=r.returncode;(p/f'idle_gate_{name}.log').write_text(r.stdout.decode('utf-8',errors='replace')+r.stderr.decode('utf-8',errors='replace'),encoding='utf-8');print(name,r.returncode,flush=True)
assert all(results[k]==0 for k in ['structure','split','guard'])
before=json.loads((p/'idle_ledger_before.json').read_text(encoding='utf-8'));after=json.loads((p/'idle_ledger_after.json').read_text(encoding='utf-8'))
def external(d):return {k:[v for v in rows if v.get('asset_id')!='ENM-NORMAL-FAT-ZOMBIE03'] for k,rows in d['issues'].items()}
assert external(before)==external(after)
assert not any(v.get('asset_id')=='ENM-NORMAL-FAT-ZOMBIE03' for rows in after['issues'].values() for v in rows)
results['other_ledger_issues_unchanged']=True
qa=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03/previews/idle_v001';(qa/'gates.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('FAT_ZOMBIE03_IDLE_DELIVERY_OK')
