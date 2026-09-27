"""Inspect a legacy (v001) expedition boss component package .blend.

  blender --factory-startup --background --python _scratch/boss_plan/inspect_v001_package.py -- <blend> [<blend> ...]
"""

from __future__ import annotations

import sys

import bpy


def dump(path: str) -> None:
    bpy.ops.wm.open_mainfile(filepath=path)
    print(f"==== {path}")
    print(f"  scenes({len(bpy.data.scenes)}): {[s.name for s in bpy.data.scenes]}")
    print(f"  current scene: {bpy.context.scene.name}")
    print(f"  collections({len(bpy.data.collections)}):")
    for col in bpy.data.collections:
        objs = sorted(o.name for o in col.objects)
        print(f"    - {col.name}: {len(objs)} objs {objs[:8]}")
    print(f"  scene objects({len(bpy.context.scene.objects)}):")
    for obj in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        parent = obj.parent.name if obj.parent else "-"
        cols = [c.name for c in obj.users_collection]
        extra = ""
        if obj.type == "MESH":
            extra = f" verts={len(obj.data.vertices)} tris(loop)={len(obj.data.polygons)}"
            extra += f" mats={[m.name for m in obj.data.materials if m]}"
        print(f"    * {obj.name} type={obj.type} parent={parent} cols={cols}{extra}")
        print(f"      loc={tuple(round(v, 4) for v in obj.location)} matrix_world_t={tuple(round(v, 4) for v in obj.matrix_world.translation)}")
    print(f"  materials({len(bpy.data.materials)}): {[m.name for m in bpy.data.materials]}")
    print(f"  images({len(bpy.data.images)}): {[i.name for i in bpy.data.images]}")


def main() -> None:
    argv = sys.argv
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    for path in args:
        dump(path)
    print("INSPECT_V001_PACKAGE_DONE")


main()
