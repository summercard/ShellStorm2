"""核对 v003 地砖组件两块板 + 房间 v006 地砖模块 + 地板装饰的完整包围盒。

只读。
"""
from __future__ import annotations
from pathlib import Path
import bpy
from mathutils import Vector

LIB3 = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/'
            r'battle/source/common_components/v003/战局区块_通用组件库_v003.blend')
ROOM6 = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/'
             r'battle/source/room_instances/entry_safe_room/v006/局内关卡01_入口安全房_15x15m_正式美术_v006.blend')


def W(o):
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def full(o, root=None):
    inv = W(root).inverted() if root is not None else None
    pts = []
    for c in o.bound_box:
        p = W(o) @ Vector(c)
        pts.append(inv @ p if inv else p)
    return ([round(min(p[i] for p in pts), 4) for i in range(3)],
            [round(max(p[i] for p in pts), 4) for i in range(3)])


print('#' * 96)
print('# v003 library -- floor tile component, LOCAL boxes (relative to its ROOT)')
bpy.ops.wm.open_mainfile(filepath=str(LIB3))
for comp, root_name in (('floor_tile_r01_c01', 'ROOT_floor_tile_r01_c01_通用组件'),
                        ('floor_tile_r01_c02', 'ROOT_floor_tile_r01_c02_通用组件')):
    coll = bpy.data.collections.get('%s_通用包' % comp)
    root = bpy.data.objects.get(root_name)
    for o in sorted((x for x in coll.objects if x.type == 'MESH'), key=lambda x: x.name):
        lo, hi = full(o, root)
        print('  %-22s %-36s lo=%s hi=%s' % (comp, o.name, lo, hi))

print()
print('#' * 96)
print('# room v006 -- FLOOR_ modules + a sample of tile decor (WORLD boxes)')
bpy.ops.wm.open_mainfile(filepath=str(ROOM6))
bpy.context.view_layer.update()
for o in sorted(bpy.data.objects, key=lambda x: x.name):
    if o.type != 'MESH':
        continue
    if o.name.startswith(('FLOOR_', 'AP_')):
        lo, hi = full(o)
        print('  %-36s lo=%s hi=%s' % (o.name, lo, hi))
print()
for o in sorted(bpy.data.objects, key=lambda x: x.name):
    if o.type == 'MESH' and ('地砖压边_主体_00001' == o.name or '地砖压边_主体_00026' == o.name
                             or '蓝色拼缝_自发光_00005' == o.name
                             or '地砖磨损_主体_00015' == o.name
                             or '检修格栅框_主体_00008' == o.name):
        lo, hi = full(o)
        print('  %-36s lo=%s hi=%s' % (o.name, lo, hi))
