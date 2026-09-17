"""Probe the v006 blend for the exact geometry the wall/floor/door art carries.

Question we are answering
  The user wants the wall art (armour panels), floor tiles, door walls and doors to stop being
  ROOM-OWNED, ORIENTED packages and instead be baked into the four common components
  (wall_standard_5m / wall_door_5m / floor_tile_* / door_5m) so an instance anywhere matches
  automatically, with no per-direction handling.

  To do that we need, per source collection:
    * the merged object bounds in room world space
    * the per-part detail bounds, so we can see whether the art is already periodic on the 5 m grid
    * the "unit" bounds (one armour panel + one cap) in the frame of a single 5 m slot

Read-only. Nothing is written back to the blend.

Run:
  blender --background --factory-startup --python probe_v006_art.py
"""
import json
from pathlib import Path

import bpy
from mathutils import Vector

OUT = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle/source/entry_safe_room/v006')
BLEND = OUT / '局内关卡01_入口安全房_15x15m_正式美术_v006.blend'


def world_matrix(o):
    """Rebuild, never read o.matrix_world -- see the background-Blibder trap note."""
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def bounds(objs):
    pts = []
    for o in objs:
        pts += [world_matrix(o) @ Vector(c) for c in o.bound_box]
    if not pts:
        return None
    return [[round(fn(p[i] for p in pts), 4) for i in range(3)] for fn in (min, max)]


def local_bounds(o):
    pts = [Vector(c) for c in o.bound_box]
    return [[round(fn(p[i] for p in pts), 4) for i in range(3)] for fn in (min, max)]


bpy.ops.wm.open_mainfile(filepath=str(BLEND))

report = {'blend': str(BLEND), 'collections': {}, 'objects': {}}

TARGET_COLLS = [
    '墙面装饰_北墙内嵌装甲壁板_资产包',
    '墙面装饰_西墙内嵌装甲壁板_资产包',
    '墙面装饰_南墙内嵌装甲壁板_资产包',
    '墙面装饰_东墙内嵌装甲壁板_资产包',
    '地面装饰_地砖压条与检修口_资产包',
    '南门装甲与门禁_资产包',
    '东门装甲与门禁_资产包',
    '承重底板与结构底台_资产包',
]
SRC_COLLS = [
    '制作_北墙.001', '制作_西墙.001', '制作_南墙.001', '制作_东墙.001',
    '制作_南门装甲与门禁', '制作_东门装甲与门禁',
]

for cn in TARGET_COLLS + SRC_COLLS:
    c = bpy.data.collections.get(cn)
    if not c:
        report['collections'][cn] = None
        continue
    objs = [o for o in c.objects if o.type == 'MESH']
    entry = {
        'count': len(objs),
        'bounds': bounds(objs),
        'objects': [],
    }
    for o in sorted(objs, key=lambda x: x.name):
        wm = world_matrix(o)
        entry['objects'].append({
            'name': o.name,
            'loc': [round(v, 4) for v in wm.translation],
            'basis_loc': [round(v, 4) for v in o.matrix_basis.translation],
            'parent': o.parent.name if o.parent else None,
            'parent_type': o.parent_type if o.parent else None,
            'local_bounds': local_bounds(o),
            'world_bounds': bounds([o]),
            'materials': [m.name.split('.')[0] for m in o.data.materials],
            'verts': len(o.data.vertices),
        })
    report['collections'][cn] = entry

# ---- the whitebox provenance ring, for the envelope numbers -------------------
RO = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(('AP_', 'WALL_', 'FLOOR_'))]
report['whitebox'] = {'count': len(RO), 'names': sorted(o.name for o in RO),
                      'bounds': bounds(RO)}

# ---- wall slots: where the room thinks the module slots are -------------------
for cn in ('01_北墙槽位', '02_南墙槽位', '03_东墙槽位', '04_西墙槽位',
           '05_门扇', '06_地面槽位'):
    c = bpy.data.collections.get(cn)
    if not c:
        report['collections'][cn] = None
        continue
    objs = [o for o in c.objects if o.type == 'MESH']
    report['collections'][cn] = {
        'count': len(objs),
        'bounds': bounds(objs),
        'objects': [{'name': o.name, 'loc': [round(v, 4) for v in world_matrix(o).translation],
                     'world_bounds': bounds([o]),
                     'materials': [m.name.split('.')[0] for m in o.data.materials]}
                    for o in sorted(objs, key=lambda x: x.name)],
    }

(OUT / 'qa' / '_probe_v006_art.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')

print('=' * 78)
print('WHITEBOX ring:', report['whitebox']['count'], report['whitebox']['bounds'])
for cn, e in report['collections'].items():
    if e is None:
        print('%-40s ABSENT' % cn)
        continue
    print('%-40s n=%-3d bounds=%s' % (cn, e['count'], e['bounds']))
print('=' * 78)
print('wrote _probe_v006_art.json')
