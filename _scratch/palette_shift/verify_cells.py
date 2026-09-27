"""只读：从磁盘重读某 blend，复算色盘格直方图（按 mesh 数据块去重），与报告 expected 对照。"""

from __future__ import annotations

import argparse
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
REPORT = ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_type_components/palette_lighten_correction.json"


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--lib", required=True)
    args = p.parse_args(argv)

    bpy.ops.wm.open_mainfile(filepath=str(ROOT / LIBS[args.lib]))
    cells: collections.Counter = collections.Counter()
    seen = set()
    scene = bpy.context.scene
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        me = obj.data
        if me.as_pointer() in seen:
            continue
        seen.add(me.as_pointer())
        layer = me.uv_layers.get("PaletteUV") or me.uv_layers.active
        if layer is None:
            continue
        uvs = layer.data
        for poly in me.polygons:
            if poly.loop_total == 0:
                continue
            cu = cv = 0.0
            for li in poly.loop_indices:
                cu += uvs[li].uv[0]
                cv += uvs[li].uv[1]
            cu /= poly.loop_total
            cv /= poly.loop_total
            cells[(min(9, max(0, int(cu * 10))), min(9, max(0, int(cv * 10))))] += 1

    report = json.loads(REPORT.read_text(encoding="utf-8"))
    key = next(k for k in report["per_library"] if k.startswith(args.lib.split("_")[0]))
    expected = report["per_library"][key]["cells_after"]
    print("mark:", scene.get("shellstorm2_palette_lighten"))
    print(f"{args.lib}  实测格数 {len(cells)}  预期格数 {len(expected)}")
    bad = 0
    for k, v in expected.items():
        u, vv = (int(t) for t in k.split("_"))
        got = cells.get((u, vv), 0)
        if got != v["faces"]:
            bad += 1
            print(f"  MISMATCH {k}: 实测 {got} 预期 {v['faces']}")
    extra = {f"{c}_{v}": n for (c, v), n in cells.items() if f"{c}_{v}" not in expected}
    for k, n in extra.items():
        print(f"  EXTRA {k}: {n}")
    total = sum(cells.values())
    exp_total = sum(v["faces"] for v in expected.values())
    print(f"  合计 实测 {total} / 预期 {exp_total}  失配 {bad} 多余 {len(extra)}")
    print("PALETTE_VERIFY_OK" if bad == 0 and not extra and total == exp_total else "PALETTE_VERIFY_FAIL")


if __name__ == "__main__":
    main()
