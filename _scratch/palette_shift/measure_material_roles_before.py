"""只读：按 verify_material_roles.py 的同一口径，测「B2 改前」备份库的金属占比。

用途：给账本与文档提供可复现的 before 数字（不引用无法复算的旧记录）。
判据：只取 `_输出_` 网格对象、按 mesh 数据块去重、按 `<组件>_输出包` 集合归组。
"""
from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

import bpy

BACKUP = Path(r"I:\workbuddy_tmp\material_role_backup")
LIBS = {
    "office_room/v006": ("v006", "expedition_office_room_components_source_v006.blend"),
    "bridge_room/v007": ("v007", "expedition_bridge_room_components_source_v007.blend"),
    "boss_room/v008": ("v008", "expedition_boss_room_components_source_v008.blend"),
    "l_corridor/v002": ("v002", "expedition_l_corridor_components_source_v002.blend"),
    "db_room/v003": ("v003", "expedition_db_room_components_source_v003.blend"),
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


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    report: dict = {}
    print(f"{'lib':<20}{'包数':>6}{'金属m2':>11}{'哑光m2':>11}{'反光m2':>10}{'金属占比':>9}")
    for label, (ver, name) in LIBS.items():
        path = BACKUP / ver / name
        if not path.is_file():
            print(f"!! 备份缺失 {path}", flush=True)
            report[label] = {"error": "backup_missing"}
            continue
        bpy.ops.wm.open_mainfile(filepath=str(path))
        per_pkg: dict[str, dict[str, float]] = collections.defaultdict(lambda: collections.defaultdict(float))
        seen = set()
        for obj in bpy.data.objects:
            if obj.type != "MESH" or "_输出_" not in obj.name:
                continue
            me = obj.data
            if me.as_pointer() in seen:
                continue
            seen.add(me.as_pointer())
            colls = [c.name for c in obj.users_collection]
            pkg = next((c for c in colls if c.rstrip(".0123456789").endswith("_输出包")), None)
            if pkg is None:
                pkg = next((c for c in colls if "输出" in c), colls[0] if colls else "<无>")
            for poly in me.polygons:
                idx = poly.material_index
                mat = me.materials[idx] if idx < len(me.materials) else None
                per_pkg[pkg][role_of(mat.name if mat else "<none>")] += poly.area
        m = sum(d.get("metal", 0.0) for d in per_pkg.values())
        mt = sum(d.get("matte", 0.0) for d in per_pkg.values())
        g = sum(d.get("gloss", 0.0) for d in per_pkg.values())
        total = m + mt + g
        share = 100 * m / total if total else 0.0
        print(f"{label:<20}{len(per_pkg):>6}{m:>11.1f}{mt:>11.1f}{g:>10.1f}{share:>8.1f}%", flush=True)
        report[label] = {
            "packages": len(per_pkg),
            "metal_m2": round(m, 3), "matte_m2": round(mt, 3), "gloss_m2": round(g, 3),
            "metal_share_pct": round(share, 2),
        }
    out = Path(r"I:\工作项目\shellstrom2\ShellStorm2\_scratch\palette_shift\material_role_before.json")
    out.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("MATERIAL_ROLE_BEFORE_MEASURED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
