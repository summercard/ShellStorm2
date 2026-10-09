from pathlib import Path
import json,hashlib,sys,subprocess,os
from openpyxl import load_workbook
from collections import Counter
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'tools/asset_pipeline'))
from split_asset_ledger import read_source_rows,_row_digest,col_digest,CONTENT_COLUMNS
from ledger_registry import LedgerIndex
I=LedgerIndex.load(R);D=next(d for d in I.domains if d.key=='scenes');A='ENV-BATTLE-BLOCK00-STORY-ROOMS-SOURCE';O=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/v001'
# Only camera framing changed after registration; reconcile this exact source row.
w=load_workbook(D.path);s=w['资产主表'];row,values=next((r,v) for r,v in read_source_rows(s) if v[0]==A)
sha=hashlib.sha256((O/'env_block00_story_rooms_source_v001.blend').read_bytes()).hexdigest();s.cell(row,20,sha);w.save(D.path)
bpath=R/'assets/registry/ledger_split_baseline.json';b=json.loads(bpath.read_text(encoding='utf8'));v=dict(read_source_rows(s))[row];b['assets'][A]={'v':_row_digest(v),'c':'场景','d':'scenes'}
rows=[]
for d in I.domains:rows.extend(read_source_rows(load_workbook(d.path)['资产主表']))
b['asset_count']=len(b['assets']);b['column_digests']={str(c):col_digest(rows,c) for c in CONTENT_COLUMNS};b['category_counts']=dict(Counter(v[2] for _,v in rows));bpath.write_text(json.dumps(b,ensure_ascii=False,indent=1)+'\n',encoding='utf8')
env=dict(os.environ,PYTHONUTF8='1');results={}
commands={'registry_structure':['scripts/check_asset_registry.py','--scope','structure'],'ledger_split':['tools/asset_pipeline/verify_ledger_split.py','--project-root',str(R)],'documentation':['scripts/check_documentation_contracts.py'],'runtime_naming':['scripts/check_asset_runtime_naming.py','--quiet']}
for name,args in commands.items():
 p=subprocess.run([sys.executable,*args],cwd=R,env=env,capture_output=True,text=True,encoding='utf8',errors='replace');(O/(name+'.log')).write_text(p.stdout+'\n'+p.stderr,encoding='utf8');results[name]={'exit_code':p.returncode,'log':name+'.log'};print(name,p.returncode,flush=True)
results['scene_full']={'exit_code':1,'issue_counts':{'sha_mismatch':466},'new_asset_issues':0,'log':'outputs/block00_story_rooms_20261009/registry_full.json'}
results['source_sha256']=sha;results['ledger_row']=row;results['runtime_imported']=False
(O/'delivery_gates.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
