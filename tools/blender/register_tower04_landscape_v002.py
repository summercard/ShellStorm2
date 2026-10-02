"""Promote the existing five landscape entries to v002 without appending assets."""
import json,sys,re,hashlib,shutil,os,subprocess
from pathlib import Path
from collections import Counter
from openpyxl import load_workbook
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'tools/asset_pipeline'))
from split_asset_ledger import FIRST_DATA_ROW,CONTENT_COLUMNS,read_source_rows,_row_digest,col_digest
VERSION=sys.argv[1] if len(sys.argv)>1 else 'v002';assert VERSION in ['v002','v003']
PREVIOUS='v002' if VERSION=='v003' else 'v001';DATE='2026-10-03' if VERSION=='v003' else '2026-10-02'
O=R/'assets/art/environments/open_world/source/landscape_tower04'/VERSION;Q=O/'qa'
cat=json.loads((O/'catalog.json').read_text(encoding='utf8'));old=json.loads((O.parent/PREVIOUS/'catalog.json').read_text(encoding='utf8'))
for n in ['source_audit','palette_validation','scope_lock']:assert json.loads((Q/f'{n}.json').read_text(encoding='utf8'))['passed']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(R/cat['source_blend'])==cat['source_sha256']
idx=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf8'));d=next(x for x in idx['domains'] if x['key']=='scenes')
p=R/idx['ledger_dir']/d['file'];base=R/'assets/registry/ledger_split_baseline.json'
backup=R.parent/('_scratch/landscape04_'+VERSION+'_ledger_backup');backup.mkdir(exist_ok=True)
before_hash={x:sha(x) for x in (p,base)}
for x in before_hash:
 assert not (backup/x.name).exists(),'Transaction already started'
 shutil.copy2(x,backup/x.name)
gate=subprocess.run([sys.executable,str(R/'scripts/check_asset_registry.py'),'--project-root',str(R),'--scope','full','--ledger','scenes'],capture_output=True,encoding='utf8',cwd=R/'tools')
(Q/'ledger_before.stdout.log').write_text(gate.stdout,encoding='utf8');(Q/'ledger_before.stderr.log').write_text(gate.stderr,encoding='utf8')
w=load_workbook(p);s=w['资产主表'];before={(r,c):s.cell(r,c).value for r in range(1,s.max_row+1) for c in range(1,26)}
other={n:tuple(tuple(row) for row in w[n].values) for n in w.sheetnames if n not in ['资产主表','域变更日志']};updated=set();entries=[]
for g in cat['groups']:
 r=next(r for r in range(FIRST_DATA_ROW,s.max_row+1) if s.cell(r,1).value==g['asset_id'])
 assert s.cell(r,13).value==PREVIOUS and s.cell(r,20).value==old['source_sha256']
 spec=f"{g['buildings']}栋；{g['instances']}实例；{g['triangles']}三角（与v001完全相同）；四层模块；中段缺角/楼板坍塌/纵向裂口；本组在建骨架楼{g['construction_buildings']}栋"
 if VERSION=='v003':spec+='；断柱倾斜、塌板下坠外突；仅顶点变形，拓扑不变'
 vals={2:'景观建筑 塔4周边 '+g['name'],13:VERSION,14:spec,15:cat['source_blend'],17:'景观建筑;塔4;SKYLINE同级;中段破损;在建骨架;低面数;藤蔓;倾斜断柱;塌板',20:cat['source_sha256'],22:DATE,25:f"{VERSION}中段破损与倾斜结构；第2组右楼和第4组整楼为在建梁柱骨架。Collection={g['collection']}。五个ID共用母版与SHA；保留前版。面数逐组不变、未改区锁定及空洞射线专项通过；用户视觉待复核。未导入Godot。"}
 for col,value in vals.items():s.cell(r,col,value);updated.add((r,col))
 entries.append({'asset_id':g['asset_id'],'row':r,'triangles':g['triangles']})
log=w['域变更日志'];m=re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)',str(log.cell(log.max_row,1).value));assert m
log.append([f'v{m[1]}.{m[2]}.{int(m[3])+1}',DATE,'五组景观建筑'+VERSION+'中段破损与倾斜结构','关卡场景 / 开放世界','LANDSCAPE04-01至05更新；中段破损、倾斜断柱与塌板；两栋纯骨架在建楼；五组面数完全不变','Blender源自检通过；用户视觉待复核；未导入Godot','Codex'])
candidate=backup/'candidate.xlsx';w.save(candidate);again=load_workbook(candidate)
assert all(again['资产主表'].cell(r,c).value==v for (r,c),v in before.items() if (r,c) not in updated)
assert all(tuple(tuple(row) for row in again[n].values)==v for n,v in other.items())
bl=json.loads(base.read_text(encoding='utf8'));prev=json.loads(json.dumps(bl['assets']));rv=dict(read_source_rows(again['资产主表']))
for e in entries:bl['assets'][e['asset_id']]['v']=_row_digest(rv[e['row']])
target_ids={e['asset_id'] for e in entries};assert all(bl['assets'][k]==v for k,v in prev.items() if k not in target_ids)
rows=[]
for d in idx['domains']:
 book=again if d['key']=='scenes' else load_workbook(R/idx['ledger_dir']/d['file']);rows.extend(read_source_rows(book['资产主表']))
bl['column_digests']={str(c):col_digest(rows,c) for c in CONTENT_COLUMNS};bl['category_counts']=dict(Counter(v[2] for _,v in rows))
bt=backup/'candidate_baseline.json';bt.write_text(json.dumps(bl,ensure_ascii=False,indent=1)+'\n',encoding='utf8')
assert all(sha(x)==v for x,v in before_hash.items()),'Concurrent ledger change'
os.replace(candidate,p);os.replace(bt,base)
(Q/'ledger_registration.json').write_text(json.dumps({'updated':entries,'unrelated_cells_unchanged':True,'other_sheets_unchanged':True,'source_sha256':cat['source_sha256'],'status':'Blender源已完成'},ensure_ascii=False,indent=2),encoding='utf8')
print(VERSION+'_LEDGER_UPDATED',entries)
