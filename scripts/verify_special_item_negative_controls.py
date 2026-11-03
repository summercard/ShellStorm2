"""Pin five-second promises by deliberately shortening both catalog durations.

Always restore bytes in finally. Expected red results are separate from green runs.
"""
import json
import os
import subprocess
import sys
from special_items_workspace import ROOT, work_path
path=ROOT/'data/special_items/catalog.json'
original=path.read_bytes()
base=work_path('sessions/2026-11-03_special_items/negative_controls.json').parent
try:
    data=json.loads(original)
    for item in data['items']:
        if item['id'] in ['special_molotov','special_gasoline']:
            item['duration']=4.0
    path.write_bytes((json.dumps(data,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))
    subprocess.run([sys.executable,'scripts/verify_special_items.py','verify_special_items_system'],cwd=ROOT,check=False)
    result=json.loads((base/'verify_special_items_system.result.json').read_text(encoding='utf-8'))
    expected=['ignited oil has an independently pinned five-second lifetime','molotov lifetime independently remains five seconds']
    matched=[text for text in expected if any(text in error for error in result['errors'])]
    result['control']='duration 5 -> 4 seconds'
    result['expected_failures_observed']=matched
    (base/'negative_controls.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (base/'negative_controls.log').write_bytes((base/'verify_special_items_system.log').read_bytes())
    if result['exit_code']!=1 or len(matched)!=2:
        raise RuntimeError('Negative control did not fail on both promises')
    print('SPECIAL_ITEM_NEGATIVE_CONTROLS_OK: both independently pinned duration assertions turn red')
finally:
    path.write_bytes(original)
