"""Compare canonical geometry of two legacy component package .blend files.

  blender --factory-startup --background --python _scratch/boss_plan/compare_geometry.py -- <a.blend> <b.blend>

Canonical form: per output mesh, vertices translated so the mesh's own bbox center is at origin,
then rounded to 1e-4 and sorted. Also reports mirror variants.
"""

from __future__ import annotations

import sys

import bpy
from mathutils import Vector


def output_meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and "_输出_" in o.name]


def canonical(path: str):
    """Return name-agnostic ordered geometry signature list for a package."""
    bpy.ops.wm.open_mainfile(filepath=path)
    meshes = sorted(output_meshes(), key=lambda o: o.name)
    out = []
    for obj in meshes:
        co = [obj.matrix_world @ v.co for v in obj.data.vertices]
        lo = hi = mid = Vector((0.0, 0.0, 0.0))
        if co:
            lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
            hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
            mid = (lo + hi) / 2.0
        pts = sorted(
            (round(p.x - mid.x, 4), round(p.y - mid.y, 4), round(p.z - mid.z, 4)) for p in co
        )
        out.append({
            "verts": pts,
            "count": len(pts),
            "lo": tuple(round(v, 4) for v in (lo - mid)),
            "hi": tuple(round(v, 4) for v in (hi - mid)),
            "mats": [m.name for m in obj.data.materials if m],
        })
    return out


def mirror(pts, axis: int):
    out = []
    for p in pts:
        q = list(p)
        q[axis] = round(-q[axis], 4)
        out.append(tuple(q))
    return sorted(out)


def main() -> None:
    argv = sys.argv
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    a_path, b_path = args[0], args[1]
    a = canonical(a_path)
    b = canonical(b_path)
    print(f"A={a_path}")
    print(f"B={b_path}")
    print(f"A mesh_count={len(a)} verts={[m['count'] for m in a]}")
    print(f"B mesh_count={len(b)} verts={[m['count'] for m in b]}")
    if len(a) != len(b):
        print("  MESH_COUNT_DIFFERS")
    for i in range(max(len(a), len(b))):
        if i >= len(a) or i >= len(b):
            continue
        pa, pb = a[i], b[i]
        same = pa["verts"] == pb["verts"]
        info = f"  [{i}] verts {pa['count']} vs {pb['count']} exact_equal={same}"
        if not same and pa["count"] == pb["count"]:
            for ax, label in ((0, "X"), (1, "Y"), (2, "Z")):
                if mirror(pa["verts"], ax) == pb["verts"]:
                    info += f" mirror_about_{label}=True"
        if not same:
            info += f"\n      A bounds {pa['lo']}..{pa['hi']}\n      B bounds {pb['lo']}..{pb['hi']}"
            info += f"\n      A mats {pa['mats']}  B mats {pb['mats']}"
        print(info)
    print("COMPARE_GEOMETRY_DONE")


main()
