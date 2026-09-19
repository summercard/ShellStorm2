import bpy
from pathlib import Path
import json

ROOT = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
SRC = ROOT / 'assets/art/environments/tower_zones/battle/source/common_components/v006/env_battle_common_components_source_v006.blend'
OUT_DIR = ROOT / 'assets/art/environments/tower_zones/battle/source/common_components/v007'
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT = OUT_DIR / 'env_battle_common_components_source_v007.blend'

def open_src():
    bpy.ops.wm.open_mainfile(filepath=str(SRC))

def normalize_collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        raise RuntimeError('missing collection: ' + name)
    c.instance_offset = (0.0, 0.0, 0.0)
    roots = [o for o in c.all_objects if o.name.startswith('ROOT_')]
    if len(roots) != 1:
        raise RuntimeError('%s roots=%d' % (name, len(roots)))
    root = roots[0]
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.scale = (1.0, 1.0, 1.0)
    for o in c.all_objects:
        if o.type == 'MESH':
            o.parent = root
    return c, root

open_src()
rows = []
for name in ['wall_door_5m_通用包', 'door_5m_通用包']:
    c, root = normalize_collection(name)
    rows.append({'collection': name, 'root': root.name, 'instance_offset': list(c.instance_offset), 'root_location': list(root.location), 'mesh_count': len([o for o in c.all_objects if o.type == 'MESH'])})
bpy.ops.wm.save_as_mainfile(filepath=str(OUT), compress=True)
print('COMMON_DOOR_ANCHOR_V007_OK', json.dumps(rows, ensure_ascii=False))
