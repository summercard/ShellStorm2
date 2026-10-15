"""Back up item import/manifests and inventory all consumers for palette migration."""
import json, shutil, sys, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'tools/asset_pipeline')]
from workspace_paths import work_path
from item_palette import TARGET, SOURCE, IMPORT_SCRIPT, sha
OUT=work_path('sessions/2026-10-15_item_palette/migration.json').parent
BACKUP=ROOT.parent/'ShellStorm2-backup/2026-10-15_item_palette/before_edits'
def backup(p):
    dst=BACKUP/p.relative_to(ROOT);dst.parent.mkdir(parents=True,exist_ok=True)
    if not dst.exists():shutil.copy2(p,dst)
glbs=sorted((ROOT/'assets/art/items_weapons').rglob('*.glb'))
for glb in glbs:
    p=Path(str(glb)+'.import');backup(p)
    s=p.read_text(encoding='utf8')
    s=re.sub(r'import_script/path="[^"]*"',f'import_script/path="res://{IMPORT_SCRIPT}"',s)
    assert 'res://'+IMPORT_SCRIPT in s
    p.write_text(s,encoding='utf8')
for p in list((ROOT/'art_source/items_weapons').rglob('*.json'))+list((ROOT/'assets/art/items_weapons').rglob('*.json')):
    backup(p)
for p in (ROOT/'assets/registry').rglob('*'):
    if p.is_file() and p.suffix in ['.json','.xlsx']:backup(p)
data=dict(scene_palette_sha256=sha(ROOT/SOURCE),palette=TARGET,glbs=[p.relative_to(ROOT).as_posix() for p in glbs],prefabs=[p.relative_to(ROOT).as_posix() for p in sorted((ROOT/'assets/art/items_weapons').rglob('*.tscn'))])
(OUT/'migration.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('ITEM_PALETTE_IMPORTS_UPDATED',len(glbs))
