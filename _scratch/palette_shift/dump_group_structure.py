"""只读：列出指定 blend 里所有网格对象 + 所属集合 + 槽指向 + 面数/面积。

用法：
  blender -b --python dump_group_structure.py -- --blend <abs path> [--filter <子串>]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--blend", required=True)
    p.add_argument("--filter", default="")
    args = p.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=args.blend)
    print("===== %s =====" % Path(args.blend).name)
    print(
        "材质数据块 %d：%s"
        % (len(bpy.data.materials), [m.name for m in bpy.data.materials])
    )
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        if obj.type != "MESH":
            continue
        if args.filter and args.filter not in obj.name:
            continue
        me = obj.data
        colls = [c.name for c in obj.users_collection]
        total_faces = len(me.polygons)
        print(
            "  %-56s mesh=%s(%d面) colls=%s"
            % (obj.name, me.name, total_faces, colls)
        )
        for i, slot in enumerate(obj.material_slots):
            area = sum(poly.area for poly in me.polygons if poly.material_index == i)
            faces = sum(1 for poly in me.polygons if poly.material_index == i)
            print(
                "      slot%-2d %-30s 面=%-6d 面积=%8.3f"
                % (i, slot.material.name if slot.material else "<none>", faces, area)
            )


if __name__ == "__main__":
    main()
