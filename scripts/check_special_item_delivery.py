"""Read-only aggregate gates with the configured Python for nested checks."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
from special_items_workspace import ROOT, work_path

GATES={
    'documentation':['scripts/check_documentation_contracts.py'],
    'traceability':['scripts/check_feature_traceability.py'],
    'media_domains':['scripts/check_media_asset_domains.py'],
    'asset_structure':['scripts/check_asset_registry.py','--scope','structure'],
    'props_full':['scripts/check_asset_registry.py','--scope','full','--ledger','props'],
    'ui_full':['scripts/check_asset_registry.py','--scope','full','--ledger','ui'],
    'vfx_full':['scripts/check_asset_registry.py','--scope','full','--ledger','vfx'],
    'audio_full':['scripts/check_asset_registry.py','--scope','full','--ledger','audio'],
    'ledger_split':['tools/asset_pipeline/verify_ledger_split.py'],
    'runtime_naming':['scripts/check_asset_runtime_naming.py'],
    'art_source_layout':['scripts/check_art_source_layout.py'],
}
def run(item):
    name,args=item
    if name=='documentation':
        # Its child gates say `python3`; resolve that to the same known runtime,
        # without changing the checked source or relying on Windows store aliases.
        wrapper="import runpy,subprocess,sys; original=subprocess.run\ndef invoke(args,*a,**k):\n if isinstance(args,list) and args and args[0] in ['python3','python']: args=[sys.executable,*args[1:]]\n return original(args,*a,**k)\nsubprocess.run=invoke\nrunpy.run_path(sys.argv[1],run_name='__main__')"
        command=[sys.executable,'-c',wrapper,*args]
    else:
        command=[sys.executable,*args]
    environment=os.environ.copy();environment['PYTHONIOENCODING']='utf-8'
    process=subprocess.run(command,cwd=ROOT,env=environment,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    output=process.stdout.decode('utf-8',errors='replace')
    path=work_path('sessions/2026-11-03_special_items/gates/'+name+'.log');path.write_text(output,encoding='utf-8')
    markers=[line for line in output.splitlines() if '_OK' in line or '_FAILED' in line or '_DRIFT' in line]
    result={'gate':name,'exit_code':process.returncode,'markers':markers[-4:],'log':str(path)}
    print(json.dumps(result,ensure_ascii=False),flush=True)
    return result
with ThreadPoolExecutor(max_workers=3) as executor:
    results=list(executor.map(run,GATES.items()))
work_path('sessions/2026-11-03_special_items/gate_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
