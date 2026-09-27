"""只读：dump 指定 blend 里每个材质的节点树（图像节点指向 + 是否有贴图 + Base Color 连线）。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--blend", required=True)
    args = p.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")
    bpy.ops.wm.open_mainfile(filepath=args.blend)
    print("===== %s" % Path(args.blend).name)
    print("bpy.data.images = %d" % len(bpy.data.images))
    for image in bpy.data.images:
        resolved = bpy.path.abspath(image.filepath)
        print(
            "  IMG %-44s filepath=%s packed=%s exists=%s size=%s"
            % (
                image.name,
                image.filepath,
                image.packed_file is not None,
                Path(resolved).is_file(),
                tuple(image.size),
            )
        )
    for material in bpy.data.materials:
        print("  MAT %s use_nodes=%s" % (material.name, material.use_nodes))
        if not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            extra = ""
            if node.type == "TEX_IMAGE":
                extra = " image=%s uv_map=%s" % (
                    node.image.name if node.image else "<None>",
                    getattr(node, "uv_map", "?"),
                )
            if node.type == "UVMap":
                extra = " uv_map=%r" % node.uv_map
            print("      %-22s %s%s" % (node.type, node.name, extra))
        for link in material.node_tree.links:
            print(
                "      LINK %s.%s -> %s.%s"
                % (
                    link.from_node.type,
                    link.from_socket.name,
                    link.to_node.type,
                    link.to_socket.name,
                )
            )


if __name__ == "__main__":
    main()
