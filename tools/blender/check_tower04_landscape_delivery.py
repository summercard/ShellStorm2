"""Capture independent gate exit codes and compare pre-existing ledger issues."""
import json,sys,subprocess,hashlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
R=Path(__file__).resolve().parents[2];VERSION=sys.argv[1] if len(sys.argv)>1 else 'v001';assert VERSION in ['v001','v002','v003']
O=R/'assets/art/environments/open_world/source/landscape_tower04'/VERSION;Q=O/'qa'
commands={
 'ledger_full':[str(R/'scripts/check_asset_registry.py'),'--project-root',str(R),'--scope','full','--ledger','scenes'],
 'ledger_structure':[str(R/'scripts/check_asset_registry.py'),'--project-root',str(R),'--scope','structure'],
 'ledger_split':[str(R/'tools/asset_pipeline/verify_ledger_split.py'),'--project-root',str(R)],
 'runtime_naming':[str(R/'scripts/check_asset_runtime_naming.py')],
 # The documentation gate hardcodes python3; make its children use this same installed interpreter.
 'documentation':['-c',"import subprocess,sys,runpy; original=subprocess.run; subprocess.run=lambda args,*a,**k:original([sys.executable,*args[1:]] if isinstance(args,list) and args[0]=='python3' else args,*a,**k); runpy.run_path(sys.argv[1],run_name='__main__')",str(R/'scripts/check_documentation_contracts.py')]
}
def run(item):
 k,args=item;p=subprocess.run([sys.executable,*args],cwd=R/'tools',capture_output=True,encoding='utf8',errors='replace')
 (Q/(k+'.stdout.log')).write_text(p.stdout,encoding='utf8');(Q/(k+'.stderr.log')).write_text(p.stderr,encoding='utf8')
 return k,{'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
res=dict(ThreadPoolExecutor(max_workers=4).map(run,commands.items()))
decoder=json.JSONDecoder();before_path=Q/'ledger_before.stdout.log' if VERSION!='v001' else R.parent/'_scratch/landscape04_ledger_before.log'
before=decoder.raw_decode(before_path.read_text(encoding='utf8'))[0];after=decoder.raw_decode(res['ledger_full']['stdout'])[0]
same=before['issues']==after['issues'] and before['issue_counts']==after['issue_counts']
assert same, 'New full-ledger issues'
assert res['ledger_structure']['exit_code']==res['ledger_split']['exit_code']==0
doc=json.loads(res['documentation']['stdout']);cat=json.loads((O/'catalog.json').read_text(encoding='utf8'))
assert hashlib.sha256((R/cat['source_blend']).read_bytes()).hexdigest()==cat['source_sha256']
report={'checks':{k:{'exit_code':v['exit_code']} for k,v in res.items()},'full_ledger_issues_unchanged':same,'preexisting_full_ledger_issue_counts':after['issue_counts'],'documentation_issues':doc['issues'],'new_asset_issues':[],'source_audit_passed':json.loads((Q/'source_audit.json').read_text(encoding='utf8'))['passed'],'palette_validation_passed':json.loads((Q/'palette_validation.json').read_text(encoding='utf8'))['passed'],'source_sha256':cat['source_sha256'],'runtime_imported':False}
(Q/'delivery_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
