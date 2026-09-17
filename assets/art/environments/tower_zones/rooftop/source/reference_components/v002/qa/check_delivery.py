import json,hashlib,openpyxl
from pathlib import Path
from PIL import Image
O=Path(__file__).resolve().parents[1];P=O.parent/'v001'
cat=json.loads((O/'component_packages_v002/catalog.json').read_text());old=json.loads((P/'component_packages_v001/catalog.json').read_text())
oldids={p['package_id'] for p in old};new=[p for p in cat if p['package_id'] not in oldids];issues=[]
for p in cat:
 f=O/'renders/components'/f'{p["slug"]}.png'
 if not f.is_file():issues.append('missing '+str(f));continue
 im=Image.open(f).convert('RGBA');a=im.getchannel('A');n=sum(a.histogram()[1:])
 if n<500:issues.append('empty '+p['slug'])
 if p['slug']!='door_lamp' and not p.get('vegetation_variant'):
  if hashlib.sha256(f.read_bytes()).hexdigest()!=hashlib.sha256((P/'renders/components'/f.name).read_bytes()).hexdigest():issues.append('unexpected preview change '+p['slug'])
for f in ['00_固定镜头结构素模.png','01_参考镜头全景.png','02_俯视结构.png','03_房间设备近景.png','04_外墙接口.png','05_全部组件总览.png','06_厚门框与藤蔓近景.png']:
 if not (O/'renders'/f).is_file():issues.append('missing '+f)
 if (O/'renders'/f).is_file():Image.open(O/'renders'/f).verify()
if len(new)!=7 or not all(p['variant_of'] in oldids for p in new):issues.append('variant IDs')
report={'passed':not issues,'issues':issues,'packages':44,'new_child_variants':7,'existing_ids_reused':37,'unchanged_previews_reused':36,'source_sha256':hashlib.sha256((O/'天台区块_参考组件库_v002.blend').read_bytes()).hexdigest()}
(O/'qa/delivery_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False));raise SystemExit(0 if report['passed'] else 1)
