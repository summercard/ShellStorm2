"""Register eight source-only assets, preserve every unrelated ledger cell and baseline."""
import sys,json,hashlib,shutil,re
from pathlib import Path
from datetime import datetime
from copy import copy,deepcopy
from collections import Counter
import openpyxl
from openpyxl.worksheet.cell_range import MultiCellRange
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'tools/asset_pipeline')]
from workspace_paths import work_path
from ledger_registry import LedgerIndex
from split_asset_ledger import read_source_rows,dedupe_key_formula,dedupe_result_formula,_row_digest,CONTENT_COLUMNS,col_digest,FIRST_DATA_ROW,HEADER_ROW
OUT=work_path('items_reference_20261014/ledger/transaction.json').parent
INDEX=LedgerIndex.load(ROOT)
BASE=ROOT/'assets/registry/ledger_split_baseline.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2,default=str)+'\n',encoding='utf8')
def cells(w):return {(s.title,c.coordinate):c.value for s in w for row in s for c in row if c.value is not None}
contracts=[]
for domain in ['props','weapons']:
 for p in (ROOT/'art_source/items_weapons'/domain).glob('*/asset_contract.json'):
  c=json.loads(p.read_text('utf8'))
  if c.get('dimension_basis',{}).get('snapshot_date')=='2026-10-14':contracts.append(c)
assert len(contracts)==8
accept=json.loads(work_path('items_reference_20261014/validation.json').read_text('utf8'));assert accept['passed']
bl=json.loads(BASE.read_text('utf8'));oldbl=deepcopy(bl)
shutil.copy2(BASE,OUT/'baseline_before.json')
books={d.key:openpyxl.load_workbook(d.path) for d in INDEX.domains}
changes={};asset_locations={}
all_old={v[0]:(d.key,r,v) for d in INDEX.domains for r,v in read_source_rows(books[d.key]['资产主表'])}
for domain in ['props','weapons']:
 d=INDEX.domain_for_key(domain);wb=books[domain];before=cells(wb);shutil.copy2(d.path,OUT/d.path.name)
 w=wb['资产主表'];old_last=max(r for r,v in read_source_rows(w));targets=[c for c in contracts if c['category']==('道具' if domain=='props' else '武器')]
 for c in targets:
  aid=c['asset_id'];known=[(r,v) for r,v in read_source_rows(w) if v[0]==aid]
  if known:r=known[0][0]
  else:
   assert aid not in all_old
   assert not any(v[4]==c['logical_id'] for _,v in read_source_rows(w))
   r=max(r for r,v in read_source_rows(w))+1
   for k in range(1,26):w.cell(r,k)._style=copy(w.cell(6,k)._style)
   w.row_dimensions[r].height=90
  dims=c['dimensions_m'];size=f"{dims['width']:.4f}×{dims['depth']:.4f}×{dims['height']:.4f}m"
  note='2026-10-14 用户参考图制作；Godot物品工厂/拾取实体/配件挂点实测后冻结主轴尺寸，其余轴按图等比。仅Blender原始源；未导出GLB、未导入Godot；运行时仍用现有占位。'
  if c['glass_note']:note+=' '+c['glass_note']
  fields={1:aid,2:c['display_name_zh'],3:c['category'],4:c['subclass'],5:c['logical_id'],6:'root',8:c['origin_and_facing'],9:'tier_0_static',10:'独立物品/配件原始源；后续拾取、库存与武器装配复用',11:'Blender源已完成',12:'P1' if domain=='props' else w.cell(r,12).value or 'P2',13:'v001',14:size+'；单位米；根缩放1；场景四材质/公共色盘/PaletteUV；实测快照见asset_contract.json',15:c['source_blend'],16:'src/world3d/ItemModelFactory3D.gd; src/world3d/GroundLootPickup3D.gd; src/combat3d/WeaponModel3D.gd; '+str(Path(c['source_dir']).parent/'asset_contract.json').replace('\\','/'),17:c['logical_id']+';'+c['display_name_zh'],20:sha(ROOT/c['source_blend']),21:'Codex',22:datetime(2026,10,14),23:'用户提供参考图重建；项目公共色盘',24:c['source_collection'],25:note}
  for k,v in fields.items():w.cell(r,k).value=v
  asset_locations[c['logical_id']]=(aid,d.path.relative_to(ROOT).as_posix()+'#资产主表!A'+str(r),c['source_blend'])
 new_last=max(r for r,v in read_source_rows(w))
 for r,_ in read_source_rows(w):w.cell(r,18).value=dedupe_key_formula(r);w.cell(r,19).value=dedupe_result_formula(r,new_last)
 if old_last!=new_last:
  for a in ['A6','C6','E6','G6','B10','C10','B11','C11']:
   cell=wb['总览'][a];assert isinstance(cell.value,str) and f'${old_last}' in cell.value
   cell.value=cell.value.replace(f'${old_last}',f'${new_last}')
  for dv in w.data_validations.dataValidation:
   ranges=[]
   for rr in dv.sqref.ranges:
    rr=copy(rr)
    if rr.min_row==FIRST_DATA_ROW:rr.max_row=new_last
    ranges.append(str(rr))
   dv.sqref=MultiCellRange(' '.join(ranges))
  w.auto_filter.ref=f'A{HEADER_ROW}:Y{new_last}'
 log=wb['域变更日志'];r=log.max_row+1
 versions=[int(str(row[0].value).split('.')[-1]) for row in log if re.fullmatch(r'v0\.1\.\d+',str(row[0].value))]
 vals=[f'v0.1.{max(versions or [0])+1}','2026-10-14','参考图8件道具：Blender原始源','道具与武器原始源',','.join(c['asset_id'] for c in targets),'实测尺寸/场景四材质/源已完成；未运行时接入','Codex']
 for k,v in enumerate(vals,1):log.cell(r,k)._style=copy(log.cell(r-1,k)._style);log.cell(r,k).value=v
 for r,v in read_source_rows(w):
  if v[0] in {c['asset_id'] for c in targets}:bl['assets'][v[0]]={'v':_row_digest(v),'c':v[2],'d':domain}
 changed=[(s,a,str(before.get((s,a))),str(v)) for (s,a),v in cells(wb).items() if before.get((s,a))!=v]
 assert all(s in ['资产主表','总览','域变更日志'] for s,a,_,_ in changed)
 changes[domain]=changed
 # Preserve all historical non-target content, including 3D Prefab pages.
 target_ids={c['asset_id'] for c in targets}
 for r,v in read_source_rows(w):
  if v[0] not in target_ids:
   old=all_old[v[0]][2];assert all(v[i]==old[i] for i in range(25) if i not in [17,18])

# Content navigation: only references and source progress, current runtime appearance remains explicit.
navpath=ROOT/'assets/registry/ledgers/ShellStorm2_物品道具账本_v001.xlsx'
nav=openpyxl.load_workbook(navpath);shutil.copy2(navpath,OUT/navpath.name)
for wb,sheet in [(nav,'物品道具'),(books['weapons'],'背包物品调用索引')]:
 ws=wb[sheet]
 for row in ws:
  logical=str(row[0].value)
  if logical not in asset_locations:continue
  aid,ref,source=asset_locations[logical];r=row[0].row
  ws.cell(r,14).value=aid;ws.cell(r,15).value=ref
  note=str(ws.cell(r,17).value or '')
  note=note.replace('；无对应资产主表登记；未虚构AssetID','').replace('；无对应资产主表登记；未编造AssetID','')
  ws.cell(r,17).value=note+'；2026-10-14 Blender源已完成（未导入运行时）：'+source
bl['asset_count']=len(bl['assets'])
union=[rv for wb in books.values() for rv in read_source_rows(wb['资产主表'])]
bl['column_digests']={str(c):col_digest(union,c) for c in CONTENT_COLUMNS}
bl['category_counts']=dict(sorted(Counter(v[2] for _,v in union).items()))
target_ids={c['asset_id'] for c in contracts}
assert all(bl['assets'][k]==v for k,v in oldbl['assets'].items() if k not in target_ids)
assert bl['sheet_digests']==oldbl['sheet_digests']
for domain in ['props','weapons']:books[domain].save(INDEX.domain_for_key(domain).path)
nav.save(navpath)
BASE.write_text(json.dumps(bl,ensure_ascii=False,indent=1)+'\n',encoding='utf8')
# Current source index appends only this batch.
indexpath=ROOT/'assets/registry/current_source_index.json';shutil.copy2(indexpath,OUT/'current_source_index_before.json')
idx=json.loads(indexpath.read_text('utf8'))
for c in contracts:
 p=ROOT/c['source_blend'];assert p.exists()
 assert not any(s['path']==c['source_blend'] for s in idx['sources'])
 idx['sources'].append({'path':c['source_blend'],'bytes':p.stat().st_size,'family':c['source_blend'].replace('_v001',''),'version':[1],'role':'source','sha256':sha(p)})
write(indexpath,idx)
write(OUT/'transaction.json',{'assets':list(target_ids),'changed_cells':changes,'unrelated_baseline_fingerprints_preserved':True,'prefab_sheet_digests_preserved':True,'navigation_updated':['物品道具','背包物品调用索引']})
print('REFERENCE_ITEMS_LEDGER_UPDATED',len(contracts))
