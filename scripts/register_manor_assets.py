"""Surgical ledger registration for the newly authored manor component batch.

Uses the user-invoked domain skill's openpyxl workflow and official formula helpers.
Does not promote any component into an assembled game room.
"""
import json,hashlib,shutil,sys,re
from pathlib import Path
from copy import copy
from collections import Counter
from openpyxl import load_workbook
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'));sys.path.insert(0,str(ROOT/'tools/asset_pipeline'))
from ledger_registry import LedgerIndex
from split_asset_ledger import FIRST_DATA_ROW,HEADER_ROW,ASSET_SHEET,CONTENT_COLUMNS,read_source_rows,_row_digest,col_digest,sheet_digest,dedupe_key_formula,dedupe_result_formula,rescope_asset_sheet
S=ROOT/'art_source/environments/tower_zones/expedition/source/common_components/v017'
W=ROOT.parent/'ShellStorm2-work/manor_v017';backup=W/'ledger_backup';backup.mkdir(exist_ok=True)
index=LedgerIndex.load(ROOT);ledger=index.path_for_category('场景');base=ROOT/'assets/registry/ledger_split_baseline.json'
C=json.loads((S/'component_catalog.json').read_text(encoding='utf-8'))['components']
ids={e['component_id'] for e in C}
for p in [ledger,base]:
 dst=backup/p.name
 if not dst.exists():shutil.copy2(p,dst)
wb=load_workbook(ledger);ws=wb[ASSET_SHEET]
existing=read_source_rows(ws);oldrows={str(v[0]):(r,v) for r,v in existing}
assert not ids.intersection(oldrows),'Batch already registered; do not append twice'
# Freeze existing cells, including domain views, for the post-write conservation audit.
oldviews={name:{(c.row,c.column):c.value for row in wb[name] for c in row if c.value is not None} for name in index.domain_for_key('scenes').sheet_scope}
oldlast=ws.max_row;newlast=oldlast+len(C)
for offset,e in enumerate(C,1):
 r=oldlast+offset;path=ROOT/e['prefab_path'];assert path.is_file()
 spec='Blender XYZ '+ '×'.join(str(x) for x in e['bounds_size_m'])+' m；墙高2.8m；5m结构模数；PaletteUV/四材质'
 vals=[e['component_id'],e['name_zh'],'场景','environment_module_3d',e['slug'],'root_3d',None,'Top3D / +Z Godot','default / independent_prefab','远征03复古公馆；COMMON_ROOM/SAFE_ROOM；独立组件未装配','已导入；优化完成','P1','v017',spec,e['prefab_path'],'docs/v0.1/design/远征03复古公馆组件制作规范.md',e['slug']+';复古公馆;2.8m;模块化;未场景拼装',dedupe_key_formula(r),dedupe_result_formula(r,newlast),hashlib.sha256(path.read_bytes()).hexdigest(),'Codex','2026-10-31','用户提供参考；本项目原创网格',e['component_id'],'源与独立优化文件见每包manifest；未接入正式房间；家具为visual_only，不隐式改玩法碰撞。']
 for col,value in enumerate(vals,1):ws.cell(r,col,value)._style=copy(ws.cell(oldlast,col)._style)
 ws.row_dimensions[r].height=ws.row_dimensions[oldlast].height
rescope_asset_sheet(ws,len(read_source_rows(ws)))
for row in wb['总览']:
 for cell in row:
  if cell.data_type=='f' and '资产主表' in str(cell.value):cell.value=re.sub(r'\$'+str(oldlast)+r'\b','$'+str(newlast),cell.value)
log=wb['域变更日志'];prev=str(log.cell(log.max_row,1).value or 'v0.1.0');version=prev.rsplit('.',1)[0]+'.'+str(int(prev.rsplit('.',1)[-1])+1)
log.append([version,'2026-10-31','新增组件','scenes / expedition_03','新增40件复古公馆组件；墙高2.8m、5m结构模数，同族不超3；独立优化并导入。','仅资产制作与导入，未装配正式房间。源哈希保护、优化与验证证据见v017/QA。','Codex'])
# Register real Prefabs on their semantic pages in a separate, audited transaction.
for e in C:
 page='3D-场景通用' if e['category']=='architecture' or e['component_family']=='door' else ('3D-设施' if e['component_family'] in ['lamp','bathtub','vanity','toilet','mirror','towel_rail'] else '3D-其他')
 pws=wb[page];row=pws.max_row+1;template=max(HEADER_ROW,pws.max_row)
 vals=[e['component_id'],e['name_zh'],e['prefab_path'],e['visual_glb'],e['component_blend'],'复古公馆独立组件；未正式房间装配','', '开' if e['collision_shape_count'] else '关','godot_wrapper',e['collision_policy'],'×'.join(str(x) for x in e['bounds_size_m'])+' m (Blender XYZ)','底面中心；XY/+Z → XZ/+Y；正面+Z','远征03 可选组件库','已导入；优化完成','v017','原始母版及优化文件见每包manifest；仅建筑核心有碰撞，门墙2个门垛留净空。']
 for col,value in enumerate(vals,1):pws.cell(row,col,value)._style=copy(pws.cell(template,col)._style)
wb.save(ledger)
after=load_workbook(ledger)
for aid,(r,v) in oldrows.items():
 for col in CONTENT_COLUMNS:assert after[ASSET_SHEET].cell(r,col).value==v[col-1],(aid,col)
for page,cells in oldviews.items():
 for (r,col),value in cells.items():assert after[page].cell(r,col).value==value,(page,r,col)
baseline=json.loads(base.read_text(encoding='utf-8'));oldassets=dict(baseline['assets'])
for r,v in read_source_rows(after[ASSET_SHEET]):
 if str(v[0]) in ids:baseline['assets'][str(v[0])]={'v':_row_digest(v),'c':'场景','d':'scenes'}
for aid,value in oldassets.items():assert baseline['assets'][aid]==value
union=[]
for domain in index.domains:
 book=after if domain.key=='scenes' else load_workbook(domain.path)
 union.extend(read_source_rows(book[ASSET_SHEET]))
baseline['asset_count']=len(baseline['assets']);baseline['category_counts']=dict(sorted(Counter(str(v[2]) for _,v in union).items()));baseline['column_digests']={str(c):col_digest(union,c) for c in CONTENT_COLUMNS}
for page in oldviews:baseline['sheet_digests'][page]=sheet_digest(after[page])
base.write_text(json.dumps(baseline,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
# Confirm XML formula and validation ranges after the zip round trip.
import zipfile
with zipfile.ZipFile(ledger) as z:
 xml=''.join(z.read(n).decode() for n in z.namelist() if n.startswith('xl/worksheets/sheet') and n.endswith('.xml'))
 assert f'C6:C{newlast}' in xml and f'K6:K{newlast}' in xml and f'L6:L{newlast}' in xml
 assert '<f>=LOWER' not in xml
(W/'ledger_registration.json').write_text(json.dumps(dict(added=len(C),first_row=oldlast+1,last_row=newlast,existing_content_unchanged=True,existing_prefab_cells_unchanged=True,baseline_existing_assets_unchanged=True),indent=2),encoding='utf-8')
print('MANOR_LEDGER_REGISTERED',len(C),oldlast+1,newlast)
