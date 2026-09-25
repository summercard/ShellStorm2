"""Stage verified source and renders; reject stale or failing validation."""
from pathlib import Path
import json,shutil,hashlib
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[8]
OUT=ROOT.parent/'outputs/expedition01_bridge_room_v002'
qa=json.loads((HERE/'qa_report.json').read_text(encoding='utf-8'))
vr=json.loads((HERE/'validator_report.json').read_text(encoding='utf-8'))
assert qa['status']=='PASS' and all(qa['checks'].values())
assert vr.get('ok') is True or vr.get('passed') is True or vr.get('status')=='PASS' or (vr.get('checks') and all(vr['checks'].values())),list(vr)
source=HERE/'通道桥房间种类_工字型_30x60m_v002.blend'
assert source.exists() and source.stat().st_size>100000
old=HERE.parent/'v001/通道桥房间种类_工字型_30x60m_v001.blend'
assert hashlib.sha256(old.read_bytes()).hexdigest()==qa['scope_lock']['v001_sha256']
wb=ROOT/'source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/bridge_60x50.json'
assert hashlib.sha256(wb.read_bytes()).hexdigest()==qa['scope_lock']['whitebox_sha256']
qa['visual_review']={'status':'reviewed_with_remaining_reference_gaps','reviewed_views':['reference_cutaway.png','lower_layers_detail.png','upper_machine_room_detail.png','top_plan.png','complete_structure.png'],'implemented':['multi-elevation supported maintenance decks','lower shaft machinery and fan backplanes','flanged pipe elbows and hanging cable bundles','upper electrical/server/console groups'],'remaining_gaps':['reference surface wear and stains are not fully reproduced','repeated equipment remains more regular than reference','no final door leaves by frozen production scope'],'cutaway_note':'Near-side upper/lower walls and near-side mid-gallery are hidden for presentation only; full source retains them.'}
(HERE/'qa_report.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\r\n')
OUT.mkdir(parents=True,exist_ok=True)
for name in [source.name,'qa_report.json','validator_report.json','room_type_manifest.json','component_inventory.json','component_tree.txt']:
    shutil.copy2(HERE/name,OUT/name)
for name in qa['visual_review']['reviewed_views']:
    p=HERE/'renders'/name; assert p.exists() and p.stat().st_size>10000,name
    shutil.copy2(p,OUT/name)
ref=Path('C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-09-25T13-40-47-307Z-1c92b0f2.jpg')
shutil.copy2(ref,OUT/'reference.jpg')
# Normalize only this newly authored version's text products, leaving all other sessions untouched.
for p in HERE.rglob('*'):
    if p.suffix in ('.py','.json','.txt'):
        b=p.read_bytes(); b=b.replace(b'\r\n',b'\n'); assert b'\r' not in b
        p.write_bytes(b.replace(b'\n',b'\r\n'))
print(json.dumps({'delivery':str(OUT),'blend_bytes':source.stat().st_size,'checks':qa['checks'],'measured':qa['measured'],'v001_preserved':True,'whitebox_preserved':True},ensure_ascii=False))
