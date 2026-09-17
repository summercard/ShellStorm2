"""诊断：recovered blend 里 c02 地砖的 18 / 22 件差异到底是什么。

只读，不写任何资产。
"""
from __future__ import annotations
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

RECOVERED = Path(r'I:/工作项目/shellstrom2/_scratch/esr_recover/v003_recovered.blend')


def W(o):
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


def loose(me):
    n = len(me.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in me.edges:
        ra, rb = find(e.vertices[0]), find(e.vertices[1])
        if ra != rb:
            parent[rb] = ra
    g = {}
    for p in me.polygons:
        g.setdefault(find(p.vertices[0]), set()).update(p.vertices)
    return list(g.values())


bpy.ops.wm.open_mainfile(filepath=str(RECOVERED))
bpy.context.view_layer.update()

for r in (1, 2, 3):
    for c in (1, 2, 3):
        col = None
        for nm in ('制作_地砖_R%02d_C%02d.001' % (r, c), '制作_地砖_R%02d_C%02d' % (r, c)):
            col = bpy.data.collections.get(nm)
            if col is not None:
                break
        if col is None:
            print('R%02dC%02d  MISSING' % (r, c))
            continue
        objs = sorted((o for o in col.objects if o.type == 'MESH'), key=lambda x: x.name)
        total = 0
        rows = []
        for o in objs:
            if o.name.startswith(('FLOOR_', 'AP_', 'WALL_')):
                rows.append(('  [skip-module] ' + o.name, '', 0))
                continue
            for k, vs in enumerate(loose(o.data)):
                pts = [W(o) @ o.data.vertices[i].co for i in vs]
                lo = [min(p[i] for p in pts) for i in range(3)]
                hi = [max(p[i] for p in pts) for i in range(3)]
                mats = {o.data.materials[pp.material_index].name.split('.')[0]
                        for pp in o.data.polygons
                        if pp.vertices[0] in vs and o.data.materials}
                total += 1
                rows.append(('%s#%d' % (o.name, k),
                             'z %.4f..%.4f  x %.3f..%.3f  y %.3f..%.3f  %s'
                             % (lo[2], hi[2], lo[0], hi[0], lo[1], hi[1], ','.join(sorted(mats))),
                             len(vs)))
        print('=' * 100)
        print('R%02dC%02d  objects=%d  parts=%d' % (r, c, len(objs), total))
        for nm, box, nv in sorted(rows, key=lambda t: t[1]):
            print('   %-34s %s' % (nm, box))
