"""Summarize a component-library master .blend (scenes / collections / objects)."""

from __future__ import annotations

import sys

import bpy


def main() -> None:
    argv = sys.argv
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    for path in args:
        bpy.ops.wm.open_mainfile(filepath=path)
        scenes = [s.name for s in bpy.data.scenes]
        print(f"==== {path}")
        print(f"  scenes={len(scenes)}")
        for nm in scenes[:6]:
            sc = bpy.data.scenes[nm]
            print(f"    - {nm}: {len(sc.objects)} objs")
        if len(scenes) > 6:
            print(f"    ... 另 {len(scenes) - 6} 个场景")
        cols = sorted(bpy.data.collections, key=lambda c: c.name)
        print(f"  collections={len(cols)}")
        kinds = {}
        for c in cols:
            key = "_".join(c.name.split("_")[-2:]) if "_" in c.name else c.name
            kinds[c.name.split("_")[-1] if "_" in c.name else c.name] = kinds.get(
                c.name.split("_")[-1] if "_" in c.name else c.name, 0
            ) + 1
        print(f"  collections 尾缀分布={kinds}")
        print(f"  objects={len(bpy.data.objects)} meshes={len(bpy.data.meshes)} materials={len(bpy.data.materials)}")
    print("SUMMARY_MASTER_DONE")


main()
