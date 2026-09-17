"""核对 v003 地砖组件上板(INSET) 与 房间 FLOORSLOT_*_INSET 的网格结构是否一致。

只读。打印 verts/polys 数与 z 分层。
"""
from __future__ import annotations
from pathlib import Path
from collections import Counter
import bpy
from mathutils import Vector

LIB3 = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/'
            r'battle/source/common_components/v003/战局区块_通用组件库_v003.blend')
ROOM6 = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/'
             r'battle/source/entry_safe_room/v006/局内关卡01_入口安全房_15x15m_正式美术_v006.blend')


def W(o):
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def stat(o, inv=None, label=''):
    me = o.data
    zs = [(inv @ (W(o) @ v.co)).z if inv else (W(o) @ v.co).z for v in me.vertices]
    c = Counter(round(z, 4) for z in zs)
    mats = sorted({m.name.split('.')[0] for m in me.materials if m}) if me.materials else []
    print('  %-40s verts=%4d polys=%4d  z-levels=%s  mats=%s'
          % (label or o.name, len(me.vertices), len(me.polygons),
             sorted(c.items()), mats))


print('#' * 100)
print('# v003 floor components (LOCAL frame relative to ROOT)')
bpy.ops.wm.open_mainfile(filepath=str(LIB3))
for comp, root_name in (('floor_tile_r01_c01', 'ROOT_floor_tile_r01_c01_通用组件'),
                        ('floor_tile_r01_c02', 'ROOT_floor_tile_r01_c02_通用组件')):
    coll = bpy.data.collections.get('%s_通用包' % comp)
    root = bpy.data.objects.get(root_name)
    inv = W(root).inverted()
    print(' %s' % comp)
    for o in sorted((x for x in coll.objects if x.type == 'MESH'), key=lambda x: x.name):
        stat(o, inv)

print()
print('#' * 100)
print('# room v006 floor slots (LOCAL frame relative to tile centre, z-0.26)')
bpy.ops.wm.open_mainfile(filepath=str(ROOM6))
bpy.context.view_layer.update()
import mathutils
for r, c in ((1, 1), (3, 2), (2, 2)):
    M = mathutils.Matrix.Translation(Vector(((c - 2) * 5.0, (r - 2) * 5.0, 0.26))).inverted()
    for o in sorted(bpy.data.objects, key=lambda x: x.name):
        if o.type != 'MESH':
            continue
        if o.name in ('FLOORSLOT_R%02d_C%02d' % (r, c), 'FLOORSLOT_R%02d_C%02d_INSET' % (r, c)):
            stat(o, M, 'R%02dC%02d %s' % (r, c, o.name))
