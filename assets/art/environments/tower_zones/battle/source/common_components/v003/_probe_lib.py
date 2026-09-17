import bpy
from pathlib import Path
from mathutils import Vector
BLEND = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend')
bpy.ops.wm.open_mainfile(filepath=str(BLEND))
print('='*84)
print('TOP COLLECTIONS:')
for c in bpy.data.collections:
    if c.name.startswith(('08','09','10')):
        print('  %-40s n_objs=%-3d n_children=%d' % (c.name, len(c.objects), len(c.children)))
print('-'*84)
print('ROOT empties:')
for o in bpy.data.objects:
    if o.type=='EMPTY' and o.name.startswith('ROOT_'):
        print('  %-44s loc=%s parent=%s' % (o.name, [round(v,4) for v in o.location], o.parent.name if o.parent else None))
print('-'*84)
TARGETS = ['wall_standard_5m_主体_输出','wall_door_5m_门垛左_输出','wall_door_5m_门垛右_输出','wall_door_5m_门楣_输出',
           'door_5m_门扇_输出','floor_tile_r01_c01_主体_输出','floor_tile_r01_c01_主体_输出.001',
           'floor_tile_r01_c02_主体_输出','floor_tile_r01_c02_主体_输出.001']
for n in TARGETS:
    o = bpy.data.objects.get(n)
    if not o:
        print('  %-34s MISSING' % n); continue
    pts=[o.matrix_basis @ v.co for v in o.data.vertices]
    lo=[min(p[i] for p in pts) for i in range(3)]
    hi=[max(p[i] for p in pts) for i in range(3)]
    print('  %-34s loc=%-22s basis_loc=%-22s dims=%s mats=%s' % (
        n, [round(v,4) for v in o.location], [round(v,4) for v in o.matrix_basis.translation],
        [round(hi[i]-lo[i],4) for i in range(3)],
        [m.name.split('.')[0] for m in o.data.materials]))
    print('       local_bounds lo=%s hi=%s  parent=%s users_coll=%s' % (
        [round(v,4) for v in lo],[round(v,4) for v in hi], o.parent.name if o.parent else None,
        [c.name for c in o.users_collection]))
