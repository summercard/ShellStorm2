"""只读：按「组件输出包」统计材质角色的**面积**占比，用于设计主面判据。

只统计 `_输出_` 网格对象（导出链真正取用的那一套），按 mesh 数据块去重避免重复计数。
"""

from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
LIBS = {
    "office_v006": "assets/art/environments/tower_zones/expedition/source/common_components/v006/expedition_office_room_components_source_v006.blend",
    "bridge_v007": "assets/art/environments/tower_zones/expedition/source/common_components/v007/expedition_bridge_room_components_source_v007.blend",
    "boss_v008": "assets/art/environments/tower_zones/expedition/source/common_components/v008/expedition_boss_room_components_source_v008.blend",
    "corridor_v002": "assets/art/environments/tower_zones/expedition/source/common_components/v002/expedition_l_corridor_components_source_v002.blend",
    "db_v003": "assets/art/environments/tower_zones/expedition/source/common_components/v003/expedition_db_room_components_source_v003.blend",
}


def role_of(name: str) -> str:
    if name.startswith("01_精工金属"):
        return "metal"
    if name.startswith("02_细腻哑光"):
        return "matte"
    if name.startswith("03_清漆反光"):
        return "gloss"
    if name.startswith("04_柔和自发光"):
        return "emissive"
    return "other:" + name


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    out = {}
    for label, rel in LIBS.items():
        bpy.ops.wm.open_mainfile(filepath=str(ROOT / rel))
        per_pkg: dict[str, dict[str, float]] = collections.defaultdict(
            lambda: collections.defaultdict(float)
        )
        seen = set()
        for obj in bpy.data.objects:
            if obj.type != "MESH" or "_输出_" not in obj.name:
                continue
            me = obj.data
            if me.as_pointer() in seen:
                continue
            seen.add(me.as_pointer())
            colls = [c.name for c in obj.users_collection]
            pkg = next((c for c in colls if c.endswith("_输出包")), None)
            if pkg is None:
                pkg = next((c for c in colls if "输出" in c), colls[0] if colls else "<无>")
            for poly in me.polygons:
                idx = poly.material_index
                mat = me.materials[idx] if idx < len(me.materials) else None
                per_pkg[pkg][role_of(mat.name if mat else "<none>")] += poly.area
        out[label] = {
            p: {k: round(v, 3) for k, v in sorted(d.items())}
            for p, d in sorted(per_pkg.items())
        }
        print(f"===== {label}：{len(per_pkg)} 个输出包 =====")
        rows = []
        for p, d in per_pkg.items():
            metal = d.get("metal", 0.0)
            matte = d.get("matte", 0.0)
            gloss = d.get("gloss", 0.0)
            emi = d.get("emissive", 0.0)
            base = metal + matte + gloss
            share = metal / base if base else 0.0
            rows.append((share, metal, p, d, base, matte, gloss, emi))
        rows.sort(reverse=True)
        for share, metal, p, d, base, matte, gloss, emi in rows:
            print(
                "  金属占比%6.1f%%  金属%8.1f 哑光%8.1f 反光%7.1f 自发光%7.1f  %s"
                % (share * 100, metal, matte, gloss, emi, p)
            )
        print()
    p = ROOT / "_scratch/palette_shift/material_area_by_package.json"
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE:{p}")


if __name__ == "__main__":
    main()
