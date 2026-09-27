"""探测 office_room/v001 组件集合的源原点与局部包围盒（Blender 4.5 headless）。"""
import bpy, sys, json
from mathutils import Vector
from pathlib import Path

ROOT = Path(r'I:/工作项目/shellstrom2/ShellStorm2')
OFFICE = ROOT/'assets/art/environments/tower_zones/expedition/source/room_types/office_room/v001/办公室房间种类_开放办公_30x40m_v001.blend'
print('OFFICE_EXISTS', OFFICE.is_file(), flush=True)


def dump(coll, tag):
    objs = sorted(coll.objects, key=lambda o: o.name)
    if not objs:
        print('EMPTY', tag); return
    o = objs[0]
    mb = o.matrix_basis
    loc = mb.translation
    print('%-34s n=%2d first=%-28s loc=(%.5f, %.5f, %.5f) rotZ=%.4f scale=%.4f' % (
        tag, len(objs), o.name, loc.x, loc.y, loc.z, mb.to_euler().z, mb.to_scale().x), flush=True)
    # 用 matrix_world 与 matrix_basis 两口径各算一次包围盒
    dg = bpy.context.evaluated_depsgraph_get()
    for mode in ('basis', 'world'):
        M = mb if mode == 'basis' else o.matrix_world
        pts = [(M @ Vector(v)) for v in o.bound_box]
        lo = [round(min(p[i] for p in pts), 4) for i in range(3)]
        hi = [round(max(p[i] for p in pts), 4) for i in range(3)]
        print('    bbox[%s] lo=%s hi=%s' % (mode, lo, hi), flush=True)


if __name__ == '__main__':
    names = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    with bpy.data.libraries.load(str(OFFICE), link=True) as (f, t):
        t.collections = [n for n in f.collections if (not names) or (n in names)]
    LOADED = [c for c in bpy.data.collections if c.library is not None]
    print('LOADED_COLLECTIONS', len(LOADED), flush=True)
    for c in sorted(LOADED, key=lambda x: x.name):
        dump(c, c.name)
