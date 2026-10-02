"""Atomic three-asset ledger transaction, preserving unrelated asset content."""
import sys,json,hashlib,shutil,re,os
from copy import copy
from pathlib import Path
from collections import Counter
from openpyxl import load_workbook
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'tools/asset_pipeline'))
from split_asset_ledger import FIRST_DATA_ROW,CONTENT_COLUMNS,read_source_rows,_row_digest,col_digest,dedupe_key_formula,dedupe_result_formula
T=R/'assets/art/environments/open_world/source/tower_04/v010';C=R/'assets/art/environments/open_world/source/tower_04_2/v002'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
tc=json.loads((T/'catalog.json').read_text(encoding='utf8'));fc=json.loads((T/'far_catalog.json').read_text(encoding='utf8'));nc=json.loads((C/'near_catalog.json').read_text(encoding='utf8'))
for folder,name in [(T,'final_structure_audit'),(T,'far_structure_audit'),(T,'palette_validation'),(T,'far_palette_validation'),(C,'near_structure_audit'),(C,'far_structure_audit'),(C,'near_palette_validation'),(C,'far_palette_validation')]:
 assert json.loads((folder/'qa'/f'{name}.json').read_text(encoding='utf8'))['passed'],name
for cat in (tc,fc,nc):assert sha(R/cat['source_blend'])==cat['source_sha256']
idx=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf8'));d=next(d for d in idx['domains'] if d['key']=='scenes');path=R/idx['ledger_dir']/d['file'];base=R/'assets/registry/ledger_split_baseline.json'
backup=R.parent/'_scratch/tower04_v010/ledger_backup';backup.mkdir(exist_ok=True)
start={p:sha(p) for p in (path,base)}
for p in start:
 assert not (backup/p.name).exists(),'Already registered; do not replay'
 shutil.copy2(p,backup/p.name)
w=load_workbook(path);s=w['资产主表'];oldlast=s.max_row
existing={s.cell(r,1).value:r for r in range(FIRST_DATA_ROW,oldlast+1)};row=existing['ENV-OPENWORLD-TOWER04'];assert s.cell(row,13).value=='v009'
assert sha(R/s.cell(row,15).value)==s.cell(row,20).value
for key in ('ENV-OPENWORLD-TOWER04-2','ENV-OPENWORLD-TOWER04-FAR'):assert key not in existing
before={(r,c):s.cell(r,c).value for r in range(1,oldlast+1) for c in range(1,26)}
original_sheets={a.title:tuple(tuple(c.value for c in r) for r in a) for a in w if a.title not in ('资产主表','域变更日志','总览')}
updates={2:'塔4 圆形屋面升层与旋梯商场',13:'v010',14:'主平台25m/圆形屋面30m；28级旋梯净宽2.1m；2051独立包/47组件定义；新增包XY≤8m',15:tc['source_blend'],16:'用户确认抬高顶部圆形屋面；docs/v0.1/design/tower04_ground_court.md',17:'塔4;圆形屋面;升层;旋转楼梯;末世商城;塔4-2',20:tc['source_sha256'],22:'2026-10-02',25:'以v009继续制作；圆形屋面及附着植物升高5m，补25–30m层窗墙、楼板、28级旋梯及平台。原连廊两段护栏在入口切开4m；3693范围外对象完整签名一致。制作方结构/UV/真实渲染复核通过；用户视觉待确认。塔4-2独立近景ENV-OPENWORLD-TOWER04-2，远景合景ENV-OPENWORLD-TOWER04-FAR。仅Blender源；未导入Godot、未做碰撞/导航/帧率验收。v009保留。'}
for c,v in updates.items():s.cell(row,c,v)
newrows=[]
for asset,name,logic,slot,version,cat,spec,note in [
 ('ENV-OPENWORLD-TOWER04-2','塔4-2 独立地面庭院近景','open_world_tower_04_2','court_source','v002',nc,'156×96m庭院；23种组件/1027实例；近景1188174三角；远景79435三角；组件XY≤8m','独立近景庭院：开裂铺地、积水池、柱下花园、透空廊架、低层店面、乔灌地被、排水与固定坐凳。near/far布局逐项一致。附同目录塔4-2_远景组件_v002.blend，合景由塔4远景源引用。v001为视觉试稿，v002为当前源。未导入Godot/碰撞/导航/帧率验收。'),
 ('ENV-OPENWORLD-TOWER04-FAR','塔4与塔4-2 远景优化合景','open_world_tower_04_far','distant_assembly_source','v010',fc,'塔4+塔4-2合景583247三角；分区独立组件；无隐藏高模；结构切片约10m以内','远景优化独立文件；塔楼503812三角+庭院79435三角，合计583247，低于60万预算。保留建筑轮廓、主要植被和地面色块；近景母版另存。不宣称已经达到引擎帧率目标；未导出GLB/PackedScene。')]:
  r=s.max_row+1
  vals=[asset,name,'场景','environment_kit_3d',logic,slot,None,'Top3D / Blender Z-up','default','开放世界塔4及下方庭院','Blender源已完成','P1',version,spec,cat['source_blend'],'docs/v0.1/design/tower04_ground_court.md','塔4;塔4-2;庭院;远近景;分区组件',None,None,cat['source_sha256'],'Codex','2026-10-02','用户提供参考图；本地程序建模，无第三方模型下载','TOWER04-2' if asset.endswith('-2') else 'TOWER04-FAR',note+' 制作方自检通过；用户视觉待确认。']
  for c,v in enumerate(vals,1):s.cell(r,c,v);s.cell(r,c)._style=copy(s.cell(row,c)._style)
  s.row_dimensions[r].height=s.row_dimensions[row].height;newrows.append(r)
last=s.max_row
for r in range(FIRST_DATA_ROW,last+1):s.cell(r,18,dedupe_key_formula(r));s.cell(r,19,dedupe_result_formula(r,last))
overview=w['总览']
for rows in overview:
 for cell in rows:
  if isinstance(cell.value,str) and cell.value.startswith('='):cell.value=re.sub(r'(\$[A-Z]+\$)'+str(oldlast)+r'\b',lambda m:m[1]+str(last),cell.value)
for dv in s.data_validations.dataValidation:
 spans=[]
 for rg in dv.sqref.ranges:
  text=str(rg)
  if rg.max_row==oldlast:text=re.sub(r'([A-Z]+)'+str(oldlast)+r'$',lambda m:m[1]+str(last),text)
  spans.append(text)
 dv.sqref=' '.join(spans)
if s.auto_filter.ref:s.auto_filter.ref=re.sub(r'(\D)'+str(oldlast)+r'$',lambda m:m[1]+str(last),s.auto_filter.ref)
log=w['域变更日志'];m=re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)',str(log.cell(log.max_row,1).value));assert m
log.append([f'v{m[1]}.{m[2]}.{int(m[3])+1}','2026-10-02','塔4屋面升层与塔4-2近远景','关卡场景 / 开放世界','ENV-OPENWORLD-TOWER04升为v010；新增ENV-OPENWORLD-TOWER04-2 v002与ENV-OPENWORLD-TOWER04-FAR v010','Blender制作方验收通过；用户视觉待确认；未导入运行时','Codex'])
assert all(sha(p)==h for p,h in start.items()),'Concurrent ledger change'
temp=backup/'new_scene_ledger.xlsx';w.save(temp);again=load_workbook(temp);ss=again['资产主表']
for (r,c),v in before.items():
 if (r==row and c in updates) or (c==19 and r>=FIRST_DATA_ROW):continue
 assert ss.cell(r,c).value==v,('Unrelated cell',r,c)
for name,values in original_sheets.items():assert tuple(tuple(c.value for c in r) for r in again[name])==values
assert all(str(ss.cell(r,18).value).startswith('=LOWER') for r in range(FIRST_DATA_ROW,last+1))
os.replace(temp,path)
bl=json.loads(base.read_text(encoding='utf8'));prior=dict(bl['assets']);changed_ids=[]
for r in [row]+newrows:
 values=dict(read_source_rows(ss))[r];asset=ss.cell(r,1).value;bl['assets'][asset]={'v':_row_digest(values),'c':'场景','d':'scenes'};changed_ids.append(asset)
bl['asset_count']=len(bl['assets']);all_rows=[]
for dom in idx['domains']:all_rows.extend(read_source_rows(load_workbook(R/idx['ledger_dir']/dom['file'])['资产主表']))
bl['column_digests']={str(c):col_digest(all_rows,c) for c in CONTENT_COLUMNS};bl['category_counts']=dict(Counter(v[2] for _,v in all_rows))
assert all(bl['assets'][k]==v for k,v in prior.items() if k not in changed_ids);assert sha(base)==start[base]
base.write_text(json.dumps(bl,ensure_ascii=False,indent=1)+'\n',encoding='utf8')
report=dict(registered=True,asset_ids=changed_ids,rows=[row]+newrows,ledger=path.relative_to(R).as_posix(),backup=str(backup),unrelated_asset_content_preserved=True,prefab_sheets_unchanged=True,old_last_row=oldlast,new_last_row=last,formula_ranges_extended=True,user_visual_confirmation='pending')
for folder in (T,C):(folder/'qa/ledger_registration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
