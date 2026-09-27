"""只读勘察：列出源 blend 的全部对象（名字 / 类型 / 世界 bbox / 集合）。

用法:
    blender -b --python list_objects.py -- <blend_path>
"""
from __future__ import annotations

import sys
from collections import Counter, defaultdict

import bpy
from mathutils import Vector


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    path = argv[0]
    bpy.ops.wm.open_mainfile(filepath=path)

    objs = list(bpy.data.objects)
    print(f"BLEND: {path}")
    print(f"OBJECTS: {len(objs)}")

    kinds = Counter(o.type for o in objs)
    print(f"TYPES: {dict(kinds)}")

    meshes = [o for o in objs if o.type == "MESH"]
    print(f"MESHES: {len(meshes)}")

    # 集合归属
    coll_of = defaultdict(list)
    for c in bpy.data.collections:
        for o in c.objects:
            coll_of[c.name].append(o.name)
    print(f"COLLECTIONS: {len(coll_of)}")
    for name in sorted(coll_of):
        print(f"  COLL {name!r}: {len(coll_of[name])} objects")

    # 每个 mesh 的世界 bbox
    print("--- MESHES (name | verts | world bbox size | world bbox center) ---")
    rows = []
    for o in meshes:
        ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = Vector((min(p.x for p in ws), min(p.y for p in ws), min(p.z for p in ws)))
        hi = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
        rows.append((o.name, len(o.data.vertices), hi - lo, (lo + hi) / 2.0))
    for name, nv, size, center in sorted(rows, key=lambda r: -r[1])[:60]:
        print(
            "  %-46s v=%-6d size=(%6.2f,%6.2f,%6.2f) c=(%6.2f,%6.2f,%6.2f)"
            % (name[:46], nv, size.x, size.y, size.z, center.x, center.y, center.z)
        )

    total_v = sum(r[1] for r in rows)
    print(f"TOTAL_VERTS: {total_v}")


main()
