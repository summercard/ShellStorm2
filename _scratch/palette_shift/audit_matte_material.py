"""只读：审计各 blend 的材质数据块构成与 `02_细腻哑光` 的 PBR 参数。

用途：核对 B2 到底在哪些 blend 里**新建**了材质球，以及新建参数是否与库内既有哑光一致。
指向 `--root`（源库根或 I:/workbuddy_tmp/material_role_backup）即可。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy

MATTE = "02_细腻哑光_青绿大面"
METAL = "01_精工金属_紫色骨架"


def params(material: bpy.types.Material) -> dict:
    out = {"metallic": None, "roughness": None, "coat": None}
    if not material.use_nodes:
        return out
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            out["metallic"] = round(node.inputs["Metallic"].default_value, 4)
            out["roughness"] = round(node.inputs["Roughness"].default_value, 4)
            out["coat"] = round(node.inputs["Coat Weight"].default_value, 4)
            break
    return out


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--root", required=True)
    args = p.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")
    root = Path(args.root)
    blends = sorted(root.rglob("*.blend"))
    missing_matte = []
    matte_params: dict[tuple, int] = {}
    metal_params: dict[tuple, int] = {}
    for blend in blends:
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        has_matte = bpy.data.materials.get(MATTE) is not None
        n = len(bpy.data.materials)
        if has_matte:
            pr = params(bpy.data.materials[MATTE])
            matte_params[(pr["metallic"], pr["roughness"], pr["coat"])] = (
                matte_params.get((pr["metallic"], pr["roughness"], pr["coat"]), 0) + 1
            )
        else:
            missing_matte.append(blend.relative_to(root).as_posix())
        metal = bpy.data.materials.get(METAL)
        if metal is not None:
            prm = params(metal)
            metal_params[(prm["metallic"], prm["roughness"], prm["coat"])] = (
                metal_params.get((prm["metallic"], prm["roughness"], prm["coat"]), 0) + 1
            )
        print(
            "%-64s 材质数=%d 哑光=%s%s 全部=%s"
            % (
                blend.relative_to(root).as_posix(),
                n,
                "有" if has_matte else "无",
                (
                    "(%s,%s,%s)"
                    % (
                        params(bpy.data.materials[MATTE])["metallic"],
                        params(bpy.data.materials[MATTE])["roughness"],
                        params(bpy.data.materials[MATTE])["coat"],
                    )
                    if has_matte
                    else ""
                ),
                [m.name for m in bpy.data.materials],
            )
        )
    print()
    print("MISSING_MATTE_COUNT:%d" % len(missing_matte))
    for rel in missing_matte:
        print("  MISSING %s" % rel)
    print("哑光 PBR 参数分布（metallic,rough,coat -> blend 数）：%s" % dict(matte_params))
    print("金属 PBR 参数分布（metallic,rough,coat -> blend 数）：%s" % dict(metal_params))


if __name__ == "__main__":
    main()
