"""Compare per-mesh geometry classes inside a family across two libraries.

  blender --factory-startup --background --python _scratch/boss_plan/family_classes.py -- <lib_dir> <glob_parent_substr>

Prints, for every package whose slug matches the substring, the per-mesh canonical
signature length and the class id, so we can see *which* mesh carries the variation.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


def quantize(obj):
    matrix = obj.matrix_world
    points = [matrix @ v.co for v in obj.data.vertices]
    if not points:
        return ()
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    center = [(lo[i] + hi[i]) * 0.5 for i in range(3)]
    return tuple(
        sorted(
            (round(p.x - center[0], 2), round(p.y - center[1], 2), round(p.z - center[2], 2))
            for p in points
        )
    )


def main() -> None:
    argv = sys.argv
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    lib = Path(args[0])
    needle = args[1] if len(args) > 1 else ""
    root = lib / "component_packages"
    slugs = sorted(d.name for d in root.iterdir() if d.is_dir() and needle in d.name)
    print(f"FAMILY={needle} packages={len(slugs)}")
    role_classes: dict[str, dict[tuple, list[str]]] = {}
    for slug in slugs:
        bpy.ops.wm.open_mainfile(filepath=str(root / slug / f"{slug}.blend"))
        meshes = sorted(
            (o for o in bpy.context.scene.objects if o.type == "MESH" and "_输出_" in o.name),
            key=lambda o: o.name,
        )
        roles = []
        for obj in meshes:
            role = obj.name.rsplit("_输出_", 1)[1]
            role = "自发光" if role.startswith("自发光") else role
            roles.append(role)
            role_classes.setdefault(role, {}).setdefault(quantize(obj), []).append(slug)
        print(f"  {slug:<34} meshes={len(meshes)} roles={roles}")
    print()
    for role, classes in sorted(role_classes.items()):
        print(f"== 角色 {role}: {len(classes)} 个几何类")
        for key, members in sorted(classes.items(), key=lambda kv: -len(kv[1])):
            print(f"   verts={len(key):<6} n={len(members):<3} {members[:4]}")
    print("FAMILY_CLASSES_DONE")


main()
