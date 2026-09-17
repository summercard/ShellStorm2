import bpy
from mathutils import Vector
from pathlib import Path
BLEND = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle/source/entry_safe_room/v006/局内关卡01_入口安全房_15x15m_正式美术_v006.blend')
def W(o):
    m=o.matrix_parent_inverse@o.matrix_basis; p=o.parent
    while p is not None: m=(p.matrix_parent_inverse@p.matrix_basis)@m; p=p.parent
    return m
def bnd(objs):
    pts=[]
    for o in objs: pts+=[W(o)@Vector(c) for c in o.bound_box]
    if not pts: return None
    return [[round(fn(p[i] for p in pts),3) for i in range(3)] for fn in (min,max)]
bpy.ops.wm.open_mainfile(filepath=str(BLEND))
print('='*80)
for c in sorted(bpy.data.collections, key=lambda x:x.name):
    objs=[o for o in c.objects if o.type=='MESH']
    if not objs: continue
    print('%-46s n=%-3d %s' % (c.name, len(objs), bnd(objs)))
print('='*80)
print('COLLECTIONS with same base name (duplicates):')
from collections import defaultdict
d=defaultdict(list)
for c in bpy.data.collections: d[c.name.split('.')[0]].append(c.name)
for k,v in sorted(d.items()):
    if len(v)>1: print('  ',k,'->',v)
