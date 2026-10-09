from pathlib import Path
from copy import copy
import hashlib, json, shutil, sys
from datetime import date
from openpyxl import load_workbook
sys.path.insert(0, str(Path(r'I:/工作项目/shellstrom2/ShellStorm2/tools/asset_pipeline')))
sys.path.insert(0, str(Path(r'I:/工作项目/shellstrom2/ShellStorm2/scripts')))
from split_asset_ledger import dedupe_key_formula, dedupe_result_formula, FIRST_DATA_ROW, HEADER_ROW, COLUMN_COUNT, CONTENT_COLUMNS, _row_digest, col_digest, read_source_rows, sheet_digest
from ledger_registry import LedgerIndex

R=Path(r'I:/工作项目/shellstrom2/ShellStorm2')
ledger=R/'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx'
baseline=R/'assets/registry/ledger_split_baseline.json'
backup=ledger.with_name(ledger.name+'.bak_mobile_landmark_hotel_50m')
shutil.copy2(ledger, backup)
wb=load_workbook(ledger)
main=wb['资产主表']; new=main.max_row+1
# ensure append after last populated row, not a styled blank row
while new>FIRST_DATA_ROW and main.cell(new-1,1).value in (None,''): new-=1
assert main.cell(new-1,1).value, new
new=main.max_row+1 if main.cell(main.max_row,1).value else new
# copy style from prior populated row
for c in range(1,COLUMN_COUNT+1): main.cell(new,c)._style=copy(main.cell(new-1,c)._style)
main.row_dimensions[new].height=main.row_dimensions[new-1].height
asset='ENV-MOBILE-LANDMARK-HOTEL-50M'
source='assets/art/environments/mobile_landmark_3d/source/env_mobile_landmark_hotel_50m/env_mobile_landmark_hotel_50m_source_v001.blend'
glb='assets/art/environments/mobile_landmark_3d/components/env_mobile_landmark_hotel_50m/env_mobile_landmark_hotel_50m_visual_top3d.glb'
runtime='assets/art/environments/mobile_landmark_3d/runtime/env_mobile_landmark_hotel_50m/env_mobile_landmark_hotel_50m_root_top3d.tscn'
values={1:asset,2:'50×50移动景观建筑·高层酒店塔楼',3:'场景',4:'environment_module_3d',5:'mobile_landmark_hotel_50m',6:'root',7:'',8:'Top3D / Godot Y-up',9:'无',10:'移动景观建筑；可复用50×50m地标包',11:'Blender源已完成',12:'P1',13:'v001',14:'包络50×50×97m；目标约8000面；实测8412面；4共享材质；PaletteUV；底面Z=0；XY中心原点',15:runtime,16:source+'; assets/art/environments/mobile_landmark_3d/source/env_mobile_landmark_hotel_50m/asset_manifest.json',17:'酒店塔楼；移动景观建筑；50米网格；高层地标；屋顶设备',20:hashlib.sha256((R/glb).read_bytes()).hexdigest(),21:'摩斯拉',22:'2026-10-09',23:'用户参考图 Clipboard_Screenshot.png；项目公共色盘',24:'mobile_landmark_hotel_50m_中文资产管理 / 02_游戏输出_独立资产包_v001',25:'源文件与GLB已生成；Godot运行场景已建立；碰撞由运行时包装后续补齐'}
for c,v in values.items(): main.cell(new,c).value=v
main.cell(new,18).value=dedupe_key_formula(new); main.cell(new,19).value=dedupe_result_formula(new,new)
for r in range(FIRST_DATA_ROW,new+1):
 main.cell(r,18).value=dedupe_key_formula(r); main.cell(r,19).value=dedupe_result_formula(r,new)
# extend overview formula references ending at old row
for ws in wb.worksheets:
 for row in ws.iter_rows():
  for cell in row:
   if isinstance(cell.value,str) and cell.value.startswith('='):
    cell.value=cell.value.replace('$836','$%d'%new).replace('836',str(new)) if ws.title=='总览' else cell.value
 # extend data validation ranges only when they end in old main row
 for dv in list(ws.data_validations.dataValidation):
  for rng in list(dv.sqref.ranges):
   txt=str(rng)
   if txt.endswith('836'): txt=txt[:-3]+str(new)
   if txt.endswith('C836'): txt=txt[:-4]+'C'+str(new)
   if txt.endswith('K836'): txt=txt[:-4]+'K'+str(new)
   if txt.endswith('L836'): txt=txt[:-4]+'L'+str(new)
   # openpyxl range objects are immutable; rebuild sqref as string after all
  # easiest preserve existing and add the new cells to the same validation
  for col in ('C','K','L'):
   if any(str(r).startswith(col+'6:') for r in dv.sqref.ranges): dv.add(f'{col}{new}')
# 3D prefab row
pref=wb['3D-场景通用']; prow=pref.max_row+1
for c in range(1,pref.max_column+1): pref.cell(prow,c)._style=copy(pref.cell(prow-1,c)._style)
pref.row_dimensions[prow].height=pref.row_dimensions[prow-1].height
pvals=[asset,'50×50移动景观建筑·高层酒店塔楼',runtime,glb,source,'可移动景观建筑地标包；参考图为高层酒店式塔楼；视觉资产独立输出，碰撞由Godot运行时包装负责','src/world3d/DungeonRoom3D.gd','开','外部脚本','BoxShape3D分区待补','50×50×97m；视觉8412面；4材质；公共色盘；PaletteUV','xy_center_bottom_z0；Godot -Z','Blender源已完成','P1','v001','ENV-MOBILE-LANDMARK-HOTEL-50M']
for c,v in enumerate(pvals,1): pref.cell(prow,c).value=v
# log
log=wb['域变更日志']; lr=log.max_row+1
for c in range(1,log.max_column+1): log.cell(lr,c)._style=copy(log.cell(lr-1,c)._style)
log.cell(lr,1).value='v0.1.23'; log.cell(lr,2).value='2026-10-09'; log.cell(lr,3).value='新条目'; log.cell(lr,4).value='移动景观建筑'; log.cell(lr,5).value='新增 ENV-MOBILE-LANDMARK-HOTEL-50M：按参考图制作50×50m移动景观建筑源，视觉包络50×50×97m，实测8412面，四标准材质与公共色盘，建立Blender源、GLB与运行场景路径。'; log.cell(lr,6).value='新增AssetID，不影响既有资产；运行碰撞由Godot包装后续接管。'; log.cell(lr,7).value='摩斯拉'
wb.save(ledger)
# baseline surgical refresh from all current ledgers
idx=LedgerIndex.load(R); bl=json.loads(baseline.read_text(encoding='utf-8'))
allrows=[]
for d in idx.domains:
 w=load_workbook(d.path, data_only=False); ws=w[idx.asset_sheet]
 allrows.extend((d, row, vals) for row,vals in read_source_rows(ws))
bl['asset_count']=len(allrows); assets={}
for d,row,vals in allrows:
 aid=str(vals[0]).strip(); assets[aid]={'v':_row_digest(vals),'c':str(vals[2]).strip(),'d':d.key}
bl['assets']=dict(sorted(assets.items()))
bl['column_digests']={str(c):col_digest([(r,v) for d,r,v in allrows],c) for c in CONTENT_COLUMNS}
bl['category_counts']={}
for d,row,vals in allrows: bl['category_counts'][str(vals[2]).strip()]=bl['category_counts'].get(str(vals[2]).strip(),0)+1
bl['captured_at']='2026-10-09T16:12:00'
baseline.write_text(json.dumps(bl,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
print(json.dumps({'asset_id':asset,'main_row':new,'prefab_row':prow,'log_row':lr,'ledger':str(ledger),'backup':str(backup),'baseline_count':bl['asset_count']},ensure_ascii=False))
