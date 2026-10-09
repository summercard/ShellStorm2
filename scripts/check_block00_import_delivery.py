"""Run global gates independently and audit only this task's files/hashes."""
from pathlib import Path
import subprocess,json,os,sys,hashlib,concurrent.futures
R=Path(__file__).resolve().parents[1];O=R/'outputs/block00_story_rooms_20261009'
commands={'registry_structure':[sys.executable,'scripts/check_asset_registry.py','--scope','structure','--ledger','scenes'],'registry_full':[sys.executable,'scripts/check_asset_registry.py','--scope','full','--ledger','scenes'],'ledger_split':[sys.executable,'tools/asset_pipeline/verify_ledger_split.py','--project-root',str(R)],'documentation':[sys.executable,'scripts/check_documentation_contracts.py'],'runtime_naming':[sys.executable,'scripts/check_asset_runtime_naming.py','--json']}
def run(item):
 name,cmd=item;env=os.environ.copy();env['PYTHONUTF8']='1'
 with (O/('runtime_'+name+'.log')).open('w',encoding='utf8') as f:r=subprocess.run(cmd,cwd=R,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=180)
 return name,{'exit_code':r.returncode,'log':str(O/('runtime_'+name+'.log'))}
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:results=dict(pool.map(run,commands.items()))
P=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/export/v001/import_manifest.json';m=json.loads(P.read_text('utf8'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(Path(p))==h for p,h in m['protected_sources'].items())
for d in m['components']:
 for key,h in [('glb_path','glb_sha256'),('optimized_path','optimized_sha256'),('prefab_path','prefab_sha256')]:assert sha(R/d[key])==d[h],(d['slug'],key)
 assert 'v00' not in d['glb_path'] and 'v00' not in d['prefab_path']
for d in m['rooms']:assert sha(R/d['scene_path'])==d['scene_sha256']
text=(O/'runtime_registry_full.log').read_text('utf8');payload=json.JSONDecoder().raw_decode(text[text.index('{'):])[0]
target=set(m['registered_assets'])|{'ENV-BATTLE-FATHER-OFFICE-SOURCE','ENV-BATTLE-BLOCK00-STORY-ROOMS-SOURCE'}
issues=payload.get('issues',{});target_issues=[]
for key,values in issues.items():
 for v in values:
  if any(a in str(v) for a in target):target_issues.append([key,v])
results['scope_audit']={'source_unchanged':True,'all_optimized_glb_prefab_and_layout_hashes_match':True,'target_registry_issues':target_issues,'global_registry_issue_counts':payload.get('issue_counts',{})}
assert not target_issues,target_issues
(O/'runtime_gates.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(results,ensure_ascii=False,indent=2))
