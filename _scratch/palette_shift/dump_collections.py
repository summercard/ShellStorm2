"""只读：列出指定 blend 的全部集合（名称 + 直接成员数），用于定位重名去重后缀。"""
from __future__ import annotations

import argparse
import sys

import bpy


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--blend", required=True)
    p.add_argument("--filter", default="")
    args = p.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=args.blend)
    print("===== %s 集合 %d 个 =====" % (args.blend, len(bpy.data.collections)))
    for coll in sorted(bpy.data.collections, key=lambda c: c.name):
        if args.filter and args.filter not in coll.name:
            continue
        print(
            "  %-56s 直接成员=%d 对象=%d"
            % (coll.name, len(coll.objects), len(coll.all_objects))
        )


if __name__ == "__main__":
    main()
