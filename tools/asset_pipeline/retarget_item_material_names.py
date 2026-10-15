"""Normalize GLB item role names without re-exporting/changing binary geometry."""
from pathlib import Path
import sys,struct,json,shutil
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'tools/asset_pipeline')]
from item_palette import MATERIAL_ROLES,sha
from workspace_paths import work_path
OUT=work_path('sessions/2026-10-15_item_materials/glb_result.json').parent
BACKUP=ROOT.parent/'ShellStorm2-backup/2026-10-15_item_materials/before_edits'
results=[]
for p in sorted((ROOT/'assets/art/items_weapons').rglob('*.glb')):
    backup=BACKUP/p.relative_to(ROOT);backup.parent.mkdir(parents=True,exist_ok=True)
    if not backup.exists():shutil.copy2(p,backup)
    raw=p.read_bytes();length,kind=struct.unpack_from('<II',raw,12)
    assert kind==0x4e4f534a
    data=json.loads(raw[20:20+length]);binary=raw[20+length:]
    for material in data.get('materials',[]):
        index=int(material['name'][:2])-1;assert 0<=index<4
        material['name']=MATERIAL_ROLES[index]
    payload=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode('utf8')
    payload+=b' '*((-len(payload))%4)
    output=struct.pack('<III',0x46546c67,2,20+len(payload)+len(binary))+struct.pack('<II',len(payload),kind)+payload+binary
    p.write_bytes(output)
    assert output[20+len(payload):]==binary
    results.append(dict(path=p.relative_to(ROOT).as_posix(),old_sha256=sha(backup),sha256=sha(p),binary_geometry_unchanged=True))
(OUT/'glb_result.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('GLB_ITEM_ROLE_NAMES_OK',len(results))
