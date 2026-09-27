"""只读：按「输出包」分组，统计每个包用到的色盘格与材质面数。

用于回答「#05050C 这种近黑到底用在哪个件上、是不是可见大面」。
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

import bpy

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
BLENDS = [
    ("office_v006", "assets/art/environments/tower_zones/expedition/source/common_components/v006/expedition_office_room_components_source_v006.blend"),
    ("bridge_v007", "assets/art/environments/tower_zones/expedition/source/common_components/v007/expedition_bridge_room_components_source_v007.blend"),
    ("boss_v008", "assets/art/environments/tower_zones/expedition/source/common_components/v008/expedition_boss_room_components_source_v008.blend"),
    ("corridor_v002", "assets/art/environments/tower_zones/expedition/source/common_components/v002/expedition_l_corridor_components_source_v002.blend"),
    ("db_v003", "assets/art/environments/tower_zones/expedition/source/common_components/v003/expedition_db_room_components_source_v003.blend"),
]


def main() -> None:
    out: dict[str, dict] = {}
    for label, rel in BLENDS:
        path = ROOT / rel
        if not path.is_file():
            print(f"SKIP {label}")
            continue
        bpy.ops.wm.open_mainfile(filepath=str(path))
        per_pkg: dict[str, dict] = collections.defaultdict(
            lambda: {"cells": collections.Counter(), "mats": collections.Counter()}
        )
        for obj in bpy.data.objects:
            if obj.type != "MESH":
                continue
            me = obj.data
            layer = me.uv_layers.get("PaletteUV")
            if layer is None:
                continue
            colls = [c.name for c in obj.users_collection] or ["<无集合>"]
            pkg = next(
                (c for c in colls if c.endswith("_输出包")),
                next((c for c in colls if "输出" in c), colls[0]),
            )
            uvs = layer.data
            for poly in me.polygons:
                if poly.loop_total == 0:
                    continue
                cu = cv = 0.0
                for li in poly.loop_indices:
                    uv = uvs[li].uv
                    cu += uv[0]
                    cv += uv[1]
                cu /= poly.loop_total
                cv /= poly.loop_total
                ci = min(9, max(0, int(cu * 10)))
                vi = min(9, max(0, int(cv * 10)))
                per_pkg[pkg]["cells"][(ci, vi)] += 1
            mat = me.materials[poly.material_index] if me.materials and poly.material_index < len(me.materials) else None
            if mat:
                per_pkg[pkg]["mats"][mat.name] += 1
        out[label] = {
            "packages": {
                p: {
                    "faces": sum(d["cells"].values()),
                    "cells": {f"{c}_{v}": n for (c, v), n in d["cells"].most_common()},
                    "mats": dict(d["mats"].most_common()),
                }
                for p, d in sorted(per_pkg.items())
            }
        }
        print(f"===== {label}：{len(per_pkg)} 包 =====")
        # 只看用到 (0,0) 近黑 或 (9,9)/(9,8) 深蓝灰 的包
        hot = [
            (p, d)
            for p, d in per_pkg.items()
            if (0, 0) in d["cells"] or (9, 9) in d["cells"] or (9, 8) in d["cells"]
        ]
        for p, d in sorted(hot, key=lambda kv: -sum(kv[1]["cells"].values())):
            cell_txt = " ".join(
                f"{c}_{v}:{n}" for (c, v), n in d["cells"].most_common(6)
            )
            print(f"  {p}  面 {sum(d['cells'].values())}  [{cell_txt}]")
        print()

    p = ROOT / "_scratch/palette_shift/per_package.json"
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE:{p}")


if __name__ == "__main__":
    main()
