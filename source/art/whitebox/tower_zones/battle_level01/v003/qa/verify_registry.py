import copy,hashlib,json,openpyxl
from pathlib import Path
ROOT=Path('/Users/summercards/ShellStorm2');OUT=ROOT/'source/art/whitebox/tower_zones/battle_level01/v003'
before=openpyxl.load_workbook(OUT/'qa/registry_before.xlsx');after=openpyxl.load_workbook(ROOT/'assets/registry/ShellStorm2_美术资产台账_v001.xlsx')
meta=json.loads((OUT/'qa/registry_update.json').read_text());sheet_name='3D-场景通用';a=before[sheet_name];b=after[sheet_name]
changes=[]
for row in range(1,100):
 for col in range(1,20):
  if a.cell(row,col).value!=b.cell(row,col).value:changes.append((row,col))
expected=set()
for item in meta['updated']:
 row=item['row'];expected.update((row,col) for col in (5,6,15,16))
expected.update((91,col) for col in range(1,17))
styles=[]
for item in meta['updated']:
 row=item['row']
 if row==91:continue
 for col in range(1,17):
  for prop in ('font','fill','alignment','border','number_format','protection'):
   if copy.copy(getattr(a.cell(row,col),prop))!=copy.copy(getattr(b.cell(row,col),prop)):styles.append((row,col,prop))
row91_style=[]
for col in range(1,17):
 for prop in ('font','fill','alignment','border','number_format','protection'):
  if copy.copy(getattr(a.cell(89,col),prop))!=copy.copy(getattr(b.cell(91,col),prop)):row91_style.append((col,prop))
hash_fail=[]
cell_fail=[]
for item in meta['updated']:
 sha=hashlib.sha256((ROOT/item['source_blend']).read_bytes()).hexdigest()
 if sha!=item['sha256']:hash_fail.append(item['asset_id'])
 if b.cell(item['row'],1).value!=item['asset_id'] or b.cell(item['row'],5).value!=item['source_blend']:cell_fail.append(item['asset_id'])
main02_unchanged=all(a.cell(73,col).value==b.cell(73,col).value for col in range(1,17))
report={'passed':set(changes)==expected and not styles and not row91_style and not hash_fail and not cell_fail and main02_unchanged,'changes':changes,'expected_changes':sorted(expected),'style_differences':styles,'new_row_style_differences':row91_style,'hash_failures':hash_fail,'cell_failures':cell_fail,'main_room_02_formal_art_preserved':main02_unchanged}
(OUT/'qa/registry_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False));raise SystemExit(0 if report['passed'] else 1)
