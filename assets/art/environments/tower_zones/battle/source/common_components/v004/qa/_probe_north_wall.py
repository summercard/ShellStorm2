"""核对房间 v006 北墙：视觉墙体到底由什么构成，装甲壁板的进深关系。

只读。列出北墙带 (x -2.6..2.6, y 7.10..7.55, z 0..12) 内所有 mesh 的集合与包围盒。
"""
from __future__ import annotations
from pathlib import Path
import bpy
from mathutils import Vector

ROOM6 = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/'
             r'battle/source/entry_safe_room/v006/局内关卡01_入口安全房_15x15m_正式美术_v006.blend')


def W(o):
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


bpy.ops.wm.open_mainfile(filepath=str(ROOM6))
bpy.context.view_layer.update()

coll_of = {}
for c in bpy.data.collections:
    for o in c.objects:
        coll_of.setdefault(o.name, []).append(c.name)

rows = []
for o in bpy.data.objects:
    if o.type != 'MESH':
        continue
    pts = [W(o) @ Vector(c) for c in o.bound_box]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    # north-wall band
    if not (hi[0] > -2.6 and lo[0] < 2.6 and hi[1] > 7.10 and lo[1] < 7.55 and hi[2] > 0.001):
        continue
    mats = sorted({m.name.split('.')[0] for m in o.data.materials if m})
    rows.append((lo[1], o.name, lo, hi, mats, coll_of.get(o.name, [])))

rows.sort(key=lambda r: (-r[3][1], r[1]))
print('=== north-wall band, sorted by max-y descending ===')
for _, name, lo, hi, mats, colls in rows:
    print('  %-34s y %.4f..%.4f  x %.3f..%.3f  z %.3f..%.3f  %s'
          % (name, lo[1], hi[1], lo[0], hi[0], lo[2], hi[2], ','.join(mats)))
    print('        colls: %s' % ', '.join(colls))

print()
print('=== collections whose name mentions north wall / wall decor ===')
for c in sorted(bpy.data.collections, key=lambda x: x.name):
    if any(k in c.name for k in ('北墙', '墙面', '墙体', 'WALL', 'wall')):
        objs = [o for o in c.objects if o.type == 'MESH']
        print('  %-50s meshes=%d' % (c.name, len(objs)))
