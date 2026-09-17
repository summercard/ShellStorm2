"""Split the merged v006 decor meshes into loose parts and measure each one.

The armour is one merged mesh per wall, but the art inside it is periodic: a 5 m slot carries
two 2.4 m panels plus a seam cap. To bake that into a 5 m common component we need the parts,
not the slab. Connected-component decomposition recovers them exactly.

Also probes the recovered source blend, where the authored north armour unit still lives as
separate objects (the v006 harvest relinked them into the merged package).

Read-only.

Run:
  blender --background --factory-startup --python probe_v006_parts.py
"""
import json
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
V006 = ROOT / 'assets/art/environments/tower_zones/battle/source/entry_safe_room/v006'
RECOVERED = Path(r'I:/工作项目/shellstrom2/_scratch/esr_recover/v003_recovered.blend')


def world_matrix(o):
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def loose_parts(o):
    """Group the mesh's polygons into connected components; return per-part bounds + material."""
    me = o.data
    n = len(me.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for e in me.edges:
        union(e.vertices[0], e.vertices[1])

    groups = {}
    for p in me.polygons:
        r = find(p.vertices[0])
        groups.setdefault(r, {'verts': set(), 'mat': None})
        groups[r]['verts'].update(p.vertices)
        if groups[r]['mat'] is None:
            groups[r]['mat'] = (me.materials[p.material_index].name.split('.')[0]
                                if me.materials and p.material_index < len(me.materials) else None)

    W = world_matrix(o)
    out = []
    for r, g in groups.items():
        pts = [W @ me.vertices[i].co for i in g['verts']]
        lo = [round(min(p[i] for p in pts), 4) for i in range(3)]
        hi = [round(max(p[i] for p in pts), 4) for i in range(3)]
        out.append({
            'verts': len(g['verts']),
            'mat': g['mat'],
            'lo': lo, 'hi': hi,
            'size': [round(hi[i] - lo[i], 4) for i in range(3)],
        })
    out.sort(key=lambda d: (d['lo'][0], d['lo'][2]))
    return out


report = {}

# ---------------------------------------------------------------- v006 merged packages
bpy.ops.wm.open_mainfile(filepath=str(V006 / '局内关卡01_入口安全房_15x15m_正式美术_v006.blend'))

V006_COLLS = [
    '墙面装饰_北墙内嵌装甲壁板_资产包',
    '墙面装饰_南墙内嵌装甲壁板_资产包',
    '墙面装饰_西墙内嵌装甲壁板_资产包',
    '墙面装饰_东墙内嵌装甲壁板_资产包',
    '地面装饰_地砖压条与检修口_资产包',
    '南门装甲与门禁_资产包',
    '东门装甲与门禁_资产包',
]
v006 = {}
for cn in V006_COLLS:
    c = bpy.data.collections.get(cn)
    if not c:
        v006[cn] = None
        continue
    v006[cn] = {}
    for o in sorted((x for x in c.objects if x.type == 'MESH'), key=lambda x: x.name):
        v006[cn][o.name] = loose_parts(o)
report['v006'] = v006

# ---------------------------------------------------------------- recovered source armour
bpy.ops.wm.open_mainfile(filepath=str(RECOVERED))
rec = {}
for cn in ('制作_北墙.001', '制作_南墙.001', '制作_东墙.001', '制作_西墙.001',
           '制作_南门装甲与门禁', '制作_地砖_R01_C01.001', '制作_地砖_R02_C02.001'):
    c = bpy.data.collections.get(cn)
    if not c:
        rec[cn] = None
        continue
    rec[cn] = {}
    for o in sorted((x for x in c.objects if x.type == 'MESH'), key=lambda x: x.name):
        W = world_matrix(o)
        pts = [W @ v.co for v in o.data.vertices]
        rec[cn][o.name] = {
            'lo': [round(min(p[i] for p in pts), 4) for i in range(3)],
            'hi': [round(max(p[i] for p in pts), 4) for i in range(3)],
            'loc': [round(v, 4) for v in W.translation],
            'parts': loose_parts(o),
        }
report['recovered'] = rec

(V006 / 'qa' / '_probe_v006_parts.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')

# ------------------------------------------------------------------------- console digest
print('=' * 84)
for cn, objs in report['v006'].items():
    if not objs:
        print('%-38s ABSENT' % cn)
        continue
    print('--- %s' % cn)
    for on, parts in objs.items():
        print('    %-46s loose=%d' % (on, len(parts)))
        for p in parts[:26]:
            print('        lo=%-26s size=%-24s mat=%s'
                  % (p['lo'], p['size'], p['mat']))
print('=' * 84)
print('RECOVERED (authored source):')
for cn, objs in report['recovered'].items():
    if not objs:
        print('  %-34s ABSENT' % cn)
        continue
    for on, d in objs.items():
        print('  %-34s %-30s parts=%d loc=%s' % (cn, on, len(d['parts']), d['loc']))
        for p in d['parts'][:14]:
            print('        lo=%-26s size=%-24s mat=%s' % (p['lo'], p['size'], p['mat']))
print('wrote _probe_v006_parts.json')
