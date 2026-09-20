import openpyxl,json,hashlib,copy
from pathlib import Path
R=Path('/Users/summercards/ShellStorm2');O=Path(__file__).resolve().parents[1]
a=openpyxl.load_workbook(O/'qa/registry_before.xlsx');b=openpyxl.load_workbook(R/'assets/registry/ShellStorm2_美术资产台账_v001.xlsx');diff=[];styles=[]
for sa in a:
 sb=b[sa.title]
 for row in sa:
  for c in row:
   allowed=(sa.title=='资产主表' and c.row==429 and c.column in [13,14,15,16,20,25]) or (sa.title=='3D-场景通用' and 97<=c.row<=134 and c.column in [5,6,11,15,16]) or (sa.title=='3D-场景通用' and 135<=c.row<=141)
   if allowed:continue
   target=sb[c.coordinate]
   if c.value!=target.value:diff.append([sa.title,c.coordinate])
   if c.value is not None:
    for prop in ['font','fill','alignment','border','number_format','protection']:
     if copy.copy(getattr(c,prop))!=copy.copy(getattr(target,prop)):styles.append([sa.title,c.coordinate,prop])
cat=json.loads((O/'component_packages_v002/catalog.json').read_text());sha=hashlib.sha256((O/'天台区块_参考组件库_v002.blend').read_bytes()).hexdigest()
ids=[b['3D-场景通用'].cell(r,1).value for r in range(98,142)]
checks={'scope_values':not diff,'scope_styles':not styles,'47_packages':set(ids)=={p['package_id'] for p in cat},'source_hash':b['资产主表']['T429'].value==sha,'source_version':b['资产主表']['M429'].value=='v002'}
report={'passed':all(checks.values()),'checks':checks,'unexpected_values':diff,'unexpected_styles':styles,'sha256':sha}
(O/'qa/registry_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False));raise SystemExit(0 if report['passed'] else 1)
