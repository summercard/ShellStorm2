"""权威核对：room v006 最终地板，在 4 个 c02 边中砖位上到底有没有方形检修盖。

只读。按 9 个砖位的中心，统计该砖位footprint内地板几何的最高 z。
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

print('=== collections mentioning floor / tile ===')
for c in sorted(bpy.data.collections, key=lambda x: x.name):
    if any(k in c.name for k in ('地板', '地砖', 'floor', 'Floor', 'FLOOR')):
        objs = [o for o in c.objects if o.type == 'MESH']
        print('  %-46s meshes=%d' % (c.name, len(objs)))
        for o in sorted(objs, key=lambda x: x.name):
            pts = [W(o) @ Vector(cc) for cc in o.bound_box]
            lo = [min(p[i] for p in pts) for i in range(3)]
            hi = [max(p[i] for p in pts) for i in range(3)]
            print('      %-44s x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f'
                  % (o.name, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))

print()
print('=== c02 边中砖位：footprint 内最高 z (x/y 取 2.4 半径，排除压边 z<0.31) ===')
# c02 边中位：R01C02(-0,-5) R02C01(-5,0) R02C03(5,0) R03C02(0,5)
for label, (cx, cy) in (('R01C02 S边', (0.0, -5.0)), ('R02C01 W边', (-5.0, 0.0)),
                        ('R02C03 E边', (5.0, 0.0)), ('R03C02 N边', (0.0, 5.0))):
    top = -1e9
    topo = ''
    for c in bpy.data.collections:
        for o in c.objects:
            if o.type != 'MESH':
                continue
            for cc in o.bound_box:
                p = W(o) @ Vector(cc)
                if abs(p[0] - cx) <= 2.35 and abs(p[1] - cy) <= 2.35 and p[2] > top:
                    top, topo = p[2], o.name
    print('  %-12s 最高 z=%.4f  (%s)' % (label, top, topo))

print()
print('=== 对照 c01 角砖位 (R01C01) ===')
for label, (cx, cy) in (('R01C01', (-5.0, -5.0)), ('R02C02 中心', (0.0, 0.0))):
    top, topo = -1e9, ''
    for c in bpy.data.collections:
        for o in c.objects:
            if o.type != 'MESH':
                continue
            for cc in o.bound_box:
                p = W(o) @ Vector(cc)
                if abs(p[0] - cx) <= 2.35 and abs(p[1] - cy) <= 2.35 and p[2] > top:
                    top, topo = p[2], o.name
    print('  %-12s 最高 z=%.4f  (%s)' % (label, top, topo))
