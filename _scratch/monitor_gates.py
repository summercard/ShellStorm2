import subprocess,json,os,concurrent.futures
from pathlib import Path
R=Path.cwd();D=R/'assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/gates';D.mkdir(exist_ok=True)
commands={
 'asset_registry_structure':['python','scripts/check_asset_registry.py','--ledger','enemies','--scope','structure'],
 'asset_registry_full':['python','scripts/check_asset_registry.py','--ledger','enemies','--scope','full','--json-output',str(D/'asset_registry_full.json')],
 'ledger_split':['python','tools/asset_pipeline/verify_ledger_split.py','--json-output',str(D/'ledger_split.json')],
 'runtime_naming':['python','scripts/check_asset_runtime_naming.py','--json'],
 'ledger_refs':['python','scripts/check_ledger_refs.py','--json-output',str(D/'ledger_refs.json')],
 'verification_registry':['python','scripts/check_verification_registry.py'],
 'documentation_contracts':['python','scripts/check_documentation_contracts.py'],
}
def run(item):
 name,args=item;env=os.environ.copy();env['PYTHONIOENCODING']='utf-8';env['PYTHONUTF8']='1'
 try:
  r=subprocess.run(args,cwd=R,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240 if name=='ledger_refs' else 60,creationflags=subprocess.CREATE_NO_WINDOW)
  (D/(name+'.log')).write_bytes(r.stdout);result={'exit_code':r.returncode,'command':args}
 except subprocess.TimeoutExpired as exc:
  (D/(name+'.log')).write_bytes(exc.stdout or b'');result={'exit_code':124,'command':args}
 print(name,result['exit_code'],flush=True);return name,result
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=dict(pool.map(run,commands.items()))
(D/'summary.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
