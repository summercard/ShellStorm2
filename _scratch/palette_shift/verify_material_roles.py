"""B2 复核（只读）：逐输出包断言「金属已是小部分」（metal < matte + gloss 或 metal == 0）。

口径与 measure_material_area.py 一致：只取 `_输出_` 网格对象并按 mesh 数据块去重，
按 `<组件>_输出包` 集合归组（母版里 `_制作源`/`_输出包` 两套镜像面积同倍率，比例不受影响）。

输出：
  - 每个库逐包一行（金属/哑光/反光面积 + 占比 + 判定）
  - 每库汇总（金属总面积占比、未达标包数）
  - 末行 MATERIAL_ROLE_VERIFY_OK / FAIL（供门禁 grep）
  - JSON 落 `_scratch/palette_shift/material_role_verify.json`
"""

from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
LIBS = {
    "office_room/v006": "assets/art/environments/tower_zones/expedition/source/common_components/v006/expedition_office_room_components_source_v006.blend",
    "bridge_room/v007": "assets/art/environments/tower_zones/expedition/source/common_components/v007/expedition_bridge_room_components_source_v007.blend",
    "boss_room/v008": "assets/art/environments/tower_zones/expedition/source/common_components/v008/expedition_boss_room_components_source_v008.blend",
    "l_corridor/v002": "assets/art/environments/tower_zones/expedition/source/common_components/v002/expedition_l_corridor_components_source_v002.blend",
    "db_room/v003": "assets/art/environments/tower_zones/expedition/source/common_components/v003/expedition_db_room_components_source_v003.blend",
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
    failures: list[str] = []
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
        rows = []
        bad = 0
        total_metal = total_matte = total_gloss = 0.0
        for pkg, d in sorted(per_pkg.items()):
            metal = d.get("metal", 0.0)
            matte = d.get("matte", 0.0)
            gloss = d.get("gloss", 0.0)
            emissive = d.get("emissive", 0.0)
            other = sum(v for k, v in d.items() if k.startswith("other:"))
            total_metal += metal
            total_matte += matte
            total_gloss += gloss
            base = metal + matte + gloss
            share = metal / base if base else 0.0
            ok = metal == 0.0 or metal < matte + gloss
            if not ok:
                bad += 1
                failures.append("%s :: %s" % (label, pkg))
            rows.append(
                {
                    "package": pkg,
                    "metal_m2": round(metal, 3),
                    "matte_m2": round(matte, 3),
                    "gloss_m2": round(gloss, 3),
                    "emissive_m2": round(emissive, 3),
                    "other_m2": round(other, 3),
                    "metal_share": round(share, 4),
                    "verdict": "OK" if ok else "FAIL",
                }
            )
        rows.sort(key=lambda r: -r["metal_share"])
        total_base = total_metal + total_matte + total_gloss
        print("===== %s：%d 个输出包，未达标 %d =====" % (label, len(per_pkg), bad))
        for r in rows:
            print(
                "  金属占比%6.1f%%  金属%8.1f 哑光%8.1f 反光%7.1f 自发光%6.1f  %-4s %s"
                % (
                    r["metal_share"] * 100,
                    r["metal_m2"],
                    r["matte_m2"],
                    r["gloss_m2"],
                    r["emissive_m2"],
                    r["verdict"],
                    r["package"],
                )
            )
        print(
            "  >> 库合计：金属%8.1f 哑光%8.1f 反光%7.1f ⇒ 金属面积占比 %.1f%%"
            % (
                total_metal,
                total_matte,
                total_gloss,
                (total_metal / total_base * 100) if total_base else 0.0,
            )
        )
        print()
        report[label] = {
            "packages": rows,
            "packages_total": len(per_pkg),
            "packages_failed": bad,
            "library_metal_m2": round(total_metal, 3),
            "library_matte_m2": round(total_matte, 3),
            "library_gloss_m2": round(total_gloss, 3),
            "library_metal_share": round(
                (total_metal / total_base) if total_base else 0.0, 4
            ),
        }
    out = ROOT / "_scratch/palette_shift/material_role_verify.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("WROTE:%s" % out)
    if failures:
        print("MATERIAL_ROLE_VERIFY_FAIL:%d :: %s" % (len(failures), "; ".join(failures[:20])))
        return 1
    print("MATERIAL_ROLE_VERIFY_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
