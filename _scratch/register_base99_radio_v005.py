import copy,hashlib,json,shutil,sys
from pathlib import Path
from datetime import datetime
from openpyxl import load_workbook
P=Path('I:/工作项目/shellstrom2/ShellStorm2');O=P/'outputs/base99_radio_v005'
sys.path.insert(0,str(P/'scripts'));sys.path.insert(0,str(P/'tools/asset_pipeline'))
from ledger_registry import LedgerIndex
from split_asset_ledger import read_source_rows,_row_digest,col_digest,CONTENT_COLUMNS,dedupe_key_formula,dedupe_result_formula,sheet_digest
index=LedgerIndex.load(P);ledger=index.path_for_category('道具');baseline=P/'assets/registry/ledger_split_baseline.json'; sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8')); assert json.loads((O/'validation/validate_source_current.json').read_text())['passed']; assert json.loads((O/'validation/validate_optimized_current.json').read_text())['passed']
backup=O/'backup_before_registration'; backup.mkdir(exist_ok=True); shutil.copy2(ledger,backup/ledger.name); shutil.copy2(baseline,backup/baseline.name)
wb=load_workbook(ledger);ws=wb['资产主表'];ps=wb['3D-道具']; assert ws['A27'].value=='PRP-BASE99-RADIO-3D' and ps['A8'].value=='PRP-BASE99-RADIO-3D'; assert ws['R27'].value==dedupe_key_formula(27)
def snap(w):return {(s.title,c.coordinate):c.value for s in w for row in s for c in row if c.value is not None}
before=snap(wb); source=Path(m['source_blend']).relative_to(P).as_posix(); opt=Path(m['optimized_blend']).relative_to(P).as_posix(); prefab=P/m['runtime_prefab_target']; glb=m['hashes_sha256']['glb']
spec='宽0.828m × 深0.456m × 高0.822m；600面/1200三角形<800面；机身铜橙金属、天线与提手等范围外几何签名保持；单根三节斜金属天线29.35度；四材质公共色盘外链/PaletteUV/Closest；StatusLight为顶面偏前侧12边低模凸帽，直径0.14m，替换旧灯且不重复，避开提手/天线；off红常亮、A/B同绿常亮、离开99F红待机；发光能量1.5；ItemRoot/Visual/StatusLight稳定；左键/E关→A→B→关及Music逻辑不变；root scale=1，bounds不变'
changes={'M27':'v005','N27':spec,'P27':source+'; '+opt+'; '+m['component_glb'].replace(str(P).replace('\\','/').rstrip('/'),'').lstrip('/').replace('\\','/')+'; src/base3d/Base99Radio3D.gd; outputs/base99_radio_v005/asset_manifest.json; outputs/base99_radio_v005/final_acceptance.json','T27':sha(prefab),'V27':datetime(2026,10,7),'Y27':'v005局部状态灯深化；旧v004源/优化保留；顶面偏前侧12边凸帽直径0.14m；586面/1156三角；红绿像素与正常玩家俯视镜头验收；音乐/摆位/范围外几何不变；GLB SHA-256='+glb+'；source SHA-256='+m['hashes_sha256']['source']+'；optimized SHA-256='+m['hashes_sha256']['optimized']}
pschanges={'E8':source,'K8':spec,'O8':'v005','P8':'ItemRoot/Visual/StatusLight接口不变；StatusLight顶面偏前侧12边低模凸帽；单一灯，无billboard/UI/bloom；源='+m['hashes_sha256']['source']+'；优化='+m['hashes_sha256']['optimized']+'；GLB='+glb+'；Prefab='+sha(prefab)+'；证据outputs/base99_radio_v005/'}
for c,v in changes.items():ws[c]=v
for c,v in pschanges.items():ps[c]=v
log=wb['域变更日志'];r=log.max_row+1; last=str(log.cell(r-1,1).value); nums=last.lstrip('v').split('.'); nums[-1]=str(int(nums[-1])+1)
for c in range(1,8):log.cell(r,c)._style=copy.copy(log.cell(r-1,c)._style)
for c,v in enumerate(['v'+'.'.join(nums),'2026-10-07','99F收音机v005顶面偏前侧凸起状态灯','道具 / decor_prop','586面/1156三角；StatusLight替换为直径0.14m、12边低模顶面凸帽；off红、A/B同绿、离楼红待机；音乐与摆位规则不变','源/优化/GLB/Prefab独立重导；Blender严格结构UV材质通过；Godot真实状态交互通过；正常俯视镜头量化证据已归档','WorkBuddy'],1):log.cell(r,c,v)
wb.save(ledger); w=load_workbook(ledger); after=snap(w); diffs=[{'sheet':s,'cell':c,'before':str(before.get((s,c))),'after':str(after.get((s,c)))} for s,c in sorted(set(before)|set(after)) if before.get((s,c))!=after.get((s,c))]; allowed={('资产主表',c) for c in changes}|{('3D-道具',c) for c in pschanges}|{('域变更日志',log.cell(r,c).coordinate) for c in range(1,8)}; assert all((d['sheet'],d['cell']) in allowed for d in diffs)
bl=json.loads(baseline.read_text(encoding='utf-8')); old=copy.deepcopy(bl); values=next(v for _,v in read_source_rows(w['资产主表']) if v[0]=='PRP-BASE99-RADIO-3D'); bl['assets']['PRP-BASE99-RADIO-3D']={'v':_row_digest(values),'c':'道具','d':'props'}; rows=[]
for domain in index.domains: rows.extend(read_source_rows(load_workbook(domain.path)['资产主表']))
bl['column_digests']={str(c):col_digest(rows,c) for c in CONTENT_COLUMNS}; bl['category_counts']={cat:sum(1 for _,v in rows if v[2]==cat) for cat in sorted({v[2] for _,v in rows})}; bl['sheet_digests']['3D-道具']=sheet_digest(w['3D-道具']); assert all(bl['assets'][k]==v for k,v in old['assets'].items() if k!='PRP-BASE99-RADIO-3D'); assert bl['asset_count']==old['asset_count']; baseline.write_text(json.dumps(bl,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
m['hashes_sha256']['prefab']=sha(prefab); (O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); (O/'registration_evidence.json').write_text(json.dumps({'passed':True,'ledger':ledger.as_posix(),'changed_cells':diffs,'backup':backup.as_posix(),'baseline_asset_count':bl['asset_count'],'other_asset_baseline_fingerprints_unchanged':True},ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); print('RADIO_V005_REGISTRATION_OK',len(diffs))
