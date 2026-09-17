"""核对竖向对齐：v003 地砖组件本体的局部 z 区间 vs recovered 地砖模块世界 z 区间。

只读。
"""
from __future__ import annotations
from pathlib import Path
import bpy
from mathutils import Vector

LIB3 = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/'
            r'battle/source/common_components/v003/战局区块_通用组件库_v003.blend')
REC = Path(r'I:/工作项目/shellstrom2/_scratch/esr_recover/v003_recovered.blend')


def W(o):
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def box(o, xform=None):
    pts = [(xform @ (W(o) @ Vector(c))) if xform else (W(o) @ Vector(c)) for c in o.bound_box]
    return ([round(min(p[i] for p in pts), 4) for i in range(3)],
            [round(max(p[i] for p in pts), 4) for i in range(3)])


print('#' * 90)
print('# v003 library -- floor tile component local boxes')
bpy.ops.wm.open_mainfile(filepath=str(LIB3))
for comp, root_name in (('floor_tile_r01_c01', 'ROOT_floor_tile_r01_c01_通用组件'),
                        ('floor_tile_r01_c02', 'ROOT_floor_tile_r01_c02_通用组件')):
    coll = bpy.data.collections.get('%s_通用包' % comp)
    root = bpy.data.objects.get(root_name)
    print('  %s  coll=%s root=%s' % (comp, coll is not None, root is not None))
    if root:
        print('      ROOT loc=%s' % [round(v, 4) for v in root.matrix_basis.to_translation()])
    if coll:
        for o in sorted((x for x in coll.objects if x.type == 'MESH'), key=lambda x: x.name):
            lo, hi = box(o)
            print('      %-44s world z %.4f..%.4f' % (o.name, lo[2], hi[2]))

print()
print('#' * 90)
print('# recovered source -- FLOOR_ module + tile decor world z')
bpy.ops.wm.open_mainfile(filepath=str(REC))
bpy.context.view_layer.update()
for r in (1, 2, 3):
    for c in (1, 2, 3):
        col = None
        for nm in ('制作_地砖_R%02d_C%02d.001' % (r, c), '制作_地砖_R%02d_C%02d' % (r, c)):
            col = bpy.data.collections.get(nm)
            if col is not None:
                break
        if col is None:
            continue
        for o in sorted((x for x in col.objects if x.type == 'MESH'), key=lambda x: x.name):
            lo, hi = box(o)
            if o.name.startswith(('FLOOR_', 'AP_')):
                print('  R%02dC%02d  %-34s world z %.4f..%.4f  x %.3f..%.3f y %.3f..%.3f'
                      % (r, c, o.name, lo[2], hi[2], lo[0], hi[0], lo[1], hi[1]))

print()
print('  --- 该 blend 里所有 FLOOR_ 顶层对象(去重) ---')
seen = set()
for o in bpy.data.objects:
    if o.type == 'MESH' and o.name.startswith('FLOOR_'):
        lo, hi = box(o)
        key = (o.name, round(lo[2], 3), round(hi[2], 3))
        if key in seen:
            continue
        seen.add(key)
        print('  %-40s world z %.4f..%.4f' % (o.name, lo[2], hi[2]))
