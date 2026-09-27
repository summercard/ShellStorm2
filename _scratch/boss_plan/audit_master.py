"""Audit a group-regrouped master .blend: which collections/objects survived."""

from __future__ import annotations

import sys

import bpy


def main() -> None:
    argv = sys.argv
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    bpy.ops.wm.open_mainfile(filepath=args[0])
    print(f"scenes={len(bpy.data.scenes)} collections={len(bpy.data.collections)} objects={len(bpy.data.objects)} meshes={len(bpy.data.meshes)}")
    names = sorted(c.name for c in bpy.data.collections)
    print("collections:")
    for name in names:
        col = bpy.data.collections[name]
        print(f"  {name}: objs={len(col.objects)} children={len(col.children)}")
    orphan = [o for o in bpy.data.objects if not o.users_collection]
    print(f"orphan_objects={len(orphan)} {[o.name for o in orphan][:5]}")
    scene = bpy.data.scenes[0]
    print(f"scene '{scene.name}' objects={len(scene.objects)}")
    print("AUDIT_MASTER_DONE")


main()
